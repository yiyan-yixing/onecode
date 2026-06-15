#!/bin/sh
# gh_fetch: download from GitHub with mirror fallback
# Usage: gh_fetch <github_path> <output_path>
#   gh_fetch "owner/repo/releases/download/v1/file.tar.gz" - | tar xz
#   gh_fetch "owner/repo/releases/download/v1/file.zip" /tmp/file.zip
#
# Env: GH_MIRROR — mirror prefix (e.g. https://gh-proxy.com), empty = direct
set -e

GH_PATH="$1"
OUT="$2"
MIRROR="${GH_MIRROR:-}"
DIRECT="https://github.com"
# --http1.1 avoids HTTP/2 stream errors under QEMU cross-platform emulation
CURL_OPTS="-fsSL --http1.1"

if [ -z "$MIRROR" ]; then
  curl $CURL_OPTS "${DIRECT}/${GH_PATH}" -o "$OUT"
else
  curl $CURL_OPTS "${MIRROR}/${GH_PATH}" -o "$OUT" 2>/dev/null \
    || curl $CURL_OPTS "${DIRECT}/${GH_PATH}" -o "$OUT"
fi
