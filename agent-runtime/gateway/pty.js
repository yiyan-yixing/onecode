'use strict';

const pty = require('node-pty');
const { EventEmitter } = require('events');

const DEFAULT_COLS = 200;
const DEFAULT_ROWS = 50;
const MAX_BUFFER_SIZE = 10 * 1024 * 1024; // 10MB ring buffer
const MAX_BUFFERED_AMOUNT = 1024 * 1024; // 1MB — kick slow clients beyond this

// Find the next valid UTF-8 leading byte position from offset.
function findUtf8Boundary(buf, offset) {
  for (var i = offset; i < buf.length; i++) {
    if ((buf[i] & 0xC0) !== 0x80) {
      return i;
    }
  }
  return buf.length;
}

// Binary protocol: control messages use frame byte 0x00, PTY data uses 0x01
// This avoids any ambiguity with text content
var FRAME_CTRL = 0x00;
var FRAME_PTY = 0x01;

// Control message types (single byte after frame byte)
var CTRL_RESET = 0x01;
var CTRL_REPLAY_START = 0x02;
var CTRL_REPLAY_END = 0x03;
var CTRL_PTY_RESIZE = 0x04;

function encodeCtrl(type, payload) {
  if (payload) {
    var json = JSON.stringify(payload);
    var jsonBuf = Buffer.from(json, 'utf8');
    var frame = Buffer.alloc(2 + jsonBuf.length);
    frame[0] = FRAME_CTRL;
    frame[1] = type;
    jsonBuf.copy(frame, 2);
    return frame;
  }
  // No payload — just [0x00][type]
  var frame = Buffer.alloc(2);
  frame[0] = FRAME_CTRL;
  frame[1] = type;
  return frame;
}

class PtyManager extends EventEmitter {
  constructor() {
    super();
    this.ptyProcess = null;
    this.clients = new Set();
    this._chunks = [];
    this._bufferLength = 0;
    this.cols = DEFAULT_COLS;
    this.rows = DEFAULT_ROWS;
    this._cmd = null;
    this._args = null;
    this._env = null;
    this._restartTimer = null;
    this._restartCount = 0;
    this._replayDirty = true;
    this._cachedReplay = null;
    this._sendPending = false;
    this._pendingChunks = [];
    this._restarting = false;
  }

  spawn(cmd, args, env) {
    this._cmd = cmd;
    this._args = args || [];
    this._env = env || {};
    this._restartCount = 0;
    this._createPty();
  }

  _createPty() {
    if (this.ptyProcess) {
      try {
        this.ptyProcess.kill();
      } catch (_) {}
    }
    var self = this;
    var p = pty.spawn(this._cmd, this._args, {
      name: 'xterm-256color',
      cols: this.cols,
      rows: this.rows,
      cwd: process.env.WORKSPACE_DIR || '/workspace',
      env: { ...process.env, ...this._env, TERM: 'xterm-256color' },
    });
    this.ptyProcess = p;
    this._chunks = [];
    this._bufferLength = 0;
    this._replayDirty = true;

    p.onData((data) => {
      if (self.ptyProcess !== p) {
        return;
      }
      var buf = Buffer.from(data, 'utf8');
      self._chunks.push(buf);
      self._bufferLength += buf.length;
      self._replayDirty = true;
      // No clients: discard buffer aggressively to save memory
      // (replay is useless while nobody is watching)
      if (self.clients.size === 0 && self._bufferLength > MAX_BUFFER_SIZE / 10) {
        self._chunks = [];
        self._bufferLength = 0;
        self._replayDirty = true;
      }
      // Trim buffer if it exceeds threshold (1.1x to avoid re-trimming on every small chunk)
      if (self._bufferLength > MAX_BUFFER_SIZE * 1.1) {
        self._flattenAndTrim();
      }
      // Batch small chunks via setImmediate to reduce GC pressure from per-chunk
      // Buffer.alloc + copy. Instead of one frame per onData, we merge all pending
      // chunks into a single frame per event-loop iteration.
      self._pendingChunks.push(buf);
      if (!self._sendPending) {
        self._sendPending = true;
        setImmediate(function () {
          self._flushPending(p);
        });
      }
    });

    // Reset restart count after process has been stable for 5 seconds
    setTimeout(function () {
      if (self.ptyProcess === p) {
        self._restartCount = 0;
      }
    }, 5000);

    p.onExit(({ exitCode }) => {
      if (self.ptyProcess !== p) {
        // If restart() set _restarting, it expects onExit to create the new PTY.
        // However, p is the *old* process that was killed by restart(), and
        // self.ptyProcess was set to null by restart() — so the guard above
        // does not catch this case. Check the _restarting flag instead.
        if (!self._restarting) {
          return;
        }
        self._restarting = false;
        self._restartCount = 0; // restart() resets the counter
        self._createPty();
        return;
      }
      self.ptyProcess = null;
      self.emit('exit', exitCode);
      self._restartCount++;
      if (self._restartCount > 10) {
        console.error('[pty] Max restart attempts reached (exitCode=%s), giving up', exitCode);
        return;
      }
      var delay = Math.min(500 * Math.pow(2, self._restartCount - 1), 30000);
      clearTimeout(self._restartTimer);
      self._restartTimer = setTimeout(() => {
        self._restartTimer = null;
        if (!self.ptyProcess) {
          self._createPty();
        }
      }, delay);
    });
  }

  // Flush pending PTY chunks as a single batched frame (called via setImmediate)
  _flushPending(stalePty) {
    this._sendPending = false;
    if (this.ptyProcess !== stalePty) {
      return;
    }
    var chunks = this._pendingChunks;
    this._pendingChunks = [];
    if (chunks.length === 0 || this.clients.size === 0) {
      return;
    }
    // Build one merged frame: [FRAME_PTY][chunk1][chunk2]...
    // Much cheaper than N separate Buffer.alloc + copy per chunk
    var totalLen = 0;
    for (var i = 0; i < chunks.length; i++) {
      totalLen += chunks[i].length;
    }
    var frame = Buffer.alloc(1 + totalLen);
    frame[0] = FRAME_PTY;
    var offset = 1;
    for (var j = 0; j < chunks.length; j++) {
      chunks[j].copy(frame, offset);
      offset += chunks[j].length;
    }
    var toTerminate = [];
    for (var ws of this.clients) {
      if (ws.readyState === 1) {
        if (ws.bufferedAmount > MAX_BUFFERED_AMOUNT) {
          toTerminate.push(ws);
          continue;
        }
        try {
          ws.send(frame);
        } catch (_) {}
      }
    }
    // Terminate slow clients after iteration to avoid modifying Set during iteration
    for (var k = 0; k < toTerminate.length; k++) {
      try {
        toTerminate[k].terminate();
      } catch (_) {}
    }
  }

  // Flatten chunks into a single buffer and trim to MAX_BUFFER_SIZE
  // Memory-conscious: avoids creating a full copy when only the tail is needed
  _flattenAndTrim() {
    if (this._chunks.length === 0) {
      return;
    }
    // Fast path: already a single chunk under the limit
    if (this._chunks.length === 1 && this._chunks[0].length <= MAX_BUFFER_SIZE) {
      this._bufferLength = this._chunks[0].length;
      this._replayDirty = true;
      return;
    }
    // Calculate total size first to decide the trimming strategy
    var totalLen = 0;
    for (var i = 0; i < this._chunks.length; i++) {
      totalLen += this._chunks[i].length;
    }
    if (totalLen <= MAX_BUFFER_SIZE) {
      // Just flatten, no trimming needed
      var flat = Buffer.concat(this._chunks, totalLen);
      this._chunks = [flat];
      this._bufferLength = totalLen;
      this._replayDirty = true;
      return;
    }
    // Need to trim: skip leading chunks that are entirely before the cut point
    var cutAt = totalLen - MAX_BUFFER_SIZE;
    var skipLen = 0;
    var startIdx = 0;
    for (var j = 0; j < this._chunks.length; j++) {
      if (skipLen + this._chunks[j].length > cutAt) {
        break;
      }
      skipLen += this._chunks[j].length;
      startIdx = j + 1;
    }
    // Concat only the tail chunks (from the one containing the cut point onward)
    var tailChunks = this._chunks.slice(startIdx);
    var tailBuf = Buffer.concat(tailChunks, totalLen - skipLen);
    // Trim from the cut point within the first tail chunk
    var localCut = cutAt - skipLen;
    var safeAt = findUtf8Boundary(tailBuf, localCut);
    var trimmed = tailBuf.slice(safeAt);
    this._chunks = [trimmed];
    this._bufferLength = trimmed.length;
    this._replayDirty = true;
  }

  // Get the full replay buffer with FRAME_PTY prefix (cached)
  getReplayBuffer() {
    if (!this._replayDirty && this._cachedReplay) {
      return this._cachedReplay;
    }
    var flat = this._chunks.length === 1 ? this._chunks[0] : Buffer.concat(this._chunks);
    var frame = Buffer.alloc(1 + flat.length);
    frame[0] = FRAME_PTY;
    flat.copy(frame, 1);
    this._cachedReplay = frame;
    this._replayDirty = false;
    return frame;
  }

  // Backward-compatible buffer accessor (for term-ws.js replay case)
  get buffer() {
    if (this._chunks.length === 0) {
      return Buffer.alloc(0);
    }
    if (this._chunks.length === 1) {
      return this._chunks[0];
    }
    return Buffer.concat(this._chunks);
  }

  resizeTo(cols, rows) {
    if (cols === this.cols && rows === this.rows) {
      return;
    }
    this.resize(cols, rows);
  }

  recalcSize() {
    var maxCols = 0;
    var maxRows = 0;
    for (var ws of this.clients) {
      if (ws._termSize) {
        if (ws._termSize.cols > maxCols) {
          maxCols = ws._termSize.cols;
        }
        if (ws._termSize.rows > maxRows) {
          maxRows = ws._termSize.rows;
        }
      }
    }
    if (maxCols && maxRows) {
      this.resizeTo(maxCols, maxRows);
    }
  }

  addClient(ws) {
    this.clients.add(ws);
    if (this._bufferLength > 0 && ws.readyState === 1) {
      this.sendReplay(ws);
    }
  }

  // Send replay buffer to a specific client (used by addClient and term-ws replay command)
  sendReplay(ws) {
    if (ws.readyState !== 1) {
      return;
    }
    try {
      ws.send(encodeCtrl(CTRL_REPLAY_START));
      ws.send(this.getReplayBuffer());
      ws.send(encodeCtrl(CTRL_REPLAY_END));
    } catch (_) {}
  }

  removeClient(ws) {
    this.clients.delete(ws);
  }

  write(data) {
    if (this.ptyProcess) {
      this.ptyProcess.write(data);
    }
  }

  resize(cols, rows) {
    this.cols = cols;
    this.rows = rows;
    if (this.ptyProcess) {
      try {
        this.ptyProcess.resize(cols, rows);
      } catch (_) {}
    }
  }

  kill() {
    clearTimeout(this._restartTimer);
    this._restartTimer = null;
    if (this.ptyProcess) {
      var p = this.ptyProcess;
      // Always null the reference so onExit cannot restart after shutdown
      this.ptyProcess = null;
      try {
        p.kill('SIGKILL');
      } catch (_) {
        // Kill failed (e.g. already exited) — reference already nulled above
      }
    }
  }

  restart() {
    clearTimeout(this._restartTimer);
    this._restartTimer = null;
    this._restarting = false;
    if (this.ptyProcess) {
      // Set flag so onExit handler knows to create new PTY immediately
      this._restarting = true;
      try {
        this.ptyProcess.kill('SIGKILL');
      } catch (_) {}
      this.ptyProcess = null;
    }
    this._chunks = [];
    this._bufferLength = 0;
    this._cachedReplay = null;
    this._replayDirty = true;
    this._pendingChunks = [];
    this._sendPending = false;
    this._restartCount = 0;
    var frame = encodeCtrl(CTRL_RESET);
    for (var ws of this.clients) {
      if (ws.readyState === 1) {
        try {
          ws.send(frame);
        } catch (_) {}
      }
    }
    // If there was no ptyProcess to kill (already exited), create immediately
    if (!this._restarting) {
      this._createPty();
    }
  }
}

var ptyManager = new PtyManager();
module.exports = ptyManager;
module.exports.encodeCtrl = encodeCtrl;
module.exports.CTRL_RESET = CTRL_RESET;
module.exports.CTRL_REPLAY_START = CTRL_REPLAY_START;
module.exports.CTRL_REPLAY_END = CTRL_REPLAY_END;
module.exports.CTRL_PTY_RESIZE = CTRL_PTY_RESIZE;
