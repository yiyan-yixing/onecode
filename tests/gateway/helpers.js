'use strict';

/**
 * Shared test helper: runs a Node.js script in a child process
 * using a temp file (avoids node -e escape issues with multiline code).
 */

const { execSync } = require('child_process');
const fs = require('fs');
let _counter = 0;

function runInChild(code, envOverrides) {
  const tmpFile = `/tmp/onecode-test-${process.pid}-${++_counter}.js`;
  fs.writeFileSync(tmpFile, `'use strict';\n${code}`);
  const env = { ...process.env, ...envOverrides };
  try {
    const out = execSync(`node "${tmpFile}"`, { encoding: 'utf8', env, timeout: 10000 });
    fs.unlinkSync(tmpFile);
    return { ok: true, output: out.trim() };
  } catch (e) {
    try { fs.unlinkSync(tmpFile); } catch (_) {}
    return { ok: false, error: e.message, stderr: e.stderr || '' };
  }
}

function runAndParse(code, envOverrides) {
  const result = runInChild(code, envOverrides);
  if (!result.ok) return null;
  try {
    return JSON.parse(result.output);
  } catch (_) {
    return result.output;
  }
}

module.exports = { runInChild, runAndParse };
