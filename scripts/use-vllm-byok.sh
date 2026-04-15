#!/usr/bin/env bash
set -euo pipefail

vllm_port="${VLLM_PORT:-8000}"
served_model_name="${VLLM_SERVED_MODEL_NAME:-}"

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

if (( $# == 0 )); then
    die "usage: ./scripts/use-vllm-byok.sh <command> [args...]"
fi

if [[ -z "${served_model_name}" && -n "${VLLM_MODEL:-}" ]]; then
    served_model_name="${VLLM_MODEL##*/}"
fi

export COPILOT_PROVIDER_TYPE="${COPILOT_PROVIDER_TYPE:-openai}"
export COPILOT_PROVIDER_BASE_URL="${COPILOT_PROVIDER_BASE_URL:-http://127.0.0.1:${vllm_port}/v1}"
export COPILOT_MODEL="${COPILOT_MODEL:-${served_model_name}}"
export COPILOT_OFFLINE="${COPILOT_OFFLINE:-true}"
export COPILOT_SANDBOX_USE_HOST_NETWORK=1

if [[ -z "${COPILOT_MODEL}" ]]; then
    die "set VLLM_MODEL, VLLM_SERVED_MODEL_NAME, or COPILOT_MODEL before using the local vLLM wrapper"
fi

exec "$@"