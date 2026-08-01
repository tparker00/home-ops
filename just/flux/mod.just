# Former .taskfiles/Flux/ — Flux bootstrap & reconciliation.
set quiet

root := justfile_directory()
kubernetes_dir := root / "kubernetes"
kubeconfig := root / "kubeconfig"
age_file := root / "age.key"
cluster_secret_sops_file := kubernetes_dir / "flux" / "vars" / "cluster-secrets.sops.yaml"
cluster_settings_file := kubernetes_dir / "flux" / "vars" / "cluster-settings.yaml"
github_deploy_key_file := kubernetes_dir / "bootstrap" / "flux" / "github-deploy-key.sops.yaml"

# Bootstrap Flux into the cluster (port of: task flux:bootstrap)
[group('flux')]
bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f "{{ kubeconfig }}" || { echo "Missing kubeconfig"; exit 1; }
    test -f "{{ age_file }}"   || { echo "Missing Sops Age key file"; exit 1; }
    kubectl apply --kubeconfig "{{ kubeconfig }}" --server-side --kustomize "{{ kubernetes_dir }}/bootstrap/flux"
    if ! kubectl --kubeconfig "{{ kubeconfig }}" -n flux-system get secret sops-age >/dev/null 2>&1; then
        cat "{{ age_file }}" | kubectl --kubeconfig "{{ kubeconfig }}" -n flux-system create secret generic sops-age --from-file=age.agekey=/dev/stdin
    else
        echo "sops-age secret already exists, skipping creation."
    fi
    sops --decrypt "{{ cluster_secret_sops_file }}" | kubectl apply --kubeconfig "{{ kubeconfig }}" --server-side --filename -
    kubectl apply --kubeconfig "{{ kubeconfig }}" --server-side --filename "{{ cluster_settings_file }}"
    kubectl apply --kubeconfig "{{ kubeconfig }}" --server-side --kustomize "{{ kubernetes_dir }}/flux/config"

# Apply a Flux Kustomization for an app path (port of: task flux:apply)
[group('flux')]
apply path ns="flux-system":
    #!/usr/bin/env bash
    set -euo pipefail
    test -f "{{ kubeconfig }}"                       || { echo "Missing kubeconfig"; exit 1; }
    test -f "{{ kubernetes_dir }}/apps/{{ path }}/ks.yaml" || { echo "Missing Flux Kustomization for app {{ path }}"; exit 1; }
    ks="$(flux --kubeconfig "{{ kubeconfig }}" --namespace {{ ns }} get kustomizations "$(basename {{ path }})" 2>&1 || true)"
    extra=""
    echo "$ks" | grep -q "not found" && extra="--dry-run"
    flux --kubeconfig "{{ kubeconfig }}" build ks "$(basename {{ path }})" \
        --namespace {{ ns }} \
        --kustomization-file "{{ kubernetes_dir }}/apps/{{ path }}/ks.yaml" \
        --path "{{ kubernetes_dir }}/apps/{{ path }}" \
        $extra \
        | kubectl apply --kubeconfig "{{ kubeconfig }}" --server-side --field-manager=kustomize-controller -f -

# Force Flux to pull changes from Git (port of: task flux:reconcile)
[group('flux')]
reconcile:
    test -f {{ kubeconfig }} || { echo "Missing kubeconfig"; exit 1; }
    flux --kubeconfig {{ kubeconfig }} reconcile --namespace flux-system kustomization cluster --with-source

# Apply the GitHub deploy key (port of: task flux:github-deploy-key)
[group('flux')]
github-deploy-key:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f "{{ kubeconfig }}"           || { echo "Missing kubeconfig"; exit 1; }
    test -f "{{ age_file }}"             || { echo "Missing Sops Age key file"; exit 1; }
    test -f "{{ github_deploy_key_file }}" || { echo "Missing Github deploy key file"; exit 1; }
    kubectl create namespace flux-system --dry-run=client -o yaml | kubectl --kubeconfig "{{ kubeconfig }}" apply --filename -
    sops --decrypt "{{ github_deploy_key_file }}" | kubectl apply --kubeconfig "{{ kubeconfig }}" --server-side --filename -
