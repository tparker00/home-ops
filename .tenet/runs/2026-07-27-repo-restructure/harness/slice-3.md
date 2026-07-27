# Slice 3: Harness

## Testable Surfaces

### Surface 1: Remove `kubernetes/components/gpu/`

**Precondition:** No app kustomization references `components/gpu`

**Test:**
```bash
# Verify no references to gpu component
grep -r "components/gpu" kubernetes/apps/ --include="kustomization.yaml" | wc -l
# Expected: 0

# Verify no dangling references to deleted GPU drivers
grep -r "intel-gpu-resource-driver\|nvidia-gpu-resource-driver" kubernetes/apps/ --include="*.yaml" | wc -l
# Expected: 0
```

**Action:** Delete `kubernetes/components/gpu/` directory

### Surface 2: Remove `kubernetes/components/replacements/`

**Precondition:** No app kustomization references `components/replacements`

**Test:**
```bash
# Verify no references to replacements component
grep -r "components/replacements" kubernetes/apps/ --include="kustomization.yaml" | wc -l
# Expected: 0
```

**Action:** Delete `kubernetes/components/replacements/` directory

### Surface 3: Clean up `kubernetes/flux/repositories/`

**Precondition:** `kubernetes/flux/repositories/git/` is empty

**Test:**
```bash
# Verify git directory is empty
ls kubernetes/flux/repositories/git/ | wc -l
# Expected: 0

# Check that repositories/kustomization.yaml references ./git
grep -c "./git" kubernetes/flux/repositories/kustomization.yaml
# Expected: 1 (before fix)
```

**Action:** 
- Remove `./git` reference from `kubernetes/flux/repositories/kustomization.yaml`
- Delete `kubernetes/flux/repositories/git/` directory

### Surface 4: Verify kubeconform

**Test:**
```bash
kubeconform -strict kubernetes/
# Expected: 0 errors
```

### Surface 5: Verify flate test

**Test:**
```bash
flate test
# Expected: all pass
```
