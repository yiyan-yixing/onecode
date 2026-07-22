#!/usr/bin/env bash
# Tests for oc CLI — v1 → v2 config migration
# Output format: PASS <label> or FAIL <label>
set -euo pipefail

# ── Setup ────────────────────────────────────────────────────────────
TEST_HOME="/tmp/onecode-test-migrate-$$"
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
# v1 → v2 migration
# ──────────────────────────────────────────────────────────────────────

# ── Test: migrate v1 config with Anthropic URL ─────────────────────
write_config '{"API_KEY":"sk-ant-oldkey123","API_BASE_URL":"https://api.anthropic.com","MODEL":"claude-3-opus-20240229"}'

# Any oc command should trigger migration
run_oc config list > /dev/null 2>&1

VERSION=$(jq -r '."$version"' "$OC_CONFIG" 2>/dev/null || echo "")
PROVIDER=$(jq -r '.provider' "$OC_CONFIG" 2>/dev/null || echo "")
API_KEY=$(jq -r '.api_key' "$OC_CONFIG" 2>/dev/null || echo "")
MODEL=$(jq -r '.model' "$OC_CONFIG" 2>/dev/null || echo "")

if [ "$VERSION" = "2" ]; then
    echo "PASS v1→v2 migration: version set to 2"
else
    echo "FAIL v1→v2 migration: expected version=2, got $VERSION"
fi

if [ "$PROVIDER" = "anthropic" ]; then
    echo "PASS v1→v2 migration: provider inferred as anthropic from URL"
else
    echo "FAIL v1→v2 migration: expected provider=anthropic, got $PROVIDER"
fi

if [ "$API_KEY" = "sk-ant-oldkey123" ]; then
    echo "PASS v1→v2 migration: API_KEY migrated to api_key"
else
    echo "FAIL v1→v2 migration: expected api_key=sk-ant-oldkey123, got $API_KEY"
fi

if [ "$MODEL" = "claude-3-opus-20240229" ]; then
    echo "PASS v1→v2 migration: MODEL migrated to model"
else
    echo "FAIL v1→v2 migration: expected model=claude-3-opus-20240229, got $MODEL"
fi

# ── Test: migrate v1 config with non-Anthropic URL ──────────────────
rm -f "$OC_CONFIG"
write_config '{"API_KEY":"sk-custom-key","API_BASE_URL":"https://gateway.example.com/v1","MODEL":"gpt-4o"}'

run_oc config list > /dev/null 2>&1

PROVIDER=$(jq -r '.provider' "$OC_CONFIG" 2>/dev/null || echo "")
if [ "$PROVIDER" = "openai_compatible" ]; then
    echo "PASS v1→v2 migration: provider inferred as openai_compatible from custom URL"
else
    echo "FAIL v1→v2 migration: expected provider=openai_compatible, got $PROVIDER"
fi

# ── Test: v2 config not re-migrated ─────────────────────────────────
rm -f "$OC_CONFIG"
write_config '{"$version":"2","provider":"anthropic","api_key":"sk-ant-alreadyv2","model":"claude-sonnet-4-6"}'

run_oc config list > /dev/null 2>&1

API_KEY=$(jq -r '.api_key' "$OC_CONFIG" 2>/dev/null || echo "")
if [ "$API_KEY" = "sk-ant-alreadyv2" ]; then
    echo "PASS v1→v2 migration: v2 config not re-migrated"
else
    echo "FAIL v1→v2 migration: v2 config was incorrectly modified"
fi

# ── Test: empty config doesn't crash ────────────────────────────────
rm -f "$OC_CONFIG"
run_oc config list > /dev/null 2>&1
echo "PASS v1→v2 migration: no config file doesn't crash"

# ── Test: malformed config doesn't crash ────────────────────────────
write_config 'this is not json'
run_oc config list > /dev/null 2>&1
echo "PASS v1→v2 migration: malformed config doesn't crash"

# ── Cleanup ──────────────────────────────────────────────────────────
rm -rf "$TEST_HOME"
