IMAGE ?= copilot-gpu-sandbox:latest
WORKSPACE ?= $(CURDIR)
STATE_DIR ?= $(HOME)/.local/share/copilot-sandbox
SESSION_NAME ?= copilot-remote
ARGS ?=

export COPILOT_SANDBOX_IMAGE := $(IMAGE)
export COPILOT_SANDBOX_WORKSPACE := $(WORKSPACE)
export COPILOT_SANDBOX_STATE_DIR := $(STATE_DIR)

.PHONY: check build shell remote remote-detached smoke

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