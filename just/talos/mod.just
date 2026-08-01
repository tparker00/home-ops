# Former .taskfiles/Talos/ — Talos lifecycle (talhelper, unchanged in Phase 1).
set quiet

root := justfile_directory()
kubernetes_dir := root / "kubernetes"
talos_dir := kubernetes_dir / "bootstrap" / "talos"
cluster_dir := talos_dir / "clusterconfig"
secret_file := talos_dir / "talsecret.sops.yaml"
config_file := talos_dir / "talconfig.yaml"
helmfile_file := kubernetes_dir / "bootstrap" / "helmfile.yaml"
talosconfig := cluster_dir / "talosconfig"
kubeconfig := root / "kubeconfig"
sops_config := root / ".sops.yaml"
age_file := root / "age.key"

# Bootstrap the Talos cluster (port of: task talos:bootstrap)
[group('talos')]
bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ talos_dir }}"
    test -f "{{ config_file }}" || { echo "Missing talhelper config file"; exit 1; }
    test -f "{{ sops_config }}" || { echo "Missing Sops config file"; exit 1; }
    test -f "{{ age_file }}"    || { echo "Missing Sops Age key file"; exit 1; }
    if [ ! -f "{{ secret_file }}" ]; then
        talhelper gensecret > "{{ secret_file }}"
        sops --encrypt --in-place "{{ secret_file }}"
    fi
    talhelper genconfig --config-file "{{ config_file }}" --secret-file "{{ secret_file }}" --out-dir "{{ cluster_dir }}"
    talhelper gencommand apply  --config-file "{{ config_file }}" --out-dir "{{ cluster_dir }}" --extra-flags="--insecure" | bash
    until talhelper gencommand bootstrap --config-file "{{ config_file }}" --out-dir "{{ cluster_dir }}" | bash; do sleep 10; done
    just talos fetch-kubeconfig
    just talos install-helm-apps
    talosctl health --server=false

# Fetch kubeconfig (port of: task talos:fetch-kubeconfig)
[group('talos')]
fetch-kubeconfig:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ talos_dir }}"
    test -f "{{ config_file }}" || { echo "Missing talhelper config file"; exit 1; }
    until talhelper gencommand kubeconfig --config-file "{{ config_file }}" --out-dir "{{ cluster_dir }}" --extra-flags="{{ root }} --force" | bash; do sleep 10; done

# Bootstrap core apps needed for Talos (port of: task talos:install-helm-apps)
[group('talos')]
install-helm-apps:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ talos_dir }}"
    test -f "{{ kubeconfig }}"   || { echo "Missing kubeconfig"; exit 1; }
    test -f "{{ helmfile_file }}" || { echo "Missing helmfile"; exit 1; }
    until kubectl --kubeconfig "{{ kubeconfig }}" wait --for=condition=Ready=False nodes --all --timeout=600s; do sleep 10; done
    helmfile --kubeconfig "{{ kubeconfig }}" --file "{{ helmfile_file }}" apply --skip-diff-on-install --suppress-diff
    until kubectl --kubeconfig "{{ kubeconfig }}" wait --for=condition=Ready nodes --all --timeout=600s; do sleep 10; done

# Upgrade Talos on a node (port of: task talos:upgrade)
[group('talos')]
upgrade node image mode="default":
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ talos_dir }}"
    test -f "{{ talosconfig }}"       || { echo "Missing talosconfig"; exit 1; }
    talosctl config info >/dev/null 2>&1 || { echo "Unable to retrieve Talos config"; exit 1; }
    talosctl --nodes {{ node }} get machineconfig >/dev/null 2>&1 || { echo "Node not found"; exit 1; }
    talosctl --nodes {{ node }} upgrade --image {{ image }} --wait=true --timeout=10m --preserve=true --reboot-mode={{ mode }}
    talosctl --nodes {{ node }} health --wait-timeout=10m --server=false

# Upgrade Kubernetes across the cluster (port of: task talos:upgrade-k8s)
[group('talos')]
upgrade-k8s controller to:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ talos_dir }}"
    test -f "{{ talosconfig }}"       || { echo "Missing talosconfig"; exit 1; }
    talosctl config info >/dev/null 2>&1 || { echo "Unable to retrieve Talos config"; exit 1; }
    talosctl --nodes {{ controller }} get machineconfig >/dev/null 2>&1 || { echo "Node not found"; exit 1; }
    talosctl --nodes {{ controller }} upgrade-k8s --to {{ to }}

# Reset nodes back to maintenance mode (port of: task talos:nuke)
[group('talos')]
nuke force="false":
    #!/usr/bin/env bash
    set -euo pipefail
    read -r -p "This will destroy your cluster and reset the nodes back to maintenance mode... continue? [y/N] " ans
    [ "$ans" = "y" ] || { echo "aborted"; exit 1; }
    cd "{{ talos_dir }}"
    extra="--reboot"
    [ "{{ force }}" = "true" ] || extra="$extra --system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL"
    talhelper gencommand reset --config-file "{{ config_file }}" --out-dir "{{ cluster_dir }}" --extra-flags="$extra --graceful=false --wait=false" | bash

# internal: drop generated Talos artifacts (port of: task talos:.reset)
[private]
_reset:
    rm -rf {{ cluster_dir }} {{ secret_file }} {{ config_file }}
