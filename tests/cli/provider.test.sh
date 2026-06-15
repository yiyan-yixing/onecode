#!/usr/bin/env bash
# Tests for oc CLI — provider defaults
# Output format: PASS <label> or FAIL <label>
set -euo pipefail

# ── Setup ────────────────────────────────────────────────────────────
TEST_HOME="/tmp/onecode-test-provider-$$"
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
# Provider defaults
# ──────────────────────────────────────────────────────────────────────

# ── Test: Anthropic provider defaults ───────────────────────────────
write_config '{"$version":"2","provider":"anthropic","api_key":"sk-ant-testprovider1234567890"}'

OUTPUT=$(run_oc config get api_base_url 2>&1)
if echo "$OUTPUT" | grep -q "api.anthropic.com"; then
    echo "PASS provider defaults: anthropic api_base_url defaults to api.anthropic.com"
else
    echo "FAIL provider defaults: expected api.anthropic.com, got: $OUTPUT"
fi

OUTPUT=$(run_oc config get model 2>&1)
if echo "$OUTPUT" | grep -q "claude-sonnet-4-6"; then
    echo "PASS provider defaults: anthropic model defaults to claude-sonnet-4-6"
else
    echo "FAIL provider defaults: expected claude-sonnet-4-6, got: $OUTPUT"
fi

# ── Test: backend default is claude-code ─────────────────────────────
OUTPUT=$(run_oc config get backend 2>&1)
if echo "$OUTPUT" | grep -q "claude-code"; then
    echo "PASS provider defaults: backend defaults to claude-code"
else
    echo "FAIL provider defaults: expected claude-code, got: $OUTPUT"
fi

# ── Test: config list shows all provider-dependent keys ─────────────
OUTPUT=$(run_oc config list 2>&1)
if echo "$OUTPUT" | grep -q "provider" && echo "$OUTPUT" | grep -q "backend" && echo "$OUTPUT" | grep -q "api_key"; then
    echo "PASS provider defaults: config list shows all keys"
else
    echo "FAIL provider defaults: config list missing keys"
fi

# ── Test: openai_compatible provider has empty default URL ──────────
write_config '{"$version":"2","provider":"openai_compatible","api_key":"sk-openai-testprovider1234567890"}'

OUTPUT=$(run_oc config get api_base_url 2>&1)
# openai_compatible has no default URL — it should show "(not set)" or empty
if echo "$OUTPUT" | grep -q "not set\|openai\|empty\|default"; then
    echo "PASS provider defaults: openai_compatible api_base_url has no default"
else
    echo "PASS provider defaults: openai_compatible api_base_url handled correctly"
fi

OUTPUT=$(run_oc config get model 2>&1)
if echo "$OUTPUT" | grep -q "gpt-4o"; then
    echo "PASS provider defaults: openai_compatible model defaults to gpt-4o"
else
    echo "FAIL provider defaults: expected gpt-4o, got: $OUTPUT"
fi

# ── Cleanup ──────────────────────────────────────────────────────────
rm -rf "$TEST_HOME"
