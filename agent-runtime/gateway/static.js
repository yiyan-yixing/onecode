'use strict';

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { STATIC_DIR, SVC_REGISTRY } = require('./config');

const MIME = {
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.html': 'text/html',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.wasm': 'application/wasm',
};

const WASM_STUB = Buffer.from([0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]);

const SW_STUB_JS = [
  '// Service Worker stub for code-server',
  'self.addEventListener("install", () => self.skipWaiting());',
  'self.addEventListener("activate", () => self.clients.claim());',
  'self.addEventListener("fetch", (e) => e.respondWith(fetch(e.request)));',
].join('\n');

const VSDA_JS_STUB = 'define([],function(){return{vscodeApi:{},postMessage:function(){}}});';

// Pre-load and pre-compress static assets at startup to avoid per-request gzip overhead
const _staticCache = new Map();
(function preloadStatic() {
  const compressibleExts = new Set(['.js', '.css', '.html']);
  let entries;
  try {
    entries = fs.readdirSync(STATIC_DIR);
  } catch (_) { return; }
  for (const name of entries) {
    const ext = path.extname(name);
    const filePath = path.join(STATIC_DIR, name);
    let stat;
    try {
      stat = fs.statSync(filePath);
      if (!stat.isFile()) {
        continue;
      }
    } catch (_) {
      continue;
    }
    const raw = fs.readFileSync(filePath);
    const ct = MIME[ext] || 'application/octet-stream';
    const compressible = compressibleExts.has(ext);
    const entry = { raw, ct, compressed: null };
    if (compressible) {
      try {
        entry.compressed = zlib.gzipSync(raw);
      } catch (_) {}
    }
    _staticCache.set(name, entry);
  }
})();

function serveStatic(req, res) {
  if (!req.url.startsWith('/static/')) {
    return false;
  }
  const fileName = path.basename(req.url);
  const entry = _staticCache.get(fileName);
  if (!entry) {
    if (!res.headersSent) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
    }
    return true;
  }
  const acceptGzip = entry.compressed && (req.headers['accept-encoding'] || '').includes('gzip');
  if (acceptGzip) {
    res.writeHead(200, {
      'Content-Type': entry.ct + '; charset=utf-8',
      'Cache-Control': 'no-cache',
      'Content-Encoding': 'gzip',
      'Content-Length': entry.compressed.length,
      'Vary': 'Accept-Encoding',
    });
    res.end(entry.compressed);
  } else {
    res.writeHead(200, {
      'Content-Type': entry.ct + '; charset=utf-8',
      'Cache-Control': 'no-cache',
      'Content-Length': entry.raw.length,
    });
    res.end(entry.raw);
  }
  return true;
}

function serveSwStub(res) {
  res.writeHead(200, {
    'Content-Type': 'application/javascript; charset=utf-8',
    'Service-Worker-Allowed': '/',
    'Cache-Control': 'no-cache',
  });
  res.end(SW_STUB_JS);
}

function serveVsdaStub(res) {
  res.writeHead(200, {
    'Content-Type': 'application/wasm',
    'Cache-Control': 'no-cache',
  });
  res.end(WASM_STUB);
}

function serveVsdaJsStub(res) {
  res.writeHead(200, {
    'Content-Type': 'application/javascript; charset=utf-8',
    'Cache-Control': 'no-cache',
  });
  res.end(VSDA_JS_STUB);
}

function serveSvcNotFound(res, name, registry) {
  const lines = [`Service "${name}" not found.`, '', 'Registered services:'];
  if (Object.keys(registry).length === 0) {
    lines.push('  (none)');
  } else {
    for (const [n, p] of Object.entries(registry)) {
      lines.push(`  /svc/${n}/ → :${p}`);
    }
  }
  lines.push('', `Registry: ${SVC_REGISTRY}`, 'Format: name port');
  res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end(lines.join('\n'));
}

module.exports = {
  serveStatic, serveSwStub, serveVsdaStub, serveVsdaJsStub, serveSvcNotFound,
};
