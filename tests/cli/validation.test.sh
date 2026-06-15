#!/usr/bin/env bash
# Tests for oc CLI — validation, backend selection, provider defaults
# Output format: PASS <label> or FAIL <label>
set -euo pipefail

# ── Setup ────────────────────────────────────────────────────────────
TEST_HOME="/tmp/onecode-test-val-$$"
OC_HOME="$TEST_HOME/.onecode"
OC_CONFIG="$OC_HOME/settings.json"
mkdir -p "$OC_HOME"

OC_SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/agent-runtime/bin/oc"

run_oc() {
    env -i HOME="$TEST_HOME" OC_HOME="$OC_HOME" PATH="$PATH" USER="$(whoami)" TERM="${TERM:-xterm}" bash "$OC_SCRIPT" "$@" 2>&1 || true
}

write_config() {
    echo "$1" > "$OC_CONFIG"
    chmod 600 "$OC_CONFIG"
}

# ──────────────────────────────────────────────────────────────────────
# Validation tests
# ──────────────────────────────────────────────────────────────────────

write_config '{"$version":"2","provider":"anthropic","api_key":"sk-ant-realkey1234567890"}'

# ── Test: reject placeholder API keys ───────────────────────────────
OUTPUT=$(run_oc config set api_key=sk-test-key 2>&1)
if echo "$OUTPUT" | grep -qi "placeholder\|error"; then
    echo "PASS validation rejects placeholder api_key (sk-test-key)"
else
    echo "FAIL validation should reject placeholder api_key, got: $OUTPUT"
fi

OUTPUT=$(run_oc config set api_key=sk-placeholder 2>&1)
if echo "$OUTPUT" | grep -qi "placeholder\|error"; then
    echo "PASS validation rejects placeholder api_key (sk-placeholder)"
else
    echo "FAIL validation should reject placeholder api_key, got: $OUTPUT"
fi

OUTPUT=$(run_oc config set api_key=sk-xxx 2>&1)
if echo "$OUTPUT" | grep -qi "placeholder\|error"; then
    echo "PASS validation rejects placeholder api_key (sk-xxx)"
else
    echo "FAIL validation should reject placeholder api_key, got: $OUTPUT"
fi

# ── Test: reject empty API key ──────────────────────────────────────
OUTPUT=$(run_oc config set api_key= 2>&1)
if echo "$OUTPUT" | grep -qi "empty\|error"; then
    echo "PASS validation rejects empty api_key"
else
    echo "FAIL validation should reject empty api_key, got: $OUTPUT"
fi

# ── Test: reject invalid backend ────────────────────────────────────
OUTPUT=$(run_oc config set backend=invalid 2>&1)
if echo "$OUTPUT" | grep -qi "error"; then
    echo "PASS validation rejects invalid backend"
else
    echo "FAIL validation should reject invalid backend, got: $OUTPUT"
fi

# ── Test: accept valid backends ─────────────────────────────────────
run_oc config set backend=claude-code > /dev/null 2>&1
VAL=$(jq -r '.backend' "$OC_CONFIG")
if [ "$VAL" = "claude-code" ]; then
    echo "PASS validation accepts backend=claude-code"
else
    echo "FAIL validation should accept claude-code, got: $VAL"
fi

run_oc config set backend=opencode > /dev/null 2>&1
VAL=$(jq -r '.backend' "$OC_CONFIG")
if [ "$VAL" = "opencode" ]; then
    echo "PASS validation accepts backend=opencode"
else
    echo "FAIL validation should accept opencode, got: $VAL"
fi

# ── Test: reject invalid api_base_url ───────────────────────────────
OUTPUT=$(run_oc config set api_base_url=not-a-url 2>&1)
if echo "$OUTPUT" | grep -qi "error\|valid URL"; then
    echo "PASS validation rejects invalid api_base_url"
else
    echo "FAIL validation should reject invalid api_base_url, got: $OUTPUT"
fi

# ── Test: accept valid api_base_url ─────────────────────────────────
run_oc config set api_base_url=https://api.anthropic.com > /dev/null 2>&1
VAL=$(jq -r '.api_base_url' "$OC_CONFIG")
if [ "$VAL" = "https://api.anthropic.com" ]; then
    echo "PASS validation accepts valid api_base_url"
else
    echo "FAIL validation should accept valid URL, got: $VAL"
fi

# ── Test: reject invalid ports ──────────────────────────────────────
OUTPUT=$(run_oc config set gateway_port=0 2>&1)
if echo "$OUTPUT" | grep -qi "error"; then
    echo "PASS validation rejects port 0"
else
    echo "FAIL validation should reject port 0, got: $OUTPUT"
fi

OUTPUT=$(run_oc config set gateway_port=99999 2>&1)
if echo "$OUTPUT" | grep -qi "error"; then
    echo "PASS validation rejects port 99999"
else
    echo "FAIL validation should reject port 99999, got: $OUTPUT"
fi

# ── Test: accept valid ports ────────────────────────────────────────
run_oc config set gateway_port=8080 > /dev/null 2>&1
VAL=$(jq -r '.gateway_port' "$OC_CONFIG")
if [ "$VAL" = "8080" ]; then
    echo "PASS validation accepts valid port 8080"
else
    echo "FAIL validation should accept port 8080, got: $VAL"
fi

# ── Test: reject invalid docker_platform ────────────────────────────
OUTPUT=$(run_oc config set docker_platform=linux/armv7 2>&1)
if echo "$OUTPUT" | grep -qi "error"; then
    echo "PASS validation rejects invalid docker_platform"
else
    echo "FAIL validation should reject linux/armv7, got: $OUTPUT"
fi

# ── Test: accept valid docker_platform ──────────────────────────────
run_oc config set docker_platform=linux/amd64 > /dev/null 2>&1
VAL=$(jq -r '.docker_platform' "$OC_CONFIG")
if [ "$VAL" = "linux/amd64" ]; then
    echo "PASS validation accepts linux/amd64"
else
    echo "FAIL validation should accept linux/amd64, got: $VAL"
fi

run_oc config set docker_platform=linux/arm64 > /dev/null 2>&1
VAL=$(jq -r '.docker_platform' "$OC_CONFIG")
if [ "$VAL" = "linux/arm64" ]; then
    echo "PASS validation accepts linux/arm64"
else
    echo "FAIL validation should accept linux/arm64, got: $VAL"
fi

# ── Test: gateway_https must be true/false ──────────────────────────
OUTPUT=$(run_oc config set gateway_https=yes 2>&1)
if echo "$OUTPUT" | grep -qi "error"; then
    echo "PASS validation rejects gateway_https=yes"
else
    echo "FAIL validation should reject gateway_https=yes, got: $OUTPUT"
fi

run_oc config set gateway_https=true > /dev/null 2>&1
VAL=$(jq -r '.gateway_https' "$OC_CONFIG")
if [ "$VAL" = "true" ]; then
    echo "PASS validation accepts gateway_https=true"
else
    echo "FAIL validation should accept true, got: $VAL"
fi

# ──────────────────────────────────────────────────────────────────────
# Key normalization tests (v1 → v2 aliases)
# ──────────────────────────────────────────────────────────────────────

run_oc config set API_KEY=sk-ant-normalized-key-test > /dev/null 2>&1
VAL=$(jq -r '.api_key' "$OC_CONFIG")
if [ "$VAL" = "sk-ant-normalized-key-test" ]; then
    echo "PASS key normalization: API_KEY → api_key"
else
    echo "FAIL key normalization: expected api_key=sk-ant-normalized-key-test, got $VAL"
fi

run_oc config set MODEL=gpt-4o > /dev/null 2>&1
VAL=$(jq -r '.model' "$OC_CONFIG")
if [ "$VAL" = "gpt-4o" ]; then
    echo "PASS key normalization: MODEL → model"
else
    echo "FAIL key normalization: expected model=gpt-4o, got $VAL"
fi

run_oc config set API_BASE_URL=https://custom.api.com/v1 > /dev/null 2>&1
VAL=$(jq -r '.api_base_url' "$OC_CONFIG")
if [ "$VAL" = "https://custom.api.com/v1" ]; then
    echo "PASS key normalization: API_BASE_URL → api_base_url"
else
    echo "FAIL key normalization: expected api_base_url, got $VAL"
fi

# ──────────────────────────────────────────────────────────────────────
# Backend selection priority tests
# ──────────────────────────────────────────────────────────────────────

write_config '{"$version":"2","provider":"anthropic","api_key":"sk-ant-testkey1234567890","backend":"opencode"}'

# When config has backend=opencode and --backend is not set, should use opencode
OUTPUT=$(run_oc config get backend 2>&1)
if echo "$OUTPUT" | grep -q "opencode"; then
    echo "PASS backend priority: config value used when no CLI flag"
else
    echo "FAIL backend priority: expected opencode from config, got: $OUTPUT"
fi

# Set to claude-code
run_oc config set backend=claude-code > /dev/null 2>&1
OUTPUT=$(run_oc config get backend 2>&1)
if echo "$OUTPUT" | grep -q "claude-code"; then
    echo "PASS backend priority: config value changed to claude-code"
else
    echo "FAIL backend priority: expected claude-code, got: $OUTPUT"
fi

# ── Cleanup ──────────────────────────────────────────────────────────
rm -rf "$TEST_HOME"
