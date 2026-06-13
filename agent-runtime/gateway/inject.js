'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const SCRIPTS_DIR = path.join(__dirname, 'scripts');

// Preload inject scripts at startup
const SE_POLYFILL = fs.readFileSync(path.join(SCRIPTS_DIR, 'se-polyfill.js'), 'utf8');
const SW_PATCH = fs.readFileSync(path.join(SCRIPTS_DIR, 'sw-patch.js'), 'utf8');

function injectVscodeHtml(body, isVscodeWorkbench, isHttps) {
  const injectScripts = [];

  // SecurityError polyfill for VS Code webviews
  injectScripts.push(SE_POLYFILL);

  // Override navigator.serviceWorker to catch ANY registration failure
  injectScripts.push(SW_PATCH);

  // When serving self-signed HTTPS, also remove workbench SW config
  if (isHttps && isVscodeWorkbench) {
    body = body.replace(
      /&quot;serviceWorker&quot;\s*:\s*\{&quot;[^}]*\}/g,
      '&quot;serviceWorker&quot;:null',
    );
  }

  if (injectScripts.length > 0) {
    let nonceAttr = '';
    const metaNonceMatch = body.match(/nonce-([A-Za-z0-9+/=]+)/);
    const scriptNonceMatch = body.match(/<script[^>]+nonce=["']([A-Za-z0-9+/=]+)["']/i);
    const nonceValue = (scriptNonceMatch || metaNonceMatch)?.[1];
    if (nonceValue) {
      nonceAttr = ' nonce="' + nonceValue + '"';
    }
    const cspHashes = [];
    let injectTags = '';
    for (const script of injectScripts) {
      const hash = crypto.createHash('sha256').update(script).digest('base64');
      cspHashes.push("'sha256-" + hash + "'");
      injectTags += '<script' + nonceAttr + '>' + script + '</script>';
    }
    if (body.match(/<\/head>/i)) {
      body = body.replace(/<\/head>/i, injectTags + '</head>');
    } else if (body.match(/<body[^>]*>/i)) {
      body = body.replace(/<body[^>]*>/i, '$&' + injectTags);
    } else {
      body = injectTags + body;
    }
    const hashesStr = cspHashes.join(' ');
    body = body.replace(
      /(script-src\s+)([^;]+)/gi,
      '$1$2 ' + hashesStr,
    );
    return { body, cspHashesStr: hashesStr };
  }
  return { body, cspHashesStr: '' };
}

module.exports = { injectVscodeHtml };
