#!/usr/bin/env bash
set -euo pipefail

# ── OneCode - Install ────────────────────────────────────
# One-click install script for cloud servers and macOS.
# Supports: Linux (amd64/arm64), macOS (amd64/arm64)
# Image is always linux/amd64 (Rosetta/QEMU emulation on arm64 hosts).
# Usage:
#   curl -fsSL <raw-url>/install.sh | bash
#   curl -fsSL <raw-url>/install.sh | bash -s -- --api-key sk-xxx --provider anthropic

# Keep in sync with agent-runtime/VERSION
VERSION="0.5.0"
IMAGE_REPO="ghcr.io/yiyan-yixing/onecode"
IMAGE_TAG="latest"
OC_HOME="${OC_HOME:-$HOME/.onecode}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
REPO_OWNER="yiyan-yixing"
REPO_NAME="onecode"
REPO_BRANCH="main"

# Defaults — provider-based (matches oc CLI v2 config system)
PROVIDER="anthropic"
API_KEY=""
API_BASE_URL=""
MODEL=""
DOCKER_PLATFORM="linux/amd64"
GH_MIRROR="https://gh-proxy.com"
REGISTRY_USER=""
REGISTRY_PASS=""
SKIP_DOCKER=false
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Provider defaults (single source of truth)
PROVIDER_DEFAULTS_anthropic_api_base_url="https://api.anthropic.com"
PROVIDER_DEFAULTS_anthropic_model="claude-sonnet-4-6"
PROVIDER_DEFAULTS_openai_compatible_api_base_url=""
PROVIDER_DEFAULTS_openai_compatible_model="gpt-4o"
PROVIDER_DEFAULTS_opencode_api_base_url=""
PROVIDER_DEFAULTS_opencode_model="local"

# v2 config defaults (used by configure())
BACKEND="${BACKEND:-claude-code}"
GATEWAY_PORT="7681"
APP_PORT="8000"
SSH_PORT="8222"
TERM_TOKEN=""
GATEWAY_HTTPS="false"

# ── Colors & Output ────────────────────────────────────────────────
# Auto-disable colors when piped (curl | bash > log.txt)
if [ -t 1 ]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[0;33m'
    CYAN=$'\033[0;36m'
    DIM=$'\033[2m'
    BOLD=$'\033[1m'
    NC=$'\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' DIM='' BOLD='' NC=''
fi

# Terminal width (for box/line drawing; fallback to 80)
TERM_WIDTH="${COLUMNS:-80}"
[ "$TERM_WIDTH" -lt 50 ] 2>/dev/null && TERM_WIDTH=50
[ "$TERM_WIDTH" -gt 80 ] 2>/dev/null && TERM_WIDTH=80

# Legacy helpers (kept for internal use, prefer step_* functions)
info()  { echo "${CYAN}[info]${NC} $*"; }
ok()    { echo "${GREEN}[ok]${NC} $*"; }
warn()  { echo "${YELLOW}[warn]${NC} $*"; }
err()   { echo "${RED}[error]${NC} $*" >&2; }

# Step status markers (primary user-facing output)
step_ok()   { echo "  ${GREEN}✓${NC} $*"; }
step_wait() { echo "  ${YELLOW}⏳${NC} $*"; }
step_skip() { echo "  ${DIM}─${NC} $* ${DIM}(skipped)${NC}"; }
step_err()  { echo "  ${RED}✗${NC} $*" >&2; }

# Step header: ── [1/8] 检测环境 ───────────────
step_header() {
    local n="$1" total="$2" label="$3"
    local line_width=$((TERM_WIDTH - 6 - ${#n} - ${#total} - ${#label} - 3))
    [ "$line_width" -lt 5 ] && line_width=5
    echo ""
    echo "  ${CYAN}──${NC} [${n}/${total}] ${label} ${CYAN}$(printf '─%.0s' $(seq 1 "$line_width"))${NC}"
}

# Box drawing: ╭────╮ ... │ text │ ... ╰────╯
show_box() {
    local w="${1:-55}"
    [ "$w" -lt 30 ] && w=30
    echo "  ${CYAN}╭$(printf '─%.0s' $(seq 1 $((w-2))))╮${NC}"
    shift
    for line in "$@"; do
        # Skip empty variable expansions (e.g. optional lines)
        [ -z "$line" ] && continue
        # Pad or truncate line to fit inside box
        local trimmed
        trimmed="$(printf '%-'"$((w-3))".'s' "$(echo "$line" | head -c $((w-4)))")"
        printf "  ${CYAN}│${NC} %s ${CYAN}│${NC}\n" "$trimmed"
    done
    echo "  ${CYAN}╰$(printf '─%.0s' $(seq 1 $((w-2))))╯${NC}"
}

# Error box: structured error with reason + recovery
error_box() {
    local title="${1:-Error}"
    shift
    local w=55
    echo "" >&2
    show_box "$w" \
        "${RED}${BOLD}${title}${NC}" \
        "" \
        "$@" \
        "" \
        "${DIM}Log: /tmp/onecode-install.log${NC}" >&2
    echo "" >&2
}

# ── GitHub fetch helper ────────────────────────────────────────────
# Robust download with multiple fallback strategies.
# Priority: mirror → GitHub API → direct raw → insecure fallback
# GitHub API is preferred over raw.githubusercontent.com because:
#   - Different CDN, not affected by raw.* DNS pollution in China
#   - No SSL certificate mismatch issues
#   - Works without any third-party mirror
github_fetch() {
    local path="$1"
    local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${path}?ref=${REPO_BRANCH}"
    local raw_url="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/${path}"
    local mirror_url=""

    # Build mirror URL if GH_MIRROR is set
    if [ -n "${GH_MIRROR:-}" ]; then
        # Mirror path format: mirror/raw.githubusercontent.com/owner/repo/branch/path
        mirror_url="${GH_MIRROR}/${raw_url}"
    fi

    # Priority 1: Mirror (if configured)
    if [ -n "$mirror_url" ]; then
        if curl -fsSL --http1.1 "$mirror_url" 2>/dev/null; then
            return 0
        fi
        warn "Mirror download failed, trying next method..."
    fi

    # Priority 2: GitHub API (most reliable — different CDN, no DNS pollution)
    #             With token for private repos, without token for public.
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        if curl -fsSL --http1.1 \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github.v3.raw" \
            "$api_url" 2>/dev/null; then
            return 0
        fi
    fi
    if curl -fsSL --http1.1 -H "Accept: application/vnd.github.v3.raw" "$api_url" 2>/dev/null; then
        return 0
    fi

    # Priority 3: Direct raw.githubusercontent.com
    if curl -fsSL --http1.1 "$raw_url" 2>/dev/null; then
        return 0
    fi

    # Priority 4: Insecure fallback (corporate proxy / DNS poisoning)
    warn "All secure methods failed, retrying without SSL verification..."
    if [ -n "$mirror_url" ]; then
        curl -fsSLk --http1.1 "$mirror_url" 2>/dev/null && return 0
    fi
    curl -fsSLk --http1.1 "$raw_url" 2>/dev/null && return 0
    curl -fsSLk -H "Accept: application/vnd.github.v3.raw" "$api_url" 2>/dev/null && return 0

    err "Failed to download: ${path}"
    err "  Solutions:"
    err "    1. Set mirror: export GH_MIRROR=https://gh-proxy.com"
    err "    2. Set token:  export GITHUB_TOKEN=your-pat"
    err "    3. Manual:     curl -fsSL -H 'Accept: application/vnd.github.v3.raw' \\"
    err "                   https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${path}?ref=${REPO_BRANCH}"
    return 1
}

# ── Banner ─────────────────────────────────────────────────────────
show_banner() {
    echo ""
    echo "${CYAN}  ___              ____          _      ${NC}"
    echo "${CYAN} / _ \\ _ __   ___ / ___|___   __| | ___ ${NC}"
    echo "${CYAN}| | | | '_ \\ / _ \\ |   / _ \\ / _\` |/ _ \\${NC}"
    echo "${CYAN}| |_| | | | |  __/ |__| (_) | (_| |  __/${NC}"
    echo "${CYAN} \\___/|_| |_|\\___|\\____\\___/ \\__,_|\\___|${NC}"
    echo ""
    echo "  ${BOLD}OneCode${NC} v${VERSION} — ${DIM}AI 原生 IDE，浏览器里写代码${NC}"
    echo "  ${DIM}Backend: claude-code (Anthropic Claude) · opencode (MIT)${NC}"
    echo "  ${DIM}Platform: Linux amd64/arm64 · macOS Intel/Apple Silicon${NC}"
    echo ""
}

# ── Help ───────────────────────────────────────────────────────────
show_help() {
    cat <<EOF
Usage: install.sh [options]

Options:
  --provider NAME       API provider: anthropic, openai_compatible, opencode (default: anthropic)
  --api-key KEY         Preset API key (skip interactive input)
  --api-base-url URL    API base URL (default: based on provider)
  --model NAME          Model name (default: based on provider)
  --backend NAME        AI backend: claude-code or opencode (default: claude-code)
  --registry-user USER  Container registry login username
  --registry-pass PASS  Container registry login password
  --github-token TOKEN  GitHub PAT for private repo access (or set GITHUB_TOKEN env)
  --tag TAG             Image tag (default: ${IMAGE_TAG})
  --skip-docker         Skip Docker installation (assume already installed)
  -h, --help            Show this help

Examples:
  bash install.sh
  bash install.sh --api-key sk-xxx --provider anthropic
  bash install.sh --api-key sk-xxx --provider openai_compatible --api-base-url https://api.example.com
  bash install.sh --backend opencode
  bash install.sh --registry-user foo --registry-pass bar --tag 0.4
EOF
    exit 0
}

# ── Parse args ─────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --provider)       PROVIDER="$2"; _PROVIDER_SET_BY_ARG=1; shift 2 ;;
        --api-key)        API_KEY="$2"; shift 2 ;;
        --api-base-url)   API_BASE_URL="$2"; shift 2 ;;
        --model)          MODEL="$2"; shift 2 ;;
        --registry-user)  REGISTRY_USER="$2"; shift 2 ;;
        --registry-pass)  REGISTRY_PASS="$2"; shift 2 ;;
        --github-token)   GITHUB_TOKEN="$2"; shift 2 ;;
        --tag)            IMAGE_TAG="$2"; shift 2 ;;
        --skip-docker)    SKIP_DOCKER=true; shift ;;
        --backend)       BACKEND="$2"; shift 2 ;;
        --yes)            shift ;;
        -h|--help)        show_help ;;
        *)                err "Unknown option: $1"; show_help ;;
    esac
done

# ── Step 1: Environment detection ──────────────────────────────────
detect_env() {
    info "Detecting environment..."

    # OS
    UNAME_S="$(uname -s)"
    case "$UNAME_S" in
        Linux)
            if [ -f /etc/os-release ]; then
                # shellcheck disable=SC1091
                . /etc/os-release
                OS_ID="${ID:-unknown}"
                OS_VERSION="${VERSION_ID:-unknown}"
            elif command -v centos-release &>/dev/null; then
                OS_ID="centos"
                OS_VERSION="7"
            else
                OS_ID="unknown"
                OS_VERSION="unknown"
            fi
            ;;
        Darwin)
            OS_ID="darwin"
            OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo "unknown")"
            ;;
        *)
            OS_ID="unknown"
            OS_VERSION="unknown"
            ;;
    esac
    info "OS: ${OS_ID} ${OS_VERSION}"

    # Arch (for display only; image is always linux/amd64)
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)         ARCH_ALIAS="amd64" ;;
        aarch64|arm64)  ARCH_ALIAS="arm64" ;;
        *)              error_box "Unsupported Architecture" \
                        "Your CPU: ${ARCH}" \
                        "OneCode requires amd64 (x86_64) or arm64 (aarch64)." \
                        "" \
                        "Recovery:" \
                        "  • Run on an x86_64 or ARM64 machine" \
                        "  • Report: github.com/yiyan-yixing/onecode/issues"
                        exit 1 ;;
    esac
    PLATFORM="linux/amd64"
    info "Platform: ${PLATFORM} (host: ${UNAME_S}/${ARCH})"

    # Force amd64 on arm64 macOS to avoid "no matching manifest for linux/arm64"
    if [ "$OS_ID" = "darwin" ] && [ "$ARCH_ALIAS" = "arm64" ]; then
        export DOCKER_DEFAULT_PLATFORM="linux/amd64"
        info "Set DOCKER_DEFAULT_PLATFORM=linux/amd64 (Rosetta emulation on Apple Silicon)"
    fi

    # Root / sudo (not needed on macOS)
    if [ "$OS_ID" = "darwin" ]; then
        SUDO=""
    elif [ "$(id -u)" = "0" ]; then
        SUDO=""
    elif command -v sudo &>/dev/null; then
        SUDO="sudo"
    else
        error_box "Need Root or Sudo" \
                  "Docker installation requires elevated privileges." \
                  "" \
                  "Recovery:" \
                  "  • Run as root: sudo bash install.sh" \
                  "  • Install sudo: apt install sudo (Debian/Ubuntu)" \
                  "  • Install Docker manually: https://docs.docker.com/engine/install/"
        exit 1
    fi
}

# ── Step 2: Install jq (required by oc CLI v2 config system) ──────────
install_jq() {
    if command -v jq &>/dev/null; then
        ok "jq already installed: $(jq --version 2>/dev/null || echo 'unknown')"
        return
    fi

    info "Installing jq (required for config management)..."

    case "$OS_ID" in
        darwin)
            if command -v brew &>/dev/null; then
                brew install jq
            else
                err "Homebrew not found. Install jq manually or install Homebrew first."
                exit 1
            fi
            ;;
        centos|rhel|anolis)
            $SUDO yum install -y jq
            ;;
        ubuntu|debian)
            $SUDO apt-get update -y
            $SUDO apt-get install -y jq
            ;;
        *)
            err "Unsupported OS for auto jq install: ${OS_ID}"
            err "Please install jq manually: https://jqlang.github.io/jq/download/"
            exit 1
            ;;
    esac

    ok "jq installed"
}

# ── Step 3: Docker installation ────────────────────────────────────
install_docker() {
    if $SKIP_DOCKER; then
        info "Skipping Docker installation (--skip-docker)"
        return
    fi

    if command -v docker &>/dev/null; then
        local ver
        ver=$(docker --version 2>/dev/null || echo "unknown")
        ok "Docker already installed: ${ver}"
        return
    fi

    info "Installing Docker..."

    case "$OS_ID" in
        darwin)
            if command -v brew &>/dev/null; then
                info "Installing Docker Desktop via Homebrew..."
                brew install --cask docker
            else
                err "Homebrew not found. Install it first:"
                err "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                err "Then re-run this script, or install Docker Desktop manually:"
                err "  https://docs.docker.com/desktop/install/mac-install/"
                exit 1
            fi
            ;;
        centos|rhel|anolis)
            $SUDO yum install -y yum-utils
            $SUDO yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
            $SUDO yum install -y docker-ce docker-ce-cli containerd.io
            ;;
        ubuntu|debian)
            $SUDO apt-get update -y
            $SUDO apt-get install -y ca-certificates curl gnupg
            $SUDO install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            $SUDO chmod a+r /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
                | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
            $SUDO apt-get update -y
            $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io
            ;;
        *)
            err "Unsupported OS for auto Docker install: ${OS_ID}"
            err "Please install Docker manually: https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac

    ok "Docker installed"
}

start_docker() {
    if docker info &>/dev/null; then
        ok "Docker service running"
        return
    fi

    info "Starting Docker service..."
    case "$OS_ID" in
        darwin)
            open -a Docker
            info "Waiting for Docker Desktop to start..."
            local retries=30
            while [ $retries -gt 0 ]; do
                sleep 2
                if docker info &>/dev/null; then
                    ok "Docker Desktop is running"
                    return
                fi
                retries=$((retries - 1))
            done
            error_box "Docker Desktop Failed to Start" \
                      "Waited 60s for Docker Desktop to become ready." \
                      "" \
                      "Recovery:" \
                      "  • Start Docker Desktop manually" \
                      "  • Re-run this script after Docker is running" \
                      "  • Check: https://docs.docker.com/desktop/troubleshoot/"
            exit 1
            ;;
        *)
            $SUDO systemctl start docker
            $SUDO systemctl enable docker
            ok "Docker service running"
            ;;
    esac
}

# ── Step 3: Registry login ────────────────────────────────────────
registry_login() {
    local registry="${IMAGE_REPO%%/*}"

    # Check if already logged in
    if [ -f "$HOME/.docker/config.json" ] && grep -q "$registry" "$HOME/.docker/config.json" 2>/dev/null; then
        ok "Already logged in to ${registry}"
        return
    fi
    if [ -f "/root/.docker/config.json" ] && grep -q "$registry" "/root/.docker/config.json" 2>/dev/null; then
        ok "Already logged in to ${registry}"
        return
    fi

    # No credentials provided and not logged in
    if [ -z "$REGISTRY_USER" ] || [ -z "$REGISTRY_PASS" ]; then
        info "No registry credentials provided, skipping docker login"
        info "If pull fails, run: docker login ${registry}"
        return
    fi

    info "Logging in to ${registry}..."
    echo "$REGISTRY_PASS" | docker login "$registry" -u "$REGISTRY_USER" --password-stdin
    ok "Registry login succeeded"
}

# ── Step 4: Pull image ────────────────────────────────────────────
pull_image() {
    local image="${IMAGE_REPO}:${IMAGE_TAG}"
    # Check if image already exists locally (skip pull for local/dev builds)
    if docker image inspect "$image" &>/dev/null; then
        ok "Image already available locally: ${image}"
    else
        info "Pulling image: ${image}"
        docker pull --platform "$PLATFORM" "$image"
        ok "Image pulled: ${image}"
    fi
}

# ── Step 6: Install oc CLI ────────────────────────────────────────
install_oc() {
    mkdir -p "$INSTALL_DIR"

    if [ -f "$INSTALL_DIR/oc" ]; then
        info "oc CLI already installed at ${INSTALL_DIR}/oc, updating..."
    fi

    # Download oc CLI from repository (avoids base64 embedding divergence)
    info "Downloading oc CLI from ${REPO_OWNER}/${REPO_NAME}..."
    if ! github_fetch "agent-runtime/bin/oc" > "$INSTALL_DIR/oc" 2>/dev/null; then
        err "Failed to download oc CLI from GitHub"
        echo "  Try: curl -fsSL https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/agent-runtime/bin/oc > ${INSTALL_DIR}/oc"
        return 1
    fi

    chmod +x "$INSTALL_DIR/oc"
    ok "oc CLI installed -> ${INSTALL_DIR}/oc"

    # Ensure INSTALL_DIR in PATH
    case ":$PATH:" in
        *":$INSTALL_DIR:"*) ;;
        *)
            SHELL_RC="$HOME/.bashrc"
            [ -n "${ZSH_VERSION:-}" ] && SHELL_RC="$HOME/.zshrc"
            echo "export PATH=\"${INSTALL_DIR}:\$PATH\"" >> "$SHELL_RC"
            export PATH="${INSTALL_DIR}:$PATH"
            info "Added ${INSTALL_DIR} to PATH in ${SHELL_RC}"
            ;;
    esac

    # Persist DOCKER_DEFAULT_PLATFORM for Apple Silicon Macs
    if [ -n "${DOCKER_DEFAULT_PLATFORM:-}" ]; then
        SHELL_RC="$HOME/.bashrc"
        [ -n "${ZSH_VERSION:-}" ] && SHELL_RC="$HOME/.zshrc"
        grep -q "DOCKER_DEFAULT_PLATFORM" "$SHELL_RC" 2>/dev/null || {
            echo "export DOCKER_DEFAULT_PLATFORM=\"${DOCKER_DEFAULT_PLATFORM}\"" >> "$SHELL_RC"
            info "Added DOCKER_DEFAULT_PLATFORM=${DOCKER_DEFAULT_PLATFORM} to ${SHELL_RC}"
        }
    fi
}

# ── Step 7: Configure ──────────────────────────────────────────────

# Mask API key for display: show first 7 chars + ••••
mask_key() {
    local key="$1"
    [ -z "$key" ] && echo "(not set)" && return
    echo "${key:0:7}••••"
}

# Provider display names
provider_display() {
    case "$1" in
        anthropic)         echo "Anthropic Claude" ;;
        openai_compatible) echo "OpenAI Compatible" ;;
        opencode)          echo "OpenCode (MIT)" ;;
        *)                 echo "$1" ;;
    esac
}

configure() {
    mkdir -p "$OC_HOME"
    # Pre-create Claude Code cache dir (bind-mounted into container at /opt/claude-code)
    mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/onecode/claude-code"

    # Migrate v1 config if present (read old fields, write v2 format)
    if [ -f "$OC_HOME/settings.json" ]; then
        local old_ver
        old_ver=$(jq -r '.$version // 0' "$OC_HOME/settings.json" 2>/dev/null || echo "0")
        if [ "$old_ver" -lt 2 ] 2>/dev/null; then
            info "Migrating config from v1 to v2 format..."
            local old_key old_url old_model
            old_key=$(jq -r '.API_KEY // empty' "$OC_HOME/settings.json" 2>/dev/null || true)
            old_url=$(jq -r '.API_BASE_URL // empty' "$OC_HOME/settings.json" 2>/dev/null || true)
            old_model=$(jq -r '.MODEL // empty' "$OC_HOME/settings.json" 2>/dev/null || true)
            [ -z "$API_KEY" ] && [ -n "$old_key" ] && API_KEY="$old_key"
            [ -z "$API_BASE_URL" ] && [ -n "$old_url" ] && API_BASE_URL="$old_url"
            [ -z "$MODEL" ] && [ -n "$old_model" ] && MODEL="$old_model"
            case "$API_BASE_URL" in
                https://api.anthropic.com*|'') PROVIDER="anthropic" ;;
                *) PROVIDER="openai_compatible" ;;
            esac
            step_ok "Config migrated (provider: $(provider_display "$PROVIDER"))"
        else
            info "Existing v2 config found at ${OC_HOME}/settings.json"
            [ -z "$API_KEY" ] && API_KEY=$(jq -r '.api_key // empty' "$OC_HOME/settings.json" 2>/dev/null || true)
            [ -z "$PROVIDER" ] && PROVIDER=$(jq -r '.provider // empty' "$OC_HOME/settings.json" 2>/dev/null || true)
            [ -z "$API_BASE_URL" ] && API_BASE_URL=$(jq -r '.api_base_url // empty' "$OC_HOME/settings.json" 2>/dev/null || true)
            [ -z "$MODEL" ] && MODEL=$(jq -r '.model // empty' "$OC_HOME/settings.json" 2>/dev/null || true)
            [ -z "${BACKEND:-}" ] && BACKEND=$(jq -r '.backend // empty' "$OC_HOME/settings.json" 2>/dev/null || true)
        fi
    fi

    # Apply provider defaults for any still-empty values
    if [ -z "$API_BASE_URL" ]; then
        eval "API_BASE_URL=\${PROVIDER_DEFAULTS_${PROVIDER}_api_base_url:-}"
    fi
    if [ -z "$MODEL" ]; then
        eval "MODEL=\${PROVIDER_DEFAULTS_${PROVIDER}_model:-}"
    fi

    # ── First run: full interactive wizard ─────────
    if [ ! -f "$OC_HOME/settings.json" ]; then
        echo ""
        echo "  ${BOLD}OneCode needs the following configuration:${NC}"
        echo ""

        # 1. Provider
        echo "  ${BOLD}? Select your AI provider:${NC}"
        echo "    ${GREEN}1)${NC} Anthropic Claude ${DIM}(default, recommended)${NC}"
        echo "    ${GREEN}2)${NC} OpenAI Compatible ${DIM}(any OpenAI-format API)${NC}"
        echo "    ${GREEN}3)${NC} OpenCode ${DIM}(MIT, local models, no API key needed)${NC}"
        echo "    ${GREEN}4)${NC} Custom ${DIM}(enter your own provider name)${NC}"
        echo ""
        if [ -z "${_PROVIDER_SET_BY_ARG:-}" ]; then
            echo -n "  ▸ "
            read -r _prov_choice
            case "$_prov_choice" in
                2) PROVIDER="openai_compatible"; BACKEND="${BACKEND:-claude-code}" ;;
                3) PROVIDER="opencode"; BACKEND="opencode" ;;
                4) echo -n "  Provider name: "; read -r PROVIDER; BACKEND="${BACKEND:-claude-code}" ;;
                *) PROVIDER="anthropic"; BACKEND="${BACKEND:-claude-code}" ;;
            esac
        fi
        echo "  ${GREEN}✓${NC} Provider: $(provider_display "$PROVIDER")"
        echo ""

        # OpenCode doesn't need API key
        if [ "$PROVIDER" = "opencode" ]; then
            info "OpenCode runs local models — no API key needed."
            [ -z "$API_BASE_URL" ] && API_BASE_URL=""
            [ -z "$MODEL" ] && MODEL="local"
        else
            # 2. API Base URL
            local default_url
            eval "default_url=\${PROVIDER_DEFAULTS_${PROVIDER}_api_base_url:-}"
            echo "  ${BOLD}? API Base URL${NC} ${DIM}(Enter for default: ${default_url:-empty})${NC}"
            echo -n "  ▸ "
            read -r _url_input
            [ -n "$_url_input" ] && API_BASE_URL="$_url_input"
            [ -z "$API_BASE_URL" ] && API_BASE_URL="$default_url"
            echo "  ${GREEN}✓${NC} API Base URL: ${API_BASE_URL:-empty}"
            echo ""

            # 3. API Key (hidden input)
            echo "  ${BOLD}? API Key${NC} ($(provider_display "$PROVIDER"))"
            case "$PROVIDER" in
                anthropic) echo "  ${DIM}Get yours: https://console.anthropic.com/settings/keys${NC}" ;;
            esac
            echo -n "  ▸ "
            if [ -t 0 ]; then
                read -rs API_KEY
            else
                read -r API_KEY
            fi
            echo ""
            [ -n "$API_KEY" ] && echo "  ${GREEN}✓${NC} API Key: $(mask_key "$API_KEY")"
            echo ""

            # 4. Model
            local default_model
            eval "default_model=\${PROVIDER_DEFAULTS_${PROVIDER}_model:-}"
            echo "  ${BOLD}? Model${NC} ${DIM}(Enter for default: ${default_model})${NC}"
            echo -n "  ▸ "
            read -r _model_input
            [ -n "$_model_input" ] && MODEL="$_model_input"
            [ -z "$MODEL" ] && MODEL="$default_model"
            echo "  ${GREEN}✓${NC} Model: ${MODEL}"
        fi

        echo ""
        echo "  ${CYAN}──${NC} ${BOLD}配置确认${NC} ${CYAN}─────────────────────────────────${NC}"
        echo "    Provider:     $(provider_display "$PROVIDER")"
        if [ "$PROVIDER" != "opencode" ]; then
            echo "    API Base URL: ${API_BASE_URL}"
            echo "    API Key:      $(mask_key "$API_KEY")"
        fi
        echo "    Model:        ${MODEL}"
        echo "    Backend:      ${BACKEND:-claude-code}"
        echo "  ${CYAN}────────────────────────────────────────────${NC}"
        echo ""

    else
        # ── Existing config: confirm or modify ─────────
        local key_display
        key_display="$(mask_key "$API_KEY")"
        echo ""
        echo "  ${CYAN}──${NC} ${BOLD}当前配置${NC} ${CYAN}─────────────────────────────────${NC}"
        echo "    Provider:     $(provider_display "$PROVIDER")"
        if [ "$PROVIDER" != "opencode" ]; then
            echo "    API Base URL: ${API_BASE_URL}"
            echo "    API Key:      ${key_display}"
        fi
        echo "    Model:        ${MODEL}"
        echo "    Backend:      ${BACKEND:-claude-code}"
        echo "  ${CYAN}────────────────────────────────────────────${NC}"
        echo ""
        echo -n "  ${BOLD}Confirm? (Y/n)${NC} "
        read -r _confirm_choice
        echo ""

        case "$_confirm_choice" in
            n|N)
                # Modify each attribute: Provider → Base URL → API Key → Model
                echo "  Modify Provider ${DIM}(Enter to keep current: $(provider_display "$PROVIDER"))${NC}"
                echo "    ${GREEN}1)${NC} Anthropic Claude"
                echo "    ${GREEN}2)${NC} OpenAI Compatible"
                echo "    ${GREEN}3)${NC} OpenCode"
                echo "    ${GREEN}4)${NC} Custom"
                echo -n "  ▸ "
                read -r _prov_choice
                case "$_prov_choice" in
                    1) PROVIDER="anthropic"; BACKEND="${BACKEND:-claude-code}" ;;
                    2) PROVIDER="openai_compatible"; BACKEND="${BACKEND:-claude-code}" ;;
                    3) PROVIDER="opencode"; BACKEND="opencode" ;;
                    4) echo -n "  Provider name: "; read -r PROVIDER; BACKEND="${BACKEND:-claude-code}" ;;
                esac

                if [ "$PROVIDER" != "opencode" ]; then
                    echo ""
                    echo "  Modify API Base URL ${DIM}(Enter to keep current: ${API_BASE_URL})${NC}"
                    echo -n "  ▸ "
                    read -r _url_input
                    [ -n "$_url_input" ] && API_BASE_URL="$_url_input"

                    echo ""
                    echo "  Modify API Key ${DIM}(Enter to keep current: ${key_display})${NC}"
                    echo -n "  ▸ "
                    if [ -t 0 ]; then
                        read -rs _new_key
                    else
                        read -r _new_key
                    fi
                    echo ""
                    [ -n "$_new_key" ] && API_KEY="$_new_key"

                    echo ""
                    echo "  Modify Model ${DIM}(Enter to keep current: ${MODEL})${NC}"
                    echo -n "  ▸ "
                    read -r _model_input
                    [ -n "$_model_input" ] && MODEL="$_model_input"
                else
                    API_BASE_URL=""
                    MODEL="local"
                fi

                echo ""
                ;;
        esac
    fi

    # Re-apply provider defaults for any still-empty values
    if [ -z "$API_BASE_URL" ]; then
        eval "API_BASE_URL=\${PROVIDER_DEFAULTS_${PROVIDER}_api_base_url:-}"
    fi
    if [ -z "$MODEL" ]; then
        eval "MODEL=\${PROVIDER_DEFAULTS_${PROVIDER}_model:-}"
    fi

    # Write v2 config using jq
    local tmp="${OC_HOME}/settings.json.tmp.$$"
    jq -n \
      --arg v "2" \
      --arg provider "${PROVIDER:-anthropic}" \
      --arg api_key "${API_KEY:-}" \
      --arg api_base_url "${API_BASE_URL:-}" \
      --arg model "${MODEL:-}" \
      --arg backend "${BACKEND:-claude-code}" \
      --arg docker_platform "${DOCKER_PLATFORM:-linux/amd64}" \
      --arg image_tag "${IMAGE_TAG:-latest}" \
      --arg gh_mirror "${GH_MIRROR:-}" \
      --argjson gateway_port "${GATEWAY_PORT:-7681}" \
      --argjson app_port "${APP_PORT:-8000}" \
      --argjson ssh_port "${SSH_PORT:-8222}" \
      --arg term_token "${TERM_TOKEN:-}" \
      --argjson gateway_https "${GATEWAY_HTTPS:-false}" \
    '{$version:$v,$provider,$api_key,$api_base_url,$model,$backend,$docker_platform,$image_tag,$gh_mirror,$gateway_port,$app_port,$ssh_port,$term_token,$gateway_https}' \
    > "$tmp" && mv "$tmp" "$OC_HOME/settings.json" && chmod 600 "$OC_HOME/settings.json"

    step_ok "Config saved to ${OC_HOME}/settings.json"
}

# ── Step 8: Verify ─────────────────────────────────────────────────
verify() {
    step_header "✓" "4" "验证"

    # Docker
    if command -v docker &>/dev/null; then
        local docker_ver
        docker_ver=$(docker --version 2>/dev/null | sed 's/Docker version //' | sed 's/,.*//')
        step_ok "Docker:  ${docker_ver}"
    else
        step_err "Docker:  not in PATH (may need re-login)"
    fi

    # Image
    if docker images "${IMAGE_REPO}" --format "{{.Tag}}" 2>/dev/null | grep -q "^${IMAGE_TAG}$"; then
        step_ok "Image:   ${IMAGE_REPO}:${IMAGE_TAG}"
    else
        step_err "Image:   not found (pull may have failed)"
    fi

    # oc CLI
    if command -v oc &>/dev/null; then
        step_ok "oc CLI:  $(command -v oc)"
    else
        step_skip "oc CLI:  not in PATH yet (run: source ~/.bashrc)"
    fi

    # Config
    if [ -f "$OC_HOME/settings.json" ]; then
        step_ok "Config:  ${OC_HOME}/settings.json"
    else
        step_err "Config:  not created"
    fi
}

# ── Main ───────────────────────────────────────────────────────────
main() {
    show_banner

    step_header "1" "8" "检测环境"
    detect_env
    step_ok "${OS_ID} ${OS_VERSION} (${UNAME_S}/${ARCH})"

    step_header "2" "8" "安装 jq"
    install_jq

    step_header "3" "8" "安装 Docker"
    install_docker

    step_header "4" "8" "启动 Docker"
    start_docker

    step_header "5" "8" "登录镜像仓库"
    registry_login

    step_header "6" "8" "拉取镜像"
    info "This usually takes 1-5 min depending on network speed..."
    pull_image

    step_header "7" "8" "安装 oc CLI"
    install_oc

    step_header "8" "8" "配置"
    configure

    # Verify
    verify

    # ── Completion ────────────────────────────────────────
    local shell_rc="~/.bashrc"
    [ "$OS_ID" = "darwin" ] && shell_rc="~/.zshrc"

    local arm64_line=""
    if [ "$OS_ID" = "darwin" ] && [ "${ARCH_ALIAS:-}" = "arm64" ]; then
        arm64_line="Apple Silicon: enable Rosetta in Docker Desktop Settings"
    fi

    show_box 55 \
        "  ${GREEN}${BOLD}✅ OneCode installed!${NC}" \
        "" \
        "  ${BOLD}First run:${NC}" \
        "    source ${shell_rc}     # load PATH" \
        "    oc remote             # → http://localhost:7681" \
        "" \
        "  ${BOLD}Common commands:${NC}" \
        "    oc                     interactive AI CLI" \
        "    oc remote              web IDE in browser" \
        "    oc --backend opencode  MIT backend, no API key" \
        "    oc config list         show all settings" \
        "${arm64_line}" \
        "" \
        "  ${DIM}Config:   ${OC_HOME}/settings.json${NC}" \
        "  ${DIM}CLI:      ${INSTALL_DIR}/oc${NC}" \
        "  ${DIM}Image:    ${IMAGE_REPO}:${IMAGE_TAG}${NC}" \
        "  ${DIM}Docs:     github.com/yiyan-yixing/onecode${NC}"
}

main
