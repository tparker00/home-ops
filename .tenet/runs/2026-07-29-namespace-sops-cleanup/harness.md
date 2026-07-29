# Iron Laws: Namespace/SOPS Cleanup

## Rules

1. **Zero-diff**: Only namespace label/annotation changes allowed. No functional changes to any manifests.
2. **Tenant namespaces**: All tenant namespaces must have `pod-security.kubernetes.io/enforce: restricted`
3. **Infra namespaces**: All infra namespaces must have `pod-security.kubernetes.io/enforce: privileged`
4. **Prune label**: `kustomize.toolkit.fluxcd.io/prune: disabled` must be a label, not an annotation
5. **No SOPS duplication**: apps.yaml patch propagates SOPS decryption; no per-namespace SOPS config needed
6. **kubeconform must pass**: `kubeconform -strict` must exit 0 after changes
