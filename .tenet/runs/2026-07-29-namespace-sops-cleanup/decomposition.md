# Decomposition: Namespace/SOPS Cleanup

## slice-7-namespace-sops-cleanup

### Fix system-upgrade namespace
- Move `kustomize.toolkit.fluxcd.io/prune: disabled` from annotation to label
- Change `pod-security.kubernetes.io/enforce: restricted` to `privileged` (infra namespace)
- File: kubernetes/apps/system-upgrade/namespace.yaml

### Add pod-security labels to downloads namespace
- Add `pod-security.kubernetes.io/audit: restricted`
- Add `pod-security.kubernetes.io/enforce: restricted`
- Add `pod-security.kubernetes.io/warn: restricted`
- File: kubernetes/apps/downloads/namespace.yaml

### Add pod-security privileged labels to infra namespaces
Files to update:
- kubernetes/apps/kube-system/namespace.yaml
- kubernetes/apps/kyverno/namespace.yaml
- kubernetes/apps/network/namespace.yaml
- kubernetes/apps/observability/namespace.yaml
- kubernetes/apps/openebs-system/namespace.yaml
- kubernetes/apps/storage/namespace.yaml
- kubernetes/apps/talos/namespace.yaml

For each, add:
```yaml
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/warn: privileged
```

### Verify SOPS decryption config
- Confirm apps.yaml patch propagates SOPS decryption to all child Kustomizations
- Confirm no duplicate SOPS decryption config in namespace kustomizations
- No changes expected (already correct)

### Verify namespace templates
- Confirm bootstrap/templates/ namespace.yaml.j2 files match rendered kubernetes/apps/*/namespace.yaml files
- No changes expected (already identical)

### Acceptance
- All tenant namespaces have pod-security `restricted` labels
- All infra namespaces have pod-security `privileged` labels
- system-upgrade namespace has `prune: disabled` as label (not annotation)
- kubeconform passes
- Zero-diff: no functional changes
