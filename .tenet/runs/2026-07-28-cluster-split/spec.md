# Feature: Cluster Split

## Goal

Reduce drift from upstream (onedr0p/cluster-template) in project layout, tooling, and methods. The fork was done a while ago and accumulated patterns that differ from community conventions, making it difficult to add new apps/components without translating between styles.

This is an architectural cleanup — **zero-diff requirement**: what is rendered by Helm/kustomize after changes must match what is currently running on the cluster (aside from disabling/removing old unused apps). No functional changes, no service disruption.

## Phased Approach

Work is delivered in discrete slices. Each slice is its own branch with its own PR. No bundling.

## Completed Slices

### Slice 1: Pod-Security Hardening
- Enforce `pod-security.kubernetes.io/enforce: restricted` on tenant namespaces (cert-manager, database, default, downloads, external-secrets, flux-system, media, security)
- Remove dead e2e CI workflow (never ran in this fork)
- Clean up stale taskfile reference

### Slice 2: Kubernetes Structural Patterns
- Per-app HelmRepository resources replacing central registries
- Remove namespace component, move alerts to flux-system
- Add flate manifest diff step to CI

### Slice 3: Cleanup & Consolidation
- Remove unused `components/gpu/` (intel/nvidia subcomponents, dangling references)
- Remove unused `components/replacements/` (ks.yaml replacement rule, unreferenced)
- Clean up empty `kubernetes/flux/repositories/git/` directory
- Remove `./git` reference from `kubernetes/flux/repositories/kustomization.yaml`

## Pending Slices

TBD — to be defined based on remaining technical debt and operational priorities.

## Guardrails

- Pod security: restricted on tenant namespaces, privileged on infra (kube-system, kyverno, network, observability, openebs-system, storage, talos)
- No direct pushes to main
- No self-approval of PRs
- Each slice = one branch, one PR
