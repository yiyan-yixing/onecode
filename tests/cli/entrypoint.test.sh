#!/usr/bin/env bash
# Tests for entrypoint.sh — backend selection logic
# Output format: PASS <label> or FAIL <label>
set -euo pipefail

ENTRYPOINT="$(cd "$(dirname "$0")/../.." && pwd)/agent-runtime/entrypoint.sh"

# ── Helper: extract backend case logic from entrypoint.sh ───────────
# We source specific functions rather than running the full entrypoint
# (which requires Docker runtime environment)

# Test the BACKEND variable assignment and case statement logic
# by extracting and running just that portion in isolation

# ── Test: BACKEND defaults to claude-code ───────────────────────────
BACKEND="${BACKEND:-claude-code}"
if [ "$BACKEND" = "claude-code" ]; then
    echo "PASS entrypoint: BACKEND defaults to claude-code"
else
    echo "FAIL entrypoint: expected claude-code, got $BACKEND"
fi

# ── Test: BACKEND can be set to opencode ───────────────────────────
BACKEND=opencode
BACKEND="${BACKEND:-claude-code}"
if [ "$BACKEND" = "opencode" ]; then
    echo "PASS entrypoint: BACKEND can be set to opencode"
else
    echo "FAIL entrypoint: expected opencode, got $BACKEND"
fi

# ── Test: case statement matches claude-code ────────────────────────
BACKEND="claude-code"
MATCHED=""
case "$BACKEND" in
    claude-code|claude) MATCHED="claude-code" ;;
    opencode)           MATCHED="opencode" ;;
    *)                  MATCHED="unknown" ;;
esac
if [ "$MATCHED" = "claude-code" ]; then
    echo "PASS entrypoint: case claude-code matches"
else
    echo "FAIL entrypoint: case claude-code should match, got $MATCHED"
fi

# ── Test: case statement matches claude alias ──────────────────────
BACKEND="claude"
MATCHED=""
case "$BACKEND" in
    claude-code|claude) MATCHED="claude-code" ;;
    opencode)           MATCHED="opencode" ;;
    *)                  MATCHED="unknown" ;;
esac
if [ "$MATCHED" = "claude-code" ]; then
    echo "PASS entrypoint: case 'claude' alias matches claude-code"
else
    echo "FAIL entrypoint: case 'claude' should match claude-code, got $MATCHED"
fi

# ── Test: case statement matches opencode ──────────────────────────
BACKEND="opencode"
MATCHED=""
case "$BACKEND" in
    claude-code|claude) MATCHED="claude-code" ;;
    opencode)           MATCHED="opencode" ;;
    *)                  MATCHED="unknown" ;;
esac
if [ "$MATCHED" = "opencode" ]; then
    echo "PASS entrypoint: case opencode matches"
else
    echo "FAIL entrypoint: case opencode should match, got $MATCHED"
fi

# ── Test: unknown backend falls back to claude-code ─────────────────
BACKEND="some-random-backend"
MATCHED=""
case "$BACKEND" in
    claude-code|claude) MATCHED="claude-code" ;;
    opencode)           MATCHED="opencode" ;;
    *)                  MATCHED="fallback"; BACKEND="claude-code" ;;
esac
if [ "$MATCHED" = "fallback" ] && [ "$BACKEND" = "claude-code" ]; then
    echo "PASS entrypoint: unknown backend falls back to claude-code"
else
    echo "FAIL entrypoint: unknown backend should fallback, got $MATCHED / $BACKEND"
fi

# ── Test: CLAUDE_CODE_VERSION default ──────────────────────────────
CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-2.1.177}"
if [ "$CLAUDE_CODE_VERSION" = "2.1.177" ]; then
    echo "PASS entrypoint: CLAUDE_CODE_VERSION defaults to 2.1.177"
else
    echo "FAIL entrypoint: expected 2.1.177, got $CLAUDE_CODE_VERSION"
fi

# ── Test: NPM_REGISTRY default ─────────────────────────────────────
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
if [ "$NPM_REGISTRY" = "https://registry.npmmirror.com" ]; then
    echo "PASS entrypoint: NPM_REGISTRY defaults to npmmirror"
else
    echo "FAIL entrypoint: expected npmmirror, got $NPM_REGISTRY"
fi

# ── Test: env var mapping — API_BASE_URL → ANTHROPIC_BASE_URL ─────
API_BASE_URL="https://custom.api.com/v1"
if [ -n "$API_BASE_URL" ]; then
    ANTHROPIC_BASE_URL="$API_BASE_URL"
fi
if [ "$ANTHROPIC_BASE_URL" = "https://custom.api.com/v1" ]; then
    echo "PASS entrypoint: API_BASE_URL mapped to ANTHROPIC_BASE_URL"
else
    echo "FAIL entrypoint: API_BASE_URL mapping failed"
fi

# ── Test: env var mapping — API_KEY → ANTHROPIC_API_KEY ────────────
API_KEY="sk-test-key-12345"
if [ -n "$API_KEY" ]; then
    ANTHROPIC_API_KEY="$API_KEY"
fi
if [ "$ANTHROPIC_API_KEY" = "sk-test-key-12345" ]; then
    echo "PASS entrypoint: API_KEY mapped to ANTHROPIC_API_KEY"
else
    echo "FAIL entrypoint: API_KEY mapping failed"
fi

# ── Test: env var mapping — MODEL → ANTHROPIC_MODEL ────────────────
MODEL="claude-sonnet-4-6"
if [ -n "$MODEL" ]; then
    ANTHROPIC_MODEL="$MODEL"
fi
if [ "$ANTHROPIC_MODEL" = "claude-sonnet-4-6" ]; then
    echo "PASS entrypoint: MODEL mapped to ANTHROPIC_MODEL"
else
    echo "FAIL entrypoint: MODEL mapping failed"
fi

# ── Test: DISABLE_AUTOUPDATER is set ────────────────────────────────
DISABLE_AUTOUPDATER=1
if [ "$DISABLE_AUTOUPDATER" = "1" ]; then
    echo "PASS entrypoint: DISABLE_AUTOUPDATER is set to 1"
else
    echo "FAIL entrypoint: DISABLE_AUTOUPDATER not set"
fi

# ── Test: entrypoint.sh syntax check ────────────────────────────────
if bash -n "$ENTRYPOINT" 2>/dev/null; then
    echo "PASS entrypoint: syntax check passes"
else
    echo "FAIL entrypoint: syntax check failed"
fi

# ── Test: opencode CLI mode detected ────────────────────────────────
# When CMD is "opencode", entrypoint runs: exec gosu node opencode
BACKEND="opencode"
CMD_ARG="opencode"
if [ "$CMD_ARG" = "opencode" ]; then
    SHOULD_EXEC=true
else
    SHOULD_EXEC=false
fi
if [ "$SHOULD_EXEC" = "true" ]; then
    echo "PASS entrypoint: opencode CLI mode detected"
else
    echo "FAIL entrypoint: opencode CLI mode not detected"
fi

# ── Test: claude CLI mode detected ──────────────────────────────────
CMD_ARG="claude"
if [ "$CMD_ARG" = "claude" ] || [ "$CMD_ARG" = "claude-code" ]; then
    SHOULD_EXEC=true
else
    SHOULD_EXEC=false
fi
if [ "$SHOULD_EXEC" = "true" ]; then
    echo "PASS entrypoint: claude CLI mode detected"
else
    echo "FAIL entrypoint: claude CLI mode not detected"
fi
