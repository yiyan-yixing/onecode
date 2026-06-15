#!/bin/bash
set -e

# Fix UID mismatch: adjust node user's UID to match /workspace mount owner
if [ "$(id -u)" = "0" ] && [ -d /workspace ]; then
    MOUNT_UID=$(stat -c '%u' /workspace)
    NODE_UID=$(id -u node)
    if [ "$MOUNT_UID" != "$NODE_UID" ] && [ "$MOUNT_UID" != "0" ]; then
        usermod -u "$MOUNT_UID" node
        chown node /home/work
        for d in /home/work/.claude /home/work/.bashrc /home/work/.local /home/work/.config; do
            [ -e "$d" ] && chown -R node "$d"
        done
        [ -f /home/work/.claude.json ] && chown node /home/work/.claude.json
        echo "[entrypoint] Adjusted node UID $NODE_UID -> $MOUNT_UID to match /workspace owner"
    fi
fi

# Install AI backend CLI at runtime (not pre-baked into the image)
# This avoids redistribution of proprietary software.
# OpenCode (MIT) is pre-installed in the image; Claude Code is installed on demand.
BACKEND="${BACKEND:-claude-code}"
CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-2.1.177}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
CLAUDE_INSTALL_LOG="/tmp/claude-install.log"

case "$BACKEND" in
    claude-code|claude)
        if ! command -v claude &>/dev/null; then
            echo "[entrypoint] Backend: claude-code — Installing Claude Code CLI v${CLAUDE_CODE_VERSION}..."
            echo "[entrypoint] This only happens on first start. Gateway is starting in parallel."

            # Install in background so gateway can start immediately
            (
                if [ "$(id -u)" = "0" ]; then
                    npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
                        --registry="$NPM_REGISTRY" \
                        --no-optional \
                        --no-audit \
                        --no-fund \
                        --prefer-online \
                    && npm cache clean --force 2>/dev/null
                else
                    npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
                        --registry="$NPM_REGISTRY" \
                        --no-optional \
                        --no-audit \
                        --no-fund \
                    && npm cache clean --force 2>/dev/null || true
                fi
                echo "[entrypoint] Claude Code CLI installed successfully." > "$CLAUDE_INSTALL_LOG"
            ) &

            export CLAUDE_INSTALL_PID=$!
        else
            echo "[entrypoint] Backend: claude-code — already installed."
        fi
        ;;
    opencode)
        if command -v opencode &>/dev/null; then
            echo "[entrypoint] Backend: opencode — ready."
        else
            echo "[entrypoint] Backend: opencode — WARNING: opencode not found in image."
            echo "[entrypoint] Falling back to claude-code."
            BACKEND="claude-code"
        fi
        ;;
    *)
        echo "[entrypoint] WARNING: Unknown backend '$BACKEND'. Valid options: claude-code, opencode"
        echo "[entrypoint] Falling back to claude-code."
        BACKEND="claude-code"
        ;;
esac

export BACKEND

# Map generic env vars to Claude Code's native env vars
export DISABLE_AUTOUPDATER=1
if [ -n "$API_BASE_URL" ]; then
    export ANTHROPIC_BASE_URL="$API_BASE_URL"
fi
if [ -n "$API_KEY" ]; then
    export ANTHROPIC_API_KEY="$API_KEY"
    unset ANTHROPIC_AUTH_TOKEN
    # Pre-approve custom API key in .claude.json to skip the dialog
    # Note: bash ${var: -20} returns empty when string < 20 chars, but JS .slice(-20)
    # returns the whole string. Use printf+tail to match JS behavior exactly.
    KEY_SUFFIX="$(printf '%s' "$API_KEY" | tail -c 20)"
    if [ -f /home/work/.claude.json ] && command -v node >/dev/null 2>&1; then
        SUFFIX="$KEY_SUFFIX" node -e '
var f="/home/work/.claude.json",d=JSON.parse(require("fs").readFileSync(f,"utf8"));
if (!d.customApiKeyResponses) { d.customApiKeyResponses = { approved: [], rejected: [] }; }
if (!d.customApiKeyResponses.approved) { d.customApiKeyResponses.approved = []; }
var s=process.env.SUFFIX;
if (s && d.customApiKeyResponses.approved.indexOf(s) < 0) { d.customApiKeyResponses.approved.push(s); }
require("fs").writeFileSync(f,JSON.stringify(d));
' 2>/dev/null || true
    fi
fi
if [ -n "$MODEL" ]; then
    export ANTHROPIC_MODEL="$MODEL"
fi

# Start SSH server (for VS Code Remote-SSH)
source /usr/local/bin/onecode/start-sshd.sh

# Web terminal mode: gateway + filebrowser
if [ "$1" = "remote" ]; then
    shift
    exec /usr/local/bin/onecode/start-remote.sh "$@"
fi

# CLI mode: start the selected backend
if [ "$1" = "claude" ] || [ "$1" = "claude-code" ]; then
    exec gosu node "$@" --permission-mode bypassPermissions
fi

# If CMD is empty or default, start backend based on BACKEND env
if [ "$1" = "opencode" ]; then
    exec gosu node opencode
fi

# Default: run as node user
if [ "$(id -u)" = "0" ]; then
    exec gosu node "$@"
fi

exec "$@"
