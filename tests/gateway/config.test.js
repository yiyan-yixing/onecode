'use strict';

/**
 * Tests for gateway/config.js
 */
module.exports = function (t) {
  const path = require('path');
  const { runAndParse } = require('./helpers');

  const configPath = path.resolve(__dirname, '..', '..', 'agent-runtime', 'gateway', 'config.js');

  function getConfig(envOverrides) {
    return runAndParse(
      `const c = require(${JSON.stringify(configPath)}); console.log(JSON.stringify(c));`,
      envOverrides,
    );
  }

  t.section('Default values');

  const defaults = getConfig({});
  t.ok(defaults, 'config loads without error');
  if (!defaults) return;

  t.equal(defaults.PORT, 7681, 'PORT defaults to 7681');
  t.equal(defaults.FB_PORT, 8081, 'FB_PORT defaults to 8081');
  t.equal(defaults.VSCODE_PORT, 8082, 'VSCODE_PORT defaults to 8082');
  t.equal(defaults.TERM_TOKEN, '', 'TERM_TOKEN defaults to empty');
  t.equal(defaults.TERM_COLS, 200, 'TERM_COLS defaults to 200');
  t.equal(defaults.TERM_ROWS, 50, 'TERM_ROWS defaults to 50');
  t.equal(defaults.BACKEND, 'claude-code', 'BACKEND defaults to claude-code');
  t.equal(defaults.BRAND_NAME, 'OneCode', 'BRAND_NAME is OneCode');

  t.section('Environment variable overrides');

  const overridden = getConfig({
    GATEWAY_PORT: '9999',
    FB_PORT: '8888',
    VSCODE_INTERNAL_PORT: '7777',
    TTYD_TOKEN: 'my-secret-token',
    TERM_COLS: '120',
    TERM_ROWS: '40',
    BACKEND: 'opencode',
  });
  t.ok(overridden, 'config loads with env overrides');
  if (!overridden) return;

  t.equal(overridden.PORT, 9999, 'PORT overridden by GATEWAY_PORT');
  t.equal(overridden.FB_PORT, 8888, 'FB_PORT overridden');
  t.equal(overridden.VSCODE_PORT, 7777, 'VSCODE_PORT overridden');
  t.equal(overridden.TERM_TOKEN, 'my-secret-token', 'TERM_TOKEN overridden by TTYD_TOKEN');
  t.equal(overridden.TERM_COLS, 120, 'TERM_COLS overridden');
  t.equal(overridden.TERM_ROWS, 40, 'TERM_ROWS overridden');
  t.equal(overridden.BACKEND, 'opencode', 'BACKEND overridden to opencode');

  t.section('TERM_TOKEN priority');

  const termTokenOnly = getConfig({ GATEWAY_PORT: '7681', TERM_TOKEN: 'from-term-token' });
  t.ok(termTokenOnly, 'config loads with TERM_TOKEN');
  if (termTokenOnly) {
    t.equal(termTokenOnly.TERM_TOKEN, 'from-term-token', 'TERM_TOKEN used when TTYD_TOKEN not set');
  }

  const bothTokens = getConfig({ TTYD_TOKEN: 'from-ttyd', TERM_TOKEN: 'from-term' });
  t.ok(bothTokens, 'config loads with both tokens');
  if (bothTokens) {
    t.equal(bothTokens.TERM_TOKEN, 'from-term', 'TERM_TOKEN takes priority over TTYD_TOKEN');
  }

  const ttydOnly = getConfig({ TTYD_TOKEN: 'from-ttyd-only' });
  t.ok(ttydOnly, 'config loads with only TTYD_TOKEN');
  if (ttydOnly) {
    t.equal(ttydOnly.TERM_TOKEN, 'from-ttyd-only', 'TTYD_TOKEN used as fallback when TERM_TOKEN not set');
  }

  t.section('Exported keys');

  const expectedKeys = [
    'PORT', 'FB_PORT', 'VSCODE_PORT', 'TERM_TOKEN',
    'TERM_COLS', 'TERM_ROWS', 'BACKEND', 'STATIC_DIR',
    'VERSION', 'BRAND_NAME', 'SVC_REGISTRY', 'GLOBAL_DIR', 'PROJECT_DIR',
  ];
  for (const key of expectedKeys) {
    t.ok(key in defaults, `exports ${key}`);
  }

  t.section('Port type coercion');

  const stringPort = getConfig({ GATEWAY_PORT: '12345' });
  t.ok(stringPort, 'config loads with string port');
  if (stringPort) {
    t.equal(typeof stringPort.PORT, 'number', 'PORT is coerced to number');
    t.equal(stringPort.PORT, 12345, 'PORT coerced correctly');
  }
};
