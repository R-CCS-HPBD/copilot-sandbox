#!/usr/bin/env bash
set -euo pipefail

image_name="${COPILOT_SANDBOX_IMAGE:-copilot-gpu-sandbox:latest}"
state_dir="${COPILOT_SANDBOX_STATE_DIR:-${HOME}/.local/share/copilot-sandbox}"
workspace_dir="${COPILOT_SANDBOX_WORKSPACE:-${PWD}}"
volume_suffix="${PODMAN_VOLUME_SUFFIX:-}"
disable_gpu="${COPILOT_SANDBOX_DISABLE_GPU:-0}"
use_host_network="${COPILOT_SANDBOX_USE_HOST_NETWORK:-0}"
copilot_provider_base_url="${COPILOT_PROVIDER_BASE_URL:-}"

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

pass_env_if_set() {
    local name="$1"

    if [[ -n "${!name:-}" ]]; then
        podman_args+=(
            -e
            "${name}=${!name}"
        )
    fi
}

requires_host_network() {
    local url="$1"

    if [[ "${use_host_network}" == "1" ]]; then
        return 0
    fi

    [[ "${url}" =~ ^https?://(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])([/:]|$) ]]
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

if [[ ! -d "${workspace_dir}" ]]; then
    die "workspace directory does not exist: ${workspace_dir}"
fi

if ! podman image exists "${image_name}"; then
    die "image ${image_name} is not available locally; run ./scripts/build-image.sh first"
fi

mkdir -p "${state_dir}/copilot" "${state_dir}/gh"

podman_args=(
    run
    --rm
    -it
    --hostname
    copilot-gpu-sandbox
    -e
    HOME=/home/copilot
    -e
    TERM=${TERM:-xterm-256color}
    -e
    COLORTERM=${COLORTERM:-truecolor}
    -e
    CLICOLOR_FORCE=1
    -v
    "${workspace_dir}:/workspace:rw${volume_suffix}"
    -v
    "${state_dir}/copilot:/home/copilot/.copilot:rw${volume_suffix}"
    -v
    "${state_dir}/gh:/home/copilot/.config/gh:rw${volume_suffix}"
    -w
    /workspace
)

for env_name in COPILOT_PROVIDER_BASE_URL COPILOT_PROVIDER_TYPE COPILOT_PROVIDER_API_KEY COPILOT_MODEL COPILOT_OFFLINE; do
    pass_env_if_set "${env_name}"
done

if requires_host_network "${copilot_provider_base_url}"; then
    podman_args+=(
        --network
        host
    )
fi

if [[ -f "${HOME}/.gitconfig" ]]; then
    podman_args+=(
        -v
        "${HOME}/.gitconfig:/home/copilot/.gitconfig:ro${volume_suffix}"
    )
fi

if [[ -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK}" ]]; then
    podman_args+=(
        -e
        SSH_AUTH_SOCK=/ssh-agent
        -v
        "${SSH_AUTH_SOCK}:/ssh-agent${volume_suffix}"
    )
fi

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

if (( $# == 0 )); then
    set -- bash
fi

exec podman "${podman_args[@]}" "${image_name}" "$@"