#!/usr/bin/env bash
set -euo pipefail

image_name="${COPILOT_SANDBOX_IMAGE:-copilot-gpu-sandbox:latest}"
state_dir="${COPILOT_SANDBOX_STATE_DIR:-${HOME}/.local/share/copilot-sandbox}"
workspace_dir="${COPILOT_SANDBOX_WORKSPACE:-${PWD}}"
volume_suffix="${PODMAN_VOLUME_SUFFIX:-}"
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