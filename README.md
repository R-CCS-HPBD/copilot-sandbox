# Copilot GPU Sandbox

Run GitHub Copilot CLI on a remote Linux server, keep the session alive after closing SSH, and continue the same session from your local machine, GitHub.com, or GitHub Mobile.

The main use case is simple: start Copilot CLI on a remote server, keep it running with `make remote-detached`, then continue that same session from GitHub.com or GitHub Mobile.

Important:

- GitHub Copilot CLI itself does not use the GPU for inference.
- The GPU is for workloads executed inside the sandbox by the agent or by the user.
- If you want Copilot CLI to call a local model, this repository now supports GitHub Copilot CLI BYOM against a local vLLM OpenAI-compatible endpoint.

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

## Local vLLM BYOM Workflow

GitHub Copilot CLI can use your own model provider by setting the standard BYOM environment variables documented by GitHub:

- `COPILOT_PROVIDER_BASE_URL`
- `COPILOT_PROVIDER_TYPE`
- `COPILOT_PROVIDER_API_KEY`
- `COPILOT_MODEL`
- `COPILOT_OFFLINE`

For vLLM, the provider type is `openai`, because vLLM exposes an OpenAI-compatible Chat Completions API. The model must support streaming and tool calling. A larger context window is strongly recommended.

This repository adds a local vLLM sidecar plus wrappers that export the official Copilot BYOM variables for you.

1. Start the vLLM server on the host.

```bash
make vllm VLLM_MODEL=meta-llama/Llama-3.1-8B-Instruct
```

That starts a detached Podman container named `copilot-sandbox-vllm`, exposes `http://127.0.0.1:8000/v1`, and reuses your host Hugging Face cache under `~/.cache/huggingface`.

1. Follow the logs until the model is ready.

```bash
make vllm-logs
```

1. Open a shell in the Copilot sandbox that is already configured to call the local vLLM endpoint.

```bash
make shell-vllm WORKSPACE=/home/alice/src/my-app VLLM_MODEL=meta-llama/Llama-3.1-8B-Instruct
```

The wrapper sets these defaults:

- `COPILOT_PROVIDER_TYPE=openai`
- `COPILOT_PROVIDER_BASE_URL=http://127.0.0.1:8000/v1`
- `COPILOT_MODEL=<served-model-name>`
- `COPILOT_OFFLINE=true`

If you already authenticated the sandbox once, that state is reused. If you want a different model name exposed to Copilot CLI, set `VLLM_SERVED_MODEL_NAME=name-you-want` for both `make vllm` and the matching `shell-vllm`, `remote-vllm`, or `remote-detached-vllm` command.

1. Start a detached remote session backed by the local model.

```bash
make remote-detached-vllm WORKSPACE=/home/alice/src/my-app SESSION_NAME=my-app-local-model VLLM_MODEL=meta-llama/Llama-3.1-8B-Instruct ARGS='--autopilot'
```

1. Stop the local vLLM server when you are done.

```bash
make vllm-stop
```

If you already run your own local or on-prem OpenAI-compatible endpoint, you can skip `make vllm` and set the GitHub BYOM environment variables yourself before `make shell`, `make remote`, or `make remote-detached`. The sandbox runner now passes those variables through and automatically switches to host networking when the provider URL points at `localhost`, `127.0.0.1`, or another loopback address.

## Compose Workflow

If you want a single Compose stack for both the Copilot sandbox and local vLLM, use [compose.yaml](compose.yaml).

This Compose path is designed for `podman compose` and keeps the two containers on the same internal network:

- `sandbox` builds from this repository's [Containerfile](Containerfile)
- `vllm` runs the OpenAI-compatible vLLM server
- the sandbox points Copilot CLI at `http://vllm:8000/v1`
- Copilot and GitHub CLI state are persisted in named volumes managed by Podman Compose

The Compose stack uses `COPILOT_MODEL=local-model` by default as the served model alias. The actual Hugging Face model to load is controlled separately with `VLLM_MODEL`.

Example:

```bash
export WORKSPACE=/home/alice/src/my-app
export VLLM_MODEL=meta-llama/Llama-3.1-8B-Instruct

make compose-build
make compose-up
make compose-shell
```

Inside the shell:

```bash
copilot
```

If you want a remote session directly from Compose:

```bash
export WORKSPACE=/home/alice/src/my-app
export VLLM_MODEL=meta-llama/Llama-3.1-8B-Instruct

make compose-up
make compose-remote ARGS='--autopilot'
```

Useful Compose commands:

- `make compose-build` builds the sandbox image from this repository
- `make compose-up` starts the vLLM service in the background
- `make compose-shell` opens an interactive shell in the sandbox container
- `make compose-remote` starts `copilot --remote --experimental` in the sandbox container
- `make compose-logs` tails the vLLM logs
- `make compose-down` stops the Compose stack

Notes:

- The Compose workflow stores Copilot state in named volumes, not in `~/.local/share/copilot-sandbox`.
- If you want `copilot` to use a different alias than `local-model`, export `COPILOT_MODEL=name-you-want` before the Compose command.
- If the Hugging Face model is gated, export `HF_TOKEN` before `make compose-up`.

## What Is In This Repository

- `Containerfile`: GPU-capable sandbox image.
- `scripts/check-host.sh`: Validate Podman and NVIDIA prerequisites on the host.
- `scripts/build-image.sh`: Build the image locally with Podman.
- `scripts/run-sandbox.sh`: Start an interactive sandbox with persistent state and workspace mount.
- `scripts/copilot-remote.sh`: Start GitHub Copilot CLI in remote-session mode inside the sandbox.
- `scripts/remote-detached.sh`: Start GitHub Copilot CLI in remote-session mode inside detached `tmux`.
- `scripts/run-vllm.sh`: Start a detached local vLLM OpenAI-compatible endpoint with Podman.
- `scripts/use-vllm-byok.sh`: Export the Copilot CLI BYOM variables for the local vLLM endpoint.
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
- `make shell-vllm`, `make remote-vllm`, and `make remote-detached-vllm` wrap the same flows but point Copilot CLI at a local vLLM endpoint.
- `make compose-build`, `make compose-up`, and `make compose-shell` provide a Compose-based workflow for the sandbox plus local vLLM.
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
- `COPILOT_SANDBOX_USE_HOST_NETWORK=1`: force `podman run --network host`, useful for local BYOM endpoints
- `PODMAN_VOLUME_SUFFIX`: optional Podman mount suffix such as `:Z` on SELinux hosts

Environment variables supported by the local vLLM helper:

- `VLLM_MODEL`: required Hugging Face model ID or local model path
- `VLLM_SERVED_MODEL_NAME`: model name returned by the local OpenAI-compatible API
- `VLLM_PORT`: API port, default `8000`
- `VLLM_IMAGE`: vLLM container image, default `docker.io/vllm/vllm-openai:latest`
- `VLLM_CONTAINER_NAME`: Podman container name, default `copilot-sandbox-vllm`
- `VLLM_CACHE_DIR`: Hugging Face cache directory on the host
- `VLLM_DETACH=0`: run the vLLM server in the foreground instead of the background

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
- `make vllm` -> start the local vLLM service in a detached Podman container
- `make vllm-logs` -> tail the local vLLM logs
- `make vllm-stop` -> stop and remove the local vLLM container
- `make shell-vllm` -> open shell inside sandbox configured for local vLLM BYOM
- `make remote-vllm` -> start Copilot CLI with `--remote` against local vLLM
- `make remote-detached-vllm` -> detached `tmux` remote session against local vLLM
- `make smoke-vllm` -> run the smoke test with the local vLLM BYOM wrapper enabled
- `make compose-build` -> build the sandbox image for the Compose stack
- `make compose-up` -> start the Compose-managed vLLM service
- `make compose-shell` -> open an interactive shell in the Compose-managed sandbox container
- `make compose-remote` -> start Copilot CLI remote mode from the Compose-managed sandbox container
- `make compose-logs` -> tail the Compose-managed vLLM logs
- `make compose-down` -> stop the Compose stack
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

Local vLLM does not start or cannot load the model:

- Confirm `make check` passes before `make vllm`.
- Confirm your selected model supports streaming and tool calling.
- Tail `make vllm-logs` and look for Hugging Face authentication or VRAM exhaustion errors.
- If the model is gated, export `HF_TOKEN` before `make vllm`.

Copilot cannot reach the local vLLM endpoint:

- Use `make smoke-vllm VLLM_MODEL=...` to verify that the sandbox can reach `http://127.0.0.1:<port>/v1/models`.
- Keep the same `VLLM_PORT` and `VLLM_SERVED_MODEL_NAME` values on both the `make vllm` command and the `make shell-vllm` or `make remote-detached-vllm` command.
- If you are setting `COPILOT_PROVIDER_BASE_URL` manually, use a loopback URL on Linux so the runner can switch to host networking automatically.

Compose sandbox cannot see the model:

- Confirm `make compose-up` has the `vllm` service running before `make compose-shell` or `make compose-remote`.
- Tail `make compose-logs` and wait until vLLM finishes model loading.
- Confirm the same `COPILOT_MODEL` alias is used by both services if you override the default `local-model`.

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
