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

if [[ -n "${COPILOT_PROVIDER_BASE_URL:-}" && -n "${COPILOT_MODEL:-}" ]]; then
	printf '\n==> Checking configured BYOK endpoint from the container\n'
	"${script_dir}/run-sandbox.sh" bash -lc '
		set -euo pipefail
		provider_type="${COPILOT_PROVIDER_TYPE:-openai}"
		base_url="${COPILOT_PROVIDER_BASE_URL%/}"

		if [[ "${provider_type}" != "openai" ]]; then
			printf "Skipping generic BYOK probe for provider type: %s\\n" "${provider_type}"
			exit 0
		fi

		curl_args=(-fsS)
		if [[ -n "${COPILOT_PROVIDER_API_KEY:-}" ]]; then
			curl_args+=(-H "Authorization: Bearer ${COPILOT_PROVIDER_API_KEY}")
		fi

		response="$(curl "${curl_args[@]}" "${base_url}/models")"
		jq -e ".data | length > 0" <<<"${response}" >/dev/null
		printf "BYOK endpoint reachable from sandbox: %s\\n" "${base_url}"
	'
fi

printf '\nSmoke test passed.\n'