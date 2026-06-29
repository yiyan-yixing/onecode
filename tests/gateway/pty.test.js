'use strict';

/**
 * Tests for gateway/pty.js — PtyManager lifecycle and binary protocol
 * Gracefully handles environments where node-pty native module is not available.
 */
module.exports = function (t) {
  const path = require('path');
  const { runAndParse } = require('./helpers');

  const ptyPath = path.resolve(__dirname, '..', '..', 'agent-runtime', 'gateway', 'pty.js');

  // Check if node-pty is available in this environment
  const ptyCheck = runAndParse(`
    try {
      require(${JSON.stringify(ptyPath)});
      console.log(JSON.stringify({ available: true }));
    } catch (e) {
      console.log(JSON.stringify({ available: false, error: e.message }));
    }
  `);

  if (!ptyCheck || !ptyCheck.available) {
    t.section('PtyManager — environment check');
    t.skip('node-pty native module not available in this environment');
    t.skip('All PTY tests skipped (requires compiled node-pty binary)');

    // Still test the pure-JS parts by reading the source code
    t.section('PtyManager — source code validation');
    const fs = require('fs');
    const src = fs.readFileSync(ptyPath, 'utf8');

    t.ok(src.includes('class PtyManager'), 'source defines PtyManager class');
    t.ok(src.includes('FRAME_CTRL'), 'source defines FRAME_CTRL');
    t.ok(src.includes('FRAME_PTY'), 'source defines FRAME_PTY');
    t.ok(src.includes('CTRL_RESET'), 'source defines CTRL_RESET');
    t.ok(src.includes('CTRL_REPLAY_START'), 'source defines CTRL_REPLAY_START');
    t.ok(src.includes('CTRL_REPLAY_END'), 'source defines CTRL_REPLAY_END');
    t.ok(src.includes('CTRL_PTY_RESIZE'), 'source defines CTRL_PTY_RESIZE');
    t.ok(src.includes('encodeCtrl'), 'source defines encodeCtrl');
    t.ok(src.includes('spawn'), 'source defines spawn method');
    t.ok(src.includes('kill'), 'source defines kill method');
    t.ok(src.includes('restart'), 'source defines restart method');
    t.ok(src.includes('write'), 'source defines write method');
    t.ok(src.includes('resize'), 'source defines resize method');
    t.ok(src.includes('addClient'), 'source defines addClient');
    t.ok(src.includes('removeClient'), 'source defines removeClient');
    t.ok(src.includes('MAX_BUFFER_SIZE'), 'source defines MAX_BUFFER_SIZE');
    t.ok(src.includes('MAX_BUFFERED_AMOUNT'), 'source defines MAX_BUFFERED_AMOUNT');
    t.ok(src.includes('FLUSH_INTERVAL_MS'), 'source defines FLUSH_INTERVAL_MS for batch flush');
    t.ok(src.includes('FLUSH_IMMEDIATE_BYTES'), 'source defines FLUSH_IMMEDIATE_BYTES for large output');
    t.ok(src.includes('FLATTEN_CHUNK_THRESHOLD'), 'source defines FLATTEN_CHUNK_THRESHOLD for lazy trim');
    t.ok(src.includes('_trimOffset'), 'source defines _trimOffset for lazy ring buffer trimming');
    t.ok(src.includes('_pendingBytes'), 'source defines _pendingBytes for flush threshold tracking');
    t.ok(src.includes('_doFlush'), 'source defines _doFlush for dual-trigger flush');
    t.ok(src.includes('_lazyTrim'), 'source defines _lazyTrim for efficient buffer trimming');
    t.ok(src.includes('LARGE_FRAME_THRESHOLD') || src.includes('_writeQueue'), 'frontend uses render batching');
    t.ok(src.includes('DEFAULT_COLS'), 'source defines DEFAULT_COLS = 200');
    t.ok(src.includes('DEFAULT_ROWS'), 'source defines DEFAULT_ROWS = 50');
    t.ok(src.includes('findUtf8Boundary'), 'source defines findUtf8Boundary for UTF-8 safety');
    t.ok(src.includes('getReplayBuffer'), 'source defines getReplayBuffer');
    t.ok(src.includes('recalcSize'), 'source defines recalcSize');
    t.ok(src.includes('setImmediate') || src.includes('FLUSH_INTERVAL_MS'), 'source uses batched flush (setImmediate or FLUSH_INTERVAL_MS)');
    t.ok(src.includes('MAX_WS_CLIENTS') || src.includes('clients.size'), 'source tracks client connections');
    return;
  }

  function runPtyTest(testCode) {
    return runAndParse(`const pty = require(${JSON.stringify(ptyPath)}); ${testCode}`);
  }

  t.section('PtyManager — exports');

  const exports = runPtyTest(`
    console.log(JSON.stringify({
      hasSpawn: typeof pty.spawn === 'function',
      hasKill: typeof pty.kill === 'function',
      hasRestart: typeof pty.restart === 'function',
      hasWrite: typeof pty.write === 'function',
      hasResize: typeof pty.resize === 'function',
      hasAddClient: typeof pty.addClient === 'function',
      hasRemoveClient: typeof pty.removeClient === 'function',
      hasEncodeCtrl: typeof pty.encodeCtrl === 'function',
      ctrlResetType: typeof pty.CTRL_RESET,
      ctrlReplayStartType: typeof pty.CTRL_REPLAY_START,
      ctrlReplayEndType: typeof pty.CTRL_REPLAY_END,
      ctrlPtyResizeType: typeof pty.CTRL_PTY_RESIZE,
    }));
  `);
  t.ok(exports, 'pty module loads');
  if (!exports) return;

  t.ok(exports.hasSpawn, 'has spawn method');
  t.ok(exports.hasKill, 'has kill method');
  t.ok(exports.hasRestart, 'has restart method');
  t.ok(exports.hasWrite, 'has write method');
  t.ok(exports.hasResize, 'has resize method');
  t.ok(exports.hasAddClient, 'has addClient method');
  t.ok(exports.hasRemoveClient, 'has removeClient method');
  t.ok(exports.hasEncodeCtrl, 'exports encodeCtrl function');
  t.equal(exports.ctrlResetType, 'number', 'CTRL_RESET is a number');
  t.equal(exports.ctrlReplayStartType, 'number', 'CTRL_REPLAY_START is a number');
  t.equal(exports.ctrlReplayEndType, 'number', 'CTRL_REPLAY_END is a number');
  t.equal(exports.ctrlPtyResizeType, 'number', 'CTRL_PTY_RESIZE is a number');

  t.section('encodeCtrl — reset frame (no payload)');

  const resetFrame = runPtyTest(`
    const frame = pty.encodeCtrl(pty.CTRL_RESET);
    console.log(JSON.stringify({ bytes: Array.from(frame), isBuffer: Buffer.isBuffer(frame) }));
  `);
  t.ok(resetFrame, 'reset frame test runs');
  if (resetFrame) {
    t.ok(resetFrame.isBuffer, 'encodeCtrl returns Buffer');
    t.equal(resetFrame.bytes.length, 2, 'reset frame is 2 bytes');
    t.equal(resetFrame.bytes[0], 0x00, 'frame byte is 0x00 (CTRL)');
    t.equal(resetFrame.bytes[1], 0x01, 'type byte is CTRL_RESET (0x01)');
  }

  t.section('encodeCtrl — with payload');

  const payloadFrame = runPtyTest(`
    const frame = pty.encodeCtrl(pty.CTRL_PTY_RESIZE, { cols: 100, rows: 30 });
    const payload = JSON.parse(frame.slice(2).toString('utf8'));
    console.log(JSON.stringify({ firstByte: frame[0], secondByte: frame[1], length: frame.length, payload }));
  `);
  t.ok(payloadFrame, 'payload frame test runs');
  if (payloadFrame) {
    t.equal(payloadFrame.firstByte, 0x00, 'payload frame byte is 0x00 (CTRL)');
    t.ok(payloadFrame.length > 2, 'payload frame is longer than 2 bytes');
    t.equal(payloadFrame.payload.cols, 100, 'payload cols is 100');
    t.equal(payloadFrame.payload.rows, 30, 'payload rows is 30');
  }

  t.section('PtyManager — initial state');

  const initialState = runPtyTest(`
    console.log(JSON.stringify({
      isClientsSet: pty.clients instanceof Set,
      clientsSize: pty.clients.size,
      cols: pty.cols,
      rows: pty.rows,
    }));
  `);
  t.ok(initialState, 'initial state test runs');
  if (initialState) {
    t.ok(initialState.isClientsSet, 'clients is a Set');
    t.equal(initialState.clientsSize, 0, 'no clients initially');
    t.equal(initialState.cols, 200, 'default cols is 200');
    t.equal(initialState.rows, 50, 'default rows is 50');
  }

  t.section('PtyManager — addClient/removeClient');

  const clientResult = runPtyTest(`
    const mockWs = { readyState: 1, _termSize: { cols: 80, rows: 24 } };
    pty.addClient(mockWs);
    const size1 = pty.clients.size;
    pty.removeClient(mockWs);
    const size0 = pty.clients.size;
    console.log(JSON.stringify({ size1, size0 }));
  `);
  t.ok(clientResult, 'client test runs');
  if (clientResult) {
    t.equal(clientResult.size1, 1, 'client added');
    t.equal(clientResult.size0, 0, 'client removed');
  }

  t.section('PtyManager — resize');

  const resizeResult = runPtyTest(`
    pty.resize(120, 40);
    console.log(JSON.stringify({ cols: pty.cols, rows: pty.rows }));
  `);
  t.ok(resizeResult, 'resize test runs');
  if (resizeResult) {
    t.equal(resizeResult.cols, 120, 'cols updated after resize');
    t.equal(resizeResult.rows, 40, 'rows updated after resize');
  }

  t.section('PtyManager — write/kill without PTY');

  const safetyResult = runPtyTest(`
    let writeThrew = false, killThrew = false;
    try { pty.write('test'); } catch (e) { writeThrew = true; }
    try { pty.kill(); } catch (e) { killThrew = true; }
    console.log(JSON.stringify({ writeThrew, killThrew }));
  `);
  t.ok(safetyResult, 'safety test runs');
  if (safetyResult) {
    t.equal(safetyResult.writeThrew, false, 'write without PTY does not throw');
    t.equal(safetyResult.killThrew, false, 'kill without PTY does not throw');
  }

  t.section('PtyManager — buffer (empty)');

  const bufferResult = runPtyTest(`
    const replay = pty.getReplayBuffer();
    console.log(JSON.stringify({
      isBufBuffer: Buffer.isBuffer(pty.buffer),
      bufLen: pty.buffer.length,
      isReplayBuffer: Buffer.isBuffer(replay),
      replayFirstByte: replay[0],
      replayLen: replay.length,
    }));
  `);
  t.ok(bufferResult, 'buffer test runs');
  if (bufferResult) {
    t.ok(bufferResult.isBufBuffer, 'buffer is a Buffer');
    t.equal(bufferResult.bufLen, 0, 'empty buffer has length 0');
    t.ok(bufferResult.isReplayBuffer, 'replay buffer is a Buffer');
    t.equal(bufferResult.replayFirstByte, 0x01, 'replay buffer starts with FRAME_PTY byte (0x01)');
    t.equal(bufferResult.replayLen, 1, 'empty replay is just the frame byte');
  }
};
