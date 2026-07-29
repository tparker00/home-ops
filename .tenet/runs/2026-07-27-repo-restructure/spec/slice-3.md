# Slice 3: Cleanup & Consolidation

## Goal

Remove unused components and clean up empty directories to reduce technical debt and simplify the repository structure.

## Changes

### 1. Remove unused components

- **`kubernetes/components/gpu/`** — Both `intel/` and `nvidia/` subcomponents are unused:
  - `gpu/intel/` has a dangling `dependsOn` reference to `intel-gpu-resource-driver` (deleted in slice 1)
  - `gpu/nvidia/` has a dangling `dependsOn` reference to `nvidia-gpu-resource-driver` (never deployed)
  - No apps reference `components/gpu` in their kustomization.yaml

- **`kubernetes/components/replacements/`** — The `ks.yaml` replacement rule (apply `targetNamespace` to Flux Kustomizations) is not referenced by any app kustomization

### 2. Clean up empty directories

- **`kubernetes/flux/repositories/git/`** — Empty directory left over from central registry removal. The `kubernetes/flux/repositories/kustomization.yaml` references it via `./git` and should be updated.

### 3. Preserved (no changes)

- **`kubernetes/components/moosefs/`** and **`kubernetes/components/moosefs2/`** — Kept as-is for the rare case of needing 2x named PVCs for apps (currently 1 instance uses this pattern)
- **`kubernetes/bootstrap/`** — Leave untouched

## Verification

- `kubeconform` passes on full `kubernetes/` tree
- `flate test` passes (all Kustomizations buildable)
- No dangling references to removed components in any app kustomization.yaml
