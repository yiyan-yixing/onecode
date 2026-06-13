'use strict';

const path = require('path');
const fs = require('fs');

const PORT = parseInt(process.env.GATEWAY_PORT || '7681', 10);
const FB_PORT = parseInt(process.env.FB_PORT || '8081', 10);
const VSCODE_PORT = parseInt(process.env.VSCODE_INTERNAL_PORT || '8082', 10);
const TERM_TOKEN = process.env.TERM_TOKEN || process.env.TTYD_TOKEN || '';
const TERM_COLS = parseInt(process.env.TERM_COLS || '200', 10);
const TERM_ROWS = parseInt(process.env.TERM_ROWS || '50', 10);

const STATIC_DIR = path.join(__dirname, 'static');
let VERSION = '';
try {
  VERSION = fs.readFileSync(path.join(__dirname, '..', 'VERSION'), 'utf8').trim();
} catch (_) {}

const BRAND_NAME = 'OneCode';

const SVC_REGISTRY = process.env.SVC_REGISTRY || path.join('/home/work', '.svc-registry');
const GLOBAL_DIR = path.join('/home/work', '.claude');
const PROJECT_DIR = path.join(process.env.WORKSPACE_DIR || process.cwd(), '.claude');

module.exports = {
  PORT, FB_PORT, VSCODE_PORT, TERM_TOKEN, TERM_COLS, TERM_ROWS,
  STATIC_DIR, VERSION, BRAND_NAME,
  SVC_REGISTRY, GLOBAL_DIR, PROJECT_DIR,
};
