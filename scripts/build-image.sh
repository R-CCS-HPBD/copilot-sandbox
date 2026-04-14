#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
image_name="${COPILOT_SANDBOX_IMAGE:-copilot-gpu-sandbox:latest}"

cd "${repo_root}"

echo "Building ${image_name} from ${repo_root}/Containerfile"
podman build --pull=missing --format docker -t "${image_name}" -f Containerfile .