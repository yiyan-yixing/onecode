'use strict';

const { WebSocketServer } = require('ws');
const ptyManager = require('./pty');
const config = require('./config');

const RESIZE_DEBOUNCE_MS = 150;
const MAX_WS_CLIENTS = 20;
const HEARTBEAT_INTERVAL_MS = 30000;

function setupTerminalWebSocket(server) {
  var wss = new WebSocketServer({ noServer: true });
  wss.on('error', function (err) {
    console.error('[term-ws] WSS error:', err.message);
  });

  // Intercept upgrade requests for /ws/term before the existing proxy handler
  server.on('upgrade', function termUpgrade(req, socket, head) {
    var url = req.url.split('?')[0];
    if (url !== '/ws/term') {
      return; // not our path, let other handlers process
    }

    // Token validation
    var token = config.TERM_TOKEN;
    if (token) {
      var params = new URL(req.url, 'http://localhost').searchParams;
      if (params.get('token') !== token) {
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
        socket.destroy();
        return;
      }
    }

    wss.handleUpgrade(req, socket, head, function (ws) {
      wss.emit('connection', ws, req);
    });
  });

  wss.on('connection', function (ws) {
    // Connection limit — check BEFORE adding client to avoid replay waste
    if (ptyManager.clients.size >= MAX_WS_CLIENTS) {
      ws.close(1013, 'Too many connections');
      return;
    }

    ptyManager.addClient(ws);

    var resizeTimer = null;
    var heartbeat = null;
    var alive = true;

    // Detect dead connections via pong timeout
    ws.on('pong', function () {
      alive = true;
    });

    // Heartbeat to detect dead connections
    heartbeat = setInterval(function () {
      if (ws.readyState === 1) {
        if (!alive) {
          clearInterval(heartbeat);
          try {
            ws.terminate();
          } catch (_) {}
          return;
        }
        alive = false;
        ws.ping();
      } else {
        clearInterval(heartbeat);
        try {
          ws.terminate();
        } catch (_) {}
      }
    }, HEARTBEAT_INTERVAL_MS);

    ws.on('message', function (data, isBinary) {
      // JSON control message: starts with '{'
      if (!isBinary && data.length > 0 && data[0] === 0x7B) {
        try {
          var msg = JSON.parse(data.toString('utf8'));
          switch (msg.type) {
          case 'resize':
            // Update size immediately so recalcSize() sees the latest value
            // even if the client disconnects during the debounce window
            ws._termSize = { cols: msg.cols, rows: msg.rows };
            clearTimeout(resizeTimer);
            resizeTimer = setTimeout(function () {
              ptyManager.resizeTo(msg.cols, msg.rows);
            }, RESIZE_DEBOUNCE_MS);
            break;
          case 'restart':
            ptyManager.restart();
            break;
          case 'replay':
            ptyManager.sendReplay(ws);
            break;
          }
        } catch (_) {}
        return;
      }
      // Raw text = PTY input
      ptyManager.write(data.toString('utf8'));
    });

    ws.on('close', function () {
      clearTimeout(resizeTimer);
      clearInterval(heartbeat);
      ptyManager.removeClient(ws);
      // If remaining clients have a different size, resize PTY to match
      ptyManager.recalcSize();
    });

    ws.on('error', function () {
      clearTimeout(resizeTimer);
      clearInterval(heartbeat);
      ptyManager.removeClient(ws);
      // Recalculate PTY size since a client was removed
      ptyManager.recalcSize();
    });
  });
}

module.exports = { setupTerminalWebSocket };
