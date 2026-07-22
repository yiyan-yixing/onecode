'use strict';

/**
 * Integration tests for gateway/index.js — HTTP server
 * Gracefully handles environments where node-pty is not available.
 */
module.exports = function (t) {
  const { execSync, spawn } = require('child_process');
  const path = require('path');
  const { runAndParse } = require('./helpers');

  const gatewayPath = path.resolve(__dirname, '..', '..', 'agent-runtime', 'gateway', 'index.js');

  // First check if node-pty is available (gateway requires it)
  const ptyCheck = runAndParse(`
    try {
      require('node-pty');
      console.log(JSON.stringify({ available: true }));
    } catch (e) {
      console.log(JSON.stringify({ available: false }));
    }
  `);

  if (!ptyCheck || !ptyCheck.available) {
    t.section('Gateway integration — environment check');
    t.skip('node-pty native module not available — gateway integration tests skipped');
    t.skip('These tests run in the Docker container where node-pty is compiled');

    // Still validate the gateway source code structure
    t.section('Gateway index.js — source validation');
    const fs = require('fs');
    const src = fs.readFileSync(gatewayPath, 'utf8');

    t.ok(src.includes("require('./config')"), 'imports config module');
    t.ok(src.includes("require('./router')"), 'imports router module');
    t.ok(src.includes("require('./proxy')"), 'imports proxy module');
    t.ok(src.includes("require('./term-ws')"), 'imports term-ws module');
    t.ok(src.includes("require('./pty')"), 'imports pty module');
    t.ok(src.includes("require('./cc-status')"), 'imports cc-status module');
    t.ok(src.includes("require('./static')"), 'imports static module');
    // inject.js is used by proxy.js, not index.js directly — verify proxy imports it
    const proxySrc = fs.readFileSync(path.resolve(path.dirname(gatewayPath), 'proxy.js'), 'utf8');
    t.ok(proxySrc.includes("require('./inject')"), 'proxy module imports inject');
    t.ok(src.includes('BACKEND'), 'reads BACKEND env var');
    t.ok(src.includes('opencode'), 'supports opencode backend');
    t.ok(src.includes('claude-code') || src.includes('claude'), 'supports claude-code backend');
    t.ok(src.includes('/api/cc-status'), 'defines /api/cc-status endpoint');
    t.ok(src.includes('/api/restart-terminal'), 'defines /api/restart-terminal endpoint');
    t.ok(src.includes('setupTerminalWebSocket'), 'sets up terminal WebSocket');
    t.ok(src.includes('handleProxy'), 'handles proxy requests');
    t.ok(src.includes('handleWsUpgrade'), 'handles WebSocket upgrades');
    t.ok(src.includes('graceful') || src.includes('SIGTERM') || src.includes('shutdown'), 'has graceful shutdown');
    t.ok(src.includes('pre-compress') || src.includes('gzipSync'), 'pre-compresses index HTML');
    return;
  }

  // Full integration tests when node-pty is available
  const gatewayPort = 18781 + Math.floor(Math.random() * 1000);
  let gatewayProc = null;
  let started = false;

  try {
    gatewayProc = spawn('node', [gatewayPath], {
      env: {
        ...process.env,
        GATEWAY_PORT: String(gatewayPort),
        FB_PORT: '18081',
        VSCODE_INTERNAL_PORT: '18082',
        BACKEND: 'opencode',
        WORKSPACE_DIR: '/tmp',
        TERM_TOKEN: 'test-token-123',
      },
      stdio: ['pipe', 'pipe', 'pipe'],
      detached: false,
    });

    const start = Date.now();
    while (!started && Date.now() - start < 8000) {
      try {
        execSync(`curl -s -o /dev/null -w "%{http_code}" http://localhost:${gatewayPort}/`, { timeout: 1000, stdio: 'pipe' });
        started = true;
      } catch (_) {}
    }

    if (!started) {
      t.assert(false, 'Gateway started within 8 seconds');
      t.skip('Remaining tests require running gateway');
      try { gatewayProc.kill('SIGKILL'); } catch (_) {}
      return;
    }

    t.assert(true, 'Gateway started within 8 seconds');
  } catch (e) {
    t.assert(false, `Gateway startup: ${e.message}`);
    t.skip('Remaining tests require running gateway');
    return;
  }

  function httpGet(urlPath) {
    return runAndParse(`
      const http = require('http');
      http.get('http://localhost:${gatewayPort}${urlPath}', (res) => {
        let body = '';
        res.on('data', (chunk) => body += chunk);
        res.on('end', () => console.log(JSON.stringify({ statusCode: res.statusCode, body })));
      }).on('error', (e) => console.log(JSON.stringify({ error: e.message })));
    `);
  }

  function httpPost(urlPath) {
    return runAndParse(`
      const http = require('http');
      const req = http.request({ hostname: 'localhost', port: ${gatewayPort}, path: ${JSON.stringify(urlPath)}, method: 'POST' }, (res) => {
        let body = '';
        res.on('data', (chunk) => body += chunk);
        res.on('end', () => console.log(JSON.stringify({ statusCode: res.statusCode, body })));
      });
      req.on('error', (e) => console.log(JSON.stringify({ error: e.message })));
      req.end();
    `);
  }

  t.section('Index page');

  const index = httpGet('/');
  t.ok(index && !index.error, 'index page response received');
  if (index && !index.error) {
    t.equal(index.statusCode, 200, 'index page returns 200');
    t.ok(index.body && index.body.includes('OneCode'), 'index page contains OneCode');
    t.ok(index.body && index.body.includes('xterm'), 'index page includes xterm');
  }

  t.section('/api/cc-status');

  const status = httpGet('/api/cc-status');
  t.ok(status && !status.error, 'cc-status response received');
  if (status && !status.error) {
    t.equal(status.statusCode, 200, 'cc-status returns 200');
    let statusObj;
    try { statusObj = JSON.parse(status.body); } catch (_) {}
    t.ok(statusObj, 'cc-status returns valid JSON');
    if (statusObj) {
      t.ok(Array.isArray(statusObj.skills), 'cc-status has skills');
    }
  }

  t.section('/api/restart-terminal');

  const restart = httpPost('/api/restart-terminal');
  t.ok(restart && !restart.error, 'restart-terminal response received');
  if (restart && !restart.error) {
    t.equal(restart.statusCode, 200, 'restart-terminal returns 200');
    let restartObj;
    try { restartObj = JSON.parse(restart.body); } catch (_) {}
    t.ok(restartObj && restartObj.ok === true, 'restart-terminal returns ok:true');
  }

  t.section('404 for unknown routes');

  const notFound = httpGet('/this-does-not-exist');
  t.ok(notFound && !notFound.error, '404 response received');
  if (notFound && !notFound.error) {
    t.equal(notFound.statusCode, 404, 'unknown route returns 404');
  }

  // Clean up
  try { gatewayProc.kill('SIGTERM'); } catch (_) {}
  setTimeout(() => { try { gatewayProc.kill('SIGKILL'); } catch (_) {} }, 2000);
};
