set quiet
set unstable
set windows-powershell := false
set shell := ['bash', '-euo', 'pipefail', '-c']
set script-interpreter := ['bash', '-euo', 'pipefail']

config_dir := justfile_directory()

# Default: list available recipes.
default:
    @just --list

# === modules (each ports one former .taskfiles/ namespace) ===

[group('template')]
mod template 'just/template'

[group('sops')]
mod sops 'just/sops'

[group('talos')]
mod talos 'just/talos'

[group('flux')]
mod flux 'just/flux'

[group('kubernetes')]
mod kube 'just/kubernetes'
