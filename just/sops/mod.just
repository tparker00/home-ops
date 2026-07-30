# Former .taskfiles/Sops/ — Age key + SOPS encryption.
set quiet

root := justfile_directory()
kubernetes_dir := root / "kubernetes"
age_file := root / "age.key"
sops_config := root / ".sops.yaml"

# Initialize Age Key for Sops (port of: task sops:age-keygen)
[group('sops')]
age-keygen:
    test -f {{ age_file }} || age-keygen --output {{ age_file }}

# Encrypt all Kubernetes SOPS secrets (port of: task sops:encrypt)
[group('sops')]
encrypt:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f {{ sops_config }} || { echo "Missing Sops config file"; exit 1; }
    test -f {{ age_file }}   || { echo "Missing Sops Age key file"; exit 1; }
    while IFS= read -r -d '' f; do
        sops --encrypt --in-place "$f"
    done < <(find "{{ kubernetes_dir }}" -type f -name "*.sops.*" -exec grep -L "ENC\[AES256_GCM" {} \; -print0)

# internal: drop the SOPS config (port of: task sops:.reset)
[private]
_reset:
    rm -rf {{ sops_config }}
