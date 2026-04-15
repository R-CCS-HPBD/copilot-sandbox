#!/usr/bin/env bash
set -euo pipefail

image_name="${VLLM_IMAGE:-docker.io/vllm/vllm-openai:latest}"
container_name="${VLLM_CONTAINER_NAME:-copilot-sandbox-vllm}"
model_name="${VLLM_MODEL:-}"
served_model_name="${VLLM_SERVED_MODEL_NAME:-}"
cache_dir="${VLLM_CACHE_DIR:-${HOME}/.cache/huggingface}"
port="${VLLM_PORT:-8000}"
volume_suffix="${PODMAN_VOLUME_SUFFIX:-}"
detach="${VLLM_DETACH:-1}"
disable_gpu="${COPILOT_SANDBOX_DISABLE_GPU:-0}"

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

gpu_ready() {
    local output status

    if ! command -v nvidia-smi >/dev/null 2>&1; then
        die "nvidia-smi is not installed on the host; set COPILOT_SANDBOX_DISABLE_GPU=1 to run without GPU"
    fi

    set +e
    output="$(nvidia-smi -L 2>&1)"
    status=$?
    set -e

    if (( status != 0 )); then
        printf '%s\n' "${output}" >&2
        die "host GPU check failed; NVIDIA driver or device nodes are not ready"
    fi

    if command -v nvidia-ctk >/dev/null 2>&1; then
        set +e
        output="$(nvidia-ctk cdi list 2>&1)"
        status=$?
        set -e

        if (( status != 0 )) || ! grep -q '^nvidia.com/gpu=all$' <<<"${output}"; then
            printf '%s\n' "${output}" >&2
            die "Podman CDI GPU devices are unavailable; set COPILOT_SANDBOX_DISABLE_GPU=1 to run without GPU"
        fi
    fi
}

usage() {
    cat <<'EOF'
Usage: ./scripts/run-vllm.sh [extra vLLM args]

Required environment:
  VLLM_MODEL                 Hugging Face model ID or local model path

Optional environment:
  VLLM_IMAGE                 Container image to run (default: docker.io/vllm/vllm-openai:latest)
  VLLM_CONTAINER_NAME        Podman container name (default: copilot-sandbox-vllm)
  VLLM_SERVED_MODEL_NAME     Model name exposed from the OpenAI-compatible API
  VLLM_PORT                  Host port for the OpenAI-compatible API (default: 8000)
  VLLM_CACHE_DIR             Hugging Face cache directory on the host
  VLLM_DETACH                Use 1 for background mode or 0 for foreground mode (default: 1)
  COPILOT_SANDBOX_DISABLE_GPU  Set to 1 to skip GPU passthrough

Examples:
  make vllm VLLM_MODEL=meta-llama/Llama-3.1-8B-Instruct
  make vllm VLLM_MODEL=Qwen/Qwen2.5-Coder-32B-Instruct ARGS='--max-model-len 131072'
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if ! command -v podman >/dev/null 2>&1; then
    die "podman is not installed"
fi

if [[ -z "${model_name}" ]]; then
    die "set VLLM_MODEL to the Hugging Face model ID or local path you want to serve"
fi

if [[ -z "${served_model_name}" ]]; then
    served_model_name="${model_name##*/}"
fi

mkdir -p "${cache_dir}"

if podman container exists "${container_name}" 2>/dev/null; then
    running="$(podman inspect --format '{{.State.Running}}' "${container_name}")"
    if [[ "${running}" == "true" ]]; then
        die "container already running: ${container_name}; use 'make vllm-logs' or 'make vllm-stop' first"
    fi

    podman rm -f "${container_name}" >/dev/null
fi

podman_args=(
    run
    --name
    "${container_name}"
    --hostname
    "${container_name}"
    --network
    host
    -e
    HF_HOME=/root/.cache/huggingface
    -v
    "${cache_dir}:/root/.cache/huggingface:rw${volume_suffix}"
)

for env_name in HF_TOKEN HUGGING_FACE_HUB_TOKEN HUGGINGFACE_HUB_TOKEN; do
    if [[ -n "${!env_name:-}" ]]; then
        podman_args+=(
            -e
            "${env_name}=${!env_name}"
        )
    fi
done

if [[ "${disable_gpu}" != "1" ]]; then
    gpu_ready

    podman_args+=(
        --device
        nvidia.com/gpu=all
        -e
        NVIDIA_VISIBLE_DEVICES=all
        -e
        NVIDIA_DRIVER_CAPABILITIES=compute,utility
    )
fi

server_args=(
    --model
    "${model_name}"
    --served-model-name
    "${served_model_name}"
    --host
    0.0.0.0
    --port
    "${port}"
)

server_args+=("$@")

if [[ "${detach}" == "1" ]]; then
    podman_args+=(
        -d
    )

    podman "${podman_args[@]}" "${image_name}" "${server_args[@]}" >/dev/null

    printf 'Started vLLM container: %s\n' "${container_name}"
    printf 'Endpoint: http://127.0.0.1:%s/v1\n' "${port}"
    printf 'Served model name: %s\n' "${served_model_name}"
    printf 'Logs: make vllm-logs VLLM_CONTAINER_NAME=%q\n' "${container_name}"
    printf 'Stop: make vllm-stop VLLM_CONTAINER_NAME=%q\n' "${container_name}"
    printf 'Copilot shell: make shell-vllm VLLM_MODEL=%q VLLM_SERVED_MODEL_NAME=%q\n' "${model_name}" "${served_model_name}"
    printf 'Copilot remote: make remote-detached-vllm WORKSPACE=%q SESSION_NAME=%q VLLM_MODEL=%q VLLM_SERVED_MODEL_NAME=%q ARGS=%q\n' "${PWD}" "copilot-vllm" "${model_name}" "${served_model_name}" "--autopilot"
    exit 0
fi

podman_args+=(
    --rm
    -it
)

exec podman "${podman_args[@]}" "${image_name}" "${server_args[@]}"