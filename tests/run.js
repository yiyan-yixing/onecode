#!/usr/bin/env node
'use strict';

/**
 * OneCode Test Runner
 *
 * Lightweight test framework — zero dependencies.
 * Usage: node tests/run.js [pattern]
 *   pattern: substring match against test file names (e.g. "config" or "router")
 */

const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');

// ── Colors ──────────────────────────────────────────────────────────
const C = {
  reset: '\x1b[0m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  cyan: '\x1b[36m',
  dim: '\x1b[2m',
  bold: '\x1b[1m',
};

// ── Global test state ───────────────────────────────────────────────
let totalSuites = 0;
let totalPassed = 0;
let totalFailed = 0;
let totalSkipped = 0;
const failures = [];

// ── Simple test context (used by each test file) ───────────────────
class TestContext {
  constructor(suiteName) {
    this.suiteName = suiteName;
    this.passed = 0;
    this.failed = 0;
    this.skipped = 0;
    this.currentSection = '';
  }

  section(name) {
    this.currentSection = name;
    console.log(`\n  ${C.cyan}▸ ${name}${C.reset}`);
  }

  assert(condition, label) {
    if (condition) {
      this.passed++;
      totalPassed++;
      console.log(`    ${C.green}✓${C.reset} ${label}`);
    } else {
      this.failed++;
      totalFailed++;
      failures.push({ suite: this.suiteName, section: this.currentSection, label });
      console.log(`    ${C.red}✗${C.reset} ${label}`);
    }
  }

  equal(actual, expected, label) {
    const pass = actual === expected;
    if (!pass) {
      this.assert(false, `${label} — expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
    } else {
      this.assert(true, label);
    }
  }

  deepEqual(actual, expected, label) {
    const pass = JSON.stringify(actual) === JSON.stringify(expected);
    if (!pass) {
      this.assert(false, `${label} — expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
    } else {
      this.assert(true, label);
    }
  }

  notEqual(actual, expected, label) {
    this.assert(actual !== expected, label);
  }

  ok(value, label) {
    this.assert(!!value, label);
  }

  throws(fn, label) {
    let threw = false;
    try {
      fn();
    } catch (_) {
      threw = true;
    }
    this.assert(threw, label);
  }

  doesNotThrow(fn, label) {
    let threw = false;
    try {
      fn();
    } catch (e) {
      threw = true;
    }
    this.assert(!threw, label || 'does not throw');
  }

  skip(label) {
    this.skipped++;
    totalSkipped++;
    console.log(`    ${C.yellow}○${C.reset} ${label} (skipped)`);
  }
}

// ── Discover and run test files ─────────────────────────────────────
const TESTS_DIR = path.join(__dirname);

function discoverTests(pattern) {
  const files = [];

  // Node.js gateway tests
  const gwDir = path.join(TESTS_DIR, 'gateway');
  if (fs.existsSync(gwDir)) {
    for (const f of fs.readdirSync(gwDir).sort()) {
      if (f.endsWith('.test.js')) {
        if (!pattern || f.includes(pattern) || 'gateway'.includes(pattern)) {
          files.push(path.join(gwDir, f));
        }
      }
    }
  }

  // Bash CLI tests
  const cliDir = path.join(TESTS_DIR, 'cli');
  if (fs.existsSync(cliDir)) {
    for (const f of fs.readdirSync(cliDir).sort()) {
      if (f.endsWith('.test.sh')) {
        if (!pattern || f.includes(pattern) || 'cli'.includes(pattern)) {
          files.push(path.join(cliDir, f));
        }
      }
    }
  }

  return files;
}

function runNodeTest(filePath) {
  const name = path.basename(filePath, '.test.js');
  const suite = new TestContext(name);
  totalSuites++;

  console.log(`\n${C.bold}${C.cyan}[${name}]${C.reset}`);

  try {
    const testFn = require(filePath);
    if (typeof testFn === 'function') {
      testFn(suite);
    }
  } catch (e) {
    console.log(`  ${C.red}SUITE ERROR: ${e.message}${C.reset}`);
    suite.assert(false, `Suite setup failed: ${e.message}`);
  }

  return suite;
}

function runBashTest(filePath) {
  const name = path.basename(filePath, '.test.sh');
  totalSuites++;

  console.log(`\n${C.bold}${C.cyan}[${name}]${C.reset}`);

  try {
    const output = execSync(`bash "${filePath}" 2>&1`, {
      cwd: path.join(__dirname, '..'),
      timeout: 30000,
      encoding: 'utf8',
      env: {
        ...process.env,
        OC_HOME: `/tmp/onecode-test-${Date.now()}`,
        PATH: `${path.join(__dirname, '..', 'agent-runtime', 'bin')}:${process.env.PATH}`,
      },
    });

    // Parse TAP-like output from bash tests
    const lines = output.split('\n');
    let suitePassed = 0;
    let suiteFailed = 0;
    for (const line of lines) {
      const passMatch = line.match(/^PASS\s+(.*)/);
      const failMatch = line.match(/^FAIL\s+(.*)/);
      if (passMatch) {
        suitePassed++;
        totalPassed++;
        console.log(`    ${C.green}✓${C.reset} ${passMatch[1]}`);
      } else if (failMatch) {
        suiteFailed++;
        totalFailed++;
        failures.push({ suite: name, section: 'bash', label: failMatch[1] });
        console.log(`    ${C.red}✗${C.reset} ${failMatch[1]}`);
      }
    }
  } catch (e) {
    // bash test exited with error — parse partial output
    const output = e.stdout || e.output || '';
    const lines = output.split('\n');
    for (const line of lines) {
      const passMatch = line.match(/^PASS\s+(.*)/);
      const failMatch = line.match(/^FAIL\s+(.*)/);
      if (passMatch) {
        totalPassed++;
        console.log(`    ${C.green}✓${C.reset} ${passMatch[1]}`);
      } else if (failMatch) {
        totalFailed++;
        failures.push({ suite: name, section: 'bash', label: failMatch[1] });
        console.log(`    ${C.red}✗${C.reset} ${failMatch[1]}`);
      }
    }
    const stderr = e.stderr || '';
    if (stderr.trim()) {
      console.log(`    ${C.red}ERROR: ${stderr.trim().split('\n')[0]}${C.reset}`);
    }
  }
}

// ── Main ────────────────────────────────────────────────────────────
const pattern = process.argv[2] || '';
const testFiles = discoverTests(pattern);

if (testFiles.length === 0) {
  console.log(`${C.yellow}No test files found${pattern ? ` matching "${pattern}"` : ''}.${C.reset}`);
  process.exit(0);
}

console.log(`${C.bold}OneCode Test Runner${C.reset}`);
console.log(`${C.dim}Found ${testFiles.length} test file(s)${C.reset}`);

const startTime = Date.now();

for (const filePath of testFiles) {
  if (filePath.endsWith('.test.js')) {
    runNodeTest(filePath);
  } else if (filePath.endsWith('.test.sh')) {
    runBashTest(filePath);
  }
}

const elapsed = ((Date.now() - startTime) / 1000).toFixed(2);

// ── Summary ─────────────────────────────────────────────────────────
console.log(`\n${'─'.repeat(60)}`);
console.log(`${C.bold}Results:${C.reset}  ${totalSuites} suites, ${totalPassed + totalFailed + totalSkipped} assertions`);
console.log(`  ${C.green}${totalPassed} passed${C.reset}, ${C.red}${totalFailed} failed${C.reset}, ${C.yellow}${totalSkipped} skipped${C.reset}`);
console.log(`  Time: ${elapsed}s`);

if (failures.length > 0) {
  console.log(`\n${C.red}${C.bold}Failures:${C.reset}`);
  for (const f of failures) {
    console.log(`  ${C.red}✗${C.reset} [${f.suite}${f.section ? '/' + f.section : ''}] ${f.label}`);
  }
}

console.log('');
process.exit(totalFailed > 0 ? 1 : 0);
