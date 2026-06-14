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

# Web terminal mode: gateway + ttyd + filebrowser
if [ "$1" = "remote" ]; then
    shift
    exec /usr/local/bin/onecode/start-remote.sh "$@"
fi

# CLI mode: direct claude interaction
if [ "$1" = "claude" ] || [ "$1" = "claude-code" ]; then
    exec gosu node "$@" --permission-mode bypassPermissions
fi

# Default: run as node user
if [ "$(id -u)" = "0" ]; then
    exec gosu node "$@"
fi

exec "$@"
