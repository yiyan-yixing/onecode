'use strict';

/**
 * Tests for gateway/router.js
 */
module.exports = function (t) {
  const path = require('path');
  const { runAndParse } = require('./helpers');

  const routerPath = path.resolve(__dirname, '..', '..', 'agent-runtime', 'gateway', 'router.js');

  // Mock config and cc-status via Module.prototype.require override
  function runRoute(url, svcReg) {
    const regStr = svcReg || '{}';
    return runAndParse(`
      const Module = require('module');
      const origReq = Module.prototype.require;
      Module.prototype.require = function(id) {
        if (id === './config') return { PORT: 7681, FB_PORT: 8081, VSCODE_PORT: 8082 };
        if (id === './cc-status') return { loadSvcRegistry: () => (${regStr}) };
        return origReq.apply(this, arguments);
      };
      const router = require(${JSON.stringify(routerPath)});
      Module.prototype.require = origReq;
      const result = router.route({ url: ${JSON.stringify(url)}, method: 'GET', headers: {} });
      console.log(JSON.stringify(result));
    `);
  }

  function runIsServiceWorkerUrl(url) {
    const result = runAndParse(`
      const Module = require('module');
      const origReq = Module.prototype.require;
      Module.prototype.require = function(id) {
        if (id === './config') return { PORT: 7681, FB_PORT: 8081, VSCODE_PORT: 8082 };
        if (id === './cc-status') return { loadSvcRegistry: () => ({}) };
        return origReq.apply(this, arguments);
      };
      const router = require(${JSON.stringify(routerPath)});
      Module.prototype.require = origReq;
      console.log(JSON.stringify(router.isServiceWorkerUrl(${JSON.stringify(url)})));
    `);
    return result;
  }

  t.section('File browser routing');

  const files = runRoute('/files');
  t.ok(files, '/files routes to filebrowser');
  if (files) {
    t.equal(files.port, 8081, '/files targets FB_PORT');
    t.equal(files.host, '127.0.0.1', '/files targets localhost');
  }

  const filesSub = runRoute('/files/some/path.txt');
  t.ok(filesSub, '/files/some/path.txt routes to filebrowser');
  if (filesSub) {
    t.equal(filesSub.port, 8081, '/files/... targets FB_PORT');
  }

  t.section('VS Code routing');

  const vscodeRedirect = runRoute('/vscode');
  t.ok(vscodeRedirect, '/vscode returns a route');
  if (vscodeRedirect) {
    t.ok(vscodeRedirect.redirect, '/vscode redirects to /vscode/');
    t.equal(vscodeRedirect.redirect, '/vscode/', 'redirects to /vscode/');
  }

  const vscodeSub = runRoute('/vscode/some/path');
  t.ok(vscodeSub, '/vscode/some/path routes to VS Code');
  if (vscodeSub) {
    t.equal(vscodeSub.port, 8082, 'VS Code subpath targets VSCODE_PORT');
    t.equal(vscodeSub.prefix, '/vscode', 'has /vscode prefix');
  }

  t.section('VSDA stub routing');

  const vsdaWasm = runRoute('/vscode/vsda_bg.wasm');
  t.ok(vsdaWasm, '/vscode/vsda_bg.wasm returns a route');
  if (vsdaWasm) {
    t.ok(vsdaWasm.vsdaStub, 'vsda_bg.wasm routes to vsda stub');
  }

  const vsdaJs = runRoute('/vscode/vsda.js');
  t.ok(vsdaJs, '/vscode/vsda.js returns a route');
  if (vsdaJs) {
    t.ok(vsdaJs.vsdaJsStub, 'vsda.js routes to vsda JS stub');
  }

  t.section('Proxy routing');

  const proxyMatch = runRoute('/proxy/9000/api/data', '{"webapp":9000}');
  t.ok(proxyMatch, '/proxy/9000/... routes');
  if (proxyMatch) {
    t.equal(proxyMatch.port, 9000, '/proxy/9000 targets port 9000');
  }

  t.section('Proxy SSRF protection');

  const proxyPrivileged = runRoute('/proxy/80/test');
  t.equal(proxyPrivileged, null, 'proxy to privileged port (80) blocked');

  const proxySelf = runRoute('/proxy/7681/test');
  t.equal(proxySelf, null, 'proxy to gateway port (7681) blocked');

  const proxyNotAllowed = runRoute('/proxy/9999/test');
  t.equal(proxyNotAllowed, null, 'proxy to unallowed port blocked');

  t.section('Service routing');

  const svcMatch = runRoute('/svc/webapp/api/data', '{"webapp":9000}');
  t.ok(svcMatch, '/svc/webapp/... routes');
  if (svcMatch) {
    t.equal(svcMatch.port, 9000, 'service route targets registered port');
    t.equal(svcMatch.prefix, '/svc/webapp', 'has service prefix');
  }

  const svcNoSlash = runRoute('/svc/webapp', '{"webapp":9000}');
  t.ok(svcNoSlash, '/svc/webapp (no trailing slash) returns a route');
  if (svcNoSlash) {
    t.ok(svcNoSlash.redirect, '/svc/webapp redirects to /svc/webapp/');
  }

  const svcNotFound = runRoute('/svc/nonexistent/path', '{"webapp":9000}');
  t.ok(svcNotFound, '/svc/nonexistent returns a route');
  if (svcNotFound) {
    t.ok(svcNotFound.svcNotFound, 'unknown service gets svcNotFound flag');
  }

  t.section('Unmatched routes');

  const unknown = runRoute('/unknown/path');
  t.equal(unknown, null, 'unmatched URL returns null');

  const root = runRoute('/');
  t.equal(root, null, '/ root returns null (handled by index.js directly)');

  t.section('isServiceWorkerUrl');

  t.equal(runIsServiceWorkerUrl('/service_worker.js'), true, 'service_worker.js detected');
  t.equal(runIsServiceWorkerUrl('/service-worker.js'), true, 'service-worker.js detected');
  t.equal(runIsServiceWorkerUrl('/sw.js'), true, 'sw.js detected');
  t.equal(runIsServiceWorkerUrl('/path/to/SW.js'), true, 'SW.js with path detected');
  t.equal(runIsServiceWorkerUrl('/app.js'), false, 'app.js not a service worker');
  t.equal(runIsServiceWorkerUrl('/service.js'), false, 'service.js not matched');
};
