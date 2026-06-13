'use strict';

const { PORT, FB_PORT, VSCODE_PORT } = require('./config');
const { loadSvcRegistry } = require('./cc-status');

function isServiceWorkerUrl(url) {
  const p = url.split('?')[0];
  return /\/service[-_]worker\.js$/i.test(p) || /\/sw\.js$/i.test(p);
}

function route(req) {
  const url = req.url.split('?')[0];
  if (url === '/files' || url.startsWith('/files/')) {
    return { port: FB_PORT, path: req.url, host: '127.0.0.1' };
  }
  if (url === '/vscode') {
    const qs = req.url.includes('?') ? req.url.slice(req.url.indexOf('?')) : '';
    return { redirect: '/vscode/' + qs };
  }
  if (url.endsWith('/vsda_bg.wasm') && url.startsWith('/vscode/')) {
    return { vsdaStub: true };
  }
  if (url.endsWith('/vsda.js') && url.startsWith('/vscode/')) {
    return { vsdaJsStub: true };
  }
  if (url.startsWith('/vscode/')) {
    const stripped = req.url.replace(/^\/vscode/, '') || '/';
    return { port: VSCODE_PORT, path: stripped, host: '127.0.0.1', prefix: '/vscode' };
  }
  if (VSCODE_PORT && (
    url.startsWith('/_static/') ||
    url.startsWith('/out/') ||
    url.startsWith('/extensions/') ||
    url.startsWith('/vscode-resource/') ||
    url.startsWith('/remote-extensions/') ||
    url === '/manifest.json' ||
    url === '/mint-key' ||
    url.startsWith('/lib/') ||
    url.startsWith('/static/') ||
    /^\/(?:stable-)?[a-f0-9]{20,}\//.test(url) ||
    url.startsWith('/extensionWebview') ||
    url === '/extensionHostWorker.js' ||
    url === '/product.json'
  )) {
    return { port: VSCODE_PORT, path: req.url, host: '127.0.0.1', prefix: '' };
  }
  const proxyMatch = url.match(/^\/proxy\/(\d+)(\/.*)?$/);
  if (proxyMatch) {
    const proxyPort = parseInt(proxyMatch[1], 10);
    // Block SSRF: reject privileged ports, gateway's own port, and
    // ports not in the allowed set (FB_PORT, VSCODE_PORT, service registry)
    if (proxyPort < 1024 || proxyPort === PORT) {
      return null;
    }
    const allowed = new Set([FB_PORT, VSCODE_PORT]);
    const reg = loadSvcRegistry();
    Object.values(reg).forEach(function (p) {
      allowed.add(p);
    });
    if (!allowed.has(proxyPort)) {
      return null;
    }
    return { port: proxyPort, path: proxyMatch[2] || '/', host: '127.0.0.1' };
  }
  const svcMatch = url.match(/^\/svc\/([^/]+)(\/.*)?$/);
  if (svcMatch) {
    const reg = loadSvcRegistry();
    const name = svcMatch[1];
    const port = reg[name];
    if (port) {
      if (!svcMatch[2]) {
        return { redirect: `/svc/${name}/` };
      }
      return { port, path: svcMatch[2], host: '127.0.0.1', prefix: `/svc/${name}` };
    }
    return { svcNotFound: name };
  }
  return null;
}

module.exports = { route, isServiceWorkerUrl };
