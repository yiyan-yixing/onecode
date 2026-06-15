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
VERSION="0.4.0"
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

# v2 config defaults (used by configure())
GATEWAY_PORT="7681"
APP_PORT="8000"
SSH_PORT="8222"
TERM_TOKEN=""
GATEWAY_HTTPS="false"

# ── Colors ─────────────────────────────────────────────────────────
# Use raw $'\033[..m' syntax to avoid \\033 interpretation issues
# in echo -e/printf where backslashes in the banner text interact badly.
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

info()  { echo "${CYAN}[info]${NC} $*"; }
ok()    { echo "${GREEN}[ok]${NC} $*"; }
warn()  { echo "${YELLOW}[warn]${NC} $*"; }
err()   { echo "${RED}[error]${NC} $*" >&2; }

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
    echo "  OneCode v${VERSION} - Install"
    echo ""
}

# ── Help ───────────────────────────────────────────────────────────
show_help() {
    cat <<EOF
Usage: install.sh [options]

Options:
  --provider NAME       API provider: anthropic or openai_compatible (default: anthropic)
  --api-key KEY         Preset API key (skip interactive input)
  --api-base-url URL    API base URL (default: based on provider)
  --model NAME          Model name (default: based on provider)
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
        *)              err "Unsupported architecture: $ARCH (only amd64/arm64 supported)"; exit 1 ;;
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
        err "Need root or sudo to install Docker"
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
            err "Docker Desktop failed to start within 60s"
            err "Please start Docker Desktop manually and re-run this script"
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
configure() {
    mkdir -p "$OC_HOME"

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
            # Carry over to shell vars if not already set
            [ -z "$API_KEY" ] && [ -n "$old_key" ] && API_KEY="$old_key"
            [ -z "$API_BASE_URL" ] && [ -n "$old_url" ] && API_BASE_URL="$old_url"
            [ -z "$MODEL" ] && [ -n "$old_model" ] && MODEL="$old_model"
            # Infer provider
            case "$API_BASE_URL" in
                https://api.anthropic.com*|'') PROVIDER="anthropic" ;;
                *) PROVIDER="openai_compatible" ;;
            esac
            info "Config migrated (provider: $PROVIDER)"
        else
            info "Existing v2 config found at ${OC_HOME}/settings.json"
            # Load existing values to fill blanks
            [ -z "$API_KEY" ] && API_KEY=$(jq -r '.api_key // empty' "$OC_HOME/settings.json" 2>/dev/null || true)
            [ -z "$PROVIDER" ] && PROVIDER=$(jq -r '.provider // empty' "$OC_HOME/settings.json" 2>/dev/null || true)
            [ -z "$API_BASE_URL" ] && API_BASE_URL=$(jq -r '.api_base_url // empty' "$OC_HOME/settings.json" 2>/dev/null || true)
            [ -z "$MODEL" ] && MODEL=$(jq -r '.model // empty' "$OC_HOME/settings.json" 2>/dev/null || true)
        fi
    fi

    # ── Interactive wizard (first run or missing fields) ─────────
    # If no existing config, run the full first-run wizard
    if [ ! -f "$OC_HOME/settings.json" ]; then
        echo ""
        echo "  ╔═══════════════════════════════════════════════╗"
        echo "  ║          Welcome to OneCode! 🚀               ║"
        echo "  ║  Let's configure your LLM API connection.     ║"
        echo "  ╚═══════════════════════════════════════════════╝"
        echo ""

        # Step 1: Provider (only if not already set via --provider flag)
        if [ -z "${_PROVIDER_SET_BY_ARG:-}" ]; then
            echo "  Step 1: Choose your API provider"
            echo ""
            echo "    1) Anthropic         (Claude models)"
            echo "    2) OpenAI Compatible (any OpenAI-format API)"
            echo ""
            read -rp "  Select [1-2]: " _prov_choice
            case "$_prov_choice" in
                2) PROVIDER="openai_compatible" ;;
                *) PROVIDER="anthropic" ;;
            esac
        fi
        echo "  Provider: ${PROVIDER}"
        echo ""

        # Step 2: API Key
        case "$PROVIDER" in
            anthropic)
                echo "  Step 2: API Key"
                echo "  Get your key at: https://console.anthropic.com/"
                ;;
            openai_compatible)
                echo "  Step 2: API Base URL"
                echo "  Enter the base URL for your OpenAI-compatible API"
                read -rp "  API Base URL (e.g. https://api.example.com/v1): " API_BASE_URL
                echo ""
                echo "  Step 3: API Key"
                ;;
        esac
        read -rsp "  API Key (press Enter to skip, configure later with 'oc config set'): " API_KEY
        echo

        # Step 3/4: Model
        local default_model
        eval "default_model=\${PROVIDER_DEFAULTS_${PROVIDER}_model:-}"
        if [ "$PROVIDER" = "anthropic" ]; then
            echo ""
            echo "  Step 3: Model"
        else
            echo ""
            echo "  Step 4: Model"
        fi
        echo "  Press Enter for ${default_model}, or type a model name."
        read -rp "  Model [${default_model}]: " MODEL
        [ -z "$MODEL" ] && MODEL="$default_model"

        echo ""
        echo "  ─────────────────────────────────────"
        echo "  Configuration summary:"
        echo "    Provider:        ${PROVIDER}"
        echo "    API Base URL:    ${API_BASE_URL:-<not set>}"
        echo "    Model:           ${MODEL}"
        echo "  ─────────────────────────────────────"
        echo ""

    else
        # Existing config — only prompt for truly missing values
        # (API_KEY prompt if empty after migration/load)
        if [ -z "$API_KEY" ]; then
            echo ""
            case "$PROVIDER" in
                anthropic)
                    echo "  Get your key at: https://console.anthropic.com/"
                    ;;
                openai_compatible)
                    echo "  Enter your API key for ${API_BASE_URL:-your API endpoint}"
                    ;;
            esac
            read -rsp "  API Key (press Enter to skip, configure later with 'oc config set'): " API_KEY
            echo
        fi

        # openai_compatible with no base URL after migration
        if [ -z "$API_BASE_URL" ] && [ "$PROVIDER" = "openai_compatible" ]; then
            echo ""
            read -rp "  API Base URL (e.g. https://api.example.com/v1): " API_BASE_URL
        fi

        # Model still missing after migration + defaults
        if [ -z "$MODEL" ]; then
            echo ""
            local default_model
            eval "default_model=\${PROVIDER_DEFAULTS_${PROVIDER}_model:-}"
            read -rp "  Model [${default_model}]: " MODEL
            [ -z "$MODEL" ] && MODEL="$default_model"
        fi
    fi

    # Apply provider-based defaults for any still-empty values
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

    ok "Config saved to ${OC_HOME}/settings.json"
}

# ── Step 8: Verify ─────────────────────────────────────────────────
verify() {
    info "Verifying installation..."

    # Docker
    if command -v docker &>/dev/null; then
        ok "Docker: $(docker --version)"
    else
        warn "Docker not found in PATH (may need to re-login)"
    fi

    # Image
    if docker images "${IMAGE_REPO}" --format "{{.Tag}}" 2>/dev/null | grep -q "^${IMAGE_TAG}$"; then
        ok "Image: ${IMAGE_REPO}:${IMAGE_TAG}"
    else
        warn "Image not found locally (pull may have failed)"
    fi

    # oc CLI
    if command -v oc &>/dev/null; then
        ok "oc CLI: $(command -v oc)"
    else
        warn "oc not in PATH yet (run: source ~/.bashrc)"
    fi

    # Config
    if [ -f "$OC_HOME/settings.json" ]; then
        ok "Config: ${OC_HOME}/settings.json"
    fi
}

# ── Main ───────────────────────────────────────────────────────────
main() {
    show_banner

    echo "========================================="
    echo "  Step 1/8: Detect environment"
    echo "========================================="
    detect_env

    echo ""
    echo "========================================="
    echo "  Step 2/8: Install jq"
    echo "========================================="
    install_jq

    echo ""
    echo "========================================="
    echo "  Step 3/8: Install Docker"
    echo "========================================="
    install_docker

    echo ""
    echo "========================================="
    echo "  Step 4/8: Start Docker service"
    echo "========================================="
    start_docker

    echo ""
    echo "========================================="
    echo "  Step 5/8: Login registry"
    echo "========================================="
    registry_login

    echo ""
    echo "========================================="
    echo "  Step 6/8: Pull image"
    echo "========================================="
    pull_image

    echo ""
    echo "========================================="
    echo "  Step 7/8: Install oc CLI"
    echo "========================================="
    install_oc

    echo ""
    echo "========================================="
    echo "  Step 8/8: Configure"
    echo "========================================="
    configure

    echo ""
    echo "========================================="
    verify

    echo ""
    echo "${GREEN}  Installation complete!${NC}"
    echo ""
    if [ "$OS_ID" = "darwin" ]; then
        echo "  ${YELLOW}Run this first to load PATH & Docker settings:${NC}"
        echo "    source ~/.zshrc"
    else
        echo "  ${YELLOW}Run this first to load PATH:${NC}"
        echo "    source ~/.bashrc"
    fi
    echo ""
    echo "${CYAN}  Common commands:${NC}"
    echo "    oc                              # start interactive Claude CLI"
    echo "    oc -d /path/to/project          # mount a specific project"
    echo "    oc remote                       # web terminal (http://localhost:7681)"
    echo "    oc remote -p 8080               # web terminal on custom port"
    echo "    oc ssh <name>                   # enable SSH access to a running container"
    echo "    oc shell <name>                 # enter a running container"
    echo "    oc stop <name>                  # stop and remove a container"
    echo "    oc ls                           # list containers and image"
    echo "    oc config                       # show current config"
    echo "    oc config set api_key=sk-xxx    # set a config value"
    echo "    oc config list                  # show all config with sources"
    echo ""
    if [ "$OS_ID" = "darwin" ] && [ "${ARCH_ALIAS:-}" = "arm64" ]; then
        echo "${YELLOW}  Note: Running linux/amd64 image via Rosetta emulation.${NC}"
        echo "  Make sure Docker Desktop > Settings > \"Use Rosetta for x86_64/amd64"
        echo "  emulation on Apple Silicon\" is enabled."
        echo ""
    fi
    echo "  Config:  ${OC_HOME}/settings.json"
    echo "  CLI:     ${INSTALL_DIR}/oc"
    echo "  Image:   ${IMAGE_REPO}:${IMAGE_TAG}"
    echo "========================================="
}

main
