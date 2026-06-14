#!/usr/bin/env bash
set -euo pipefail

# ── OneCode - Install ────────────────────────────────────
# One-click install script for cloud servers and macOS.
# Supports: Linux (amd64/arm64), macOS (amd64/arm64)
# Image is always linux/amd64 (Rosetta/QEMU emulation on arm64 hosts).
# Usage:
#   curl -fsSL <raw-url>/install.sh | bash
#   curl -fsSL <raw-url>/install.sh | bash -s -- --api-key sk-xxx --model GLM-5.1

# Keep in sync with agent-runtime/VERSION
VERSION="0.3.5"
IMAGE_REPO="ghcr.io/yiyan-yixing/onecode"
IMAGE_TAG="latest"
OC_HOME="${OC_HOME:-$HOME/.onecode}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/bin}"

# Defaults
API_KEY=""
API_BASE_URL="https://api.anthropic.com"
MODEL="GLM-5.1"
REGISTRY_USER=""
REGISTRY_PASS=""
SKIP_DOCKER=false

# ── Colors ─────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[info]${NC} $*"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
err()   { echo -e "${RED}[error]${NC} $*" >&2; }

# ── Banner ─────────────────────────────────────────────────────────
show_banner() {
    echo ""
    echo -e "${CYAN}  ___              ____          _      ${NC}"
    echo -e "${CYAN} / _ \\ _ __   ___ / ___|___   __| | ___ ${NC}"
    echo -e "${CYAN}| | | | '_ \\ / _ \\ |   / _ \\ / _\` |/ _ \\${NC}"
    echo -e "${CYAN}| |_| | | | |  __/ |__| (_) | (_| |  __/${NC}"
    echo -e "${CYAN} \\___/|_| |_|\\___|\\____\\___/ \\__,_|\\___|${NC}"
    echo ""
    echo "  OneCode v${VERSION} - Install"
    echo ""
}

# ── Help ───────────────────────────────────────────────────────────
show_help() {
    cat <<EOF
Usage: install.sh [options]

Options:
  --api-key KEY         Preset API key (skip interactive input)
  --api-base-url URL    API base URL (default: ${API_BASE_URL})
  --model NAME          Model name (default: ${MODEL})
  --registry-user USER  Container registry login username
  --registry-pass PASS  Container registry login password
  --tag TAG             Image tag (default: ${IMAGE_TAG})
  --skip-docker         Skip Docker installation (assume already installed)
  -h, --help            Show this help

Examples:
  bash install.sh
  bash install.sh --api-key sk-xxx --model GLM-5.1
  bash install.sh --registry-user foo --registry-pass bar --tag 0.2
EOF
    exit 0
}

# ── Parse args ─────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --api-key)        API_KEY="$2"; shift 2 ;;
        --api-base-url)   API_BASE_URL="$2"; shift 2 ;;
        --model)          MODEL="$2"; shift 2 ;;
        --registry-user)  REGISTRY_USER="$2"; shift 2 ;;
        --registry-pass)  REGISTRY_PASS="$2"; shift 2 ;;
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

# ── Step 2: Docker installation ────────────────────────────────────
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

# ── Step 5: Install oc CLI ────────────────────────────────────────
install_oc() {
    mkdir -p "$INSTALL_DIR"

    if [ -f "$INSTALL_DIR/oc" ]; then
        info "oc CLI already installed at ${INSTALL_DIR}/oc, updating..."
    fi

    # Write embedded oc CLI (base64-encoded to avoid heredoc nesting issues)
    # Use -D on macOS, -d on Linux for base64 decode
    _b64flag="-d"
    if [ "$(uname -s)" = "Darwin" ]; then _b64flag="-D"; fi
    base64 "$_b64flag" <<'B64' > "$INSTALL_DIR/oc"
IyEvdXNyL2Jpbi9lbnYgYmFzaApzZXQgLWV1byBwaXBlZmFpbAoKSU1BR0VfUkVQTz0iZ2hjci5pby95aXlhbi15aXhpbmcvb25lY29kZSIKSU1BR0U9IiR7QUdFTlRfUlVOVElNRV9JTUFHRTotJHtJTUFHRV9SRVBPfTpsYXRlc3R9IgpQTEFURk9STT0iJHtBR0VOVF9SVU5USU1FX1BMQVRGT1JNOi1saW51eC9hbWQ2NH0iCklNQUdFX1RBRz0iIgpPQ19WRVJTSU9OPSIwLjMuNSIKCiMg4pSA4pSAIENvbmZpZyDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKT0NfSE9NRT0iJHtPQ19IT01FOi0kSE9NRS8ub25lY29kZX0iCk9DX0NPTkZJRz0iJE9DX0hPTUUvc2V0dGluZ3MuanNvbiIKCl9lbnZfYXBpX2tleT0iJHtBUElfS0VZOi19IgpfZW52X2Jhc2VfdXJsPSIke0FQSV9CQVNFX1VSTDotfSIKX2Vudl9tb2RlbD0iJHtNT0RFTDotfSIKCmxvYWRfY29uZmlnKCkgewogICAgWyAtZiAiJE9DX0NPTkZJRyIgXSB8fCByZXR1cm4gMAogICAgd2hpbGUgSUZTPSc6JyByZWFkIC1yIGtleSB2YWx1ZTsgZG8KICAgICAgICB2YWx1ZT0iJHt2YWx1ZSMgXCJ9IgogICAgICAgIHZhbHVlPSIke3ZhbHVlJVwiKn0iCiAgICAgICAgdmFsdWU9IiR7dmFsdWUlLH0iCiAgICAgICAgY2FzZSAiJGtleSIgaW4KICAgICAgICAgICAgKiciQVBJX0tFWSInKSAgICAgIEFQSV9LRVk9IiR2YWx1ZSIgOzsKICAgICAgICAgICAgKiciQVBJX0JBU0VfVVJMIicpIEFQSV9CQVNFX1VSTD0iJHZhbHVlIiA7OwogICAgICAgICAgICAqJyJNT0RFTCInKSAgICAgICAgTU9ERUw9IiR2YWx1ZSIgOzsKICAgICAgICBlc2FjCiAgICBkb25lIDwgIiRPQ19DT05GSUciCn0KCnNhdmVfY29uZmlnKCkgewogICAgbWtkaXIgLXAgIiRPQ19IT01FIgogICAgY2F0ID4gIiRPQ19DT05GSUciIDw8RU9GCnsKICAiQVBJX0tFWSI6ICIkQVBJX0tFWSIsCiAgIkFQSV9CQVNFX1VSTCI6ICIkQVBJX0JBU0VfVVJMIiwKICAiTU9ERUwiOiAiJE1PREVMIgp9CkVPRgogICAgY2htb2QgNjAwICIkT0NfQ09ORklHIgp9Cgpsb2FkX2NvbmZpZwpbIC1uICIkX2Vudl9hcGlfa2V5IiBdICAmJiBBUElfS0VZPSIkX2Vudl9hcGlfa2V5IiAgICAgIHx8IHRydWUKWyAtbiAiJF9lbnZfYmFzZV91cmwiIF0gJiYgQVBJX0JBU0VfVVJMPSIkX2Vudl9iYXNlX3VybCIgfHwgdHJ1ZQpbIC1uICIkX2Vudl9tb2RlbCIgXSAgICAmJiBNT0RFTD0iJF9lbnZfbW9kZWwiICAgICAgICAgICB8fCB0cnVlCkFQSV9CQVNFX1VSTD0iJHtBUElfQkFTRV9VUkw6LWh0dHBzOi8vYXBpLmFudGhyb3BpYy5jb219IgpNT0RFTD0iJHtNT0RFTDotR0xNLTUuMX0iCgpyZXNvbHZlX2FwaV9rZXkoKSB7CiAgICBpZiBbIC16ICIke0FQSV9LRVk6LX0iIF07IHRoZW4KICAgICAgICByZWFkIC1yc3AgIkVudGVyIEFQSV9LRVk6ICIgQVBJX0tFWQogICAgICAgIGVjaG8KICAgICAgICBpZiBbIC16ICIkQVBJX0tFWSIgXTsgdGhlbgogICAgICAgICAgICBlY2hvICJFcnJvcjogQVBJX0tFWSBpcyByZXF1aXJlZCIgPiYyCiAgICAgICAgICAgIGV4aXQgMQogICAgICAgIGZpCiAgICAgICAgc2F2ZV9jb25maWcKICAgICAgICBlY2hvICJBUElfS0VZIHNhdmVkIHRvIH4vLm9uZWNvZGUvc2V0dGluZ3MuanNvbiIKICAgIGZpCiAgICBleHBvcnQgQVBJX0tFWQp9CgojIOKUgOKUgCBEb2NrZXIgY29tbW9uIGFyZ3Mg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACkNPTlRBSU5FUl9OQU1FPSIiCldPUktESVI9IiIKCmJ1aWxkX2RvY2tlcl9hcmdzKCkgewogICAgbG9jYWwgbmFtZT0iJHtDT05UQUlORVJfTkFNRTotb2MtJChiYXNlbmFtZSAiJChwd2QpIiktJCRfJChkYXRlICslcyl9IgogICAgbG9jYWwgZGlyPSIke1dPUktESVI6LSQocHdkKX0iCiAgICBsb2NhbCBvY19uYW1lPSIke0NPTlRBSU5FUl9OQU1FOi0kKGJhc2VuYW1lICIkKHB3ZCkiKX0iCiAgICBhcmdzPSgKICAgICAgICAtLXBsYXRmb3JtICIkUExBVEZPUk0iCiAgICAgICAgLS1uYW1lICIkbmFtZSIKICAgICAgICAtdiAiJHtkaXJ9Ijovd29ya3NwYWNlCiAgICAgICAgLXcgL3dvcmtzcGFjZQogICAgICAgIC1lICJBUElfQkFTRV9VUkw9JEFQSV9CQVNFX1VSTCIKICAgICAgICAtZSAiQVBJX0tFWT0kQVBJX0tFWSIKICAgICAgICAtZSAiTU9ERUw9JE1PREVMIgogICAgICAgIC1lICJPQ19OQU1FPSRvY19uYW1lIgogICAgKQogICAgIyAuc3NoIG1vdW50ZWQgcmVhZC1vbmx5IGJ5IGRlZmF1bHQgKGZvciBnaXQpCiAgICBsb2NhbCBzc2hfZGlyPSIke1NTSF9ESVI6LSRIT01FLy5zc2h9IgogICAgWyAtZCAiJHNzaF9kaXIiIF0gJiYgYXJncys9KC12ICIkc3NoX2RpciI6L2hvbWUvd29yay8uc3NoOnJvKQoKICAgIGlmIGdpdCBjb25maWcgLS1nbG9iYWwgdXNlci5uYW1lICY+L2Rldi9udWxsOyB0aGVuCiAgICAgICAgYXJncys9KC1lICJHSVRfQVVUSE9SX05BTUU9JChnaXQgY29uZmlnIC0tZ2xvYmFsIHVzZXIubmFtZSkiKQogICAgICAgIGFyZ3MrPSgtZSAiR0lUX0NPTU1JVFRFUl9OQU1FPSQoZ2l0IGNvbmZpZyAtLWdsb2JhbCB1c2VyLm5hbWUpIikKICAgIGZpCiAgICBpZiBnaXQgY29uZmlnIC0tZ2xvYmFsIHVzZXIuZW1haWwgJj4vZGV2L251bGw7IHRoZW4KICAgICAgICBhcmdzKz0oLWUgIkdJVF9BVVRIT1JfRU1BSUw9JChnaXQgY29uZmlnIC0tZ2xvYmFsIHVzZXIuZW1haWwpIikKICAgICAgICBhcmdzKz0oLWUgIkdJVF9DT01NSVRURVJfRU1BSUw9JChnaXQgY29uZmlnIC0tZ2xvYmFsIHVzZXIuZW1haWwpIikKICAgIGZpCn0KCiMg4pSA4pSAIEhlbHAg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACnNob3dfaGVscCgpIHsKICAgIGxvY2FsIGNtZD0iJHsxOi19IgogICAgaWYgWyAtbiAiJGNtZCIgXTsgdGhlbgogICAgICAgIHNob3dfY29tbWFuZF9oZWxwICIkY21kIgogICAgICAgIHJldHVybgogICAgZmkKICAgIGNhdCA8PEVPRgpvYyDigJQgT25lQ29kZSBDTEkgKHNob3J0aGFuZCBmb3IgT25lQ29kZSkKClVzYWdlOiBvYyBbb3B0aW9uc10gPGNvbW1hbmQ+IFtjb21tYW5kLWFyZ3NdCgpDb21tYW5kczoKICBydW4gICAgICAgU3RhcnQgaW50ZXJhY3RpdmUgQ2xhdWRlIENMSSBpbiBhIGNvbnRhaW5lciAoZGVmYXVsdCkKICByZW1vdGUgICAgU3RhcnQgV2ViIHRlcm1pbmFsIGZvciBicm93c2VyIGFjY2VzcwogIHNzaCAgICAgICBFbmFibGUgU1NIIGFuZCBhZGQgcHVibGljIGtleSB0byBhIHJ1bm5pbmcgY29udGFpbmVyCiAgc2hlbGwgICAgIEVudGVyIGNvbnRhaW5lciBzaGVsbCAobmV3IG9yIGF0dGFjaCBleGlzdGluZykKICBzdG9wICAgICAgU3RvcCBhbmQgcmVtb3ZlIGEgY29udGFpbmVyCiAgdXBkYXRlICAgIFB1bGwgbGF0ZXN0IGltYWdlIGFuZCBvcHRpb25hbGx5IHJlc3RhcnQgY29udGFpbmVycwogIGxzICAgICAgICBMaXN0IG9jIGNvbnRhaW5lcnMgYW5kIGltYWdlCiAgY29uZmlnICAgIFNob3cgc2F2ZWQgY29uZmlndXJhdGlvbgogIGhlbHAgICAgICBTaG93IGhlbHAgKHRoaXMgbWVzc2FnZSwgb3IgaGVscCBmb3IgYSBzcGVjaWZpYyBjb21tYW5kKQoKR2xvYmFsIE9wdGlvbnM6CiAgLW4gTkFNRSAgICAgICBDb250YWluZXIgbmFtZSAoZGVmYXVsdDogb2MtPGRpcj4tPHBpZD4tPHRzPikKICAtZCBESVIgICAgICAgIExvY2FsIGRpcmVjdG9yeSB0byBtb3VudCAoZGVmYXVsdDogY3VycmVudCBkaXJlY3RvcnkpCiAgLXAgUE9SVCAgICAgICBXZWIgdGVybWluYWwgcG9ydCAocmVtb3RlIG1vZGUsIGRlZmF1bHQ6IDc2ODEpCiAgLWEgUE9SVCAgICAgICBBcHAgc2VydmljZSBwb3J0IChBSS1nZW5lcmF0ZWQgc2VydmljZXMsIGRlZmF1bHQ6IDgwMDApCiAgLXMgUE9SVCAgICAgICBTU0ggcG9ydCAoc3NoIGNvbW1hbmQsIGRlZmF1bHQ6IDgyMjIpCiAgLS10YWcgVEFHICAgICBJbWFnZSB0YWcgKGRlZmF1bHQ6IGxhdGVzdCkKICAtLWh0dHBzICAgICAgIEVuYWJsZSBIVFRQUyBvbiBnYXRld2F5IChzZWxmLXNpZ25lZCBjZXJ0LCBmb3IgZGlyZWN0IG5vbi1sb2NhbGhvc3QgYWNjZXNzKQogIC0tZGVidWcgICAgICAgU2hvdyBmdWxsIGRvY2tlciBjb21tYW5kcyBhbmQgY29udGFpbmVyIGxvZ3MgZm9yIHRyb3VibGVzaG9vdGluZwogIC12LCAtLXZlcnNpb24gU2hvdyB2ZXJzaW9uCiAgLWggICAgICAgICAgICBTaG93IGhlbHAKClF1aWNrIFN0YXJ0OgogIG9jICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIyBpbnRlcmFjdGl2ZSBDTEkgKGxhdGVzdCBpbWFnZSkKICBvYyAtLXRhZyAwLjIgcmVtb3RlICAgICAgICAgICAgICAgICAgICMgd2ViIHRlcm1pbmFsIHdpdGggc3BlY2lmaWMgdmVyc2lvbgogIG9jIHJlbW90ZSAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIyB3ZWIgdGVybWluYWwgYXQgaHR0cDovL2xvY2FsaG9zdDo3NjgxCiAgb2MgLS1odHRwcyByZW1vdGUgICAgICAgICAgICAgICAgICAgICAjIEhUVFBTIHdpdGggc2VsZi1zaWduZWQgY2VydAogIG9jIHNzaCA8bmFtZT4gICAgICAgICAgICAgICAgICAgICAgICAgIyBlbmFibGUgU1NIIG9uIHJ1bm5pbmcgY29udGFpbmVyCgpSdW4gJ29jIGhlbHAgPGNvbW1hbmQ+JyBmb3IgZGV0YWlscyBvbiBhIHNwZWNpZmljIGNvbW1hbmQuCkVPRgogICAgZXhpdCAwCn0KCnNob3dfY29tbWFuZF9oZWxwKCkgewogICAgbG9jYWwgY21kPSIkMSIKICAgIGNhc2UgIiRjbWQiIGluCiAgICAgICAgcnVuKQogICAgICAgICAgICBjYXQgPDxFT0YKb2MgcnVuIOKAlCBTdGFydCBpbnRlcmFjdGl2ZSBDbGF1ZGUgQ0xJCgpVc2FnZTogb2MgcnVuIFtjbGF1ZGUtYXJnc10KClN0YXJ0cyBhIGNvbnRhaW5lciB3aXRoIENsYXVkZSBDb2RlIENMSSBpbiBpbnRlcmFjdGl2ZSBtb2RlLgpZb3VyIGN1cnJlbnQgZGlyZWN0b3J5IGlzIG1vdW50ZWQgYXQgL3dvcmtzcGFjZSBpbnNpZGUgdGhlIGNvbnRhaW5lci4KQW55IGFkZGl0aW9uYWwgYXJndW1lbnRzIGFyZSBwYXNzZWQgZGlyZWN0bHkgdG8gdGhlICdjbGF1ZGUnIGNvbW1hbmQuCgpPcHRpb25zIChnbG9iYWwpOgogIC1uIE5BTUUgICAgIENvbnRhaW5lciBuYW1lCiAgLWQgRElSICAgICAgTG9jYWwgZGlyZWN0b3J5IHRvIG1vdW50IChkZWZhdWx0OiBjdXJyZW50IGRpcmVjdG9yeSkKCkV4YW1wbGVzOgogIG9jICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICMgc3RhcnQgQ2xhdWRlIGluIGN1cnJlbnQgZGlyZWN0b3J5CiAgb2MgLWQgL3BhdGgvdG8vcHJvamVjdCAgICAgICAgICAgICAjIG1vdW50IGEgc3BlY2lmaWMgcHJvamVjdAogIG9jIC1uIG15LWFnZW50ICAgICAgICAgICAgICAgICAgICAgIyBuYW1lZCBjb250YWluZXIKICBvYyBydW4gIkV4cGxhaW4gdGhpcyBjb2RlIiAgICAgICAgICMgcGFzcyBwcm9tcHQgdG8gY2xhdWRlCiAgb2MgcnVuIC0tZGFuZ2Vyb3VzbHktc2tpcC1wZXJtaXNzaW9ucyAgIyBwYXNzIGNsYXVkZSBmbGFncwoKVGhlIGNvbnRhaW5lciBpcyByZW1vdmVkIGF1dG9tYXRpY2FsbHkgd2hlbiB5b3UgZXhpdCAoIC0tcm0gKS4KRU9GCiAgICAgICAgICAgIDs7CiAgICAgICAgcmVtb3RlKQogICAgICAgICAgICBjYXQgPDxFT0YKb2MgcmVtb3RlIOKAlCBTdGFydCBXZWIgdGVybWluYWwgZm9yIGJyb3dzZXIgYWNjZXNzCgpVc2FnZTogb2MgcmVtb3RlIFtvcHRpb25zXQoKU3RhcnRzIGEgY29udGFpbmVyIGluIGRldGFjaGVkIG1vZGUgd2l0aCBhIHdlYi1iYXNlZCB0ZXJtaW5hbCAodHR5ZCkuCk9wZW4gdGhlIHByaW50ZWQgVVJMIGluIHlvdXIgYnJvd3NlciB0byBpbnRlcmFjdCB3aXRoIENsYXVkZSBDb2RlLgpTU0ggaXMgTk9UIGVuYWJsZWQgYnkgZGVmYXVsdCDigJQgdXNlICdvYyBzc2ggPG5hbWU+JyBzZXBhcmF0ZWx5LgoKT3B0aW9ucyAoZ2xvYmFsKToKICAtbiBOQU1FICAgICBDb250YWluZXIgbmFtZQogIC1kIERJUiAgICAgIExvY2FsIGRpcmVjdG9yeSB0byBtb3VudAogIC1wIFBPUlQgICAgIFdlYiB0ZXJtaW5hbCBwb3J0IG9uIGhvc3QgKGRlZmF1bHQ6IDc2ODEpCiAgLWEgUE9SVCAgICAgQXBwIHNlcnZpY2UgcG9ydCBvbiBob3N0IChBSS1nZW5lcmF0ZWQgc2VydmljZXMsIGRlZmF1bHQ6IDgwMDApCiAgLS1odHRwcyAgICAgRW5hYmxlIEhUVFBTIG9uIGdhdGV3YXkgKHNlbGYtc2lnbmVkIGNlcnQsIGZvciBub24tbG9jYWxob3N0IGFjY2VzcykKCkVudmlyb25tZW50OgogIFRUWURfVE9LRU4gICAgSWYgc2V0LCByZXF1aXJlcyB0aGlzIHRva2VuIGZvciB3ZWIgdGVybWluYWwgYWNjZXNzCiAgR0FURVdBWV9IVFRQUyBTZXQgdG8gMSB0byBlbmFibGUgSFRUUFMgb24gdGhlIGdhdGV3YXkKCkV4YW1wbGVzOgogIG9jIHJlbW90ZSAgICAgICAgICAgICAgICAgICAgICAgICAgICMgd2ViIHRlcm1pbmFsIGF0IGh0dHA6Ly9sb2NhbGhvc3Q6NzY4MQogIG9jIC0taHR0cHMgcmVtb3RlICAgICAgICAgICAgICAgICAgICMgSFRUUFMgbW9kZSAoc2VsZi1zaWduZWQgY2VydCkKICBvYyAtcCA4MDgwIHJlbW90ZSAgICAgICAgICAgICAgICAgICAjIGN1c3RvbSBwb3J0CiAgb2MgLW4gbXktYWdlbnQgLWQgL3NyYy9wcm9qZWN0IHJlbW90ZQoKQWZ0ZXIgc3RhcnRpbmcsIHlvdSBjYW46CiAgb2Mgc3NoIDxuYW1lPiAgICAgICAgICAgICAgICAgICAgICAgIyBlbmFibGUgU1NIIGFjY2VzcwogIG9jIHNoZWxsIDxuYW1lPiAgICAgICAgICAgICAgICAgICAgICMgZW50ZXIgdGhlIGNvbnRhaW5lcgogIG9jIHN0b3AgPG5hbWU+ICAgICAgICAgICAgICAgICAgICAgICMgc3RvcCB0aGUgY29udGFpbmVyCkVPRgogICAgICAgICAgICA7OwogICAgICAgIHNzaCkKICAgICAgICAgICAgY2F0IDw8RU9GCm9jIHNzaCDigJQgRW5hYmxlIFNTSCBhbmQgYWRkIHB1YmxpYyBrZXkgdG8gYSBydW5uaW5nIGNvbnRhaW5lcgoKVXNhZ2U6IG9jIHNzaCA8bmFtZT4gW3B1YmxpYy1rZXldIFstcyBQT1JUXQoKQWRkcyB5b3VyIFNTSCBwdWJsaWMga2V5IHRvIGEgcnVubmluZyBjb250YWluZXIncyBhdXRob3JpemVkX2tleXMsCnRoZW4gc2V0cyB1cCBwb3J0IGZvcndhcmRpbmcgc28geW91IGNhbiBjb25uZWN0IGZyb20gdGhlIGhvc3QuClJlcXVpcmVzICdzb2NhdCcgb24gdGhlIGhvc3QgZm9yIGF1dG9tYXRpYyBwb3J0IGZvcndhcmRpbmcuCgpBcmd1bWVudHM6CiAgPG5hbWU+ICAgICAgICBSdW5uaW5nIGNvbnRhaW5lciBuYW1lIG9yIElECiAgW3B1YmxpYy1rZXldICBTU0ggcHVibGljIGtleSBzdHJpbmcgKG9wdGlvbmFsLCBhdXRvLWRldGVjdGVkIGlmIG9taXR0ZWQpCgpPcHRpb25zOgogIC1zIFBPUlQgICAgICAgSG9zdC1zaWRlIFNTSCBwb3J0IChkZWZhdWx0OiA4MjIyKQoKS2V5IEF1dG8tRGV0ZWN0aW9uICh3aGVuIG5vIHB1YmxpYy1rZXkgaXMgZ2l2ZW4pOgogIFJlYWRzIHRoZSBmaXJzdCBmb3VuZCBmaWxlIGZyb206CiAgICB+Ly5zc2gvaWRfZWQyNTUxOS5wdWIKICAgIH4vLnNzaC9pZF9yc2EucHViCiAgICB+Ly5zc2gvaWRfZWNkc2EucHViCgpQb3J0IEZvcndhcmRpbmc6CiAgVXNlcyBzb2NhdCB0byBmb3J3YXJkIGhvc3Q6U1NIX1BPUlQgLT4gY29udGFpbmVyX2lwOjgyMjIKICBJbnN0YWxsIHNvY2F0OiBhcHQgaW5zdGFsbCBzb2NhdCAob3IgeXVtIGluc3RhbGwgc29jYXQpCgpFeGFtcGxlczoKICBvYyBzc2ggbXktYWdlbnQgICAgICAgICAgICAgICAgICAgICAjIGF1dG8tZGV0ZWN0IGtleSwgZGVmYXVsdCBwb3J0CiAgb2Mgc3NoIG15LWFnZW50IC1zIDIyMjIgICAgICAgICAgICAgIyBjdXN0b20gaG9zdCBwb3J0CiAgb2Mgc3NoIG15LWFnZW50ICJzc2gtcnNhIEFBQS4uLiIgICAgIyBzcGVjaWZpYyBwdWJsaWMga2V5CgpWUyBDb2RlIH4vLnNzaC9jb25maWcgYWZ0ZXIgZW5hYmxpbmc6CiAgSG9zdCBvYwogICAgICBIb3N0TmFtZSA8c2VydmVyLWlwPgogICAgICBQb3J0IDgyMjIKICAgICAgVXNlciBub2RlCiAgICAgIElkZW50aXR5RmlsZSB+Ly5zc2gvaWRfcnNhCgpOb3RlczoKICAtIFNTSCB1c2VzIHB1YmxpYyBrZXkgYXV0aGVudGljYXRpb24gb25seSAobm8gcGFzc3dvcmRzKQogIC0gVGhlIGNvbnRhaW5lciBtdXN0IGFscmVhZHkgYmUgcnVubmluZyAodXNlICdvYyByZW1vdGUnIGZpcnN0KQogIC0gLnNzaCBkaXJlY3RvcnkgaXMgbW91bnRlZCByZWFkLW9ubHkgZnJvbSBob3N0IGZvciBnaXQ7CiAgICAnb2Mgc3NoJyBhZGRzIGtleXMgdmlhIGRvY2tlciBleGVjIGludG8gdGhlIGNvbnRhaW5lcgpFT0YKICAgICAgICAgICAgOzsKICAgICAgICBzaGVsbCkKICAgICAgICAgICAgY2F0IDw8RU9GCm9jIHNoZWxsIOKAlCBFbnRlciBjb250YWluZXIgc2hlbGwKClVzYWdlOiBvYyBzaGVsbCBbbmFtZV0KCklmIGEgY29udGFpbmVyIG5hbWUvSUQgaXMgZ2l2ZW4sIG9wZW5zIGFuIGludGVyYWN0aXZlIGJhc2ggc2hlbGwKaW5zaWRlIHRoZSBydW5uaW5nIGNvbnRhaW5lci4gT3RoZXJ3aXNlIHN0YXJ0cyBhIG5ldyBjb250YWluZXIKd2l0aCBhIGJhc2ggc2hlbGwuCgpBcmd1bWVudHM6CiAgW25hbWVdICBSdW5uaW5nIGNvbnRhaW5lciBuYW1lIG9yIElEIChvbWl0IHRvIHN0YXJ0IGEgbmV3IHNoZWxsIGNvbnRhaW5lcikKCk9wdGlvbnMgKHdoZW4gc3RhcnRpbmcgbmV3IGNvbnRhaW5lcik6CiAgLW4gTkFNRSAgICAgQ29udGFpbmVyIG5hbWUKICAtZCBESVIgICAgICBMb2NhbCBkaXJlY3RvcnkgdG8gbW91bnQKCkV4YW1wbGVzOgogIG9jIHNoZWxsICAgICAgICAgICAgICAgICAgICAgICAgICAgICMgbmV3IGNvbnRhaW5lciB3aXRoIGJhc2ggc2hlbGwKICBvYyBzaGVsbCBteS1hZ2VudCAgICAgICAgICAgICAgICAgICAjIGF0dGFjaCB0byBydW5uaW5nIGNvbnRhaW5lcgogIG9jIC1kIC9wYXRoL3RvL3Byb2plY3Qgc2hlbGwgICAgICAgICMgbmV3IHNoZWxsIHdpdGggc3BlY2lmaWMgbW91bnQKRU9GCiAgICAgICAgICAgIDs7CiAgICAgICAgc3RvcCkKICAgICAgICAgICAgY2F0IDw8RU9GCm9jIHN0b3Ag4oCUIFN0b3AgYW5kIHJlbW92ZSBhIGNvbnRhaW5lcgoKVXNhZ2U6IG9jIHN0b3AgPG5hbWU+CgpTdG9wcyB0aGUgY29udGFpbmVyIGFuZCByZW1vdmVzIGl0LiBBbHNvIGtpbGxzIGFueSBzb2NhdApwb3J0IGZvcndhcmRpbmcgcHJvY2VzcyBhc3NvY2lhdGVkIHdpdGggdGhpcyBjb250YWluZXIncyBTU0ggcG9ydC4KCkFyZ3VtZW50czoKICA8bmFtZT4gIENvbnRhaW5lciBuYW1lIG9yIElECgpFeGFtcGxlczoKICBvYyBzdG9wIG15LWFnZW50CgpOb3RlOiBDb250YWluZXJzIHN0YXJ0ZWQgd2l0aCAnb2MgcmVtb3RlJyB1c2UgLS1ybSwgc28gc3RvcHBpbmcKdGhlbSBhbHNvIHJlbW92ZXMgdGhlIGNvbnRhaW5lciBhdXRvbWF0aWNhbGx5LgpFT0YKICAgICAgICAgICAgOzsKICAgICAgICB1cGRhdGUpCiAgICAgICAgICAgIGNhdCA8PEVPRgpvYyB1cGRhdGUg4oCUIFB1bGwgaW1hZ2UgYW5kIG9wdGlvbmFsbHkgcmVzdGFydCBjb250YWluZXJzCgpVc2FnZTogb2MgdXBkYXRlIFtvcHRpb25zXQoKUHVsbHMgdGhlIG9uZWNvZGUgaW1hZ2UgZnJvbSB0aGUgcmVnaXN0cnkuCkFsc28gdXBkYXRlcyB0aGUgb2MgQ0xJIGl0c2VsZiBieSBydW5uaW5nIGluc3RhbGwuc2ggZnJvbSB0aGUgcmVtb3RlLgpJZiBydW5uaW5nIGNvbnRhaW5lcnMgYXJlIGRldGVjdGVkLCBvZmZlcnMgdG8gcmVzdGFydCB0aGVtCndpdGggdGhlIG5ldyBpbWFnZSAocHJlc2VydmluZyB0aGUgc2FtZSBuYW1lLCBtb3VudHMsIGFuZCBlbnYpLgoKT3B0aW9uczoKICAtLXRhZyBUQUcgICAgIFB1bGwgYSBzcGVjaWZpYyB2ZXJzaW9uIGluc3RlYWQgb2YgZGVmYXVsdCAoZS5nLiAwLjIpCiAgLS1yZXN0YXJ0ICAgICBSZXN0YXJ0IGFsbCBydW5uaW5nIG9jIGNvbnRhaW5lcnMgYWZ0ZXIgcHVsbGluZwogIC0teWVzICAgICAgICAgU2tpcCBjb25maXJtYXRpb24gcHJvbXB0cwoKRXhhbXBsZXM6CiAgb2MgdXBkYXRlICAgICAgICAgICAgICAgICAgICAgICAgICAgIyBwdWxsIGxhdGVzdCBpbWFnZQogIG9jIHVwZGF0ZSAtLXRhZyAwLjIgICAgICAgICAgICAgICAgICMgcHVsbCBzcGVjaWZpYyB2ZXJzaW9uCiAgb2MgdXBkYXRlIC0tcmVzdGFydCAgICAgICAgICAgICAgICAgIyBwdWxsIGFuZCByZXN0YXJ0IHJ1bm5pbmcgY29udGFpbmVycwogIG9jIHVwZGF0ZSAtLXJlc3RhcnQgLS15ZXMgICAgICAgICAgICMgcHVsbCBhbmQgcmVzdGFydCB3aXRob3V0IHByb21wdApFT0YKICAgICAgICAgICAgOzsKICAgICAgICBscykKICAgICAgICAgICAgY2F0IDw8RU9GCm9jIGxzIOKAlCBMaXN0IG9jIGNvbnRhaW5lcnMgYW5kIGltYWdlCgpVc2FnZTogb2MgbHMKClNob3dzIGFsbCBjb250YWluZXJzIHVzaW5nIHRoZSBvbmVjb2RlIGltYWdlIGFuZCB0aGUKYXZhaWxhYmxlIGltYWdlIHZlcnNpb25zLgoKT3V0cHV0OgogIENvbnRhaW5lcnMgc2VjdGlvbiDigJQgbmFtZSwgc3RhdHVzLCBwb3J0IG1hcHBpbmdzCiAgSW1hZ2Ugc2VjdGlvbiAgICAgIOKAlCByZXBvc2l0b3J5OnRhZywgc2l6ZSwgY3JlYXRlZCB0aW1lCgpFeGFtcGxlczoKICBvYyBscwpFT0YKICAgICAgICAgICAgOzsKICAgICAgICBjb25maWcpCiAgICAgICAgICAgIGNhdCA8PEVPRgpvYyBjb25maWcg4oCUIFNob3cgc2F2ZWQgY29uZmlndXJhdGlvbgoKVXNhZ2U6IG9jIGNvbmZpZwoKRGlzcGxheXMgdGhlIGNvbmZpZ3VyYXRpb24gc3RvcmVkIGluIH4vLm9uZWNvZGUvc2V0dGluZ3MuanNvbi4KVGhlIEFQSV9LRVkgaXMgbWFza2VkIGZvciBzZWN1cml0eS4KCkNvbmZpZ3VyYXRpb24gZmlsZTogfi8ub25lY29kZS9zZXR0aW5ncy5qc29uIChwZXJtaXNzaW9uczogNjAwKQpDb250YWluczogQVBJX0tFWSwgQVBJX0JBU0VfVVJMLCBNT0RFTAoKUHJpb3JpdHk6IEVudmlyb25tZW50IHZhcmlhYmxlcyA+IENvbmZpZyBmaWxlID4gRGVmYXVsdHMKCkV4YW1wbGVzOgogIG9jIGNvbmZpZyAgICAgICAgICAgICAgICAgICAgICAgICAgICMgc2hvdyBjdXJyZW50IGNvbmZpZwogIEFQSV9LRVk9c2steHh4IG9jIGNvbmZpZyAgICAgICAgICAgICMgZW52IHZhcnMgb3ZlcnJpZGUgY29uZmlnCkVPRgogICAgICAgICAgICA7OwogICAgICAgIGhlbHApCiAgICAgICAgICAgIGNhdCA8PEVPRgpvYyBoZWxwIOKAlCBTaG93IGhlbHAKClVzYWdlOiBvYyBoZWxwIFtjb21tYW5kXQoKU2hvdyBnZW5lcmFsIGhlbHAsIG9yIGRldGFpbGVkIGhlbHAgZm9yIGEgc3BlY2lmaWMgY29tbWFuZC4KCkV4YW1wbGVzOgogIG9jIGhlbHAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICMgZ2VuZXJhbCBoZWxwCiAgb2MgaGVscCByZW1vdGUgICAgICAgICAgICAgICAgICAgICAgIyBoZWxwIGZvciAncmVtb3RlJyBjb21tYW5kCiAgb2MgaGVscCBzc2ggICAgICAgICAgICAgICAgICAgICAgICAgIyBoZWxwIGZvciAnc3NoJyBjb21tYW5kCkVPRgogICAgICAgICAgICA7OwogICAgICAgICopCiAgICAgICAgICAgIGVjaG8gIlVua25vd24gY29tbWFuZDogJGNtZCIgPiYyCiAgICAgICAgICAgIGVjaG8gIlJ1biAnb2MgaGVscCcgdG8gc2VlIGF2YWlsYWJsZSBjb21tYW5kcy4iID4mMgogICAgICAgICAgICBleGl0IDEKICAgICAgICAgICAgOzsKICAgIGVzYWMKICAgIGV4aXQgMAp9CgojIOKUgOKUgCBQYXJzZSBnbG9iYWwgb3B0aW9ucyDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKQ09NTUFORD0iIgpQT1JUPSIiCkFQUF9QT1JUPSIiClNTSF9QT1JUPSI4MjIyIgpHQVRFV0FZX0hUVFBTPSIiCk9DX0RFQlVHPSIiCgp3aGlsZSBbICQjIC1ndCAwIF07IGRvCiAgICBjYXNlICIkMSIgaW4KICAgICAgICAtbikgICAgICAgICAgQ09OVEFJTkVSX05BTUU9IiQyIjsgc2hpZnQgMiA7OwogICAgICAgIC1kKSAgICAgICAgICBXT1JLRElSPSIkMiI7IHNoaWZ0IDIgOzsKICAgICAgICAtcCkgICAgICAgICAgUE9SVD0iJDIiOyBzaGlmdCAyIDs7CiAgICAgICAgLWEpICAgICAgICAgIEFQUF9QT1JUPSIkMiI7IHNoaWZ0IDIgOzsKICAgICAgICAtcykgICAgICAgICAgU1NIX1BPUlQ9IiQyIjsgc2hpZnQgMiA7OwogICAgICAgIC0tdGFnKSAgICAgICBJTUFHRV9UQUc9IiQyIjsgc2hpZnQgMiA7OwogICAgICAgIC0taHR0cHMpICAgIEdBVEVXQVlfSFRUUFM9IjEiOyBzaGlmdCA7OwogICAgICAgIC0tZGVidWcpICAgIE9DX0RFQlVHPSIxIjsgc2hpZnQgOzsKICAgICAgICAtaHwtLWhlbHApICAgc2hvd19oZWxwIDs7CiAgICAgICAgLXZ8LS12ZXJzaW9uKSBlY2hvICJvYyAke09DX1ZFUlNJT059IjsgZXhpdCAwIDs7CiAgICAgICAgcnVufHJlbW90ZXxzc2h8c2hlbGx8c3RvcHx1cGRhdGV8bHN8Y29uZmlnfGhlbHApCiAgICAgICAgICAgICAgICAgICAgIENPTU1BTkQ9IiQxIjsgc2hpZnQ7IGJyZWFrIDs7CiAgICAgICAgKikgICAgICAgICAgIENPTU1BTkQ9InJ1biI7IGJyZWFrIDs7CiAgICBlc2FjCmRvbmUKCiMgRGVmYXVsdCBjb21tYW5kCkNPTU1BTkQ9IiR7Q09NTUFORDotcnVufSIKCiMgUGFyc2Ugc3ViY29tbWFuZC1zcGVjaWZpYyBvcHRpb25zCndoaWxlIFsgJCMgLWd0IDAgXTsgZG8KICAgIGNhc2UgIiQxIiBpbgogICAgICAgIC1uKSAgICAgICAgQ09OVEFJTkVSX05BTUU9IiQyIjsgc2hpZnQgMiA7OwogICAgICAgIC1kKSAgICAgICAgV09SS0RJUj0iJDIiOyBzaGlmdCAyIDs7CiAgICAgICAgLXApICAgICAgICBQT1JUPSIkMiI7IHNoaWZ0IDIgOzsKICAgICAgICAtYSkgICAgICAgIEFQUF9QT1JUPSIkMiI7IHNoaWZ0IDIgOzsKICAgICAgICAtcykgICAgICAgIFNTSF9QT1JUPSIkMiI7IHNoaWZ0IDIgOzsKICAgICAgICAtLXRhZykgICAgIElNQUdFX1RBRz0iJDIiOyBzaGlmdCAyIDs7CiAgICAgICAgLS1odHRwcykgICAgR0FURVdBWV9IVFRQUz0iMSI7IHNoaWZ0IDs7CiAgICAgICAgLS1kZWJ1ZykgICAgT0NfREVCVUc9IjEiOyBzaGlmdCA7OwogICAgICAgIC12fC0tdmVyc2lvbikgZWNobyAib2MgJHtPQ19WRVJTSU9OfSI7IGV4aXQgMCA7OwogICAgICAgICopICBicmVhayA7OwogICAgZXNhYwpkb25lCgojIEFwcGx5IGltYWdlIHRhZyBvdmVycmlkZQpbIC1uICIkSU1BR0VfVEFHIiBdICYmIElNQUdFPSIke0lNQUdFX1JFUE99OiR7SU1BR0VfVEFHfSIKCiMg4pSA4pSAIERlYnVnIGhlbHBlciDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKZGVidWdfbG9nKCkgewogICAgWyAiJHtPQ19ERUJVRzotfSIgPSAiMSIgXSB8fCByZXR1cm4gMAogICAgZWNobyAiW2RlYnVnXSAkKiIgPiYyCn0KCmRlYnVnX2NtZCgpIHsKICAgIFsgIiR7T0NfREVCVUc6LX0iID0gIjEiIF0gfHwgcmV0dXJuIDAKICAgIGVjaG8gIltkZWJ1Z10gY29tbWFuZDogJCoiID4mMgp9CgojIOKUgOKUgCBTdWJjb21tYW5kcyDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKCmNtZF9ydW4oKSB7CiAgICByZXNvbHZlX2FwaV9rZXkKICAgIGJ1aWxkX2RvY2tlcl9hcmdzCiAgICBhcmdzKz0oLS1ybSAtaXQgIiRJTUFHRSIgY2xhdWRlKQogICAgZGVidWdfY21kIGRvY2tlciBydW4gIiR7YXJnc1tAXX0iICIkQCIKICAgIGV4ZWMgZG9ja2VyIHJ1biAiJHthcmdzW0BdfSIgIiRAIgp9CgpjbWRfcmVtb3RlKCkgewogICAgcmVzb2x2ZV9hcGlfa2V5CiAgICBidWlsZF9kb2NrZXJfYXJncwogICAgbG9jYWwgcD0iJHtQT1JUOi03NjgxfSIKICAgIGxvY2FsIGFwPSIke0FQUF9QT1JUOi04MDAwfSIKICAgIGFyZ3MrPSgKICAgICAgICAtZAogICAgICAgIC1wICIke3B9Ojc2ODEiCiAgICAgICAgLXAgIiR7YXB9OjgwMDAiCiAgICAgICAgLWUgIlRUWURfUE9SVD03NjgxIgogICAgICAgIC1lICJBUFBfUE9SVD04MDAwIgogICAgKQogICAgWyAtbiAiJHtUVFlEX1RPS0VOOi19IiBdICYmIGFyZ3MrPSgtZSAiVFRZRF9UT0tFTj0kVFRZRF9UT0tFTiIpCiAgICBbIC1uICIke0dBVEVXQVlfSFRUUFM6LX0iIF0gJiYgYXJncys9KC1lICJHQVRFV0FZX0hUVFBTPSRHQVRFV0FZX0hUVFBTIikKICAgICMgTGFiZWwgdGhlIFNTSCBwb3J0IHNvIGNtZF9zdG9wIGNhbiBmaW5kIHRoZSByaWdodCBzb2NhdCBwcm9jZXNzCiAgICBhcmdzKz0oLS1sYWJlbCAib2Muc3NoX3BvcnQ9JHtTU0hfUE9SVH0iKQogICAgYXJncys9KCIkSU1BR0UiIHJlbW90ZSkKICAgIGRlYnVnX2NtZCBkb2NrZXIgcnVuICIke2FyZ3NbQF19IgogICAgIyBDYXB0dXJlIHRoZSBhY3R1YWwgY29udGFpbmVyIG5hbWUgZnJvbSBkb2NrZXIgcnVuIG91dHB1dAogICAgbG9jYWwgY29udGFpbmVyX2lkCiAgICBjb250YWluZXJfaWQ9JChkb2NrZXIgcnVuICIke2FyZ3NbQF19IiAyPiYxKSB8fCB7IGVjaG8gIkVycm9yOiBmYWlsZWQgdG8gc3RhcnQgY29udGFpbmVyIiA+JjI7IGVjaG8gIiRjb250YWluZXJfaWQiID4mMjsgZXhpdCAxOyB9CiAgICAjIFZhbGlkYXRlOiBvbiBzdWNjZXNzIGRvY2tlciBydW4gb3V0cHV0cyBhIDY0LWNoYXIgaGV4IGNvbnRhaW5lciBJRAogICAgaWYgW1sgISAiJGNvbnRhaW5lcl9pZCIgPX4gXlswLTlhLWZdezY0fSQgXV07IHRoZW4KICAgICAgICBlY2hvICJFcnJvcjogZmFpbGVkIHRvIHN0YXJ0IGNvbnRhaW5lciIgPiYyCiAgICAgICAgZWNobyAiJGNvbnRhaW5lcl9pZCIgPiYyCiAgICAgICAgZXhpdCAxCiAgICBmaQogICAgIyBSZXNvbHZlIHRvIHRoZSBhY3R1YWwgY29udGFpbmVyIG5hbWUgdG8gYXZvaWQgdGltZXN0YW1wIGRyaWZ0CiAgICBkZWJ1Z19sb2cgImNvbnRhaW5lcl9pZDogJHtjb250YWluZXJfaWR9IgogICAgbG9jYWwgYWN0dWFsX25hbWUKICAgIGFjdHVhbF9uYW1lPSQoZG9ja2VyIGluc3BlY3QgIiRjb250YWluZXJfaWQiIC0tZm9ybWF0ICd7ey5OYW1lfX0nIDI+L2Rldi9udWxsIHwgc2VkICdzL15cLy8vJykgfHwgYWN0dWFsX25hbWU9IiR7Q09OVEFJTkVSX05BTUU6LW9jLSQoYmFzZW5hbWUgIiQocHdkKSIpfSIKICAgICMgV2FpdCBicmllZmx5IGFuZCB2ZXJpZnkgdGhlIGNvbnRhaW5lciBpcyBhY3R1YWxseSBydW5uaW5nIChub3QgY3Jhc2hlZCBhZnRlciBzdGFydCkKICAgIHNsZWVwIDIKICAgIGxvY2FsIGNvbnRhaW5lcl9zdGF0ZQogICAgY29udGFpbmVyX3N0YXRlPSQoZG9ja2VyIGluc3BlY3QgIiRjb250YWluZXJfaWQiIC0tZm9ybWF0ICd7ey5TdGF0ZS5TdGF0dXN9fScgMj4vZGV2L251bGwgfHwgZWNobyAiZ29uZSIpCiAgICBpZiBbICIkY29udGFpbmVyX3N0YXRlIiAhPSAicnVubmluZyIgXTsgdGhlbgogICAgICAgIGVjaG8gIkVycm9yOiBjb250YWluZXIgZXhpdGVkIGltbWVkaWF0ZWx5IChzdGF0dXM6ICR7Y29udGFpbmVyX3N0YXRlfSkiID4mMgogICAgICAgIGxvY2FsIGV4aXRfY29kZQogICAgICAgIGV4aXRfY29kZT0kKGRvY2tlciBpbnNwZWN0ICIkY29udGFpbmVyX2lkIiAtLWZvcm1hdCAne3suU3RhdGUuRXhpdENvZGV9fScgMj4vZGV2L251bGwgfHwgZWNobyAiPyIpCiAgICAgICAgZWNobyAiRXhpdCBjb2RlOiAke2V4aXRfY29kZX0iID4mMgogICAgICAgIGVjaG8gIiIgPiYyCiAgICAgICAgZWNobyAiQ29udGFpbmVyIGxvZ3M6IiA+JjIKICAgICAgICBkb2NrZXIgbG9ncyAiJGNvbnRhaW5lcl9pZCIgMj4mMSB8IHRhaWwgLTIwID4mMgogICAgICAgIGV4aXQgMQogICAgZmkKICAgICMgRGVidWc6IHNob3cgY29udGFpbmVyIGxvZ3MgYWZ0ZXIgc3VjY2Vzc2Z1bCBzdGFydAogICAgaWYgWyAiJHtPQ19ERUJVRzotfSIgPSAiMSIgXTsgdGhlbgogICAgICAgIGRlYnVnX2xvZyAiY29udGFpbmVyIHN0YXRlOiAke2NvbnRhaW5lcl9zdGF0ZX0iCiAgICAgICAgZWNobyAiW2RlYnVnXSBjb250YWluZXIgbG9ncyAobGFzdCAyMCBsaW5lcyk6IiA+JjIKICAgICAgICBkb2NrZXIgbG9ncyAiJGNvbnRhaW5lcl9pZCIgMj4mMSB8IHRhaWwgLTIwID4mMgogICAgZmkKICAgIGxvY2FsIHByb3RvPSJodHRwIgogICAgWyAiJHtHQVRFV0FZX0hUVFBTOi0wfSIgPSAiMSIgXSAmJiBwcm90bz0iaHR0cHMiCiAgICBlY2hvICJPbmVDb2RlIHJ1bm5pbmc6IgogICAgZWNobyAiICBXZWI6ICAke3Byb3RvfTovL2xvY2FsaG9zdDoke3B9IgogICAgZWNobyAiICBBcHA6ICAke3Byb3RvfTovL2xvY2FsaG9zdDoke2FwfSAgKEFJLWdlbmVyYXRlZCBzZXJ2aWNlcykiCiAgICBlY2hvICIgIENvbnRhaW5lcjogJHthY3R1YWxfbmFtZX0iCiAgICBlY2hvICIiCiAgICBlY2hvICIgIG9jIHNzaCAke2FjdHVhbF9uYW1lfSAgICAgICAgICAgICAgIyBlbmFibGUgU1NIIgogICAgZWNobyAiICBvYyBzaGVsbCAke2FjdHVhbF9uYW1lfSIKICAgIGVjaG8gIiAgb2Mgc3RvcCAke2FjdHVhbF9uYW1lfSIKfQoKY21kX3NzaCgpIHsKICAgIGlmIFsgLXogIiR7MTotfSIgXTsgdGhlbgogICAgICAgIGVjaG8gIlVzYWdlOiBvYyBzc2ggPG5hbWU+IFtwdWJsaWMta2V5XSBbLXMgUE9SVF0iID4mMgogICAgICAgIGVjaG8gIiIgPiYyCiAgICAgICAgZWNobyAiICBvYyBzc2ggbXktYWdlbnQgICAgICAgICAgICAgICAgICAgICAgICAgICAjIGF1dG8tZGV0ZWN0IGtleSBmcm9tIH4vLnNzaC8qLnB1YiIgPiYyCiAgICAgICAgZWNobyAiICBvYyBzc2ggbXktYWdlbnQgLXMgMjIyMiAgICAgICAgICAgICAgICAgICAjIHVzZSBjdXN0b20gcG9ydCIgPiYyCiAgICAgICAgZWNobyAiICBvYyBzc2ggbXktYWdlbnQgXCJzc2gtcnNhIEFBQS4uLlwiICAgICAgICAgICAjIHVzZSBzcGVjaWZpYyBrZXkiID4mMgogICAgICAgIGV4aXQgMQogICAgZmkKICAgIGxvY2FsIG5hbWU9IiQxIgogICAgc2hpZnQKCiAgICAjIFBhcnNlIHNzaC1zcGVjaWZpYyBvcHRpb25zCiAgICBsb2NhbCBzc2hfa2V5PSIiCiAgICB3aGlsZSBbICQjIC1ndCAwIF07IGRvCiAgICAgICAgY2FzZSAiJDEiIGluCiAgICAgICAgICAgIC1zKSBTU0hfUE9SVD0iJDIiOyBzaGlmdCAyIDs7CiAgICAgICAgICAgICopICBzc2hfa2V5PSIkMSI7IHNoaWZ0IDs7CiAgICAgICAgZXNhYwogICAgZG9uZQoKICAgICMgQXV0by1kZXRlY3Qga2V5IGlmIG5vdCBwcm92aWRlZAogICAgaWYgWyAteiAiJHNzaF9rZXkiIF0gJiYgWyAtZCAiJEhPTUUvLnNzaCIgXTsgdGhlbgogICAgICAgIGxvY2FsIHB1Yl9maWxlPSIiCiAgICAgICAgZm9yIGYgaW4gIiRIT01FLy5zc2gvaWRfZWQyNTUxOS5wdWIiICIkSE9NRS8uc3NoL2lkX3JzYS5wdWIiICIkSE9NRS8uc3NoL2lkX2VjZHNhLnB1YiI7IGRvCiAgICAgICAgICAgIGlmIFsgLWYgIiRmIiBdOyB0aGVuCiAgICAgICAgICAgICAgICBwdWJfZmlsZT0iJGYiCiAgICAgICAgICAgICAgICBicmVhawogICAgICAgICAgICBmaQogICAgICAgIGRvbmUKICAgICAgICBpZiBbIC1uICIkcHViX2ZpbGUiIF07IHRoZW4KICAgICAgICAgICAgc3NoX2tleT0kKGNhdCAiJHB1Yl9maWxlIikKICAgICAgICAgICAgZWNobyAiVXNpbmcga2V5IGZyb20gJHtwdWJfZmlsZX0iCiAgICAgICAgZmkKICAgIGZpCgogICAgaWYgWyAteiAiJHNzaF9rZXkiIF07IHRoZW4KICAgICAgICBlY2hvICJFcnJvcjogbm8gcHVibGljIGtleSBmb3VuZC4gUHJvdmlkZSBvbmUgZXhwbGljaXRseToiID4mMgogICAgICAgIGVjaG8gIiAgb2Mgc3NoICR7bmFtZX0gXCJzc2gtcnNhIEFBQS4uLlwiIiA+JjIKICAgICAgICBleGl0IDEKICAgIGZpCgogICAgIyBBZGQga2V5IHRvIGNvbnRhaW5lcidzIGF1dGhvcml6ZWRfa2V5cyAod3JpdGFibGUgcGF0aCwgLnNzaCBpcyByZWFkLW9ubHkgbW91bnQpCiAgICAjIFVzZSBzdGRpbiB0byBhdm9pZCBzaGVsbCBpbmplY3Rpb24gZnJvbSBTU0gga2V5IGNvbnRlbnQKICAgIGRlYnVnX2NtZCBkb2NrZXIgZXhlYyAtaSAiJG5hbWUiIGJhc2ggLWMgJy4uLicKICAgIGRvY2tlciBleGVjIC1pICIkbmFtZSIgYmFzaCAtYyAnCiAgICAgICAgbWtkaXIgLXAgL2hvbWUvd29yay8uc3NoLWtleXMKICAgICAgICByZWFkIC1yIGtleQogICAgICAgIGdyZXAgLXFGICIka2V5IiAvaG9tZS93b3JrLy5zc2gta2V5cy9hdXRob3JpemVkX2tleXMgMj4vZGV2L251bGwgfHwgZWNobyAiJGtleSIgPj4gL2hvbWUvd29yay8uc3NoLWtleXMvYXV0aG9yaXplZF9rZXlzCiAgICAgICAgY2hvd24gLVIgbm9kZTpub2RlIC9ob21lL3dvcmsvLnNzaC1rZXlzCiAgICAgICAgY2htb2QgNzAwIC9ob21lL3dvcmsvLnNzaC1rZXlzCiAgICAgICAgY2htb2QgNjAwIC9ob21lL3dvcmsvLnNzaC1rZXlzL2F1dGhvcml6ZWRfa2V5cwogICAgJyA8PDwgIiRzc2hfa2V5IgoKICAgICMgU2V0IHVwIHBvcnQgZm9yd2FyZGluZzogaG9zdDpTU0hfUE9SVCAtPiBjb250YWluZXI6ODIyMgogICAgIyBVc2UgZG9ja2VyIHBvcnQgbWFwcGluZyB2aWEgaXB0YWJsZXMvc29jYXQgc2luY2UgY29udGFpbmVyIGlzIGFscmVhZHkgcnVubmluZwogICAgbG9jYWwgY29udGFpbmVyX2lwCiAgICBkZWJ1Z19jbWQgZG9ja2VyIGluc3BlY3QgIiRuYW1lIiAtLWZvcm1hdCAne3tyYW5nZSAuTmV0d29ya1NldHRpbmdzLk5ldHdvcmtzfX17ey5JUEFkZHJlc3N9fXt7ZW5kfX0nCiAgICBjb250YWluZXJfaXA9JChkb2NrZXIgaW5zcGVjdCAiJG5hbWUiIC0tZm9ybWF0ICd7e3JhbmdlIC5OZXR3b3JrU2V0dGluZ3MuTmV0d29ya3N9fXt7LklQQWRkcmVzc319e3tlbmR9fScgMj4vZGV2L251bGwgfHwgdHJ1ZSkKCiAgICAjIFVzZSBzb2NhdCB0byBmb3J3YXJkIHBvcnQgaWYgYXZhaWxhYmxlLCBvdGhlcndpc2UgcHJpbnQgbWFudWFsIGluc3RydWN0aW9ucwogICAgaWYgY29tbWFuZCAtdiBzb2NhdCAmPi9kZXYvbnVsbDsgdGhlbgogICAgICAgICMgS2lsbCBhbnkgZXhpc3Rpbmcgc29jYXQgb24gdGhpcyBwb3J0CiAgICAgICAgcGtpbGwgLWYgInNvY2F0IFRDUC1MSVNURU46JHtTU0hfUE9SVH0iIDI+L2Rldi9udWxsIHx8IHRydWUKICAgICAgICBub2h1cCBzb2NhdCBUQ1AtTElTVEVOOiR7U1NIX1BPUlR9LGZvcmsscmV1c2VhZGRyIFRDUDoke2NvbnRhaW5lcl9pcH06ODIyMiA+L2Rldi9udWxsIDI+JjEgJgogICAgICAgIGxvY2FsIHNlcnZlcl9pcAogICAgICAgIHNlcnZlcl9pcD0kKGhvc3RuYW1lIC1JIDI+L2Rldi9udWxsIHwgYXdrICd7cHJpbnQgJDF9JyB8fCBlY2hvICI8c2VydmVyLWlwPiIpCiAgICAgICAgZWNobyAiU1NIIGVuYWJsZWQ6IgogICAgICAgIGVjaG8gIiAgc3NoIC1wICR7U1NIX1BPUlR9IG5vZGVAJHtzZXJ2ZXJfaXB9IgogICAgICAgIGVjaG8gIiIKICAgICAgICBlY2hvICJWUyBDb2RlIH4vLnNzaC9jb25maWc6IgogICAgICAgIGVjaG8gIiAgSG9zdCBvYyIKICAgICAgICBlY2hvICIgICAgICBIb3N0TmFtZSAke3NlcnZlcl9pcH0iCiAgICAgICAgZWNobyAiICAgICAgUG9ydCAke1NTSF9QT1JUfSIKICAgICAgICBlY2hvICIgICAgICBVc2VyIG5vZGUiCiAgICAgICAgZWNobyAiICAgICAgSWRlbnRpdHlGaWxlIH4vLnNzaC9pZF9yc2EiCiAgICBlbHNlCiAgICAgICAgZWNobyAiU1NIIGVuYWJsZWQgKGtleSBhZGRlZCkuIENvbnRhaW5lciBJUDogJHtjb250YWluZXJfaXB9OjgyMjIiCiAgICAgICAgZWNobyAiIgogICAgICAgIGVjaG8gIkluc3RhbGwgc29jYXQgZm9yIGF1dG9tYXRpYyBwb3J0IGZvcndhcmRpbmc6IgogICAgICAgIGVjaG8gIiAgYXB0IGluc3RhbGwgc29jYXQgICAjIG9yIHl1bSBpbnN0YWxsIHNvY2F0IgogICAgICAgIGVjaG8gIiIKICAgICAgICBlY2hvICJUaGVuIHJlLXJ1bjogb2Mgc3NoICR7bmFtZX0iCiAgICAgICAgZWNobyAiIgogICAgICAgIGVjaG8gIk9yIGNvbm5lY3QgZGlyZWN0bHkgZnJvbSB0aGlzIHNlcnZlcjoiCiAgICAgICAgZWNobyAiICBzc2ggLXAgODIyMiBub2RlQCR7Y29udGFpbmVyX2lwfSIKICAgIGZpCn0KCmNtZF9zaGVsbCgpIHsKICAgICMgSWYgYSBuYW1lL2lkIGlzIGdpdmVuLCBhdHRhY2ggdG8gZXhpc3RpbmcgY29udGFpbmVyCiAgICBpZiBbIC1uICIkezE6LX0iIF07IHRoZW4KICAgICAgICBkZWJ1Z19jbWQgZG9ja2VyIGV4ZWMgLWl0ICIkMSIgL2Jpbi9iYXNoCiAgICAgICAgZXhlYyBkb2NrZXIgZXhlYyAtaXQgIiQxIiAvYmluL2Jhc2gKICAgIGZpCiAgICAjIE90aGVyd2lzZSBzdGFydCBhIG5ldyBzaGVsbCBjb250YWluZXIKICAgIHJlc29sdmVfYXBpX2tleQogICAgYnVpbGRfZG9ja2VyX2FyZ3MKICAgIGFyZ3MrPSgtLXJtIC1pdCAiJElNQUdFIiAvYmluL2Jhc2gpCiAgICBkZWJ1Z19jbWQgZG9ja2VyIHJ1biAiJHthcmdzW0BdfSIKICAgIGV4ZWMgZG9ja2VyIHJ1biAiJHthcmdzW0BdfSIKfQoKY21kX3N0b3AoKSB7CiAgICBpZiBbIC16ICIkezE6LX0iIF07IHRoZW4KICAgICAgICBlY2hvICJVc2FnZTogb2Mgc3RvcCA8bmFtZT4iID4mMgogICAgICAgIGV4aXQgMQogICAgZmkKICAgICMgS2lsbCBzb2NhdCBmb3J3YXJkaW5nIOKAlCByZWFkIHRoZSBhY3R1YWwgU1NIIHBvcnQgZnJvbSB0aGUgY29udGFpbmVyIGxhYmVsCiAgICAjIChoYW5kbGVzIGN1c3RvbSBwb3J0cyBzZXQgdmlhIC1zIGR1cmluZyAnb2MgcmVtb3RlJykKICAgIGxvY2FsIHN0b3Bfc3NoX3BvcnQKICAgIGRlYnVnX2NtZCBkb2NrZXIgaW5zcGVjdCAiJDEiIC0tZm9ybWF0ICd7e2luZGV4IC5Db25maWcuTGFiZWxzICJvYy5zc2hfcG9ydCJ9fScKICAgIHN0b3Bfc3NoX3BvcnQ9JChkb2NrZXIgaW5zcGVjdCAiJDEiIC0tZm9ybWF0ICd7e2luZGV4IC5Db25maWcuTGFiZWxzICJvYy5zc2hfcG9ydCJ9fScgMj4vZGV2L251bGwpIHx8IHRydWUKICAgIHN0b3Bfc3NoX3BvcnQ9IiR7c3RvcF9zc2hfcG9ydDotJHtTU0hfUE9SVH19IgogICAgcGtpbGwgLWYgInNvY2F0IFRDUC1MSVNURU46JHtzdG9wX3NzaF9wb3J0fSIgMj4vZGV2L251bGwgfHwgdHJ1ZQogICAgZGVidWdfY21kIGRvY2tlciBzdG9wICIkMSIKICAgIGRlYnVnX2NtZCBkb2NrZXIgcm0gIiQxIgogICAgZG9ja2VyIHN0b3AgIiQxIiAyPi9kZXYvbnVsbCAmJiBkb2NrZXIgcm0gIiQxIiAyPi9kZXYvbnVsbAogICAgZWNobyAiQ29udGFpbmVyICQxIHJlbW92ZWQiCn0KCmNtZF9scygpIHsKICAgIGVjaG8gIj09PSBDb250YWluZXJzID09PSIKICAgIGRvY2tlciBwcyAtYSAtLWZvcm1hdCAie3suSUR9fVx0e3suTmFtZXN9fVx0e3suU3RhdHVzfX1cdHt7LlBvcnRzfX0iIDI+L2Rldi9udWxsIHwgd2hpbGUgSUZTPSQnXHQnIHJlYWQgLXIgaWQgbmFtZSBzdGF0dXMgcG9ydHM7IGRvCiAgICAgICAgaW1nPSQoZG9ja2VyIGluc3BlY3QgIiRpZCIgLS1mb3JtYXQgJ3t7LkNvbmZpZy5JbWFnZX19JyAyPi9kZXYvbnVsbCB8fCB0cnVlKQogICAgICAgIGlmIGVjaG8gIiRpbWciIHwgZ3JlcCAtcSAib25lY29kZSI7IHRoZW4KICAgICAgICAgICAgbW91bnRfc3JjPSQoZG9ja2VyIGluc3BlY3QgIiRpZCIgLS1mb3JtYXQgJ3t7cmFuZ2UgLk1vdW50c319e3tpZiBlcSAuRGVzdGluYXRpb24gIi93b3Jrc3BhY2UifX17ey5Tb3VyY2V9fXt7ZW5kfX17e2VuZH19JyAyPi9kZXYvbnVsbCB8fCB0cnVlKQogICAgICAgICAgICBwcmludGYgIiVzXHQlc1x0JXNcdCVzXG4iICIkbmFtZSIgIiRzdGF0dXMiICIkcG9ydHMiICIkbW91bnRfc3JjIgogICAgICAgIGZpCiAgICBkb25lIHwgY29sdW1uIC10IC1zICQnXHQnIDI+L2Rldi9udWxsIHx8IHRydWUKICAgIGVjaG8gIiIKICAgIGVjaG8gIj09PSBJbWFnZSA9PT0iCiAgICBkb2NrZXIgaW1hZ2VzICJnaGNyLmlvL3lpeWFuLXlpeGluZy9vbmVjb2RlIiAtLWZvcm1hdCAidGFibGUge3suUmVwb3NpdG9yeX19Ont7LlRhZ319XHR7ey5TaXplfX1cdHt7LkNyZWF0ZWRBdH19IiAyPi9kZXYvbnVsbCB8fCB0cnVlCn0KCmNtZF9jb25maWcoKSB7CiAgICBpZiBbIC1mICIkT0NfQ09ORklHIiBdOyB0aGVuCiAgICAgICAgZWNobyAiQ29uZmlnOiAkT0NfQ09ORklHIgogICAgICAgIHNlZCAncy9cKCJBUElfS0VZIjogKiJcKVteIl0qL1wxKioqKi8nICIkT0NfQ09ORklHIgogICAgZWxzZQogICAgICAgIGVjaG8gIk5vIGNvbmZpZyBmaWxlICgkT0NfQ09ORklHKSIKICAgIGZpCn0KCmNtZF91cGRhdGUoKSB7CiAgICBsb2NhbCBkb19yZXN0YXJ0PWZhbHNlCiAgICBsb2NhbCBhdXRvX3llcz1mYWxzZQogICAgbG9jYWwgdXBkYXRlX3RhZz0iIgoKICAgIHdoaWxlIFsgJCMgLWd0IDAgXTsgZG8KICAgICAgICBjYXNlICIkMSIgaW4KICAgICAgICAgICAgLS1yZXN0YXJ0KSBkb19yZXN0YXJ0PXRydWU7IHNoaWZ0IDs7CiAgICAgICAgICAgIC0teWVzKSAgICAgYXV0b195ZXM9dHJ1ZTsgc2hpZnQgOzsKICAgICAgICAgICAgLS10YWcpICAgICB1cGRhdGVfdGFnPSIkMiI7IHNoaWZ0IDIgOzsKICAgICAgICAgICAgKikgICAgICAgICBzaGlmdCA7OwogICAgICAgIGVzYWMKICAgIGRvbmUKCiAgICAjIERldGVybWluZSB0YXJnZXQgdmVyc2lvbgogICAgbG9jYWwgcmVtb3RlX3ZlcnNpb25fdXJsPSJodHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20veWl5YW4teWl4aW5nL29uZWNvZGUvbWFpbi9hZ2VudC1ydW50aW1lL1ZFUlNJT04iCiAgICBsb2NhbCB0YXJnZXRfdmVyc2lvbj0iJHVwZGF0ZV90YWciCgogICAgaWYgWyAteiAiJHRhcmdldF92ZXJzaW9uIiBdOyB0aGVuCiAgICAgICAgZWNobyAiQ2hlY2tpbmcgbGF0ZXN0IHZlcnNpb24gZnJvbSAke3JlbW90ZV92ZXJzaW9uX3VybH0gLi4uIgogICAgICAgIHRhcmdldF92ZXJzaW9uPSQoY3VybCAtZnNTTCAiJHJlbW90ZV92ZXJzaW9uX3VybCIgMj4vZGV2L251bGwgfCB0ciAtZCAnWzpzcGFjZTpdJykgfHwgdHJ1ZQogICAgICAgIGlmIFsgLXogIiR0YXJnZXRfdmVyc2lvbiIgXTsgdGhlbgogICAgICAgICAgICBlY2hvICJXYXJuaW5nOiBjb3VsZCBub3QgZmV0Y2ggcmVtb3RlIHZlcnNpb24sIGZhbGxpbmcgYmFjayB0byBjdXJyZW50IGltYWdlIgogICAgICAgICAgICB0YXJnZXRfdmVyc2lvbj0ibGF0ZXN0IgogICAgICAgIGVsc2UKICAgICAgICAgICAgZWNobyAiTGF0ZXN0IHZlcnNpb246ICR7dGFyZ2V0X3ZlcnNpb259IgogICAgICAgIGZpCiAgICBmaQoKICAgIGxvY2FsIHB1bGxfaW1hZ2U9IiR7SU1BR0VfUkVQT306JHt0YXJnZXRfdmVyc2lvbn0iCgogICAgIyBQdWxsIGltYWdlCiAgICBlY2hvICJQdWxsaW5nICRwdWxsX2ltYWdlIC4uLiIKICAgIGRlYnVnX2NtZCBkb2NrZXIgcHVsbCAtLXBsYXRmb3JtICIkUExBVEZPUk0iICIkcHVsbF9pbWFnZSIKICAgIGRvY2tlciBwdWxsIC0tcGxhdGZvcm0gIiRQTEFURk9STSIgIiRwdWxsX2ltYWdlIgoKICAgICMgU2VsZi11cGRhdGUgb2MgQ0xJIHZpYSBpbnN0YWxsLnNoCiAgICBsb2NhbCBpbnN0YWxsX3VybD0iaHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3lpeWFuLXlpeGluZy9vbmVjb2RlL21haW4vYWdlbnQtcnVudGltZS9iaW4vaW5zdGFsbC5zaCIKICAgIGVjaG8gIlVwZGF0aW5nIG9jIENMSSBmcm9tICR7aW5zdGFsbF91cmx9IC4uLiIKICAgIGxvY2FsIGluc3RhbGxfc2NyaXB0CiAgICBpbnN0YWxsX3NjcmlwdD0kKGN1cmwgLWZzU0wgIiRpbnN0YWxsX3VybCIgMj4vZGV2L251bGwpIHx8IHRydWUKICAgIGlmIFsgLW4gIiRpbnN0YWxsX3NjcmlwdCIgXTsgdGhlbgogICAgICAgICMgVmVyaWZ5IHNjcmlwdCBpbnRlZ3JpdHkgd2l0aCBTSEEyNTYgaWYgY2hlY2tzdW0gZmlsZSBpcyBhdmFpbGFibGUKICAgICAgICBsb2NhbCBjaGVja3N1bV91cmw9Imh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS95aXlhbi15aXhpbmcvb25lY29kZS9tYWluL2FnZW50LXJ1bnRpbWUvYmluL2luc3RhbGwuc2guc2hhMjU2IgogICAgICAgIGxvY2FsIGNoZWNrc3VtCiAgICAgICAgY2hlY2tzdW09JChjdXJsIC1mc1NMICIkY2hlY2tzdW1fdXJsIiAyPi9kZXYvbnVsbCB8fCB0cnVlKQogICAgICAgIGlmIFsgLW4gIiRjaGVja3N1bSIgXTsgdGhlbgogICAgICAgICAgICBsb2NhbCBhY3R1YWwKICAgICAgICAgICAgYWN0dWFsPSQoZWNobyAiJGluc3RhbGxfc2NyaXB0IiB8IHNoYTI1NnN1bSB8IGF3ayAne3ByaW50ICQxfScpCiAgICAgICAgICAgIGlmIFsgIiRhY3R1YWwiICE9ICIkY2hlY2tzdW0iIF07IHRoZW4KICAgICAgICAgICAgICAgIGVjaG8gIkVycm9yOiBjaGVja3N1bSBtaXNtYXRjaCBmb3IgaW5zdGFsbC5zaCAoZXhwZWN0ZWQgJGNoZWNrc3VtLCBnb3QgJGFjdHVhbCkiID4mMgogICAgICAgICAgICAgICAgZWNobyAiQ0xJIG5vdCB1cGRhdGVkIGZvciBzYWZldHkuIiA+JjIKICAgICAgICAgICAgZWxzZQogICAgICAgICAgICAgICAgZWNobyAiJGluc3RhbGxfc2NyaXB0IiB8IGJhc2ggLXMgLS0gLS1za2lwLWRvY2tlciAtLXRhZyAiJHRhcmdldF92ZXJzaW9uIgogICAgICAgICAgICBmaQogICAgICAgIGVsc2UKICAgICAgICAgICAgIyBObyBjaGVja3N1bSBhdmFpbGFibGUg4oCUIEhUVFBTLW9ubHkgcHJvdmlkZXMgdHJhbnNwb3J0IHNlY3VyaXR5CiAgICAgICAgICAgIGVjaG8gIiRpbnN0YWxsX3NjcmlwdCIgfCBiYXNoIC1zIC0tIC0tc2tpcC1kb2NrZXIgLS10YWcgIiR0YXJnZXRfdmVyc2lvbiIKICAgICAgICBmaQogICAgZWxzZQogICAgICAgIGVjaG8gIldhcm5pbmc6IGNvdWxkIG5vdCBmZXRjaCBpbnN0YWxsLnNoLCBDTEkgbm90IHVwZGF0ZWQiCiAgICBmaQoKICAgICMgU2hvdyB3aGF0IGNoYW5nZWQKICAgIGVjaG8gIiIKICAgIGVjaG8gIkltYWdlIHVwZGF0ZWQgdG8gJHtwdWxsX2ltYWdlfS4iCgogICAgIyBGaW5kIHJ1bm5pbmcgb2MgY29udGFpbmVycwogICAgbG9jYWwgY29udGFpbmVycwogICAgY29udGFpbmVycz0kKGRvY2tlciBwcyAtLWZpbHRlciAiYW5jZXN0b3I9JElNQUdFIiAtLWZvcm1hdCAie3suSUR9fVx0e3suTmFtZXN9fVx0e3suU3RhdHVzfX0iIDI+L2Rldi9udWxsIHx8IHRydWUpCgogICAgaWYgWyAteiAiJGNvbnRhaW5lcnMiIF07IHRoZW4KICAgICAgICBlY2hvICJObyBydW5uaW5nIGNvbnRhaW5lcnMgdG8gcmVzdGFydC4iCiAgICAgICAgcmV0dXJuIDAKICAgIGZpCgogICAgZWNobyAiIgogICAgZWNobyAiUnVubmluZyBjb250YWluZXJzIHVzaW5nIHRoaXMgaW1hZ2U6IgogICAgZWNobyAiJGNvbnRhaW5lcnMiIHwgY29sdW1uIC10IC1zICQnXHQnIDI+L2Rldi9udWxsCiAgICBlY2hvICIiCgogICAgaWYgWyAiJGRvX3Jlc3RhcnQiID0gZmFsc2UgXTsgdGhlbgogICAgICAgIGVjaG8gIlJ1biAnb2MgdXBkYXRlIC0tcmVzdGFydCcgdG8gcmVzdGFydCB0aGVtIHdpdGggdGhlIG5ldyBpbWFnZS4iCiAgICAgICAgcmV0dXJuIDAKICAgIGZpCgogICAgIyBDb25maXJtIHJlc3RhcnQKICAgIGlmIFsgIiRhdXRvX3llcyIgPSBmYWxzZSBdOyB0aGVuCiAgICAgICAgcmVhZCAtcnAgIlJlc3RhcnQgdGhlc2UgY29udGFpbmVycyB3aXRoIHRoZSBuZXcgaW1hZ2U/IFt5L05dICIgYW5zd2VyCiAgICAgICAgY2FzZSAiJGFuc3dlciIgaW4KICAgICAgICAgICAgeXxZKSA7OwogICAgICAgICAgICAqKSAgIGVjaG8gIkFib3J0ZWQuIjsgcmV0dXJuIDAgOzsKICAgICAgICBlc2FjCiAgICBmaQoKICAgICMgUmVzdGFydCBlYWNoIGNvbnRhaW5lciwgcHJlc2VydmluZyBpdHMgY29uZmlnCiAgICB3aGlsZSBJRlM9JCdcdCcgcmVhZCAtciBpZCBuYW1lIHN0YXR1czsgZG8KICAgICAgICBlY2hvICJSZXN0YXJ0aW5nICRuYW1lIC4uLiIKCiAgICAgICAgIyBDYXB0dXJlIG9yaWdpbmFsIHJ1biBjb25maWcgQkVGT1JFIHN0b3BwaW5nL3JlbW92aW5nCiAgICAgICAgbG9jYWwgaW1hZ2UgYmluZHMgZW52X3JhdyBwb3J0cyByZXN0YXJ0X3BvbGljeSB3b3JrZGlyIHR0eV9zZXR0aW5nIGVudHJ5cG9pbnQgY21kX2FyZ3MKICAgICAgICBpbWFnZT0kKGRvY2tlciBpbnNwZWN0ICIkaWQiIC0tZm9ybWF0ICd7ey5Db25maWcuSW1hZ2V9fScgMj4vZGV2L251bGwpCiAgICAgICAgYmluZHM9JChkb2NrZXIgaW5zcGVjdCAiJGlkIiAtLWZvcm1hdCAne3tyYW5nZSAuSG9zdENvbmZpZy5CaW5kc319e3sufX17eyJcbiJ9fXt7ZW5kfX0nIDI+L2Rldi9udWxsKQogICAgICAgICMgQ2FwdHVyZSByYXcgZW52IChvbmUgcGVyIGxpbmUpIHRvIHByZXNlcnZlIHZhbHVlcyB3aXRoIHNwYWNlcwogICAgICAgIGVudl9yYXc9JChkb2NrZXIgaW5zcGVjdCAiJGlkIiAtLWZvcm1hdCAne3tyYW5nZSAuQ29uZmlnLkVudn19e3sufX17eyJcbiJ9fXt7ZW5kfX0nIDI+L2Rldi9udWxsKQogICAgICAgIHBvcnRzPSQoZG9ja2VyIGluc3BlY3QgIiRpZCIgLS1mb3JtYXQgJ3t7cmFuZ2UgJHAsICRjb25mIDo9IC5Ib3N0Q29uZmlnLlBvcnRCaW5kaW5nc319LXAge3soaW5kZXggJGNvbmYgMCkuSG9zdFBvcnR9fTp7eyRwfX17eyJcbiJ9fXt7ZW5kfX0nIDI+L2Rldi9udWxsKQogICAgICAgIHJlc3RhcnRfcG9saWN5PSQoZG9ja2VyIGluc3BlY3QgIiRpZCIgLS1mb3JtYXQgJ3t7Lkhvc3RDb25maWcuUmVzdGFydFBvbGljeS5OYW1lfX0nIDI+L2Rldi9udWxsKQogICAgICAgIHdvcmtkaXI9JChkb2NrZXIgaW5zcGVjdCAiJGlkIiAtLWZvcm1hdCAne3suQ29uZmlnLldvcmtpbmdEaXJ9fScgMj4vZGV2L251bGwpCiAgICAgICAgdHR5X3NldHRpbmc9JChkb2NrZXIgaW5zcGVjdCAiJGlkIiAtLWZvcm1hdCAne3suQ29uZmlnLlR0eX19JyAyPi9kZXYvbnVsbCB8fCBlY2hvICJmYWxzZSIpCiAgICAgICAgIyBDYXB0dXJlIG9yaWdpbmFsIENNRCBhbmQgRW50cnlwb2ludCB0byBwcmVzZXJ2ZSBydW4gbW9kZSAoZS5nLiAicmVtb3RlIikKICAgICAgICBjbWRfYXJncz0kKGRvY2tlciBpbnNwZWN0ICIkaWQiIC0tZm9ybWF0ICd7e3JhbmdlIC5Db25maWcuQ21kfX17ey59fXt7IlxuIn19e3tlbmR9fScgMj4vZGV2L251bGwpCiAgICAgICAgZW50cnlwb2ludD0kKGRvY2tlciBpbnNwZWN0ICIkaWQiIC0tZm9ybWF0ICd7e3JhbmdlIC5Db25maWcuRW50cnlwb2ludH19e3sufX17eyJcbiJ9fXt7ZW5kfX0nIDI+L2Rldi9udWxsKQoKICAgICAgICAjIFN0b3AgYW5kIHJlbW92ZSBvbGQgY29udGFpbmVyCiAgICAgICAgZG9ja2VyIHN0b3AgIiRpZCIgPi9kZXYvbnVsbCAyPiYxCiAgICAgICAgZG9ja2VyIHJtICIkaWQiID4vZGV2L251bGwgMj4mMQoKICAgICAgICAjIFJlLXJ1biB3aXRoIHNhbWUgY29uZmlnIGJ1dCBuZXcgaW1hZ2UKICAgICAgICBsb2NhbCBydW5fYXJncz0oLS1uYW1lICIkbmFtZSIgLS1wbGF0Zm9ybSAiJFBMQVRGT1JNIikKICAgICAgICBbIC1uICIkYmluZHMiIF0gJiYgd2hpbGUgSUZTPSByZWFkIC1yIGI7IGRvIFsgLW4gIiRiIiBdICYmIHJ1bl9hcmdzKz0oLXYgIiRiIik7IGRvbmUgPDw8ICIkYmluZHMiCiAgICAgICAgIyBQYXNzIGVudiB2YXJzIGxpbmUtYnktbGluZSB0byBhdm9pZCB3b3JkLXNwbGl0dGluZyBvbiB2YWx1ZXMgd2l0aCBzcGFjZXMKICAgICAgICBpZiBbIC1uICIkZW52X3JhdyIgXTsgdGhlbgogICAgICAgICAgICB3aGlsZSBJRlM9IHJlYWQgLXIgZXY7IGRvCiAgICAgICAgICAgICAgICBbIC1uICIkZXYiIF0gJiYgcnVuX2FyZ3MrPSgiLS1lbnYiICIkZXYiKQogICAgICAgICAgICBkb25lIDw8PCAiJGVudl9yYXciCiAgICAgICAgZmkKICAgICAgICBpZiBbIC1uICIkcG9ydHMiIF07IHRoZW4KICAgICAgICAgICAgd2hpbGUgSUZTPSByZWFkIC1yIHA7IGRvIFsgLW4gIiRwIiBdICYmIHJ1bl9hcmdzKz0oJHApOyBkb25lIDw8PCAiJHBvcnRzIgogICAgICAgIGZpCiAgICAgICAgWyAiJHJlc3RhcnRfcG9saWN5IiAhPSAiIiBdICYmIFsgIiRyZXN0YXJ0X3BvbGljeSIgIT0gIm5vIiBdICYmIHJ1bl9hcmdzKz0oLS1yZXN0YXJ0ICIkcmVzdGFydF9wb2xpY3kiKQogICAgICAgIFsgLW4gIiR3b3JrZGlyIiBdICYmIHJ1bl9hcmdzKz0oLXcgIiR3b3JrZGlyIikKCiAgICAgICAgIyBEZXRlcm1pbmUgZGV0YWNoZWQgdnMgaW50ZXJhY3RpdmUgYmFzZWQgb24gb3JpZ2luYWwgY29udGFpbmVyJ3MgVFRZIHNldHRpbmcKICAgICAgICBpZiBbICIkdHR5X3NldHRpbmciID0gInRydWUiIF07IHRoZW4KICAgICAgICAgICAgcnVuX2FyZ3MrPSgtaXQpCiAgICAgICAgZWxzZQogICAgICAgICAgICBydW5fYXJncys9KC1kKQogICAgICAgIGZpCgogICAgICAgICMgUHJlc2VydmUgb3JpZ2luYWwgZW50cnlwb2ludCBpZiBpdCB3YXMgb3ZlcnJpZGRlbgogICAgICAgICMgRG9ja2VyIC0tZW50cnlwb2ludCBvbmx5IGFjY2VwdHMgYSBzaW5nbGUgZXhlY3V0YWJsZSwgbm90IGFyZ3MuCiAgICAgICAgIyBTcGxpdDogZmlyc3QgZWxlbWVudCA9IGVudHJ5cG9pbnQsIHJlc3QgPSBwcmVwZW5kIHRvIENNRC4KICAgICAgICBsb2NhbCBzaGlmdF9lcF9hcmdzPSgpCiAgICAgICAgaWYgWyAtbiAiJGVudHJ5cG9pbnQiIF07IHRoZW4KICAgICAgICAgICAgbG9jYWwgZXBfcGFydHM9KCkKICAgICAgICAgICAgd2hpbGUgSUZTPSByZWFkIC1yIGVwOyBkbyBbIC1uICIkZXAiIF0gJiYgZXBfcGFydHMrPSgiJGVwIik7IGRvbmUgPDw8ICIkZW50cnlwb2ludCIKICAgICAgICAgICAgaWYgWyAkeyNlcF9wYXJ0c1tAXX0gLWd0IDAgXTsgdGhlbgogICAgICAgICAgICAgICAgcnVuX2FyZ3MrPSgtLWVudHJ5cG9pbnQgIiR7ZXBfcGFydHNbMF19IikKICAgICAgICAgICAgICAgIGlmIFsgJHsjZXBfcGFydHNbQF19IC1ndCAxIF07IHRoZW4KICAgICAgICAgICAgICAgICAgICBzaGlmdF9lcF9hcmdzPSgiJHtlcF9wYXJ0c1tAXToxfSIpCiAgICAgICAgICAgICAgICBmaQogICAgICAgICAgICBmaQogICAgICAgIGZpCgogICAgICAgIHJ1bl9hcmdzKz0oIiRwdWxsX2ltYWdlIikKCiAgICAgICAgIyBQcmVwZW5kIGFueSBleHRyYSBlbnRyeXBvaW50IGFyZ3MgKGUuZy4gIi0tIiBmcm9tICJ0aW5pIC0tIGVudHJ5cG9pbnQuc2giKSwKICAgICAgICAjIHRoZW4gYXBwZW5kIG9yaWdpbmFsIENNRCBhcmdzIChlLmcuICJyZW1vdGUiKSB0byBwcmVzZXJ2ZSBydW4gbW9kZQogICAgICAgIGlmIFsgJHsjc2hpZnRfZXBfYXJnc1tAXX0gLWd0IDAgXTsgdGhlbgogICAgICAgICAgICBydW5fYXJncys9KCIke3NoaWZ0X2VwX2FyZ3NbQF19IikKICAgICAgICBmaQogICAgICAgIGlmIFsgLW4gIiRjbWRfYXJncyIgXTsgdGhlbgogICAgICAgICAgICB3aGlsZSBJRlM9IHJlYWQgLXIgY2E7IGRvIFsgLW4gIiRjYSIgXSAmJiBydW5fYXJncys9KCIkY2EiKTsgZG9uZSA8PDwgIiRjbWRfYXJncyIKICAgICAgICBmaQogICAgICAgIGxvY2FsIHJlc3RhcnRfb3V0cHV0CiAgICAgICAgZGVidWdfY21kIGRvY2tlciBydW4gIiR7cnVuX2FyZ3NbQF19IgogICAgICAgIHJlc3RhcnRfb3V0cHV0PSQoZG9ja2VyIHJ1biAiJHtydW5fYXJnc1tAXX0iIDI+JjEpIHx8IHsgZWNobyAiV2FybmluZzogZmFpbGVkIHRvIHJlc3RhcnQgJG5hbWUiID4mMjsgZWNobyAiJHJlc3RhcnRfb3V0cHV0IiA+JjI7IH0KICAgICAgICBlY2hvICIgICRuYW1lIHJlc3RhcnRlZCB3aXRoIG5ldyBpbWFnZSIKICAgIGRvbmUgPDw8ICIkY29udGFpbmVycyIKCiAgICBlY2hvICIiCiAgICBlY2hvICJBbGwgY29udGFpbmVycyByZXN0YXJ0ZWQgd2l0aCAkcHVsbF9pbWFnZSIKfQoKIyDilIDilIAgRGlzcGF0Y2gg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACmNhc2UgIiRDT01NQU5EIiBpbgogICAgcnVuKSAgICBjbWRfcnVuICIkQCIgOzsKICAgIHJlbW90ZSkgY21kX3JlbW90ZSAiJEAiIDs7CiAgICBzc2gpICAgIGNtZF9zc2ggIiRAIiA7OwogICAgc2hlbGwpICBjbWRfc2hlbGwgIiRAIiA7OwogICAgc3RvcCkgICBjbWRfc3RvcCAiJEAiIDs7CiAgICB1cGRhdGUpIGNtZF91cGRhdGUgIiRAIiA7OwogICAgbHMpICAgICBjbWRfbHMgOzsKICAgIGNvbmZpZykgY21kX2NvbmZpZyA7OwogICAgaGVscCkgICBzaG93X2hlbHAgIiRAIiA7OwogICAgKikgICAgICBlY2hvICJVbmtub3duIGNvbW1hbmQ6ICRDT01NQU5EIiA+JjI7IHNob3dfaGVscCA7Owplc2FjCg==
B64

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

# ── Step 6: Configure ──────────────────────────────────────────────
configure() {
    mkdir -p "$OC_HOME"

    # API_KEY
    if [ -z "$API_KEY" ]; then
        if [ -f "$OC_HOME/settings.json" ]; then
            info "Existing config found at ${OC_HOME}/settings.json"
            API_KEY=$(grep '"API_KEY"' "$OC_HOME/settings.json" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/' || true)
            if [ -n "$API_KEY" ]; then
                ok "API_KEY loaded from existing config"
            fi
        fi
        if [ -z "$API_KEY" ]; then
            echo ""
            read -rsp "Enter API_KEY (press Enter to skip, configure later with 'oc'): " API_KEY
            echo
        fi
    fi

    # Write config
    cat > "$OC_HOME/settings.json" <<EOF
{
  "API_KEY": "${API_KEY}",
  "API_BASE_URL": "${API_BASE_URL}",
  "MODEL": "${MODEL}"
}
EOF
    chmod 600 "$OC_HOME/settings.json"
    ok "Config saved to ${OC_HOME}/settings.json"
}

# ── Step 7: Verify ─────────────────────────────────────────────────
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
    echo "  Step 1/7: Detect environment"
    echo "========================================="
    detect_env

    echo ""
    echo "========================================="
    echo "  Step 2/7: Install Docker"
    echo "========================================="
    install_docker

    echo ""
    echo "========================================="
    echo "  Step 3/7: Start Docker service"
    echo "========================================="
    start_docker

    echo ""
    echo "========================================="
    echo "  Step 4/7: Login registry"
    echo "========================================="
    registry_login

    echo ""
    echo "========================================="
    echo "  Step 5/7: Pull image"
    echo "========================================="
    pull_image

    echo ""
    echo "========================================="
    echo "  Step 6/7: Install oc CLI"
    echo "========================================="
    install_oc

    echo ""
    echo "========================================="
    echo "  Step 7/7: Configure"
    echo "========================================="
    configure

    echo ""
    echo "========================================="
    verify

    echo ""
    echo -e "${GREEN}  Installation complete!${NC}"
    echo ""
    if [ "$OS_ID" = "darwin" ]; then
        echo -e "  ${YELLOW}Run this first to load PATH & Docker settings:${NC}"
        echo "    source ~/.zshrc"
    else
        echo -e "  ${YELLOW}Run this first to load PATH:${NC}"
        echo "    source ~/.bashrc"
    fi
    echo ""
    echo -e "${CYAN}  Common commands:${NC}"
    echo "    oc                              # start interactive Claude CLI"
    echo "    oc -d /path/to/project          # mount a specific project"
    echo "    oc remote                       # web terminal (http://localhost:7681)"
    echo "    oc remote -p 8080               # web terminal on custom port"
    echo "    oc flow \"Add login page\"        # autonomous dev: clone -> code -> test -> submit"
    echo "    oc flow --repo <git-url> \"Fix\"  # autonomous dev with git clone"
    echo "    oc ssh <name>                   # enable SSH access to a running container"
    echo "    oc shell <name>                 # enter a running container"
    echo "    oc stop <name>                  # stop and remove a container"
    echo "    oc ls                           # list containers and image"
    echo "    oc config                       # show current config (API_KEY etc.)"
    echo ""
    if [ "$OS_ID" = "darwin" ] && [ "${ARCH_ALIAS:-}" = "arm64" ]; then
        echo -e "${YELLOW}  Note: Running linux/amd64 image via Rosetta emulation.${NC}"
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
