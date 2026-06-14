#!/bin/bash
# Configure code-server: navigator polyfill, product.json, API credentials
set -e

VSCODE_INTERNAL_PORT="${1:-8082}"

# Inject API credentials into code-server settings so Claude Code extension uses them
CS_SETTINGS="/home/work/.local/share/code-server/User/settings.json"
if [ -f "$CS_SETTINGS" ]; then
    python3 -c "
import json, os
with open('$CS_SETTINGS') as f:
    s = json.load(f)
env = s.setdefault('claudeCode.environmentVariables', {})
for key in ['ANTHROPIC_API_KEY', 'ANTHROPIC_BASE_URL', 'ANTHROPIC_MODEL']:
    val = os.environ.get(key, '')
    if val:
        env[key] = val
with open('$CS_SETTINGS', 'w') as f:
    json.dump(s, f, indent=2)
"
fi

# Create navigator polyfill to fix PendingMigrationError in code-server's
# extension host (Node.js 20 doesn't provide navigator as a global)
NAV_POLYFILL="/usr/local/share/onecode/navigator-polyfill.js"
mkdir -p /usr/local/share/onecode
cat > "$NAV_POLYFILL" <<'NAVPOLY'
// Polyfill navigator for code-server extension host on Node.js 20
// Node.js 20 defines navigator as a getter that throws PendingMigrationError on access,
// so we must use try/catch instead of typeof/instanceof checks.
(function() {
  try {
    var n = globalThis.navigator;
    if (n && typeof n === 'object') { return; }
  } catch (_) {}
  try {
    var os = require('os');
    Object.defineProperty(globalThis, 'navigator', {
      value: {
        userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36',
        platform: 'linux',
        language: 'en-US',
        languages: ['en-US'],
        hardwareConcurrency: os.cpus().length,
      },
      writable: true,
      configurable: true,
      enumerable: true,
    });
  } catch (_) {}
})();
NAVPOLY

# Also inject the polyfill directly into the extension host process file,
# because code-server's fork() uses custom execArgv that strips NODE_OPTIONS.
EHP="/usr/lib/code-server/lib/vscode/out/vs/workbench/api/node/extensionHostProcess.js"
if [ -f "$EHP" ] && ! grep -q 'navigator-polyfill-injected' "$EHP" 2>/dev/null; then
    cat >> "$EHP" <<'NAVAPPEND'
// navigator-polyfill-injected
(function(){try{delete globalThis.navigator}catch(_){}try{Object.defineProperty(globalThis,"navigator",{value:{userAgent:"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",platform:"linux",language:"en-US",languages:["en-US"],hardwareConcurrency:require("os").cpus().length},writable:true,configurable:false,enumerable:true})}catch(_){}})();
NAVAPPEND
fi

# Remove copilot-chat from auto-update list to prevent 404 errors from open-vsx.org
PRODUCT_JSON="/usr/lib/code-server/lib/vscode/product.json"
if [ -f "$PRODUCT_JSON" ]; then
    python3 -c "
import json
with open('$PRODUCT_JSON') as f:
    p = json.load(f)
if 'builtInExtensionsEnabledWithAutoUpdates' in p:
    p['builtInExtensionsEnabledWithAutoUpdates'] = [e for e in p['builtInExtensionsEnabledWithAutoUpdates'] if 'copilot' not in e.lower()]
with open('$PRODUCT_JSON', 'w') as f:
    json.dump(p, f, indent=2)
"
fi
