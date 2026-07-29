# Feature: Namespace/SOPS Cleanup

## Goal

Fix namespace label inconsistencies and ensure pod-security labels are correctly applied to all namespaces. Zero-diff: only label/annotation changes, no functional impact.

## Scope

- Fix system-upgrade namespace (prune label, pod-security privileged)
- Add pod-security labels to downloads namespace
- Add pod-security privileged labels to infra namespaces
- Verify no duplicate SOPS decryption config

## Acceptance Criteria

1. All tenant namespaces have pod-security `restricted` labels
2. All infra namespaces have pod-security `privileged` labels
3. system-upgrade namespace has `prune: disabled` as label (not annotation)
4. No duplicate SOPS decryption config in namespace kustomizations
5. No functional changes to any manifests

## Guardrails

- Pod security: restricted on tenant namespaces, privileged on infra (kube-system, kyverno, network, observability, openebs-system, storage, talos, system-upgrade)
- Zero-diff requirement: only label/annotation changes
- kubeconform must pass after changes
