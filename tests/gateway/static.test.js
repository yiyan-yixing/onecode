'use strict';

/**
 * Tests for gateway/static.js
 */
module.exports = function (t) {
  const path = require('path');
  const fs = require('fs');
  const { runAndParse } = require('./helpers');

  // Create test fixture directory
  const STATIC_DIR = path.join(__dirname, '..', 'fixtures', 'static_for_test');
  fs.mkdirSync(STATIC_DIR, { recursive: true });
  fs.writeFileSync(path.join(STATIC_DIR, 'test.js'), 'console.log("hello");');
  fs.writeFileSync(path.join(STATIC_DIR, 'test.css'), 'body { color: red; }');
  fs.writeFileSync(path.join(STATIC_DIR, 'test.html'), '<h1>Hello</h1>');

  const staticPath = path.resolve(__dirname, '..', '..', 'agent-runtime', 'gateway', 'static.js');

  function runStaticTest(testCode) {
    return runAndParse(`
      const Module = require('module');
      const origReq = Module.prototype.require;
      Module.prototype.require = function(id) {
        if (id === './config') return { STATIC_DIR: ${JSON.stringify(STATIC_DIR)}, SVC_REGISTRY: '/tmp/.svc-registry-test' };
        if (id === './cc-status') return { loadSvcRegistry: () => ({}) };
        return origReq.apply(this, arguments);
      };
      const staticMod = require(${JSON.stringify(staticPath)});
      Module.prototype.require = origReq;
      ${testCode}
    `);
  }

  t.section('serveStatic — JS file');

  const jsResult = runStaticTest(`
    const res = { headersSent: false, statusCode: 0, body: '', ended: false, headers: {} };
    res.writeHead = (code, h) => { res.statusCode = code; res.headers = h || {}; };
    res.end = (data) => { res.body = data ? data.toString() : ''; res.ended = true; };
    const served = staticMod.serveStatic({ url: '/static/test.js', headers: {} }, res);
    console.log(JSON.stringify({ served, statusCode: res.statusCode, body: res.body, ended: res.ended }));
  `);
  t.ok(jsResult, 'JS file test runs');
  if (!jsResult) { t.skip('JS static test failed'); } else {
    t.ok(jsResult.served, 'JS file served');
    t.equal(jsResult.statusCode, 200, 'status 200');
    t.ok(jsResult.body && jsResult.body.includes('console.log'), 'JS content correct');
  }

  t.section('serveStatic — CSS file');

  const cssResult = runStaticTest(`
    const res = { headersSent: false, statusCode: 0, body: '', ended: false, headers: {} };
    res.writeHead = (code, h) => { res.statusCode = code; res.headers = h || {}; };
    res.end = (data) => { res.body = data ? data.toString() : ''; res.ended = true; };
    const served = staticMod.serveStatic({ url: '/static/test.css', headers: {} }, res);
    console.log(JSON.stringify({ served, statusCode: res.statusCode, body: res.body }));
  `);
  t.ok(cssResult, 'CSS file test runs');
  if (cssResult) {
    t.ok(cssResult.served, 'CSS file served');
    t.ok(cssResult.body && cssResult.body.includes('color: red'), 'CSS content correct');
  }

  t.section('serveStatic — HTML file');

  const htmlResult = runStaticTest(`
    const res = { headersSent: false, statusCode: 0, body: '', ended: false, headers: {} };
    res.writeHead = (code, h) => { res.statusCode = code; res.headers = h || {}; };
    res.end = (data) => { res.body = data ? data.toString() : ''; res.ended = true; };
    const served = staticMod.serveStatic({ url: '/static/test.html', headers: {} }, res);
    console.log(JSON.stringify({ served, statusCode: res.statusCode, body: res.body }));
  `);
  t.ok(htmlResult, 'HTML file test runs');
  if (htmlResult) {
    t.ok(htmlResult.served, 'HTML file served');
    t.ok(htmlResult.body && htmlResult.body.includes('Hello'), 'HTML content correct');
  }

  t.section('serveStatic — gzip compression');

  const gzipResult = runStaticTest(`
    const res = { headersSent: false, statusCode: 0, body: '', ended: false, headers: {} };
    res.writeHead = (code, h) => { res.statusCode = code; res.headers = h || {}; };
    res.end = (data) => { res.body = 'binary'; res.ended = true; };
    const served = staticMod.serveStatic({ url: '/static/test.js', headers: { 'accept-encoding': 'gzip' } }, res);
    const ce = res.headers['Content-Encoding'] || '';
    console.log(JSON.stringify({ served, statusCode: res.statusCode, contentEncoding: ce }));
  `);
  t.ok(gzipResult, 'gzip test runs');
  if (gzipResult) {
    t.ok(gzipResult.served, 'gzip request served');
    t.equal(gzipResult.contentEncoding, 'gzip', 'Content-Encoding is gzip');
  }

  t.section('serveStatic — 404 for missing file');

  const missingResult = runStaticTest(`
    const res = { headersSent: false, statusCode: 0, body: '', ended: false, headers: {} };
    res.writeHead = (code, h) => { res.statusCode = code; res.headers = h || {}; };
    res.end = (data) => { res.body = data ? data.toString() : ''; res.ended = true; };
    const served = staticMod.serveStatic({ url: '/static/nonexistent.js', headers: {} }, res);
    console.log(JSON.stringify({ served, statusCode: res.statusCode }));
  `);
  t.ok(missingResult, '404 test runs');
  if (missingResult) {
    t.ok(missingResult.served, 'missing file handled (returns true)');
    t.equal(missingResult.statusCode, 404, 'status 404 for missing file');
  }

  t.section('serveStatic — non-static URL');

  const nonStatic = runStaticTest(`
    const res = { headersSent: false, statusCode: 0, body: '', ended: false, headers: {} };
    res.writeHead = (code, h) => { res.statusCode = code; res.headers = h || {}; };
    res.end = (data) => { res.body = data ? data.toString() : ''; res.ended = true; };
    const served = staticMod.serveStatic({ url: '/api/something', headers: {} }, res);
    console.log(JSON.stringify({ served }));
  `);
  t.ok(nonStatic !== null, 'non-static test runs');
  t.equal(nonStatic && nonStatic.served, false, 'non-static URL returns false');

  t.section('serveSwStub');

  const swResult = runStaticTest(`
    const res = { headersSent: false, body: '', ended: false, headers: {} };
    res.writeHead = (code, h) => { res.statusCode = code; res.headers = h || {}; };
    res.end = (data) => { res.body = data ? data.toString() : ''; res.ended = true; };
    staticMod.serveSwStub(res);
    const swa = res.headers['Service-Worker-Allowed'] || '';
    console.log(JSON.stringify({ ended: res.ended, hasInstall: res.body.includes('install'), hasFetch: res.body.includes('fetch'), swAllowed: swa }));
  `);
  t.ok(swResult, 'SW stub test runs');
  if (swResult) {
    t.ok(swResult.ended, 'SW stub response ended');
    t.ok(swResult.hasInstall, 'SW stub contains install handler');
    t.ok(swResult.hasFetch, 'SW stub contains fetch handler');
  }

  t.section('serveVsdaStub');

  const vsdaResult = runStaticTest(`
    const res = { headersSent: false, body: Buffer.alloc(0), ended: false, headers: {} };
    res.writeHead = (code, h) => { res.statusCode = code; res.headers = h || {}; };
    res.end = (data) => { res.body = data || Buffer.alloc(0); res.ended = true; };
    staticMod.serveVsdaStub(res);
    const bytes = Array.from(res.body.slice(0, 4));
    console.log(JSON.stringify({ ended: res.ended, bytes }));
  `);
  t.ok(vsdaResult, 'vsda stub test runs');
  if (vsdaResult) {
    t.ok(vsdaResult.ended, 'vsda stub response ended');
    t.deepEqual(vsdaResult.bytes, [0x00, 0x61, 0x73, 0x6d], 'vsda stub starts with WASM magic bytes');
  }

  t.section('serveVsdaJsStub');

  const vsdaJsResult = runStaticTest(`
    const res = { headersSent: false, body: '', ended: false, headers: {} };
    res.writeHead = (code, h) => { res.statusCode = code; res.headers = h || {}; };
    res.end = (data) => { res.body = data ? data.toString() : ''; res.ended = true; };
    staticMod.serveVsdaJsStub(res);
    console.log(JSON.stringify({ ended: res.ended, hasDefine: res.body.includes('define') }));
  `);
  t.ok(vsdaJsResult, 'vsda JS stub test runs');
  if (vsdaJsResult) {
    t.ok(vsdaJsResult.ended, 'vsda JS stub response ended');
    t.ok(vsdaJsResult.hasDefine, 'vsda JS stub contains define()');
  }

  t.section('serveSvcNotFound');

  const svcResult = runStaticTest(`
    const res = { headersSent: false, body: '', ended: false, headers: {} };
    res.writeHead = (code, h) => { res.statusCode = code; res.headers = h || {}; };
    res.end = (data) => { res.body = data ? data.toString() : ''; res.ended = true; };
    staticMod.serveSvcNotFound(res, 'test-service', { webapp: 9000 });
    console.log(JSON.stringify({ ended: res.ended, statusCode: res.statusCode, hasName: res.body.includes('test-service'), hasRegistered: res.body.includes('webapp') }));
  `);
  t.ok(svcResult, 'svc not found test runs');
  if (svcResult) {
    t.ok(svcResult.ended, 'svc not found response ended');
    t.equal(svcResult.statusCode, 404, 'status 404');
    t.ok(svcResult.hasName, 'error message includes service name');
    t.ok(svcResult.hasRegistered, 'lists registered services');
  }

  // Clean up test fixtures
  try { fs.rmSync(STATIC_DIR, { recursive: true }); } catch (_) {}
};
