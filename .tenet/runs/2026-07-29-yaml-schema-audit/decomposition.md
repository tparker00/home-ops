# Decomposition: YAML Language Server Schema Audit

## slice-yaml-schema-audit

### Priority 1: Fix broken schemas (LSP errors)
- `kube-schemas.pages.dev` schemas returning "No content" → replace with `kubernetes-schemas.pages.dev`
  - Files: kubernetes/apps/network/envoy-gateway/ks.yaml, kubernetes/apps/network/envoy-gateway/app/helmrelease.yaml
- `schemas.budimanjojo.com/kyverno.io/clusterpolicy_v1.json` returning "No content" → replace with `kubernetes-schemas.pages.dev`
  - Files: kubernetes/apps/default/clusterpolicies/app/add-psa-labels.yaml
- `helmrelease_v2beta2.json` returning "Unable to parse content" → update to `helmrelease_v2.json`
  - Files: ~29 helmrelease.yaml files

### Priority 2: Standardize domain (kube-schemas → kubernetes-schemas)
- Replace all `kube-schemas.pages.dev` references with `kubernetes-schemas.pages.dev`
- Files affected: ~39 references across network/, observability/, etc.

### Priority 3: Standardize domain (lds-schemas → kubernetes-schemas)
- Replace all `lds-schemas.pages.dev` references with `kubernetes-schemas.pages.dev`
- Files affected: ~38 references across external-secrets/, storage/, downloads/, default/

### Priority 4: Standardize domain (ok8.sh → kubernetes-schemas)
- Replace `kubernetes-schemas.ok8.sh` references with `kubernetes-schemas.pages.dev`
- Files: kubernetes/apps/database/barman-cloud/ks.yaml, kubernetes/apps/database/cloudnative-pg/clusters/immich/prometheusrule.yaml

### Priority 5: Standardize domain (ajgon.casa → kubernetes-schemas)
- Replace `schemas.ajgon.casa` references with `kubernetes-schemas.pages.dev` where available
- Files: kubernetes/apps/system-upgrade/*, kubernetes/apps/database/meilisearch/app/helmrelease.yaml

### Priority 6: Fix www.schemastore.org → json.schemastore.org
- Replace `www.schemastore.org/kustomization.json` with `json.schemastore.org/kustomization`
- Files: kubernetes/apps/system-upgrade/kustomization.yaml, kubernetes/apps/system-upgrade/upgrades/app/kustomization.yaml, kubernetes/apps/system-upgrade/tuppr/app/kustomization.yaml

### Priority 7: Replace raw GitHub URLs where possible
- Replace `raw.githubusercontent.com/bjw-s/helm-charts/.../helmrelease-helm-v2beta2.schema.json` with `kubernetes-schemas.pages.dev/helm.toolkit.fluxcd.io/helmrelease_v2.json`
- Replace `raw.githubusercontent.com/bjw-s-labs/helm-charts/.../helmrelease-helm-v2.schema.json` with `kubernetes-schemas.pages.dev/helm.toolkit.fluxcd.io/helmrelease_v2.json`
- Replace `raw.githubusercontent.com/fluxcd-community/flux2-schemas/...` with `kubernetes-schemas.pages.dev` equivalents
- Keep raw GitHub URLs only for schemas not mirrored (talhelper, cloudnative-pg CRDs, yannh/kubernetes-json-schema, datreeio/CRDs-catalog)

### Acceptance
- `kubeconform -strict -schema-location default -schema-location 'https://kubernetes-schemas.pages.dev/{{.Group}}/{{.Kind}}_{{.Version}.json' -ignore-mime-type kubernetes/...` passes
- All LSP errors resolved
- No functional changes to any manifests (only comment changes)
