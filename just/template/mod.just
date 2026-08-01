# Former root Taskfile + .taskfiles/Repository/ — config init/render/clean/reset.
set quiet

root := justfile_directory()
bootstrap_dir := root / "bootstrap"
kubernetes_dir := root / "kubernetes"
private_dir := root / ".private"
scripts_dir := root / "scripts"
age_file := root / "age.key"
bootstrap_config := root / "config.yaml"
bootstrap_sample := root / "config.sample.yaml"
kubeconfig := root / "kubeconfig"
makejinja_config := root / "makejinja.toml"
pyproject_file := root / "pyproject.toml"
sops_config := root / ".sops.yaml"
venv := root / ".venv"

# Initialize configuration files (port of: task init)
[group('template')]
init:
    test -f {{ bootstrap_config }} || cp -n {{ bootstrap_sample }} {{ bootstrap_config }}
    @echo "=== Configuration file copied ==="
    @echo "Proceed with updating the configuration files..."
    @echo "{{ bootstrap_config }}"

# Configure repository from bootstrap vars (port of: task configure)
[group('template')]
configure:
    #!/usr/bin/env bash
    set -euo pipefail
    read -r -p "Any conflicting config in the kubernetes directory will be overwritten... continue? [y/N] " ans
    [ "$ans" = "y" ] || { echo "aborted"; exit 1; }
    just sops age-keygen
    just template init
    uv sync --frozen
    just template _render
    just sops encrypt
    just template _validate

# internal: render templates via makejinja (port of: task .template)
[private]
_render:
    #!/usr/bin/env bash
    set -euo pipefail
    test -d "{{ venv }}"            || { echo "Missing virtual environment"; exit 1; }
    test -f "{{ makejinja_config }}" || { echo "Missing Makejinja config file"; exit 1; }
    test -f "{{ bootstrap_dir / "scripts" / "plugin.py" }}" || { echo "Missing Makejinja plugin file"; exit 1; }
    test -f "{{ bootstrap_config }}" || { echo "Missing bootstrap config file"; exit 1; }
    "{{ venv / "bin" / "makejinja" }}"

# internal: validate rendered output (port of: task .validate)
[private]
_validate:
    #!/usr/bin/env bash
    set -euo pipefail
    just kube kubeconform
    echo "=== Done rendering and validating YAML ==="
    [ "$KUBECONFIG" = "{{ kubeconfig }}" ] || echo "WARNING: KUBECONFIG is not set to the expected value, this may cause conflicts."
    [ "$SOPS_AGE_KEY_FILE" = "{{ age_file }}" ] || echo "WARNING: SOPS_AGE_KEY_FILE is not set to the expected value, this may cause conflicts."
    [ -f ~/.config/sops/age/keys.txt ] && echo "WARNING: SOPS Age key found in home directory, this may cause conflicts." || true

# Clean files no longer needed after cluster bootstrap (port of: task repository:clean)
# NOTE: renovate path corrected to repo-root .renovaterc.json5 (was the broken .github/renovaterc.json5).
[group('template')]
clean:
    #!/usr/bin/env bash
    set -euo pipefail
    test -d "{{ bootstrap_dir }}" || { echo "Missing bootstrap directory"; exit 1; }
    test -f "{{ root / ".renovaterc.json5" }}" || { echo "Missing Renovate config file"; exit 1; }
    mkdir -p "{{ private_dir }}"
    rm -rf "{{ root / ".github" / "tests" }}"
    rm -rf "{{ root / ".devcontainer" / "ci" }}"
    rm -rf "{{ root / ".github" / "workflows" / "devcontainer.yaml" }}"
    mv "{{ bootstrap_dir }}" "{{ private_dir / "bootstrap-" }}$(date +%H%M%S)"
    mv "{{ makejinja_config }}" "{{ private_dir / "makejinja-" }}$(date +%H%M%S).toml"
    if [ "$(uname)" = "Darwin" ]; then sed -i '' 's/(..\.j2)\?//g' "{{ root / ".renovaterc.json5" }}"; else sed -i 's/(..\.j2)\?//g' "{{ root / ".renovaterc.json5" }}"; fi

# Reset templated configuration files (port of: task repository:reset)
[group('template')]
reset:
    #!/usr/bin/env bash
    set -euo pipefail
    read -r -p "Reset templated configuration files... continue? [y/N] " ans
    [ "$ans" = "y" ] || { echo "aborted"; exit 1; }
    just kube _reset
    just sops _reset
    just talos _reset

# Reset repo back to HEAD (port of: task repository:force-reset)
[group('template')]
force-reset:
    #!/usr/bin/env bash
    set -euo pipefail
    read -r -p "Reset repo back to HEAD... continue? [y/N] " ans
    [ "$ans" = "y" ] || { echo "aborted"; exit 1; }
    just template reset
    git reset --hard HEAD
    git clean -f -d
    git pull origin main
