#!/usr/bin/env node
'use strict';

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const config = require('./config');
const { route, isServiceWorkerUrl } = require('./router');
const { loadCcStatus, loadSvcRegistry } = require('./cc-status');
const { serveStatic, serveSwStub, serveVsdaStub, serveVsdaJsStub, serveSvcNotFound } = require('./static');
const { handleProxy, handleWsUpgrade } = require('./proxy');
const { setupTerminalWebSocket } = require('./term-ws');
const ptyManager = require('./pty');

const htmlTemplate = fs.readFileSync(path.join(__dirname, 'onecode.html'), 'utf8');
const indexHtml = htmlTemplate
  .replace('{{CONFIG}}', JSON.stringify({
    token: config.TERM_TOKEN, ocName: process.env.OC_NAME || '', version: config.VERSION,
  }))
  .replace('{{TITLE}}', 'OneCode · AI 原生 IDE');

// Pre-compress indexHtml at startup so each request avoids re-gzipping ~44KB
const indexHtmlBuf = Buffer.from(indexHtml, 'utf8');
const indexHtmlGz = zlib.gzipSync(indexHtmlBuf);

const server = (() => {
  const certPath = process.env.GATEWAY_CERT || '';
  const keyPath = process.env.GATEWAY_KEY || '';
  let tlsOptions = null;
  if (certPath && keyPath) {
    try {
      tlsOptions = {
        cert: fs.readFileSync(certPath),
        key: fs.readFileSync(keyPath),
      };
      console.log('[gateway] TLS enabled (HTTPS)');
    } catch (e) {
      console.warn('[gateway] Failed to load TLS cert, falling back to HTTP:', e.message);
    }
  }
  const s = tlsOptions
    ? https.createServer(tlsOptions, (req, res) => handleRequest(req, res))
    : http.createServer((req, res) => handleRequest(req, res));
  return s;
})();

function handleRequest(req, res) {
  // Index page (use pre-compressed cache)
  if (req.url === '/' || req.url === '/index.html') {
    const acceptGzip = (req.headers['accept-encoding'] || '').includes('gzip');
    if (acceptGzip) {
      res.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Content-Encoding': 'gzip',
        'Content-Length': indexHtmlGz.length,
        'Vary': 'Accept-Encoding',
      });
      res.end(indexHtmlGz);
    } else {
      res.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Content-Length': indexHtmlBuf.length,
      });
      res.end(indexHtmlBuf);
    }
    return;
  }

  // Static files
  if (serveStatic(req, res)) {
    return;
  }

  // Claude Code status API
  if (req.url === '/api/cc-status') {
    res.writeHead(200, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-cache',
    });
    res.end(JSON.stringify(loadCcStatus()));
    return;
  }

  // Restart terminal session (restart claude in current PTY)
  if (req.url === '/api/restart-terminal' && req.method === 'POST') {
    try {
      ptyManager.restart();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end('{"ok":true}');
    } catch (e) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: e.message }));
    }
    return;
  }

  // Route and proxy
  const target = route(req);
  if (!target) {
    res.writeHead(404);
    res.end('Not Found');
    return;
  }
  if (target.redirect) {
    res.writeHead(302, { Location: target.redirect });
    res.end();
    return;
  }
  // Service worker stub for code-server
  if (target.port === config.VSCODE_PORT && isServiceWorkerUrl(req.url)) {
    serveSwStub(res);
    return;
  }
  if (target.vsdaStub) {
    serveVsdaStub(res);
    return;
  }
  if (target.vsdaJsStub) {
    serveVsdaJsStub(res);
    return;
  }
  if (target.svcNotFound) {
    serveSvcNotFound(res, target.svcNotFound, loadSvcRegistry());
    return;
  }

  handleProxy(req, res, target, server);
}

// WebSocket upgrade proxy — terminal WS handler intercepts /ws/term first
setupTerminalWebSocket(server);
server.on('upgrade', (req, socket, head) => {
  // /ws/term is handled by setupTerminalWebSocket; remaining upgrades go to proxy
  if (req.url.split('?')[0] === '/ws/term') {
    return;
  }
  handleWsUpgrade(req, socket, head, route);
});

// Spawn the main terminal PTY based on BACKEND env var
// Supported backends: claude-code (default), opencode
const backend = process.env.BACKEND || 'claude-code';

if (backend === 'opencode') {
  // OpenCode is pre-installed (MIT license), start immediately
  ptyManager.spawn('opencode', [], {
    HOME: '/home/work',
  });
} else {
  // Claude Code: may need runtime install
  const claudeReady = (() => {
    try {
      const { execSync } = require('child_process');
      execSync('which claude', { stdio: 'ignore' });
      return true;
    } catch (_) {
      return false;
    }
  })();

  if (claudeReady) {
    ptyManager.spawn('claude', ['--permission-mode', 'bypassPermissions'], {
      HOME: '/home/work',
    });
  } else {
    // Claude is being installed in background (by entrypoint.sh).
    // Start a shell that shows a friendly message and auto-launches claude when ready.
    ptyManager.spawn('/bin/bash', ['-c', [
      'echo ""',
      'echo "  ⏳ Claude Code CLI is being installed..."',
      'echo "  This only happens on first start (~30-60s)."',
      'echo "  OneCode is ready — you can browse files and agents while waiting."',
      'echo ""',
      // Wait for claude to become available (install runs in background)
      'while ! command -v claude &>/dev/null; do sleep 2; done',
      'echo ""',
      'echo "  ✅ Claude Code CLI installed! Starting..."',
      'echo ""',
      'exec claude --permission-mode bypassPermissions',
    ].join('\n')], {
      HOME: '/home/work',
    });
  }
}

server.listen(config.PORT, '0.0.0.0', () => {
  const proto = server instanceof https.Server ? 'https' : 'http';
  console.log(`[gateway] ${proto}://0.0.0.0:${config.PORT} filebrowser=${config.FB_PORT} vscode=${config.VSCODE_PORT}`);
});

// Graceful shutdown
let shuttingDown = false;
function shutdown(signal) {
  if (shuttingDown) {
    return;
  }
  shuttingDown = true;
  console.log(`[gateway] ${signal} received, shutting down...`);
  ptyManager.kill();
  for (const ws of [...ptyManager.clients]) {
    try {
      ws.close(1001, 'server shutdown');
    } catch (_) {}
  }
  // Kill child processes (filebrowser, code-server) tracked by start-remote.sh
  const childPids = (process.env.CHILD_PIDS || '').trim().split(/\s+/);
  for (const pid of childPids) {
    const num = Number(pid);
    if (pid && num > 0) {
      try {
        process.kill(num, 'SIGTERM');
      } catch (_) {}
    }
  }
  // Destroy idle keep-alive connections so server.close() can complete promptly
  server.close(() => process.exit(0));
  server.closeAllConnections && server.closeAllConnections();
  setTimeout(() => process.exit(1), 3000);
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

process.on('uncaughtException', (err) => {
  console.error('[gateway] Uncaught exception:', err);
  // Only shut down on critical errors; network/system errors are recoverable
  if (err.code === 'ERR_ASSERTION' || err.code === 'ERR_MODULE_NOT_FOUND' || err.name === 'SyntaxError') {
    shutdown('uncaughtException');
  }
});
process.on('unhandledRejection', (reason) => {
  console.error('[gateway] Unhandled rejection:', reason);
  // Do not exit — most rejections are recoverable (network errors, proxy failures, etc.)
});
