# Feature: YAML Language Server Schema Audit

## Goal

Standardize all `# yaml-language-server: $schema=...` references across kubernetes/ to use consistent, reliable schema sources. Zero-diff: only comment changes, no functional impact.

## Scope

- Audit all 300+ schema references in kubernetes/
- Update broken/outdated schema URLs
- Standardize on `kubernetes-schemas.pages.dev` for Kubernetes CRD schemas
- Standardize on `json.schemastore.org` for kustomization schemas
- Replace raw GitHub URLs with stable schema sources where possible

## Acceptance Criteria

1. All `helmrelease_v2beta2` references updated to `helmrelease_v2`
2. All kustomization schemas use `json.schemastore.org/kustomization`
3. All Kubernetes CRD schemas use `kubernetes-schemas.pages.dev` (not kube-schemas, lds-schemas, ok8.sh, or ajgon.casa)
4. Raw GitHub URLs replaced with stable schema sources where possible
5. No functional changes to any manifests

## Files to Update

### Outdated v2beta2 → v2 (48 references)
- All helmrelease.yaml files using `helmrelease_v2beta2.json`
- All helmrelease schemas from `bjw-s/helm-charts` and `fluxcd-community/flux2-schemas`

### Domain standardization (93 references)
- `kube-schemas.pages.dev` → `kubernetes-schemas.pages.dev`
- `lds-schemas.pages.dev` → `kubernetes-schemas.pages.dev`
- `kubernetes-schemas.ok8.sh` → `kubernetes-schemas.pages.dev`
- `schemas.ajgon.casa` → `kubernetes-schemas.pages.dev` (where available)
- `www.schemastore.org` → `json.schemastore.org`

### Raw GitHub URLs (40 references)
- Replace `raw.githubusercontent.com` URLs with `kubernetes-schemas.pages.dev` where schemas are available
- Keep raw GitHub URLs only for schemas not mirrored (talhelper, cloudnative-pg CRDs, etc.)

## Guardrails

- Zero-diff requirement: only comment changes
- No functional changes to any manifests
- Verify kubeconform passes after changes
