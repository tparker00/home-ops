# Iron Laws: YAML Language Server Schema Audit

## Rules

1. **Zero-diff**: Only comment changes allowed. No functional changes to any manifests.
2. **Standard source**: All Kubernetes CRD schemas use `https://kubernetes-schemas.pages.dev`
3. **Kustomization schema**: All kustomization.yaml files use `https://json.schemastore.org/kustomization`
4. **No raw GitHub for CRDs**: Replace raw GitHub URLs with `kubernetes-schemas.pages.dev` where schemas are available
5. **Keep raw GitHub for upstream CRDs**: Raw GitHub URLs are OK for upstream CRD YAML files (cloudnative-pg, talhelper, etc.) that aren't mirrored
6. **Current API versions only**: No v2beta2, v2beta1, etc. Use stable API versions (v2 for HelmRelease, v1 for Kustomization, etc.)
7. **kubeconform must pass**: `kubeconform -strict` must exit 0 after changes
