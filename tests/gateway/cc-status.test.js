'use strict';

/**
 * Tests for gateway/cc-status.js — cronNext function and status loading
 */
module.exports = function (t) {
  const path = require('path');
  const { runAndParse } = require('./helpers');

  const ccStatusPath = path.resolve(__dirname, '..', '..', 'agent-runtime', 'gateway', 'cc-status.js');

  function runCronNext(expr) {
    return runAndParse(`
      const Module = require('module');
      const origReq = Module.prototype.require;
      Module.prototype.require = function(id) {
        if (id === './config') return { SVC_REGISTRY: '/tmp/test-svc', GLOBAL_DIR: '/tmp/test-g', PROJECT_DIR: '/tmp/test-p' };
        return origReq.apply(this, arguments);
      };
      const cc = require(${JSON.stringify(ccStatusPath)});
      Module.prototype.require = origReq;
      console.log(JSON.stringify(cc.cronNext(${JSON.stringify(expr)})));
    `);
  }

  function runStatusLoad() {
    return runAndParse(`
      const Module = require('module');
      const origReq = Module.prototype.require;
      Module.prototype.require = function(id) {
        if (id === './config') return { SVC_REGISTRY: '/tmp/test-svc', GLOBAL_DIR: '/tmp/test-g', PROJECT_DIR: '/tmp/test-p' };
        return origReq.apply(this, arguments);
      };
      const cc = require(${JSON.stringify(ccStatusPath)});
      Module.prototype.require = origReq;
      const status = cc.loadCcStatus();
      const reg = cc.loadSvcRegistry();
      console.log(JSON.stringify({ status, reg }));
    `);
  }

  t.section('cronNext — every minute');

  const everyMinute = runCronNext('* * * * *');
  t.ok(everyMinute, 'every minute returns a value');
  if (everyMinute) {
    t.ok(everyMinute === '< 1m' || everyMinute.match(/^\d+m$/),
      'every minute returns a short duration');
  }

  t.section('cronNext — every hour');

  const everyHour = runCronNext('0 * * * *');
  t.ok(everyHour, 'every hour returns a value');
  if (everyHour) {
    t.ok(everyHour.match(/^[<\d]/), 'every hour returns a duration string');
  }

  t.section('cronNext — daily at midnight');

  const dailyMidnight = runCronNext('0 0 * * *');
  t.ok(dailyMidnight, 'daily at midnight returns a value');

  t.section('cronNext — every 5 minutes');

  const every5Min = runCronNext('*/5 * * * *');
  t.ok(every5Min, 'every 5 minutes returns a value');

  t.section('cronNext — weekday only');

  const weekday = runCronNext('0 9 * * 1-5');
  t.ok(weekday, 'weekday schedule returns a value');

  t.section('cronNext — invalid inputs');

  t.equal(runCronNext(''), '', 'empty string returns empty');
  t.equal(runCronNext('not a cron'), '', 'bad format returns empty');
  t.equal(runCronNext('* * *'), '', 'too few fields returns empty');

  t.section('cronNext — impossible date (Feb 31)');

  t.equal(runCronNext('0 0 31 2 *'), '', 'Feb 31 returns empty (impossible)');

  t.section('loadCcStatus — returns structure');

  const result = runStatusLoad();
  t.ok(result, 'status load returns result');
  if (!result) return;

  const status = result.status;
  t.ok(status, 'loadCcStatus returns a value');
  if (status) {
    t.ok(Array.isArray(status.skills), 'has skills array');
    t.ok(typeof status.hooks === 'object', 'has hooks object');
    t.ok(Array.isArray(status.plugins), 'has plugins array');
    t.ok(Array.isArray(status.tasks), 'has tasks array');
    t.ok(Array.isArray(status.agents), 'has agents array');
  }

  t.section('loadSvcRegistry — returns object');

  const reg = result.reg;
  t.ok(reg, 'loadSvcRegistry returns a value');
  if (reg) {
    t.equal(typeof reg, 'object', 'returns an object');
  }
};
