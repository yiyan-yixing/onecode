'use strict';

const fs = require('fs');
const fsp = fs.promises;
const path = require('path');
const { SVC_REGISTRY, GLOBAL_DIR, PROJECT_DIR } = require('./config');

function cronNext(expr) {
  if (!expr || typeof expr !== 'string') {
    return '';
  }
  const fields = expr.trim().split(/\s+/);
  if (fields.length !== 5) {
    return '';
  }
  const now = new Date();
  const start = new Date(
    now.getFullYear(), now.getMonth(), now.getDate(),
    now.getHours(), now.getMinutes() + 1, 0, 0,
  );
  function expand(field, min, max) {
    const vals = new Set();
    for (const part of field.split(',')) {
      if (part === '*') {
        for (let i = min; i <= max; i++) {
          vals.add(i);
        }
      } else if (part.includes('/')) {
        const [range, step] = part.split('/');
        const s = parseInt(step, 10) || 1;
        let lo = min;
        let hi = max;
        if (range !== '*') {
          const p = range.split('-');
          lo = parseInt(p[0], 10);
          hi = p.length > 1 ? parseInt(p[1], 10) : lo;
        }
        for (let i = lo; i <= hi; i += s) {
          vals.add(i);
        }
      } else if (part.includes('-')) {
        const [a, b] = part.split('-').map(Number);
        for (let i = a; i <= b; i++) {
          vals.add(i);
        }
      } else {
        vals.add(parseInt(part, 10));
      }
    }
    return vals;
  }
  const mins = expand(fields[0], 0, 59);
  const hrs = expand(fields[1], 0, 23);
  const doms = expand(fields[2], 1, 31);
  const mons = expand(fields[3], 1, 12);
  const dows = expand(fields[4], 0, 6);
  // Early exit: check for impossible day-of-month/month combinations
  // (e.g. "0 0 31 2 *" — Feb 31 never exists). If the smallest month
  // in the set can't contain the smallest day, no match is possible.
  if (doms.size > 0 && mons.size > 0) {
    const maxDayByMonth = { 1: 31, 2: 29, 3: 31, 4: 30, 5: 31, 6: 30, 7: 31, 8: 31, 9: 30, 10: 31, 11: 30, 12: 31 };
    let possible = false;
    for (const m of mons) {
      if (maxDayByMonth[m] >= Math.min(...doms)) {
        possible = true;
        break;
      }
    }
    if (!possible) {
      return '';
    }
  }
  // Standard cron: when both DOM and DOW are specified (neither is '*'), the job
  // runs when EITHER matches (OR logic). When one is '*', the other must match (AND).
  var domIsStar = fields[2] === '*';
  var dowIsStar = fields[4] === '*';
  function dayMatches(month, day, dow) {
    if (!mons.has(month + 1)) {
      return false;
    }
    if (domIsStar && dowIsStar) {
      return doms.has(day) || dows.has(dow);
    }
    if (domIsStar) {
      return dows.has(dow) && doms.has(day);
    }
    if (dowIsStar) {
      return doms.has(day) && dows.has(dow);
    }
    // Both specified: OR logic (standard Vixie cron behavior)
    return doms.has(day) || dows.has(dow);
  }
  var iterations = 0;
  var MAX_CRON_ITER = 500;
  for (let d = new Date(start.getTime());
    d.getTime() - start.getTime() < 366 * 86400000;
    d.setHours(0, 0, 0, 0), d.setDate(d.getDate() + 1)) {
    if (!dayMatches(d.getMonth(), d.getDate(), d.getDay())) {
      continue;
    }
    for (const hr of hrs) {
      d.setHours(hr);
      if (d < start) {
        continue;
      }
      for (const min of mins) {
        d.setMinutes(min);
        if (d < start) {
          continue;
        }
        if (++iterations > MAX_CRON_ITER) {
          return '';
        }
        const diff = d.getTime() - now.getTime();
        if (diff < 60000) {
          return '< 1m';
        }
        if (diff < 3600000) {
          return Math.floor(diff / 60000) + 'm';
        }
        if (diff < 86400000) {
          return Math.floor(diff / 3600000) + 'h ' + Math.floor((diff % 3600000) / 60000) + 'm';
        }
        return Math.floor(diff / 86400000) + 'd ' + Math.floor((diff % 86400000) / 3600000) + 'h';
      }
    }
  }
  return '';
}

// --- Async loaders (non-blocking, used for all reads) ---

async function loadCcStatusAsync() {
  var result = { skills: [], hooks: {}, plugins: [], tasks: [], agents: [] };

  async function readFile(fp) {
    try {
      return await fsp.readFile(fp, 'utf8');
    } catch (_) {
      return null;
    }
  }

  async function readJson(fp) {
    var data = await readFile(fp);
    if (data === null) {
      return null;
    }
    try {
      return JSON.parse(data);
    } catch (_) {
      return null;
    }
  }

  async function loadSkills(dir, scope) {
    const skillsDir = path.join(dir, 'skills');
    async function scanDir(currentDir) {
      var entries;
      try {
        const st = await fsp.stat(currentDir);
        if (!st.isDirectory()) {
          return;
        }
        entries = await fsp.readdir(currentDir);
      } catch (_) {
        return;
      }
      for (const entry of entries) {
        if (entry.startsWith('.')) {
          continue;
        }
        const fp = path.join(currentDir, entry);
        try {
          const st = await fsp.stat(fp);
          if (st.isDirectory()) {
            const content = await readFile(path.join(fp, 'SKILL.md'));
            if (content !== null) {
              const fm = content.match(/^---\n([\s\S]*?)\n---/);
              if (fm) {
                const name = (fm[1].match(/name:\s*(.+)/) || [])[1]?.trim() || entry;
                const desc = (fm[1].match(/description:\s*(.+)/) || [])[1]?.trim() || '';
                result.skills.push({ name, description: desc, scope });
              } else {
                const name = entry;
                const firstLine = content.split('\n').find(l => l.trim().startsWith('#'));
                const desc = firstLine ? firstLine.replace(/^#+\s*/, '').trim() : '';
                result.skills.push({ name, description: desc, scope });
              }
            } else {
              await scanDir(fp);
            }
          } else if (st.isFile() && entry.endsWith('.md')) {
            const content = await readFile(fp);
            if (content === null) {
              continue;
            }
            const fm = content.match(/^---\n([\s\S]*?)\n---/);
            if (fm) {
              const name = (fm[1].match(/name:\s*(.+)/) || [])[1]?.trim() || entry.replace(/\.md$/, '');
              const desc = (fm[1].match(/description:\s*(.+)/) || [])[1]?.trim() || '';
              result.skills.push({ name, description: desc, scope });
            } else {
              const name = entry.replace(/\.md$/, '');
              const firstLine = content.split('\n').find(l => l.trim().startsWith('#'));
              const desc = firstLine ? firstLine.replace(/^#+\s*/, '').trim() : '';
              result.skills.push({ name, description: desc, scope });
            }
          }
        } catch (_) {}
      }
    }
    await scanDir(skillsDir);
  }

  async function loadHooks(dir, scope) {
    for (const f of ['settings.json', 'settings.local.json']) {
      const s = await readJson(path.join(dir, f));
      if (s && s.hooks) {
        for (const [event, hookList] of Object.entries(s.hooks)) {
          if (!result.hooks[event]) {
            result.hooks[event] = [];
          }
          for (const h of hookList) {
            if (h.hooks) {
              for (const sub of h.hooks) {
                result.hooks[event].push({
                  type: sub.type,
                  command: sub.command || '',
                  message: sub.message || '',
                  scope,
                });
              }
            }
          }
        }
      }
    }
  }

  async function loadPlugins(dir, scope) {
    for (const f of ['settings.json', 'settings.local.json']) {
      const s = await readJson(path.join(dir, f));
      if (s && s.mcpServers) {
        for (const [name, cfg] of Object.entries(s.mcpServers)) {
          result.plugins.push({
            name,
            type: cfg.type || '',
            command: cfg.command || '',
            args: cfg.args || [],
            scope,
          });
        }
      }
    }
  }

  async function loadTasks(dir, scope) {
    const seenIds = new Set();
    async function loadTaskFile(fp) {
      const raw = await readJson(fp);
      if (!raw) {
        return;
      }
      const tasks = Array.isArray(raw) ? raw : (Array.isArray(raw.tasks) ? raw.tasks : []);
      for (const t of tasks) {
        const id = t.id || t.cron + (t.prompt || t.name || '');
        if (seenIds.has(id)) {
          continue;
        }
        seenIds.add(id);
        result.tasks.push({
          name: t.name || t.prompt?.slice(0, 60),
          prompt: t.prompt || '',
          cron: t.cron,
          recurring: t.recurring,
          nextRun: cronNext(t.cron),
          scope,
        });
      }
    }
    await loadTaskFile(path.join(dir, 'scheduled_tasks.json'));
    await loadTaskFile(path.join(dir, 'cron-session.json'));
  }

  async function loadAgents(dir, scope) {
    const agentsDir = path.join(dir, 'agents');
    var entries;
    try {
      const st = await fsp.stat(agentsDir);
      if (!st.isDirectory()) {
        return;
      }
      entries = await fsp.readdir(agentsDir);
    } catch (_) {
      return;
    }
    for (const entry of entries) {
      if (entry.startsWith('.') || !entry.endsWith('.md')) {
        continue;
      }
      const fp = path.join(agentsDir, entry);
      try {
        const content = await readFile(fp);
        if (content === null) {
          continue;
        }
        const fm = content.match(/^---\n([\s\S]*?)\n---/);
        if (!fm) {
          continue;
        }
        const name = (fm[1].match(/name:\s*(.+)/) || [])[1]?.trim();
        if (!name) {
          continue;
        }
        const id = entry.replace(/\.md$/, '');
        const description = (fm[1].match(/description:\s*(.+)/) || [])[1]?.trim() || '';
        const tools = (fm[1].match(/tools:\s*(.+)/) || [])[1]?.trim() || '';
        const model = (fm[1].match(/model:\s*(.+)/) || [])[1]?.trim() || '';
        const color = (fm[1].match(/color:\s*(.+)/) || [])[1]?.trim() || '';
        const icon = (fm[1].match(/icon:\s*(.+)/) || [])[1]?.trim() || '';
        result.agents.push({ id, name, description, tools, model, color, icon, scope });
      } catch (_) {}
    }
  }

  await loadSkills(PROJECT_DIR, 'project');
  await loadSkills(GLOBAL_DIR, 'global');
  await loadHooks(PROJECT_DIR, 'project');
  await loadHooks(GLOBAL_DIR, 'global');
  await loadPlugins(PROJECT_DIR, 'project');
  await loadPlugins(GLOBAL_DIR, 'global');
  await loadTasks(PROJECT_DIR, 'project');
  await loadTasks(GLOBAL_DIR, 'global');
  await loadAgents(PROJECT_DIR, 'project');
  await loadAgents(GLOBAL_DIR, 'global');

  return result;
}

async function loadSvcRegistryAsync() {
  var reg = {};
  try {
    var data = await fsp.readFile(SVC_REGISTRY, 'utf8');
    for (var line of data.split('\n')) {
      var trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) {
        continue;
      }
      var parts = trimmed.split(/[\t\s]+/);
      var name = parts[0];
      var port = parseInt(parts[1], 10);
      if (name && port > 0 && port < 65536) {
        reg[name] = port;
      }
    }
  } catch (_) {}
  return reg;
}

// TTL-based cache with on-demand async refresh — no sync I/O ever blocks the event loop.
var _ccStatusCache = null;
var _ccStatusCacheTime = 0;
var CC_STATUS_TTL = 5000; // 5 seconds
var _ccRefreshInProgress = false;

function getCcStatus() {
  var now = Date.now();
  if (_ccStatusCache && (now - _ccStatusCacheTime < CC_STATUS_TTL * 2)) {
    // Trigger async refresh in background if TTL expired but still within 2x
    if (now - _ccStatusCacheTime >= CC_STATUS_TTL && !_ccRefreshInProgress) {
      _ccRefreshInProgress = true;
      loadCcStatusAsync().then(function (data) {
        _ccStatusCache = data;
        _ccStatusCacheTime = Date.now();
        _ccRefreshInProgress = false;
      }).catch(function () {
        _ccRefreshInProgress = false;
      });
    }
    return _ccStatusCache;
  }
  // Cache miss or fully expired — kick off async refresh, return stale or empty
  if (!_ccRefreshInProgress) {
    _ccRefreshInProgress = true;
    loadCcStatusAsync().then(function (data) {
      _ccStatusCache = data;
      _ccStatusCacheTime = Date.now();
      _ccRefreshInProgress = false;
    }).catch(function () {
      _ccRefreshInProgress = false;
    });
  }
  return _ccStatusCache || { skills: [], hooks: {}, plugins: [], tasks: [], agents: [] };
}

var _svcRegCache = null;
var _svcRegCacheTime = 0;
var SVC_REG_TTL = 5000;
var _svcRefreshInProgress = false;

function getSvcRegistry() {
  var now = Date.now();
  if (_svcRegCache && (now - _svcRegCacheTime < SVC_REG_TTL * 2)) {
    // Trigger async refresh in background if TTL expired
    if (now - _svcRegCacheTime >= SVC_REG_TTL && !_svcRefreshInProgress) {
      _svcRefreshInProgress = true;
      loadSvcRegistryAsync().then(function (data) {
        _svcRegCache = data;
        _svcRegCacheTime = Date.now();
        _svcRefreshInProgress = false;
      }).catch(function () {
        _svcRefreshInProgress = false;
      });
    }
    return _svcRegCache;
  }
  // Cache miss — async refresh, return stale or empty
  if (!_svcRefreshInProgress) {
    _svcRefreshInProgress = true;
    loadSvcRegistryAsync().then(function (data) {
      _svcRegCache = data;
      _svcRegCacheTime = Date.now();
      _svcRefreshInProgress = false;
    }).catch(function () {
      _svcRefreshInProgress = false;
    });
  }
  return _svcRegCache || {};
}

module.exports = { loadCcStatus: getCcStatus, loadSvcRegistry: getSvcRegistry, cronNext };
