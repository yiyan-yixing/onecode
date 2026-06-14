#!/bin/bash
# Start remote mode: gateway (with PTY) + filebrowser + code-server
set -eo pipefail

GATEWAY_PORT="${TTYD_PORT:-7681}"
FB_PORT=8081
VSCODE_INTERNAL_PORT=8082
TERM_TOKEN="${TTYD_TOKEN:-}"

# Track background process PIDs for cleanup
CHILD_PIDS=""

cleanup() {
    # Send SIGTERM to all children, then SIGKILL after grace period
    for pid in $CHILD_PIDS; do
        kill "$pid" 2>/dev/null || true
    done
    sleep 2
    for pid in $CHILD_PIDS; do
        kill -9 "$pid" 2>/dev/null || true
    done
}
trap cleanup EXIT

# Start filebrowser (web file manager)
gosu node filebrowser --noauth --port "$FB_PORT" --root /workspace --baseurl /files --database /tmp/filebrowser.db &
CHILD_PIDS="$CHILD_PIDS $!"

# Generate self-signed TLS certificate if HTTPS is requested
if [ "${GATEWAY_HTTPS:-0}" = "1" ]; then
    GATEWAY_CERT="/tmp/gateway-cert.pem"
    GATEWAY_KEY="/tmp/gateway-key.pem"
    openssl req -x509 -newkey rsa:2048 \
        -keyout "$GATEWAY_KEY" -out "$GATEWAY_CERT" \
        -days 365 -nodes -subj '/CN=onecode' \
        -addext 'subjectAltName=DNS=onecode,IP:0.0.0.0' \
        2>/dev/null
    chown node:node "$GATEWAY_CERT" "$GATEWAY_KEY"
    export GATEWAY_CERT GATEWAY_KEY
else
    unset GATEWAY_CERT GATEWAY_KEY
fi

# Configure code-server (polyfill, product.json, API credentials)
source /usr/local/bin/onecode/setup-code-server.sh "$VSCODE_INTERNAL_PORT"

NAV_POLYFILL="/usr/local/share/onecode/navigator-polyfill.js"

gosu node env NODE_OPTIONS="--require ${NAV_POLYFILL}" ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" ANTHROPIC_BASE_URL="$ANTHROPIC_BASE_URL" ANTHROPIC_MODEL="$ANTHROPIC_MODEL" code-server \
    --bind-addr 127.0.0.1:$VSCODE_INTERNAL_PORT \
    --auth none \
    --disable-workspace-trust \
    --disable-telemetry \
    /workspace &
CHILD_PIDS="$CHILD_PIDS $!"

# Start gateway (main process — now includes terminal server + PTY)
# Run in background so EXIT trap can clean up sibling processes on termination
export GATEWAY_PORT FB_PORT VSCODE_INTERNAL_PORT TERM_TOKEN CHILD_PIDS
gosu node node /usr/local/share/gateway/index.js &
GATEWAY_PID=$!
CHILD_PIDS="$CHILD_PIDS $GATEWAY_PID"
wait $GATEWAY_PID
