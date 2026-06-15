'use strict';

/**
 * Tests for gateway/inject.js
 */
module.exports = function (t) {
  const path = require('path');
  const fs = require('fs');
  const { runAndParse } = require('./helpers');

  const injectPath = path.resolve(__dirname, '..', '..', 'agent-runtime', 'gateway', 'inject.js');
  const scriptsDir = path.resolve(__dirname, '..', '..', 'agent-runtime', 'gateway', 'scripts');

  const sePolyfillExists = fs.existsSync(path.join(scriptsDir, 'se-polyfill.js'));
  const swPatchExists = fs.existsSync(path.join(scriptsDir, 'sw-patch.js'));

  if (!sePolyfillExists || !swPatchExists) {
    t.skip('inject.js requires script files that are not present');
    return;
  }

  function runInject(html, isWorkbench, isHttps) {
    return runAndParse(`
      const inject = require(${JSON.stringify(injectPath)});
      const result = inject.injectVscodeHtml(
        ${JSON.stringify(html)},
        ${JSON.stringify(isWorkbench)},
        ${JSON.stringify(isHttps)},
      );
      console.log(JSON.stringify({
        bodyLen: result.body.length,
        hasScript: result.body.includes('<script'),
        hasCsp: result.cspHashesStr.includes('sha256-'),
        body: result.body,
      }));
    `);
  }

  t.section('injectVscodeHtml — basic injection');

  const simpleHtml = '<html><head><title>Test</title></head><body>Hello</body></html>';
  const result = runInject(simpleHtml, false, false);
  t.ok(result, 'basic injection runs');
  if (result) {
    t.ok(result.bodyLen > simpleHtml.length, 'body is longer after injection');
    t.ok(result.hasScript, 'body contains injected script');
  }

  t.section('injectVscodeHtml — CSP hash returned');

  if (result) {
    t.ok(result.hasCsp, 'CSP hash includes sha256 prefix');
  }

  t.section('injectVscodeHtml — workbench mode');

  const workbenchHtml = '<html><head><title>Workbench</title></head><body>VS Code</body></html>';
  const workbenchResult = runInject(workbenchHtml, true, false);
  t.ok(workbenchResult, 'workbench injection runs');
  if (workbenchResult) {
    t.ok(workbenchResult.bodyLen > workbenchHtml.length, 'workbench body is longer');
  }

  t.section('injectVscodeHtml — HTTPS mode removes serviceWorker config');

  const httpsHtml = '<html><head></head><body>&quot;serviceWorker&quot;:{&quot;scope&quot;:&quot;/&quot;}</body></html>';
  const httpsResult = runInject(httpsHtml, true, true);
  t.ok(httpsResult, 'HTTPS injection runs');
  if (httpsResult) {
    t.ok(!httpsResult.body.includes('&quot;scope&quot;:&quot;/&quot;'),
      'HTTPS mode removes serviceWorker config');
    t.ok(httpsResult.body.includes('serviceWorker&quot;:null') ||
         httpsResult.body.includes('serviceWorker":null'),
      'HTTPS mode replaces serviceWorker with null');
  }

  t.section('injectVscodeHtml — no head tag (fallback)');

  const noHeadHtml = '<html><body>No head tag</body></html>';
  const noHeadResult = runInject(noHeadHtml, false, false);
  t.ok(noHeadResult, 'no-head injection runs');
  if (noHeadResult) {
    t.ok(noHeadResult.hasScript, 'script injected even without head tag');
  }

  t.section('injectVscodeHtml — preserves nonce');

  const nonceHtml = '<html><head><script nonce="abc123">var x=1;</script></head><body></body></html>';
  const nonceResult = runInject(nonceHtml, false, false);
  t.ok(nonceResult, 'nonce injection runs');
  if (nonceResult) {
    t.ok(nonceResult.body.includes('nonce="abc123"'), 'nonce preserved in injected scripts');
  }
};
