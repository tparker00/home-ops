# Former .taskfiles/Kubernetes/ — cluster manifest validation & introspection.
set quiet

root := justfile_directory()
kubernetes_dir := root / "kubernetes"
kubeconfig := root / "kubeconfig"

# Validate Kubernetes manifests with kubeconform (port of: task kubernetes:kubeconform)
[group('kubernetes')]
kubeconform:
    bash {{ root / "scripts" / "kubeconform.sh" }} {{ kubernetes_dir }}

# Gather common resources in the cluster (port of: task kubernetes:resources)
[group('kubernetes')]
resources *extra="-A":
    #!/usr/bin/env bash
    set -euo pipefail
    for r in nodes gitrepositories kustomizations helmrepositories helmreleases certificates certificaterequests ingresses pods; do
        kubectl --kubeconfig {{ kubeconfig }} get "$r" {{ extra }} || true
    done

# internal: wipe the rendered kubernetes tree (port of: task kubernetes:.reset)
[private]
_reset:
    rm -rf {{ kubernetes_dir }}
