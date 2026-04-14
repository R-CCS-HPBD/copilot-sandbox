#!/usr/bin/env bash
set -euo pipefail

failures=0

have() {
    command -v "$1" >/dev/null 2>&1
}

check_ok() {
    printf '[ok] %s\n' "$1"
}

check_warn() {
    printf '[warn] %s\n' "$1"
}

check_fail() {
    printf '[fail] %s\n' "$1"
    failures=$((failures + 1))
}

if have podman; then
    check_ok "podman: $(podman --version)"
else
    check_fail "podman is not installed"
fi

if have nvidia-smi; then
    set +e
    gpu_list="$(nvidia-smi -L 2>&1)"
    gpu_status=$?
    set -e

    if (( gpu_status == 0 )) && [[ -n "${gpu_list}" ]]; then
        check_ok "nvidia-smi detected GPU(s)"
        printf '%s\n' "${gpu_list}"
    else
        check_fail "nvidia-smi failed; NVIDIA driver or device nodes are not ready"
        printf '%s\n' "${gpu_list}"
    fi
else
    check_fail "nvidia-smi is not installed or not in PATH"
fi

if have nvidia-container-toolkit; then
    check_ok "nvidia-container-toolkit is installed"
elif have nvidia-ctk; then
    check_ok "nvidia-ctk is installed"
else
    check_fail "NVIDIA container toolkit is missing"
fi

if have nvidia-ctk; then
    set +e
    cdi_devices="$(nvidia-ctk cdi list 2>&1)"
    cdi_status=$?
    set -e

    if (( cdi_status == 0 )) && grep -q '^nvidia.com/gpu=all$' <<<"${cdi_devices}"; then
        check_ok "NVIDIA CDI devices are available to Podman"
    else
        check_fail "NVIDIA CDI devices are not available to Podman"
        printf '%s\n' "${cdi_devices}"
    fi
fi

if have podman && podman info --format '{{.Host.Security.Rootless}}' >/dev/null 2>&1; then
    rootless="$(podman info --format '{{.Host.Security.Rootless}}')"
    check_ok "podman rootless mode: ${rootless}"
fi

printf '\n'

if (( failures > 0 )); then
    printf 'Host check failed with %d issue(s).\n' "${failures}"
    exit 1
fi

printf 'Host check passed. Next steps:\n'
printf '  1. ./scripts/build-image.sh\n'
printf '  2. ./scripts/run-sandbox.sh\n'
printf '  3. ./scripts/copilot-remote.sh\n'