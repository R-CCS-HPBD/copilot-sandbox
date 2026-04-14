#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
session_name="${COPILOT_REMOTE_SESSION_NAME:-copilot-remote}"

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

if ! command -v tmux >/dev/null 2>&1; then
    die "tmux is not installed on the host; install tmux or use make remote from an existing tmux session"
fi

if tmux has-session -t "${session_name}" 2>/dev/null; then
    die "tmux session already exists: ${session_name}"
fi

command=("${script_dir}/copilot-remote.sh" "$@")
printf -v tmux_command '%q ' "${command[@]}"

tmux new-session -d -s "${session_name}" -c "${repo_root}" "exec ${tmux_command}"

printf 'Started detached session: %s\n' "${session_name}"
printf 'The Copilot CLI process will keep running after SSH disconnects as long as this host stays online.\n'
printf 'Inspect output: tmux capture-pane -pt %q | tail -n 40\n' "${session_name}"
printf 'Reattach: tmux attach -t %q\n' "${session_name}"