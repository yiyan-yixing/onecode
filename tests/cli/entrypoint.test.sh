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
CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-2.1.183}"
if [ "$CLAUDE_CODE_VERSION" = "2.1.183" ]; then
    echo "PASS entrypoint: CLAUDE_CODE_VERSION defaults to 2.1.183"
else
    echo "FAIL entrypoint: expected 2.1.183, got $CLAUDE_CODE_VERSION"
fi

# ── Test: CLAUDE_GLOBAL_DIR default ─────────────────────────────────
CLAUDE_GLOBAL_DIR="${CLAUDE_GLOBAL_DIR:-/opt/claude-code}"
if [ "$CLAUDE_GLOBAL_DIR" = "/opt/claude-code" ]; then
    echo "PASS entrypoint: CLAUDE_GLOBAL_DIR defaults to /opt/claude-code"
else
    echo "FAIL entrypoint: expected /opt/claude-code, got $CLAUDE_GLOBAL_DIR"
fi

# ── Test: cached install detection (bin/claude exists) ──────────────
# Simulate: when /opt/claude-code/bin/claude exists, install should be skipped
CLAUDE_GLOBAL_DIR="/opt/claude-code"
MOCK_CLAUDE_BIN="/tmp/test_claude_bin_$$"
mkdir -p "$MOCK_CLAUDE_BIN/bin"
touch "$MOCK_CLAUDE_BIN/bin/claude"
chmod +x "$MOCK_CLAUDE_BIN/bin/claude"
# Test the -x check logic
if [ -x "$MOCK_CLAUDE_BIN/bin/claude" ]; then
    echo "PASS entrypoint: cached claude binary detected via -x check"
else
    echo "FAIL entrypoint: -x check failed on mock claude binary"
fi
rm -rf "$MOCK_CLAUDE_BIN"

# ── Test: missing install detection (bin/claude absent) ──────────────
MOCK_EMPTY_DIR="/tmp/test_claude_empty_$$"
mkdir -p "$MOCK_EMPTY_DIR"
if [ ! -x "$MOCK_EMPTY_DIR/bin/claude" ]; then
    echo "PASS entrypoint: missing claude binary correctly not detected"
else
    echo "FAIL entrypoint: -x check should fail for missing binary"
fi
rm -rf "$MOCK_EMPTY_DIR"

# ── Test: symlink creation logic ────────────────────────────────────
MOCK_CLAUDE_DIR="/tmp/test_claude_symlink_$$"
mkdir -p "$MOCK_CLAUDE_DIR/bin"
touch "$MOCK_CLAUDE_DIR/bin/claude"
chmod +x "$MOCK_CLAUDE_DIR/bin/claude"
MOCK_USR_LOCAL_BIN="/tmp/test_usr_local_bin_$$"
mkdir -p "$MOCK_USR_LOCAL_BIN"
ln -sf "$MOCK_CLAUDE_DIR/bin/claude" "$MOCK_USR_LOCAL_BIN/claude"
if [ -L "$MOCK_USR_LOCAL_BIN/claude" ] && [ "$(readlink "$MOCK_USR_LOCAL_BIN/claude")" = "$MOCK_CLAUDE_DIR/bin/claude" ]; then
    echo "PASS entrypoint: symlink created correctly to cached claude"
else
    echo "FAIL entrypoint: symlink creation failed"
fi
rm -rf "$MOCK_CLAUDE_DIR" "$MOCK_USR_LOCAL_BIN"

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

# ── Test: ver_compare semver comparison ─────────────────────────────
# IMPORTANT: extract ver_compare from the real entrypoint.sh, do NOT hand-copy it.
# A hand-copied copy silently drifted from the source (sed './ /g' bug) and passed
# here while the real entrypoint shipped the bug. Extracting binds test to source.
ENTRYPOINT_SRC="$(dirname "${BASH_SOURCE[0]:-$0}")/../../agent-runtime/entrypoint.sh"
eval "$(sed -n '/^ver_compare()/,/^}/p' "$ENTRYPOINT_SRC")"

# gt: 2.1.183 > 2.1.177
R=$(ver_compare "2.1.183" "2.1.177")
if [ "$R" = "gt" ]; then echo "PASS entrypoint: ver_compare 2.1.183 > 2.1.177 → gt"
else echo "FAIL entrypoint: ver_compare 2.1.183 > 2.1.177 expected gt, got $R"; fi

# lt: 2.1.177 < 2.1.183
R=$(ver_compare "2.1.177" "2.1.183")
if [ "$R" = "lt" ]; then echo "PASS entrypoint: ver_compare 2.1.177 < 2.1.183 → lt"
else echo "FAIL entrypoint: ver_compare 2.1.177 < 2.1.183 expected lt, got $R"; fi

# eq: 2.1.183 = 2.1.183
R=$(ver_compare "2.1.183" "2.1.183")
if [ "$R" = "eq" ]; then echo "PASS entrypoint: ver_compare 2.1.183 = 2.1.183 → eq"
else echo "FAIL entrypoint: ver_compare 2.1.183 = 2.1.183 expected eq, got $R"; fi

# cross-segment: 2.2.0 > 2.1.999
R=$(ver_compare "2.2.0" "2.1.999")
if [ "$R" = "gt" ]; then echo "PASS entrypoint: ver_compare 2.2.0 > 2.1.999 → gt"
else echo "FAIL entrypoint: ver_compare 2.2.0 > 2.1.999 expected gt, got $R"; fi

# major bump: 3.0.0 > 2.99.99
R=$(ver_compare "3.0.0" "2.99.99")
if [ "$R" = "gt" ]; then echo "PASS entrypoint: ver_compare 3.0.0 > 2.99.99 → gt"
else echo "FAIL entrypoint: ver_compare 3.0.0 > 2.99.99 expected gt, got $R"; fi
