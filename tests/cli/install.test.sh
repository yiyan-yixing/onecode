#!/usr/bin/env bash
# Tests for install.sh — one-click install script
# Output format: PASS <label> or FAIL <label>
set -euo pipefail

INSTALL_SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/agent-runtime/bin/install.sh"

# ── Test: script syntax check ────────────────────────────────────────
if bash -n "$INSTALL_SCRIPT" 2>/dev/null; then
    echo "PASS install.sh: syntax check passes"
else
    echo "FAIL install.sh: syntax check failed"
fi

# ── Test: script is executable ───────────────────────────────────────
if [ -x "$INSTALL_SCRIPT" ]; then
    echo "PASS install.sh: is executable"
else
    echo "FAIL install.sh: is not executable"
fi

# ── Test: --help flag ───────────────────────────────────────────────
OUTPUT=$(bash "$INSTALL_SCRIPT" --help 2>&1 || true)
if echo "$OUTPUT" | grep -q "Usage:"; then
    echo "PASS install.sh: --help shows usage"
else
    echo "FAIL install.sh: --help does not show usage"
fi

if echo "$OUTPUT" | grep -q "\-\-api-key"; then
    echo "PASS install.sh: --help shows --api-key option"
else
    echo "FAIL install.sh: --help missing --api-key option"
fi

if echo "$OUTPUT" | grep -q "\-\-provider"; then
    echo "PASS install.sh: --help shows --provider option"
else
    echo "FAIL install.sh: --help missing --provider option"
fi

if echo "$OUTPUT" | grep -q "\-\-skip-docker"; then
    echo "PASS install.sh: --help shows --skip-docker option"
else
    echo "FAIL install.sh: --help missing --skip-docker option"
fi

# ── Test: VERSION matches oc CLI ────────────────────────────────────
OC_SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/agent-runtime/bin/oc"
INSTALL_VERSION=$(grep '^VERSION=' "$INSTALL_SCRIPT" | head -1 | sed 's/VERSION="//' | sed 's/"//')
OC_VERSION=$(grep '^OC_VERSION=' "$OC_SCRIPT" | head -1 | sed 's/OC_VERSION="//' | sed 's/"//')
if [ "$INSTALL_VERSION" = "$OC_VERSION" ]; then
    echo "PASS install.sh: VERSION ($INSTALL_VERSION) matches oc CLI ($OC_VERSION)"
else
    echo "FAIL install.sh: VERSION ($INSTALL_VERSION) does not match oc CLI ($OC_VERSION)"
fi

# ── Test: IMAGE_REPO matches oc CLI ─────────────────────────────────
INSTALL_REPO=$(grep '^IMAGE_REPO=' "$INSTALL_SCRIPT" | head -1 | sed 's/IMAGE_REPO="//' | sed 's/"//')
OC_REPO=$(grep '^IMAGE_REPO=' "$OC_SCRIPT" | head -1 | sed 's/IMAGE_REPO="//' | sed 's/"//')
if [ "$INSTALL_REPO" = "$OC_REPO" ]; then
    echo "PASS install.sh: IMAGE_REPO ($INSTALL_REPO) matches oc CLI ($OC_REPO)"
else
    echo "FAIL install.sh: IMAGE_REPO ($INSTALL_REPO) does not match oc CLI ($OC_REPO)"
fi

# ── Test: REPO_OWNER/REPO_NAME consistency ──────────────────────────
INSTALL_OWNER=$(grep '^REPO_OWNER=' "$INSTALL_SCRIPT" | head -1 | sed 's/REPO_OWNER="//' | sed 's/"//')
OC_OWNER=$(grep '^REPO_OWNER=' "$OC_SCRIPT" | head -1 | sed 's/REPO_OWNER="//' | sed 's/"//')
if [ "$INSTALL_OWNER" = "$OC_OWNER" ]; then
    echo "PASS install.sh: REPO_OWNER ($INSTALL_OWNER) matches oc CLI"
else
    echo "FAIL install.sh: REPO_OWNER mismatch: install=$INSTALL_OWNER oc=$OC_OWNER"
fi

INSTALL_NAME=$(grep '^REPO_NAME=' "$INSTALL_SCRIPT" | head -1 | sed 's/REPO_NAME="//' | sed 's/"//')
OC_NAME=$(grep '^REPO_NAME=' "$OC_SCRIPT" | head -1 | sed 's/REPO_NAME="//' | sed 's/"//')
if [ "$INSTALL_NAME" = "$OC_NAME" ]; then
    echo "PASS install.sh: REPO_NAME ($INSTALL_NAME) matches oc CLI"
else
    echo "FAIL install.sh: REPO_NAME mismatch: install=$INSTALL_NAME oc=$OC_NAME"
fi

# ── Test: Provider defaults match oc CLI ────────────────────────────
INSTALL_ANTHROPIC_URL=$(grep 'PROVIDER_DEFAULTS_anthropic_api_base_url=' "$INSTALL_SCRIPT" | head -1 | sed 's/.*="//' | sed 's/"//')
OC_ANTHROPIC_URL=$(grep 'PROVIDER_DEFAULTS_anthropic_api_base_url=' "$OC_SCRIPT" | head -1 | sed 's/.*="//' | sed 's/"//')
if [ "$INSTALL_ANTHROPIC_URL" = "$OC_ANTHROPIC_URL" ]; then
    echo "PASS install.sh: Anthropic default URL matches oc CLI ($INSTALL_ANTHROPIC_URL)"
else
    echo "FAIL install.sh: Anthropic default URL mismatch: install=$INSTALL_ANTHROPIC_URL oc=$OC_ANTHROPIC_URL"
fi

INSTALL_ANTHROPIC_MODEL=$(grep 'PROVIDER_DEFAULTS_anthropic_model=' "$INSTALL_SCRIPT" | head -1 | sed 's/.*="//' | sed 's/"//')
OC_ANTHROPIC_MODEL=$(grep 'PROVIDER_DEFAULTS_anthropic_model=' "$OC_SCRIPT" | head -1 | sed 's/.*="//' | sed 's/"//')
if [ "$INSTALL_ANTHROPIC_MODEL" = "$OC_ANTHROPIC_MODEL" ]; then
    echo "PASS install.sh: Anthropic default model matches oc CLI ($INSTALL_ANTHROPIC_MODEL)"
else
    echo "FAIL install.sh: Anthropic default model mismatch: install=$INSTALL_ANTHROPIC_MODEL oc=$OC_ANTHROPIC_MODEL"
fi

INSTALL_OPENAI_MODEL=$(grep 'PROVIDER_DEFAULTS_openai_compatible_model=' "$INSTALL_SCRIPT" | head -1 | sed 's/.*="//' | sed 's/"//')
OC_OPENAI_MODEL=$(grep 'PROVIDER_DEFAULTS_openai_compatible_model=' "$OC_SCRIPT" | head -1 | sed 's/.*="//' | sed 's/"//')
if [ "$INSTALL_OPENAI_MODEL" = "$OC_OPENAI_MODEL" ]; then
    echo "PASS install.sh: OpenAI Compatible default model matches oc CLI ($INSTALL_OPENAI_MODEL)"
else
    echo "FAIL install.sh: OpenAI Compatible model mismatch: install=$INSTALL_OPENAI_MODEL oc=$OC_OPENAI_MODEL"
fi

# ── Test: install.sh contains all 8 steps ───────────────────────────
for step in "Detect environment" "Install jq" "Install Docker" "Start Docker" "Login registry" "Pull image" "Install oc CLI" "Configure"; do
    if grep -q "$step" "$INSTALL_SCRIPT"; then
        echo "PASS install.sh: step '$step' exists"
    else
        echo "FAIL install.sh: step '$step' missing"
    fi
done

# ── Test: install.sh contains v1→v2 migration ───────────────────────
if grep -q "Migrating config from v1 to v2" "$INSTALL_SCRIPT"; then
    echo "PASS install.sh: v1→v2 migration present"
else
    echo "FAIL install.sh: v1→v2 migration missing"
fi

# ── Test: install.sh writes backend field ────────────────────────────
if grep -q 'backend' "$INSTALL_SCRIPT"; then
    echo "PASS install.sh: backend field included in config"
else
    echo "FAIL install.sh: backend field missing from config"
fi

# ── Test: install.sh has Apple Silicon handling ──────────────────────
if grep -q "DOCKER_DEFAULT_PLATFORM" "$INSTALL_SCRIPT" && grep -q "Rosetta" "$INSTALL_SCRIPT"; then
    echo "PASS install.sh: Apple Silicon (Rosetta) handling present"
else
    echo "FAIL install.sh: Apple Silicon handling missing"
fi

# ── Test: install.sh has interactive wizard ──────────────────────────
if grep -q "Welcome to OneCode" "$INSTALL_SCRIPT"; then
    echo "PASS install.sh: interactive wizard present"
else
    echo "FAIL install.sh: interactive wizard missing"
fi

# ── Test: install.sh has verify step ─────────────────────────────────
if grep -q "Verifying installation" "$INSTALL_SCRIPT"; then
    echo "PASS install.sh: verify step present"
else
    echo "FAIL install.sh: verify step missing"
fi
