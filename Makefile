.PHONY: build test clean

# ── Config ────────────────────────────────────────────────────────────
VERSION   := $(shell cat agent-runtime/VERSION)
IMAGE     := onecode
PLATFORM := linux/amd64

# Test defaults
TEST_NAME := test-env
TEST_PORT := 9001
TEST_APORT:= 9002

# ── build: 本地打镜像 ────────────────────────────────────────────────
build:
	docker buildx build --platform $(PLATFORM) -t $(IMAGE):$(VERSION) -t $(IMAGE):latest --load agent-runtime/

# ── test: 启动测试环境 ──────────────────────────────────────────────
test:
	agent-runtime/bin/oc remote -n $(TEST_NAME) -p $(TEST_PORT) -a $(TEST_APORT) --tag $(VERSION)

# ── clean: 清理镜像 ──────────────────────────────────────────────────
clean:
	docker rmi $(IMAGE):$(VERSION) $(IMAGE):latest 2>/dev/null || true
