# Decomposition: Cluster Split

## Slice 1: Pod-Security Restricted on Tenant Namespaces

### slice-1-ci-cleanup
- Remove `.github/workflows/e2e.yaml` (never ran in this fork: guard `github.repository == onedr0p/cluster-template` fails, paths-ignore: kubernetes/** makes it vestigial)
- Remove stale Taskfile reference in `.taskfiles/Repository/Taskfile.yaml`
- Acceptance: no dangling references to e2e.yaml; kubeconform passes

### slice-1-pod-security
- Add `pod-security.kubernetes.io/audit: restricted`, `enforce: restricted`, `warn: restricted` to tenant namespace manifests
- Files to edit:
  - Hand-written: kubernetes/apps/{default,downloads,media,database,security,external-secrets}/namespace.yaml
  - Templated (edit BOTH rendered AND .j2): kubernetes/apps/cert-manager/namespace.yaml + bootstrap/templates/kubernetes/apps/cert-manager/namespace.yaml.j2 ; kubernetes/apps/flux-system/namespace.yaml + bootstrap/templates/kubernetes/apps/flux-system/namespace.yaml.j2
- Do NOT touch: kube-system, network, storage, openebs-system, system-upgrade, talos, observability, kyverno
- system-upgrade already has restricted — leave it
- Acceptance: grep confirms all 3 labels on all 8 files; kubeconform exits 0

## Slice 2: Kubernetes Structural Patterns (COMPLETED)
- Per-app HelmRepository resources replacing central registries
- Remove namespace component, move alerts to flux-system
- Add flate manifest diff step

## Slice 3: Cleanup & Consolidation (COMPLETED)
- Remove `kubernetes/components/gpu/` (unused, dangling dependsOn references)
- Remove `kubernetes/components/replacements/` (unreferenced)
- Clean up empty `kubernetes/flux/repositories/git/` directory
- Acceptance: kubeconform passes, no dangling references

## Slice 4: TBD
- To be defined after reviewing remaining technical debt
