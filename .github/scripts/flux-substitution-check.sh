#!/usr/bin/env bash
# flux-substitution-check: fail on ${VAR} placeholders that Flux post-build
# envsubst (strict mode) would reject as undefined.
#
# Motivation: PR #2256 embedded a Grafana dashboard JSON containing
# ${datasource} panel refs; kustomize/CI passed but the grafana Kustomization
# failed at deploy time with:
#   envsubst error: variable substitution failed: variable not set (strict mode)
#
# Defined vars come from kubernetes/flux/vars/* (cluster settings + sops
# secrets, via substitute.from) and inline postBuild.substitute dicts in
# ks.yaml files. Vars that only exist cluster-side go in the allowlist file.
# Resources with the substitute-disabled annotation live in EXCLUDES.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

defined=$(cat \
  <(grep -hA50 -E '^[[:space:]]*(data|stringData):' kubernetes/flux/vars/*.yaml 2>/dev/null \
    | grep -oE '^ +[A-Za-z_][A-Za-z0-9_]*:') \
  <(grep -rhA100 'substitute:' --include='ks.yaml' kubernetes/ 2>/dev/null \
    | grep -oE '^ +[A-Za-z_][A-Za-z0-9_]*:') \
  | tr -d ' :' | sort -u || true)

script_dir="$(cd "$(dirname "$0")" && pwd)"
ALLOWLIST="$(grep -vE '^#|^$' "$script_dir/flux-substitution-allowlist.txt" 2>/dev/null || true)"

EXCLUDES="kubernetes/apps/observability/grafana-operator/instance/dashboards/media"

fails=0
while IFS= read -r f; do
  rel="${f#./}"
  skip=0
  for e in ${EXCLUDES}; do [[ "$rel" == "$e"* ]] && skip=1; done
  [ "$skip" -eq 1 ] && continue
  vars=$(grep -ohE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$f" 2>/dev/null | tr -d '\$\{\}' | sort -u || true)
  for v in ${vars}; do
    # SECRET_* vars come from the cluster secret store; names not statically verifiable.
    case "$v" in SECRET_*) continue;; esac
    if ! printf '%s\n' "$defined" | grep -qx "$v" && ! printf '%s\n' "$ALLOWLIST" | grep -qx "$v"; then
      echo "FAIL: undefined variable $v (Flux envsubst strict mode would reject): $rel"
      fails=1
    fi
  done
done < <(find kubernetes -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' \))

if [ "$fails" -eq 1 ]; then
  echo "flux-substitution-check: FAILED"
  exit 1
fi
echo "flux-substitution-check: OK (all placeholders defined)"
