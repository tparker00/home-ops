# Harness: Cluster Split

## Iron Laws

1. Deliver in phased slices. Each phase/slice MUST be its own branch with its own distinct PR.
2. Always create branches from a FRESH main (`git checkout main && git pull` before branching).
3. NEVER push directly to main. NEVER approve your own PRs — the user reviews and merges.
4. Do not bundle multiple slices into one PR.
5. You are on a slice branch created by the orchestrator — commit ONLY on the current branch.
6. Stage specific paths (avoid `git add -A`). Do not stage `.tenet/`.
7. Include the commit SHA in your final output.

## Acceptance Criteria

### Per-Slice
- `kubeconform -strict` passes on `kubernetes/` tree
- No dangling references to removed/renamed files
- All modified namespace manifests validate
- Git diff is clean (no unexpected changes)

### Slice-Specific
See `decomposition.md` for slice-specific acceptance criteria.

## Model Tier

local — follow instructions precisely. Do not guess or improvise.
