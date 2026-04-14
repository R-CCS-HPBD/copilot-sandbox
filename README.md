# Copilot GPU Sandbox

Run GitHub Copilot CLI on a remote Linux server, keep the session alive after closing SSH, and continue the same session from your local machine, GitHub.com, or GitHub Mobile.

The main use case is simple: start Copilot CLI on a remote server, keep it running with `make remote-detached`, then continue that same session from GitHub.com or GitHub Mobile.

Important:

- GitHub Copilot CLI itself does not use the GPU for inference.
- The GPU is for workloads executed inside the sandbox by the agent or by the user.

## One End-to-End Example

This is the most important workflow in this repository.

1. SSH to the remote machine.

```bash
ssh alice@gpu-server.example.com
```

1. Clone this repository and enter it.

```bash
git clone https://github.com/your-org/copilot-sandbox.git
cd copilot-sandbox
```

1. Build the image.

```bash
make build
```

1. Authenticate once for the target workspace.

```bash
make shell WORKSPACE=/home/alice/src/my-app
```

Inside the container:

```bash
copilot
```

Then run `/login`, complete the authentication flow, and exit the container.

1. Start the remote session in detached autopilot mode.

```bash
make remote-detached WORKSPACE=/home/alice/src/my-app SESSION_NAME=my-app-agent ARGS='--autopilot'
```

1. Check the session output once.

```bash
tmux capture-pane -pt my-app-agent | tail -n 40
```

That output contains the remote-session link. After that, you can close SSH and let the session keep running on the server.

If you reconnect later and want to retrieve the URL or inspect the live session again:

```bash
tmux ls
tmux attach -t my-app-agent
```

Inside `tmux`, you can run `/remote` in Copilot CLI to redisplay the remote session details. Press `Ctrl+E` to toggle the QR code for GitHub Mobile. You can also use `Ctrl-b [` to enter copy or scroll mode if you want to inspect older output, then press `q` to return to the live Copilot terminal. To detach from `tmux` without stopping the session, use `Ctrl-b d` from the normal terminal view.

If you only want the recent output without attaching:

```bash
tmux capture-pane -pt my-app-agent | tail -n 80
```

GitHub.com example:

- Open the remote-session URL printed by the CLI, or open the Copilot icon or menu on GitHub.com and select the running session from recent agent sessions.

GitHub Mobile example:

- Open GitHub Mobile, go to Copilot, then open your recent agent sessions and select the same running session.
- If you are attached to the CLI in `tmux`, run `/remote` and press `Ctrl+E` to show the QR code, then scan it with your phone.
- GitHub Mobile remote control is in public preview. Changelog: [Remote control CLI sessions on web and mobile in public preview](https://github.blog/changelog/2026-04-13-remote-control-cli-sessions-on-web-and-mobile-in-public-preview)
- Remote access docs: [About remote access for GitHub Copilot CLI](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/about-remote-access)

## What Is In This Repository

- `Containerfile`: GPU-capable sandbox image.
- `scripts/check-host.sh`: Validate Podman and NVIDIA prerequisites on the host.
- `scripts/build-image.sh`: Build the image locally with Podman.
- `scripts/run-sandbox.sh`: Start an interactive sandbox with persistent state and workspace mount.
- `scripts/copilot-remote.sh`: Start GitHub Copilot CLI in remote-session mode inside the sandbox.
- `scripts/remote-detached.sh`: Start GitHub Copilot CLI in remote-session mode inside detached `tmux`.
- `scripts/smoke-test.sh`: Verify the full stack after build.
- `Makefile`: Shortcuts for the common commands.

## Host Requirements

- Linux host with Podman.
- `tmux` on the host if you want the remote session to survive SSH disconnects.
- NVIDIA GPU visible on the host with `nvidia-smi`.
- `nvidia-container-toolkit` installed for container GPU passthrough.
- Outbound HTTPS access to GitHub.
- A GitHub account with Copilot access.

This layout was validated on a GPU server with:

- Podman 4.9.3
- `nvidia-container-toolkit` installed
- one visible NVIDIA GPU

## How It Works

- `WORKSPACE=/path/to/project` selects the host checkout mounted into the container as `/workspace`.
- `make shell` is the one-time login path.
- `make remote-detached` starts the persistent remote session inside detached `tmux`.
- `make remote` is the non-detached version if you want the session tied to your current terminal.
- Use `tmux ls` to find the session, `tmux attach -t <session-name>` to reopen it, `/remote` to redisplay the session details, `Ctrl+E` to toggle the mobile QR code, `Ctrl-b [` to enter copy mode, `q` to exit copy mode, and `Ctrl-b d` to detach without stopping it.

## Verify GPU Access In The Sandbox

```bash
./scripts/run-sandbox.sh nvidia-smi
```

If that succeeds, the container has GPU access.

## Persistent State Layout

By default, the helper scripts keep state in:

```text
~/.local/share/copilot-sandbox/
```

That directory contains isolated state for this sandbox instead of writing directly into the host's default Copilot paths.

- `~/.local/share/copilot-sandbox/copilot` -> mounted as `/home/copilot/.copilot`
- `~/.local/share/copilot-sandbox/gh` -> mounted as `/home/copilot/.config/gh`

This keeps the setup self-contained and makes it easier to remove later.

## Notes On Authentication

Recommended:

- Use `make shell WORKSPACE=/path/to/project`, then run `copilot` and `/login` inside the sandbox.

Alternative:

- Provide a fine-grained token with the `Copilot Requests` permission using `GH_TOKEN` or `GITHUB_TOKEN`.

Examples:

```bash
GH_TOKEN=github_pat_xxx ./scripts/copilot-remote.sh
```

If you also need standard GitHub CLI operations, you can log in with:

```bash
gh auth login
```

inside the container.

## Optional Host Customization

Environment variables supported by the helper scripts:

- `COPILOT_SANDBOX_IMAGE`: image name, default `copilot-gpu-sandbox:latest`
- `COPILOT_SANDBOX_STATE_DIR`: persistent host state directory
- `COPILOT_SANDBOX_WORKSPACE`: host workspace to mount into `/workspace`
- `COPILOT_SANDBOX_DISABLE_GPU=1`: run without GPU passthrough
- `PODMAN_VOLUME_SUFFIX`: optional Podman mount suffix such as `:Z` on SELinux hosts

Examples:

```bash
COPILOT_SANDBOX_DISABLE_GPU=1 ./scripts/run-sandbox.sh
```

```bash
PODMAN_VOLUME_SUFFIX=:Z ./scripts/run-sandbox.sh
```

## Make Targets

The repository includes a small `Makefile` so colleagues can use short commands:

- `make check` -> host prerequisite validation
- `make build` -> image build
- `make shell` -> open shell inside sandbox
- `make remote` -> start Copilot CLI with `--remote`
- `make remote-detached` -> start Copilot CLI with `--remote` inside detached `tmux`
- `make smoke` -> run preflight, build, GPU check, and Copilot version check

## Troubleshooting

Image not found:

- Run `make build` first.

SELinux mount permission problems:

- Retry with `PODMAN_VOLUME_SUFFIX=:Z make shell`

No GPU in the container:

- Confirm `make check` passes on the host.
- Confirm `nvidia-smi -L` succeeds on the host, not just that `nvidia-smi` exists.
- Then run `make smoke`.
- If the host is temporarily missing NVIDIA device nodes, the scripts now fail early with that reason.

Copilot login issues:

- Launch `make shell WORKSPACE=/path/to/project`, run `copilot`, then use `/login`.
- If token-based auth is preferred, export `GH_TOKEN` or `GITHUB_TOKEN` before `make remote`.

Session stopped when SSH disconnected:

- Use `make remote-detached ...` instead of `make remote`.
- Confirm `tmux` is installed on the host.

## Publish Checklist

Before sharing this repository with colleagues:

1. Review [Containerfile](Containerfile) for any site-specific packages you want baked into the image.
2. Review [README.md](README.md) and replace any local assumptions with your team-specific server paths or policy notes.
3. Commit the repository and push it to GitHub.
4. Ask one colleague to run `make smoke` on the server as an independent verification.

## Security Notes

- This repository is intended for trusted colleagues on a trusted server.
- The sandbox can read and modify whatever directory you mount into `/workspace`.
- Do not pass broad host mounts unless they are necessary.
- Prefer sandbox-specific state directories over mounting your entire home directory.

## Compatibility Note

This repository targets the current GitHub Copilot CLI (`copilot`), not the deprecated `gh extension install github/gh-copilot` workflow.

If your organization still uses `gh copilot`, keep that as a separate compatibility path rather than mixing both installs into the same user workflow.
