#!/usr/bin/env python3
"""Flux manifest validation gate.

Replicates, at PR time, the pipeline kustomize-controller actually runs over
kubernetes/apps/** in this repo. Three layers:

LAYER 1 - plain kustomize build of each touched app dir (ks spec.path).
  Catches anything 'kustomize build' rejects: malformed YAML, missing
  resources/components, broken patches. Repo CI previously built no manifests
  at all, so these surfaced only at reconcile time.

LAYER 2 - parent-patched build. THE #2292 CLASS.
  kubernetes/flux/apps.yaml (Kustomization cluster-apps) applies a global
  patch that re-injects spec.decryption + spec.postBuild into EVERY child
  Kustomization that does not opt out via the label
  'substitution.flux.home.arpa/disabled: "true"'. Inspecting a child ks.yaml
  alone can never see this: #2292 dropped postBuild from the child file, CI
  was green, and the parent silently re-added it - the app kept failing
  in-cluster. This layer extracts the live patch block from apps.yaml and
  applies it to a scratch copy of each ks with the same labelSelector, then
  asserts the opt-out semantics hold:
    - an opted-out ks must NOT receive injected postBuild/decryption;
    - a ks with no postBuild of its own that GAINS one via injection while
      its built manifests contain $VAR references is flagged: the parent
      re-enabled the strict envsubst the author meant to disable.

LAYER 3 - strict envsubst emulation. THE #2269 CLASS.
  kustomize-controller post-build substitution runs drone/envsubst in strict
  mode: the first undefined variable fails the whole build ('variable not set
  (strict mode)' - the exact post-merge error of #2269/#2292). For every ks
  whose EFFECTIVE postBuild (own + parent-injected) is present, every braced
  ${VAR} in the built app manifests must be declared via substitute /
  substituteFrom. Bare $VAR references are reported informationally only:
  Flux's envsubst leaves them untouched (Go-template {{ $labels }} and promql
  in alerting rules pass through in-cluster), while the first undeclared
  braced ${VAR} fails the whole build - the #2269/#2292 signature. ConfigMaps are resolved from the repo; Secret-sourced vars
  cannot be enumerated without cluster keys, so the repo convention applies:
  SECRET_* names are accepted and anything else cluster-side goes in
  flux-substitution-allowlist.txt (same file and convention as the
  ci-flux-substitution-check branch). Resources annotated
  'kustomize.toolkit.fluxcd.io/substitute: disabled' are skipped, exactly
  like Flux does (see the grafana dashboards configMapGenerator).

Failure messages name the failure class and the fix (declare / $$-escape /
add the opt-out label) so the gate is actionable, not just red.

Exit 0 = pass, 1 = failures. --json-report writes machine-readable results.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

OPTOUT_LABEL = "substitution.flux.home.arpa/disabled"
SUBST_DISABLED_ANNOTATION = "kustomize.toolkit.fluxcd.io/substitute"
SECRET_VAR_PREFIX = "SECRET_"
PARENT_KS = Path("kubernetes/flux/apps.yaml")
ALLOWLIST_FILE = Path(".github/scripts/flux-substitution-allowlist.txt")
FLUX_GROUP = "kustomize.toolkit.fluxcd.io"
MAX_REPORT_VARS = 12

# ${VAR} and ${VAR:-default}-style forms. A modifier (:- := :? :+ - = + ?)
# supplies a fallback, so drone/envsubst accepts it even when VAR is unset;
# a bare ${VAR} with no modifier is what strict mode rejects.
RE_BRACED = re.compile(r"(?<!\$)\$\{([A-Za-z_][A-Za-z0-9_]*)([:=+? -][^}]*)?\}")
# $VAR (unbraced). Excludes \\escaped, ${...}, $(cmd), $1/$@ positional.
RE_UNBRACED = re.compile(r"(?<![\w$])\$([A-Za-z_][A-Za-z0-9_]*)")


def log(msg: str) -> None:
    print(msg, flush=True)


def load_docs(text: str) -> list[dict]:
    return [d for d in yaml.safe_load_all(text) if isinstance(d, dict)]


def kustomize_build(path: Path, repo: Path) -> tuple[bool, str]:
    """Build with kustomize, falling back to 'kubectl kustomize'."""
    for cmd in (["kustomize", "build"], ["kubectl", "kustomize"]):
        try:
            r = subprocess.run(cmd + [str(path)], capture_output=True, text=True, timeout=120, cwd=repo)
        except FileNotFoundError:
            continue
        except subprocess.TimeoutExpired:
            return False, "build timed out after 120s"
        if r.returncode == 0:
            return True, r.stdout
        return False, (r.stderr.strip() or r.stdout.strip())[:500]
    return False, "no kustomize/kubectl binary available"


def build_app_dir(app_dir: Path, repo: Path) -> tuple[bool, str]:
    """Build an app dir; for rootless dirs (no kustomization.yaml) synthesize
    an overlay - Flux tolerates rootless paths, the kustomize CLI does not."""
    if (app_dir / "kustomization.yaml").exists() or (app_dir / "kustomization.yml").exists():
        return kustomize_build(app_dir, repo)
    yamls = sorted(p for p in app_dir.iterdir() if p.suffix in (".yaml", ".yml"))
    if not yamls:
        return False, "no kustomization.yaml and no YAML resources in " + str(app_dir)
    scratch = Path(tempfile.mkdtemp(prefix="flux-gate-app-"))
    try:
        names = []
        for p in yamls:
            shutil.copyfile(p, scratch / p.name)
            names.append(p.name)
        (scratch / "kustomization.yaml").write_text(
            yaml.safe_dump({"resources": names}, sort_keys=False)
        )
        return kustomize_build(scratch, repo)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


class KsDoc:
    """One Flux Kustomization document from a ks.yaml file."""

    def __init__(self, ks_file: Path, doc: dict):
        self.ks_file = ks_file
        meta = doc.get("metadata") or {}
        self.name = meta.get("name") or ks_file.parent.name
        spec = doc.get("spec") or {}
        self.path = (spec.get("path") or "").lstrip("./")
        labels = meta.get("labels") or {}
        self.optout = str(labels.get(OPTOUT_LABEL, "")).lower() == "true"
        self.own_postbuild = spec.get("postBuild")
        self.app_root = ks_file.parent

    @property
    def id(self) -> str:
        return str(self.ks_file.parent.relative_to(self.ks_file.parent.parents[3])) + "/" + self.name


def discover_ks(repo: Path) -> list[KsDoc]:
    docs = []
    for ks_file in sorted((repo / "kubernetes" / "apps").rglob("ks.yaml")):
        for d in load_docs(ks_file.read_text()):
            if str(d.get("apiVersion", "")).startswith(FLUX_GROUP) and d.get("kind") == "Kustomization":
                docs.append(KsDoc(ks_file, d))
    return docs


def changed_files(repo: Path, base: str) -> tuple[list[str], str | None]:
    try:
        r = subprocess.run(["git", "merge-base", base, "HEAD"], capture_output=True, text=True, cwd=repo, check=True)
        sha = r.stdout.strip()
        r = subprocess.run(["git", "diff", "--name-only", sha, "HEAD"], capture_output=True, text=True, cwd=repo, check=True)
        return [l for l in r.stdout.splitlines() if l.strip()], None
    except subprocess.CalledProcessError as e:
        return [], "git diff failed (" + (e.stderr.strip() if e.stderr else str(e)) + "); validating everything"


def select_ks(all_docs: list[KsDoc], repo: Path, changed: list[str]) -> tuple[list[KsDoc], str]:
    """Map changed files to affected ks docs. Namespace-level files select the
    whole namespace; kubernetes/flux or CI changes select everything."""
    if any(c.startswith("kubernetes/flux/") or c.startswith(".github/") for c in changed):
        return all_docs, "kubernetes/flux or CI files changed - validating all Kustomizations"
    selected: dict[int, KsDoc] = {}
    ns_wide: set[str] = set()
    for c in changed:
        if not c.startswith("kubernetes/apps/"):
            continue
        matched = False
        for i, d in enumerate(all_docs):
            rel = str(d.app_root.relative_to(repo))
            if c.startswith(rel + "/") or c == rel + "/ks.yaml":
                selected[i] = d
                matched = True
        if not matched:
            parts = Path(c).parts
            if len(parts) >= 3:
                ns_wide.add(parts[2])  # namespace-level file (ns kustomization, namespace.yaml, ...)
    for i, d in enumerate(all_docs):
        if i not in selected:
            rel = str(d.app_root.relative_to(repo))
            parts = Path(rel).parts
            if len(parts) >= 4 and parts[2] in ns_wide:
                selected[i] = d
    docs = [all_docs[i] for i in sorted(selected)]
    if changed and not docs:
        return all_docs, "changed files matched no app dir - validating all Kustomizations"
    return docs, ""


def parent_injection_patches(repo: Path) -> tuple[list[dict], str | None]:
    """Extract the substitution/decryption injection patch verbatim from the
    parent Kustomization (kubernetes/flux/apps.yaml). Extracted dynamically so
    the gate always tracks the real parent, never a stale copy."""
    f = repo / PARENT_KS
    if not f.exists():
        return [], str(PARENT_KS) + " not found - cannot replicate the parent pipeline"
    patches = []
    for d in load_docs(f.read_text()):
        for p in (d.get("spec") or {}).get("patches") or []:
            t = p.get("target") or {}
            body = p.get("patch") or ""
            if t.get("kind") == "Kustomization" and t.get("group") == FLUX_GROUP and OPTOUT_LABEL in (t.get("labelSelector") or ""):
                patches.append({"patch": body, "target": t})
    if not patches:
        return [], "no injection patch with the " + OPTOUT_LABEL + " selector in " + str(PARENT_KS) + " - gate needs updating"
    return patches, None


def patched_ks_build(ks_file: Path, patches: list[dict], repo: Path) -> tuple[dict[str, dict], str | None]:
    """Copy the ks into a scratch overlay, apply the parent patch verbatim,
    build, return output docs keyed by metadata.name."""
    scratch = Path(tempfile.mkdtemp(prefix="flux-gate-ks-"))
    try:
        shutil.copyfile(ks_file, scratch / "ks.yaml")
        (scratch / "kustomization.yaml").write_text(
            yaml.safe_dump(
                {
                    "apiVersion": "kustomize.config.k8s.io/v1beta1",
                    "kind": "Kustomization",
                    "resources": ["ks.yaml"],
                    "patches": patches,
                },
                sort_keys=False,
            )
        )
        ok, out = kustomize_build(scratch, repo)
        if not ok:
            return {}, out
        return {((d.get("metadata") or {}).get("name")): d for d in load_docs(out)}, None
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


class VarSources:
    def __init__(self, repo: Path):
        self.repo = repo
        self.allow = set()
        al = repo / ALLOWLIST_FILE
        if not al.exists():
            # allowlist travels with the script, so --repo worktrees of older
            # revisions (before/after proofs) still resolve it
            al = Path(__file__).resolve().parent / ALLOWLIST_FILE.name
        if al.exists():
            for line in al.read_text().splitlines():
                line = line.strip()
                if line and not line.startswith("#"):
                    self.allow.add(line)
        self._cm_cache: dict[str, set[str]] | None = None
        self._sec_cache: dict[str, set[str] | None] = {}

    def _configmaps(self) -> dict[str, set[str]]:
        if self._cm_cache is not None:
            return self._cm_cache
        cache: dict[str, set[str]] = {}
        for f in (self.repo / "kubernetes").rglob("*.yaml"):
            try:
                for d in load_docs(f.read_text()):
                    if d.get("kind") == "ConfigMap":
                        name = (d.get("metadata") or {}).get("name")
                        if name:
                            cache.setdefault(name, set()).update((d.get("data") or {}).keys())
            except yaml.YAMLError:
                continue
        self._cm_cache = cache
        return cache

    def _secret_keys(self, name: str) -> set[str] | None:
        if name in self._sec_cache:
            return self._sec_cache[name]
        result = None
        for cand in (self.repo / "kubernetes" / "flux" / "vars").glob(name + "*.yaml"):
            try:
                r = subprocess.run(["sops", "-d", str(cand)], capture_output=True, text=True, timeout=30)
            except FileNotFoundError:
                break
            if r.returncode == 0:
                keys = set()
                for d in load_docs(r.stdout):
                    keys.update(set((d.get("data") or {}).keys()) | set((d.get("stringData") or {}).keys()))
                result = keys
                break
        self._sec_cache[name] = result
        return result

    def substitute_from_vars(self, entries: list[dict]) -> set[str]:
        found = set()
        for e in entries or []:
            kind, name = e.get("kind"), e.get("name")
            optional = bool(e.get("optional"))
            if kind == "ConfigMap":
                keys = self._configmaps().get(name)
                if keys:
                    found |= keys
                elif not optional:
                    global_notes.add("ConfigMap " + name + " not found in repo (cluster-only?)")
            elif kind == "Secret":
                got = self._secret_keys(name)
                if got:
                    found |= got
                elif not optional:
                    global_notes.add("Secret " + name + " not decryptable in CI - vars must follow the " + SECRET_VAR_PREFIX + "* convention or the allowlist")
        return found

    def is_accepted(self, var: str) -> bool:
        return var.startswith(SECRET_VAR_PREFIX) or var in self.allow


global_notes: set[str] = set()


def scan_doc_text(text: str) -> tuple[set[str], set[str]]:
    braced, unbraced = set(), set()
    for m in RE_BRACED.finditer(text):
        if not m.group(2):  # no modifier -> strict-mode failure when undefined
            braced.add(m.group(1))
    for m in RE_UNBRACED.finditer(text):
        unbraced.add(m.group(1))
    unbraced -= braced
    return braced, unbraced


def split_doc_texts(built: str) -> list[tuple[dict | None, str]]:
    out = []
    for chunk in re.split(r"(?m)^---\s*$", built):
        if not chunk.strip():
            continue
        try:
            doc = yaml.safe_load(chunk)
        except yaml.YAMLError:
            doc = None
        out.append((doc if isinstance(doc, dict) else None, chunk))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Flux manifest validation gate (see module docstring)")
    ap.add_argument("--repo", default=".", help="repo root (default: cwd)")
    ap.add_argument("--base", help="base ref for changed-file selection (PR mode)")
    ap.add_argument("--all", action="store_true", help="validate every Kustomization")
    ap.add_argument("--only", help="restrict to ks whose id or path contains this substring")
    ap.add_argument("--json-report", help="write machine-readable results to this file")
    args = ap.parse_args()

    repo = Path(args.repo).resolve()
    results: list[dict] = []

    def record(layer: str, status: str, app: str, detail: str) -> None:
        results.append({"layer": layer, "status": status, "app": app, "detail": detail})
        log(layer + " " + status.ljust(4) + " " + app + ": " + detail)

    all_docs = discover_ks(repo)
    log("discovered " + str(len(all_docs)) + " Flux Kustomization docs under kubernetes/apps")

    docs = all_docs
    if not args.all:
        if args.base:
            changed, err = changed_files(repo, args.base)
            if err:
                log("WARN: " + err)
            if changed:
                log("changed files vs " + args.base + ":")
                for c in changed[:40]:
                    log("  " + c)
            docs, why = select_ks(all_docs, repo, changed)
            if why:
                log("NOTE: " + why)
        else:
            log("no --base and no --all given: validating everything")
    if args.only:
        docs = [d for d in docs if args.only in d.id or args.only in str(d.ks_file)]
    names = ", ".join(d.id for d in docs[:10]) + (" ..." if len(docs) > 10 else "")
    log("validating " + str(len(docs)) + " Kustomization(s): " + names)

    patches, perr = parent_injection_patches(repo)
    if perr:
        record("L2", "FAIL", "cluster-apps", perr)
    sources = VarSources(repo)

    for d in docs:
        # ---- LAYER 1: plain build of the app dir ----
        if not d.path:
            record("L1", "WARN", d.id, "ks has no spec.path - skipped")
            continue
        app_dir = repo / d.path
        if not app_dir.is_dir():
            record("L1", "FAIL", d.id, "spec.path " + d.path + " does not exist")
            continue
        ok, built = build_app_dir(app_dir, repo)
        if not ok:
            record("L1", "FAIL", d.id, "plain kustomize build of " + d.path + " failed: " + built)
            continue
        record("L1", "OK", d.id, "built " + d.path)

        # ---- LAYER 2: parent-patched build of the ks ----
        eff_pb = d.own_postbuild
        if patches:
            outdocs, err = patched_ks_build(d.ks_file, patches, repo)
            if err:
                record("L2", "FAIL", d.id, "parent-patched build failed: " + err)
                continue
            od = outdocs.get(d.name) or {}
            ospec = od.get("spec") or {}
            eff_pb = ospec.get("postBuild")
            injected = eff_pb is not None and d.own_postbuild is None
            if d.optout:
                if injected:
                    record("L2", "FAIL", d.id, "opt-out label set but the parent patch still injected postBuild - selector no longer matches expectations (gate/parent drift)")
                    continue
                if d.own_postbuild is not None:
                    record("L2", "OK", d.id, "opted out of injection; own postBuild still effective (Flux semantics)")
                else:
                    record("L2", "OK", d.id, "opted out - no postBuild injected")
            else:
                if eff_pb is None:
                    record("L2", "FAIL", d.id, "no opt-out and no effective postBuild - injection replication failed; gate does not match the real pipeline")
                    continue
                record("L2", "OK", d.id, "postBuild effective" + (" (parent-injected)" if injected else " (own)"))
        else:
            record("L2", "WARN", d.id, "parent patch unavailable - L3 checks own postBuild only")

        # ---- LAYER 3: strict envsubst over the built manifests ----
        if eff_pb is None:
            record("L3", "OK", d.id, "no effective postBuild - Flux does not substitute this app")
            continue
        eff_sub = (eff_pb.get("substitute") or (d.own_postbuild or {}).get("substitute") or {})
        declared = set(eff_sub)
        declared |= sources.substitute_from_vars(eff_pb.get("substituteFrom") or [])
        undef_b, undef_u = set(), set()
        for doc, chunk in split_doc_texts(built):
            ann = ((doc or {}).get("metadata") or {}).get("annotations") or {}
            if ann.get(SUBST_DISABLED_ANNOTATION) == "disabled":
                continue
            b, u = scan_doc_text(chunk)
            undef_b |= b
            undef_u |= u
        bad = {v for v in undef_b if v not in declared and not sources.is_accepted(v)}
        warn_u = {v for v in undef_u if v not in declared and not sources.is_accepted(v)}
        if bad:
            sample = ", ".join(sorted(bad)[:MAX_REPORT_VARS])
            extra = " (+" + str(len(bad) - MAX_REPORT_VARS) + " more)" if len(bad) > MAX_REPORT_VARS else ""
            if d.own_postbuild is not None:
                hint = "#2269 class: this ks declares postBuild, so Flux strict-envsubst the built manifests - declare the vars, $$-escape them, or drop postBuild"
            else:
                hint = "#2292 class: the parent kustomize (kubernetes/flux/apps.yaml) injects postBuild into every ks without the opt-out label - add label " + OPTOUT_LABEL + ": 'true' to metadata.labels, declare the vars, or $$-escape them"
            record("L3", "FAIL", d.id, "undefined braced variable(s): " + sample + extra + ". " + hint)
        else:
            detail = "all '${VAR} references declared (" + str(len(declared)) + " known vars)"
            if warn_u:
                detail += "; unbraced (informational, Flux passes these through): " + ", ".join(sorted(warn_u)[:MAX_REPORT_VARS])
            record("L3", "OK", d.id, detail)

    for n in sorted(global_notes):
        log("WARN (global): " + n)

    failures = sum(1 for r in results if r["status"] == "FAIL")
    warnings = sum(1 for r in results if r["status"] == "WARN") + len(global_notes)
    log("")
    log("=" * 72)
    log("RESULT: " + ("FAIL" if failures else "PASS") + " - " + str(len(docs)) + " ks validated, " + str(failures) + " failure(s), " + str(warnings) + " warning(s)")
    if args.json_report:
        Path(args.json_report).write_text(json.dumps(
            {"ok": failures == 0, "validated": len(docs), "failures": failures,
             "warnings": warnings, "results": results}, indent=2))
        log("json report: " + args.json_report)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
