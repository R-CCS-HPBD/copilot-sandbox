IMAGE ?= copilot-gpu-sandbox:latest
WORKSPACE ?= $(CURDIR)
STATE_DIR ?= $(HOME)/.local/share/copilot-sandbox
SESSION_NAME ?= copilot-remote
VLLM_IMAGE ?= docker.io/vllm/vllm-openai:latest
VLLM_CONTAINER_NAME ?= copilot-sandbox-vllm
VLLM_MODEL ?=
VLLM_SERVED_MODEL_NAME ?=
VLLM_PORT ?= 8000
VLLM_CACHE_DIR ?= $(HOME)/.cache/huggingface
ARGS ?=

export COPILOT_SANDBOX_IMAGE := $(IMAGE)
export COPILOT_SANDBOX_WORKSPACE := $(WORKSPACE)
export COPILOT_SANDBOX_STATE_DIR := $(STATE_DIR)
export VLLM_IMAGE := $(VLLM_IMAGE)
export VLLM_CONTAINER_NAME := $(VLLM_CONTAINER_NAME)
export VLLM_MODEL := $(VLLM_MODEL)
export VLLM_SERVED_MODEL_NAME := $(VLLM_SERVED_MODEL_NAME)
export VLLM_PORT := $(VLLM_PORT)
export VLLM_CACHE_DIR := $(VLLM_CACHE_DIR)

.PHONY: check build shell remote remote-detached smoke vllm vllm-logs vllm-stop shell-vllm remote-vllm remote-detached-vllm smoke-vllm compose-build compose-up compose-shell compose-remote compose-logs compose-down

check:
	./scripts/check-host.sh

build:
	./scripts/build-image.sh

shell:
	./scripts/run-sandbox.sh

remote:
	./scripts/copilot-remote.sh $(ARGS)

remote-detached:
	COPILOT_REMOTE_SESSION_NAME='$(SESSION_NAME)' ./scripts/remote-detached.sh $(ARGS)

smoke:
	./scripts/smoke-test.sh

vllm:
	./scripts/run-vllm.sh $(ARGS)

vllm-logs:
	podman logs -f "$(VLLM_CONTAINER_NAME)"

vllm-stop:
	podman rm -f "$(VLLM_CONTAINER_NAME)"

shell-vllm:
	./scripts/use-vllm-byok.sh ./scripts/run-sandbox.sh

remote-vllm:
	./scripts/use-vllm-byok.sh ./scripts/copilot-remote.sh $(ARGS)

remote-detached-vllm:
	COPILOT_REMOTE_SESSION_NAME='$(SESSION_NAME)' ./scripts/use-vllm-byok.sh ./scripts/remote-detached.sh $(ARGS)

smoke-vllm:
	./scripts/use-vllm-byok.sh ./scripts/smoke-test.sh

compose-build:
	podman compose build sandbox

compose-up:
	podman compose up -d vllm

compose-shell:
	podman compose run --rm sandbox

compose-remote:
	podman compose run --rm sandbox copilot --remote --experimental $(ARGS)

compose-logs:
	podman compose logs -f vllm

compose-down:
	podman compose down