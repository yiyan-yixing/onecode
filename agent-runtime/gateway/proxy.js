'use strict';

const http = require('http');
const net = require('net');
const zlib = require('zlib');
const { VSCODE_PORT } = require('./config');
const { injectVscodeHtml } = require('./inject');

const MAX_HTML_BUFFER = 20 * 1024 * 1024; // 20MB safety limit for buffered HTML
const PROXY_TIMEOUT_MS = 30000; // Timeout for proxy connections (ms)
const WS_UPGRADE_TIMEOUT_MS = 10000; // Timeout for WebSocket upgrade connections (ms)
const WS_IDLE_TIMEOUT_MS = 300000; // 5 min idle timeout for established WebSocket pipes
const MAX_PROXY_WS = 100; // Max concurrent proxy WebSocket connections

// Reusable keep-alive agent for proxy connections
const proxyAgent = new http.Agent({ keepAlive: true, maxSockets: 50 });

const VSCODE_STARTING_HTML = '<!DOCTYPE html><html><head><meta charset="utf-8"><title>VS Code Starting...</title>' +
  '<style>body{background:#1b1b1b;color:#ccc;font-family:system-ui;' +
  'display:flex;align-items:center;justify-content:center;height:100vh;margin:0}' +
  '.s{text-align:center}h2{color:#6a9fb5;margin:0 0 8px}p{color:#888;font-size:14px}</style></head>' +
  '<body><div class="s"><h2>VS Code is starting...</h2><p>This page will refresh automatically.</p></div>' +
  '<script>setTimeout(function(){location.reload()},3000)</script></body></html>';

function gzipEnd(req, res, statusCode, headers, body) {
  const acceptGzip = (req.headers['accept-encoding'] || '').includes('gzip');
  if (acceptGzip) {
    zlib.gzip(body, (err, compressed) => {
      if (err) {
        headers['content-length'] = Buffer.byteLength(body);
        res.writeHead(statusCode, headers);
        res.end(body);
        return;
      }
      headers['content-encoding'] = 'gzip';
      headers['content-length'] = compressed.length;
      headers.vary = 'Accept-Encoding';
      res.writeHead(statusCode, headers);
      res.end(compressed);
    });
  } else {
    headers['content-length'] = Buffer.byteLength(body);
    res.writeHead(statusCode, headers);
    res.end(body);
  }
}

function handleProxy(req, res, target, server) {
  const isVscode = target.port === VSCODE_PORT && target.host === '127.0.0.1';
  const headers = { ...req.headers, host: `${target.host}:${target.port}` };
  if (isVscode) {
    if (headers.origin) {
      headers.origin = `http://${target.host}:${target.port}`;
    }
  }
  if (isVscode) {
    delete headers['accept-encoding'];
  }
  let activeProxyRes = null;
  const proxyReq = http.request({
    hostname: target.host,
    port: target.port,
    path: target.path,
    method: req.method,
    headers,
    agent: proxyAgent,
    timeout: PROXY_TIMEOUT_MS,
  }, (proxyRes) => {
    activeProxyRes = proxyRes;
    const resHeaders = { ...proxyRes.headers };
    if (typeof resHeaders.location === 'string'
        && resHeaders.location.startsWith('/')) {
      const prefix = target.prefix || '';
      if (!prefix || !resHeaders.location.startsWith(prefix)) {
        resHeaders.location = prefix + resHeaders.location;
      }
    }

    const ct = (proxyRes.headers['content-type'] || '').toLowerCase();
    const isVscodeWorkbench = isVscode && (target.path === '/' || target.path.startsWith('/?'));
    if (isVscode && ct.includes('text/html')) {
      const chunks = [];
      let totalSize = 0;
      let oversized = false;
      let bufferTimeout = setTimeout(() => {
        bufferTimeout = null;
        oversized = true; // prevent end handler from proceeding
        proxyRes.destroy();
        proxyReq.destroy();
        req.unpipe(proxyReq);
        if (!res.headersSent) {
          res.writeHead(504, { 'Content-Type': 'text/plain' });
          res.end('Gateway Timeout');
        }
      }, PROXY_TIMEOUT_MS);
      proxyRes.on('data', (chunk) => {
        if (oversized) {
          return;
        }
        totalSize += chunk.length;
        if (totalSize > MAX_HTML_BUFFER) {
          oversized = true;
          clearTimeout(bufferTimeout);
          bufferTimeout = null;
          proxyRes.destroy();
          proxyReq.destroy();
          req.unpipe(proxyReq);
          if (!res.headersSent) {
            res.writeHead(502, { 'Content-Type': 'text/plain' });
            res.end('Response too large');
          }
          return;
        }
        chunks.push(chunk);
      });
      proxyRes.on('end', () => {
        if (oversized) {
          return;
        }
        if (bufferTimeout) {
          clearTimeout(bufferTimeout);
          bufferTimeout = null;
        }
        let body = Buffer.concat(chunks).toString('utf8');
        if (isVscodeWorkbench) {
          body = body.replace(/<head([^>]*)>/i, '<head$1><base href="/vscode/">');
        }
        const isHttps = server instanceof require('https').Server;
        const { body: newBody, cspHashesStr } = injectVscodeHtml(body, isVscodeWorkbench, isHttps);
        body = newBody;
        if (cspHashesStr && resHeaders['content-security-policy']) {
          resHeaders['content-security-policy'] = resHeaders['content-security-policy'].replace(
            /(script-src\s+)([^;]+)/gi,
            '$1$2 ' + cspHashesStr,
          );
        }
        delete resHeaders['transfer-encoding'];
        delete resHeaders['content-encoding'];
        gzipEnd(req, res, proxyRes.statusCode, resHeaders, Buffer.from(body, 'utf8'));
      });
      proxyRes.on('error', () => {
        if (oversized) {
          return;
        }
        oversized = true;
        if (bufferTimeout) {
          clearTimeout(bufferTimeout);
          bufferTimeout = null;
        }
        proxyReq.destroy();
        req.unpipe(proxyReq);
        if (!res.headersSent) {
          res.writeHead(502, { 'Content-Type': 'text/plain' });
          res.end('Bad Gateway');
        }
      });
      return;
    }

    res.writeHead(proxyRes.statusCode, resHeaders);
    proxyRes.on('error', () => {
      if (!res.headersSent) {
        res.writeHead(502, { 'Content-Type': 'text/plain' });
        res.end('Bad Gateway');
      }
      try {
        res.end();
      } catch (_) {}
    });
    res.on('error', () => { /* client disconnected during streaming — expected */ });
    proxyRes.pipe(res);
  });

  proxyReq.on('timeout', () => {
    proxyReq.destroy(new Error('Proxy request timed out'));
  });
  proxyReq.on('error', () => {
    req.unpipe(proxyReq);
    // Tear down the proxyRes->res pipe if it was established
    if (activeProxyRes) {
      activeProxyRes.unpipe(res);
      activeProxyRes.destroy();
    }
    if (!res.headersSent) {
      if (isVscode) {
        res.writeHead(502, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(VSCODE_STARTING_HTML);
      } else {
        res.writeHead(502);
        res.end('Bad Gateway');
      }
    }
  });
  req.on('error', () => { /* client disconnected — expected in proxy */ });
  req.pipe(proxyReq);
}

// Track active proxy WebSocket connections for connection limiting
var _proxyWsCount = 0;

function handleWsUpgrade(req, socket, head, routeFn) {
  // Connection limit check
  if (_proxyWsCount >= MAX_PROXY_WS) {
    socket.write('HTTP/1.1 503 Service Unavailable\r\n\r\n');
    socket.destroy();
    return;
  }

  let target = routeFn(req);
  if (!target && VSCODE_PORT) {
    const url = req.url.split('?')[0];
    if (url === '/' || url.startsWith('/out/') || url.startsWith('/_static/') ||
        url.startsWith('/extensions/') || url.startsWith('/vscode-resource/') ||
        url.startsWith('/static/') || /^\/(?:stable-)?[a-f0-9]{20,}\//.test(url)) {
      target = { port: VSCODE_PORT, path: req.url, host: '127.0.0.1', prefix: '' };
    }
  }
  if (!target || target.redirect || target.svcNotFound) {
    socket.destroy();
    return;
  }

  _proxyWsCount++;

  function cleanup() {
    if (_proxyWsCount > 0) {
      _proxyWsCount--;
    }
    // Avoid double-decrement: replace cleanup with no-op after first call
    cleanup = function () {};
  }

  // Set connect timeout BEFORE net.connect so a hanging SYN is caught
  let backend;
  const connectTimer = setTimeout(() => {
    cleanup();
    if (backend) {
      backend.destroy();
    }
    socket.destroy();
  }, WS_UPGRADE_TIMEOUT_MS);
  backend = net.connect(target.port, target.host, () => {
    clearTimeout(connectTimer);
    backend.setTimeout(0); // Clear connect timeout once connected
    // Set idle timeout for the established pipe — if no data flows for 5 min,
    // tear down both ends to reclaim stale connections
    backend.setTimeout(WS_IDLE_TIMEOUT_MS);
    const lines = [`GET ${target.path} HTTP/1.1`];
    const proxyHost = `${target.host}:${target.port}`;
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      const k = req.rawHeaders[i];
      const v = req.rawHeaders[i + 1];
      const kl = k.toLowerCase();
      if (kl === 'host') {
        lines.push(`Host: ${proxyHost}`);
      } else if (kl === 'origin') {
        lines.push(`Origin: http://${proxyHost}`);
      } else {
        lines.push(`${k}: ${v}`);
      }
    }
    lines.push('', '');
    backend.write(lines.join('\r\n'));
    if (head.length > 0) {
      backend.write(head);
    }
    // Backpressure-aware piping: pause source when destination is congested
    backend.pipe(socket, { end: false });
    socket.pipe(backend, { end: false });
    socket.on('drain', () => {
      if (!backend.destroyed) {
        backend.resume();
      }
    });
    backend.on('drain', () => {
      if (!socket.destroyed) {
        socket.resume();
      }
    });
    backend.on('end', () => {
      if (!socket.destroyed) {
        socket.end();
      }
    });
    socket.on('end', () => {
      if (!backend.destroyed) {
        backend.end();
      }
    });
  });

  backend.on('timeout', () => {
    clearTimeout(connectTimer);
    cleanup();
    backend.destroy();
    socket.destroy();
  });
  backend.on('error', () => {
    clearTimeout(connectTimer);
    cleanup();
    socket.destroy();
  });
  socket.on('error', () => {
    cleanup();
    backend.destroy();
  });
  // Mutual cleanup: when one side closes, destroy the other to reclaim
  // file descriptors promptly instead of waiting for idle timeout
  backend.on('close', () => {
    cleanup();
    socket.destroy();
  });
  socket.on('close', () => {
    cleanup();
    backend.destroy();
  });
}

module.exports = { handleProxy, handleWsUpgrade };
