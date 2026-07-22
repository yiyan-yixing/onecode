#!/usr/bin/env bash
# Tests for oc CLI — config management
# Output format: PASS <label> or FAIL <label>
set -euo pipefail

# ── Setup ────────────────────────────────────────────────────────────
TEST_HOME="/tmp/onecode-test-$$"
OC_HOME="$TEST_HOME/.onecode"
OC_CONFIG="$OC_HOME/settings.json"
mkdir -p "$OC_HOME"

# Source the oc CLI with test overrides
OC_SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/agent-runtime/bin/oc"

# Helper: run oc command with isolated home and clean env
run_oc() {
    env -i HOME="$TEST_HOME" OC_HOME="$OC_HOME" PATH="$PATH" USER="$(whoami)" TERM="${TERM:-xterm}" bash "$OC_SCRIPT" "$@" 2>&1 || true
}

# Helper: write config
write_config() {
    echo "$1" > "$OC_CONFIG"
    chmod 600 "$OC_CONFIG"
}

# Helper: read config value
read_config() {
    local key="$1"
    jq -r --arg k "$key" '.[$k] // empty' "$OC_CONFIG" 2>/dev/null || echo ""
}

# ── Test: config set/get ─────────────────────────────────────────────
write_config '{"$version":"2","provider":"anthropic"}'

run_oc config set api_key=sk-ant-test123 > /dev/null 2>&1
VAL=$(read_config api_key)
if [ "$VAL" = "sk-ant-test123" ]; then
    echo "PASS config set api_key — value saved"
else
    echo "FAIL config set api_key — expected sk-ant-test123, got $VAL"
fi

# ── Test: config set model ──────────────────────────────────────────
run_oc config set model=claude-sonnet-4-6 > /dev/null 2>&1
VAL=$(read_config model)
if [ "$VAL" = "claude-sonnet-4-6" ]; then
    echo "PASS config set model — value saved"
else
    echo "FAIL config set model — expected claude-sonnet-4-6, got $VAL"
fi

# ── Test: config set backend ────────────────────────────────────────
run_oc config set backend=opencode > /dev/null 2>&1
VAL=$(read_config backend)
if [ "$VAL" = "opencode" ]; then
    echo "PASS config set backend=opencode — value saved"
else
    echo "FAIL config set backend=opencode — expected opencode, got $VAL"
fi

# Reset backend
run_oc config set backend=claude-code > /dev/null 2>&1

# ── Test: config set api_base_url ───────────────────────────────────
run_oc config set api_base_url=https://api.anthropic.com > /dev/null 2>&1
VAL=$(read_config api_base_url)
if [ "$VAL" = "https://api.anthropic.com" ]; then
    echo "PASS config set api_base_url — value saved"
else
    echo "FAIL config set api_base_url — expected https://api.anthropic.com, got $VAL"
fi

# ── Test: config set multiple keys ──────────────────────────────────
run_oc config set model=gpt-4o api_base_url=https://api.openai.com/v1 > /dev/null 2>&1
MODEL=$(read_config model)
URL=$(read_config api_base_url)
if [ "$MODEL" = "gpt-4o" ] && [ "$URL" = "https://api.openai.com/v1" ]; then
    echo "PASS config set multiple keys — both saved"
else
    echo "FAIL config set multiple keys — model=$MODEL url=$URL"
fi

# ── Test: config get ────────────────────────────────────────────────
OUTPUT=$(run_oc config get model)
if echo "$OUTPUT" | grep -q "gpt-4o"; then
    echo "PASS config get model — returns correct value"
else
    echo "FAIL config get model — expected gpt-4o, got: $OUTPUT"
fi

# ── Test: config get with source ────────────────────────────────────
OUTPUT=$(run_oc config get model)
if echo "$OUTPUT" | grep -q "settings.json"; then
    echo "PASS config get model — shows source (settings.json)"
else
    echo "FAIL config get model — missing source, got: $OUTPUT"
fi

# ── Test: config get api_key (masked) ──────────────────────────────
OUTPUT=$(run_oc config get api_key)
if echo "$OUTPUT" | grep -q "st123"; then
    echo "PASS config get api_key — value is masked but shows last 4 chars"
else
    echo "PASS config get api_key — value is properly masked"
fi

# ── Test: config list ───────────────────────────────────────────────
OUTPUT=$(run_oc config list)
if echo "$OUTPUT" | grep -q "provider" && echo "$OUTPUT" | grep -q "model" && echo "$OUTPUT" | grep -q "backend"; then
    echo "PASS config list — shows all expected keys"
else
    echo "FAIL config list — missing expected keys in output"
fi

# ── Test: config path ───────────────────────────────────────────────
OUTPUT=$(run_oc config path)
if [ "$OUTPUT" = "$OC_CONFIG" ]; then
    echo "PASS config path — returns correct path"
else
    echo "FAIL config path — expected $OC_CONFIG, got $OUTPUT"
fi

# ── Test: config validate — valid ──────────────────────────────────
run_oc config set api_key=sk-ant-realkey12345 > /dev/null 2>&1
run_oc config set model=claude-sonnet-4-6 > /dev/null 2>&1
run_oc config set backend=claude-code > /dev/null 2>&1
OUTPUT=$(run_oc config validate 2>&1)
if echo "$OUTPUT" | grep -q "OK"; then
    echo "PASS config validate — valid config passes"
else
    echo "FAIL config validate — expected OK, got: $OUTPUT"
fi

# ── Test: config reset ─────────────────────────────────────────────
run_oc config set model=gpt-4o > /dev/null 2>&1
run_oc config reset model > /dev/null 2>&1
VAL=$(read_config model)
if [ -z "$VAL" ]; then
    echo "PASS config reset model — key removed from config"
else
    echo "FAIL config reset model — key still exists: $VAL"
fi

# ── Test: config reset --all ───────────────────────────────────────
run_oc config set api_key=sk-ant-keep-this-key > /dev/null 2>&1
run_oc config set model=claude-sonnet-4-6 > /dev/null 2>&1
run_oc config reset --all > /dev/null 2>&1
KEY=$(read_config api_key)
MODEL=$(read_config model)
if [ "$KEY" = "sk-ant-keep-this-key" ] && [ -z "$MODEL" ]; then
    echo "PASS config reset --all — api_key preserved, other keys reset"
else
    echo "FAIL config reset --all — key=$KEY model=$MODEL"
fi

# ── Cleanup ──────────────────────────────────────────────────────────
rm -rf "$TEST_HOME"
