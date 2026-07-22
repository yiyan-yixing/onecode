#!/bin/sh
# gh_fetch: download from GitHub release/raw via multi-mirror acceleration + fallback
# Usage: gh_fetch <github_path> <output_path>
#   gh_fetch "owner/repo/releases/download/v1/file.tar.gz" - | tar xz
#   gh_fetch "owner/repo/raw/main/file" /tmp/file
#
# Env:
#   GH_MIRROR — mirror prefix or comma-separated list
#               (e.g. "https://ghfast.top" or "https://ghfast.top,https://gh.llkk.cc")
#               Default: built-in list (verified reachable). Empty = direct github.com only.
set -e

GH_PATH="$1"
OUT="$2"
DIRECT="https://github.com"
# --http1.1 avoids HTTP/2 stream errors under QEMU cross-platform emulation.
# connect-timeout: give up on a dead mirror fast; max-time: cap a slow one.
CURL_OPTS="-fsSL --http1.1 --connect-timeout 8 --max-time 300"

# Built-in CN GitHub accelerators, tried in order. Each proxies the full github URL.
DEFAULT_MIRRORS="https://ghfast.top,https://gh.llkk.cc,https://gh-proxy.com"

MIRRORS="${GH_MIRROR:-$DEFAULT_MIRRORS}"

if [ -n "$MIRRORS" ]; then
  OLD_IFS="$IFS"
  IFS=','
  for m in $MIRRORS; do
    [ -z "$m" ] && continue
    # curl failing inside `if` does not trip `set -e`; fall through to next mirror
    if curl $CURL_OPTS "${m}/https://github.com/${GH_PATH}" -o "$OUT" 2>/dev/null; then
      exit 0
    fi
  done
  IFS="$OLD_IFS"
fi

# last resort: direct github.com (fails the build if this also fails)
curl $CURL_OPTS "${DIRECT}/${GH_PATH}" -o "$OUT"
