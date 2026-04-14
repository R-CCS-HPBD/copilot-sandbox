#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

printf '==> Checking host prerequisites\n'
"${script_dir}/check-host.sh"

printf '\n==> Building image if needed\n'
"${script_dir}/build-image.sh"

if [[ "${COPILOT_SANDBOX_DISABLE_GPU:-0}" != "1" ]]; then
	printf '\n==> Checking GPU visibility in the container\n'
	"${script_dir}/run-sandbox.sh" nvidia-smi -L
else
	printf '\n==> Skipping GPU visibility check because COPILOT_SANDBOX_DISABLE_GPU=1\n'
fi

printf '\n==> Checking Copilot CLI in the container\n'
"${script_dir}/run-sandbox.sh" copilot --version

printf '\nSmoke test passed.\n'