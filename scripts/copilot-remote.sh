#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

copilot_args=(copilot --remote)

if [[ "${COPILOT_SANDBOX_EXPERIMENTAL:-1}" == "1" ]]; then
    copilot_args+=(--experimental)
fi

copilot_args+=("$@")

exec "${script_dir}/run-sandbox.sh" "${copilot_args[@]}"