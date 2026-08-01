# Feature: Upstream Alignment (task/bootstrap → just/template)

## Goal

Reduce drift from upstream (`onedr0p/cluster-template`) in the project's
scaffolding layer — the task runner, config format, env/tool management, and
templating engine. The fork was cut from an earlier generation of the template
and still uses `Taskfile`/`bootstrap`/`config.yaml`, while upstream has moved to
`just`/`template`/`cluster.toml` with `mise` for tool management.

This continues the drift-reduction work tracked in
`2026-07-28-cluster-split/spec.md`. The `.lefthook.toml` already anticipates it:
"Slice 4 extends this with just/mise formatting once those tools are adopted."

## Scope boundary

Only the **scaffolding** changes. The fork's value — `kubernetes/apps/**`,
`.tenet/`, `opencode.json` — is untouched. Cluster rendering output is
zero-diff against what currently runs (aside from the Kyverno/Goldilocks/CPU
work already merged in #1962–#1964).

## Divergence summary

| Layer | Fork (now) | Upstream `main` |
|---|---|---|
| Runner | `Taskfile.yaml` + `.taskfiles/*` | `justfile` + `mod.just` modules |
| Config | `config.sample.yaml` | `cluster.sample.toml` (schema-validated, `template-tests/`) |
| Talos gen | `talhelper` | `topf` (postfinance/topf) |
| Env/tools | `.envrc` (direnv) + `.venv` (uv) | `.mise` (mise, pinned) |
| Flux | bootstrap config **+** flux-operator (half-migrated) | flux-operator + flux-instance only |
| Templating | `bootstrap/templates` + `plugin.py` | `template/config/**` engine |

## Phased approach

Each phase is its own branch/PR. Phases are independent and can be scheduled
separately.

### Phase 1: Toolchain & runner (target of this effort)

Adopt `just` + `mise`; delete `Taskfile`/`.taskfiles`/`scripts`/`.envrc`.
**Keep `talhelper` and `config.yaml` for now** — no change to Talos workflow or
config format. Fixes the broken `repository:clean` and `kubernetes:kubeconform`
tasks by porting them to faithful `just` recipes.

- `.mise/config.toml` — port env vars from `.envrc`, pin tools
- `justfile` + `just/{kubernetes,flux,talos,sops,template}/mod.just` — port every task
- delete `Taskfile.yaml`, `.taskfiles/`, `.envrc`, `.devcontainer/`
- keep `scripts/kubeconform.sh` for now (the `just kube kubeconform` recipe calls it verbatim; inlining into the recipe is deferred to Phase 2 to avoid kubeconform Go-template `{{ }}` escaping churn)
- update `.lefthook.toml` — add `format-just`, `mise-lock`; route kubeconform through `just kube kubeconform`
- **Effort:** M · **Risk:** low (no cluster interaction; recipes are 1:1 ports)

### Phase 2: Config format

- author `cluster.toml` from current `config.yaml` values (leverage `template-tests/` fixtures for validation)
- port `bootstrap/templates/**` → `template/config/**`; rename `bootstrap/` → `template/`
- delete `config.yaml`, old `bootstrap/`
- **Effort:** L · **Risk:** medium (one-time re-render; dry-run before prod)

### Phase 3: Talos tooling + Flux finish

- `talhelper` → `topf`: rewrite the `talos` module; regenerate talconfig/talosconfig
- finish Flux migration: drop `flux/config/flux.yaml` bootstrap, go operator-only
- **Effort:** M-L · **Risk:** medium-high (touches running nodes)

## Task → recipe mapping (Phase 1)

| Current `task …` | New `just …` |
|---|---|
| `configure` | `just template configure` |
| `init` | `just template init` |
| `sops:age-keygen` | `just sops age-keygen` |
| `sops:encrypt` | `just sops encrypt` |
| `talos:bootstrap` | `just talos bootstrap` |
| `talos:fetch-kubeconfig` | `just talos fetch-kubeconfig` |
| `talos:install-helm-apps` | `just talos install-helm-apps` |
| `talos:upgrade` | `just talos upgrade node= image=` |
| `talos:upgrade-k8s` | `just talos upgrade-k8s controller= to=` |
| `talos:nuke` | `just talos nuke` |
| `flux:bootstrap` | `just flux bootstrap` |
| `flux:apply` | `just flux apply path= [ns=]` |
| `flux:reconcile` | `just flux reconcile` |
| `flux:github-deploy-key` | `just flux github-deploy-key` |
| `kubernetes:kubeconform` | `just kube kubeconform` |
| `kubernetes:resources` | `just kube resources` |
| `repository:clean` | `just template clean` |
| `repository:reset` | `just template reset` |
| `repository:force-reset` | `just template force-reset` |
| `workstation:*` | **removed** — `mise` installs all tools |

## Guardrails

- Phase 1 recipes are 1:1 ports; commands preserved verbatim, only syntax translated.
- `preconditions` → shell guards at recipe start (just has no native preconditions).
- `status:`/`sources:` skip behavior → shell existence checks where it matters (e.g. age-keygen).
- `prompt:` confirmations → preserved via an explicit read prompt in dangerous recipes (nuke, force-reset).
- No direct pushes to main; one branch, one PR per phase.
- Each phase must leave `just --list` clean and `just kube kubeconform` runnable.
