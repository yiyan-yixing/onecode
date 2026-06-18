(function () {
  var cfg = window.GW_CONFIG || {};
  var termEl = document.getElementById('term');
  if (!termEl || typeof Terminal === 'undefined') {
    return;
  }

  var term = new Terminal({
    scrollback: 5000,
    fontSize: 13,
    lineHeight: 1.0,
    fontWeight: 'normal',
    fontWeightBold: 'bold',
    fontFamily: "'JetBrains Mono','SF Mono','Fira Code',Consolas,monospace",
    theme: {
      background: '#080a12',
      foreground: '#d4dff0',
      cursor: '#7dd3fc',
      cursorAccent: '#080a12',
      selectionBackground: 'rgba(125,211,252,.22)',
      selectionForeground: '#eaf0ff',
      black: '#161a28',
      red: '#ff6b6b',
      green: '#2dd4a0',
      yellow: '#f7c948',
      blue: '#4d9cff',
      magenta: '#c084fc',
      cyan: '#22d3ee',
      white: '#d4dff0',
      brightBlack: '#4a5270',
      brightRed: '#ff8787',
      brightGreen: '#52e8b8',
      brightYellow: '#ffd55a',
      brightBlue: '#79b4ff',
      brightMagenta: '#d8b4fe',
      brightCyan: '#67e8f9',
      brightWhite: '#eef2ff',
    },
    allowProposedApi: true,
    allowTransparency: true,
    convertEol: false,
  });

  // Fit addon
  var fitAddon = new FitAddon.FitAddon();
  term.loadAddon(fitAddon);

  // Web links addon
  var webLinksAddon = new WebLinksAddon.WebLinksAddon();
  term.loadAddon(webLinksAddon);

  term.open(termEl);

  // WebGL addon (skip on Safari — rendering bugs with scroll, use canvas fallback)
  var isSafari = /^((?!chrome|android).)*safari/i.test(navigator.userAgent);
  if (!isSafari) {
    try {
      var webglAddon = new WebglAddon.WebglAddon();
      webglAddon.onContextLoss(function () {
        webglAddon.dispose();
      });
      term.loadAddon(webglAddon);
    } catch (_) {}
  }

  fitAddon.fit();

  // Auto-fit when terminal element becomes visible or resizes (e.g. mobile tab switch)
  if (typeof ResizeObserver !== 'undefined') {
    var roTimer = null;
    var ro = new ResizeObserver(function () {
      clearTimeout(roTimer);
      roTimer = setTimeout(function () {
        if (termEl.offsetWidth > 0 && termEl.offsetHeight > 0) {
          try {
            fitAddon.fit();
          } catch (_) {}
        }
      }, 100);
    });
    ro.observe(termEl);
  }

  // Prevent overscroll bounce on mobile but allow normal scroll
  var s = document.createElement('style');
  s.textContent =
    '.xterm-viewport{overscroll-behavior:none!important;' +
    'scrollbar-width:none!important;touch-action:none!important}' +
    '.xterm-viewport::-webkit-scrollbar{display:none!important}' +
    '.xterm-helpers{position:absolute!important;opacity:0}' +
    '.xterm{-webkit-font-smoothing:antialiased!important;' +
    '-moz-osx-font-smoothing:grayscale!important;' +
    'text-rendering:optimizeLegibility!important}' +
    '.xterm-rows{font-variant-ligatures:none!important;' +
    'letter-spacing:0!important}';
  document.head.appendChild(s);

  // Fix CJK IME input: stale textarea + commit-key leak.
  //
  // Problem 1 — stale textarea: xterm's CompositionHelper reads
  // textarea.value on compositionend but never clears it. After paste or a
  // prior composition, the old text lingers. The next compositionend sends
  // old + new text together.
  // Fix: clear textarea after compositionend and paste via requestAnimationFrame
  // (after xterm has already read the value).
  //
  // Problem 2 — commit-key leak: Chinese/Japanese/Korean IME commits
  // composition when the user presses Space, Enter, a number, or Tab.
  // Chrome fires compositionend BEFORE the keydown for the committing key,
  // so xterm's keydown handler sees the key with _isComposing=false and
  // processes it as a regular keystroke. Result: the terminal receives both
  // the composed text AND the committing key (e.g. "你 " instead of "你").
  // Fix: block keydown events right after compositionend (using a justEnded
  // flag cleared via setTimeout(0)).
  //
  // CRITICAL: do NOT block keydown during composition (isComposing).
  // During CJK composition, all keydown events carry keyCode 229 and are
  // already ignored by xterm's handler. Calling preventDefault() on these
  // events can interfere with the IME on some browsers (especially Safari),
  // preventing the candidate window from appearing or the composition from
  // completing. Only the commit-key after compositionend needs blocking.
  (function fixIME() {
    var ta = termEl.querySelector('.xterm-helper-textarea');
    if (!ta) {
      if (typeof fixIME._retry === 'undefined') fixIME._retry = 0;
      if (fixIME._retry < 15) {
        fixIME._retry++;
        setTimeout(fixIME, 200);
      }
      return;
    }
    var isComposing = false;
    // Set on compositionend; cleared after the current event-loop tick.
    // Prevents the commit key (Space, Enter, number, Tab) from being
    // processed by xterm — Chrome fires compositionend before keydown,
    // so xterm would see the key with isComposing=false and send it as a
    // regular keystroke alongside the composed text.
    var justEnded = false;

    ta.addEventListener('compositionstart', function () {
      isComposing = true;
      justEnded = false;
    }, true);

    ta.addEventListener('compositionend', function () {
      isComposing = false;
      justEnded = true;
      // Clear justEnded after the current event-loop tick — the keydown
      // for the commit key fires in the same tick.
      setTimeout(function () { justEnded = false; }, 0);
      // Clear textarea after xterm's compositionHelper has read it.
      // requestAnimationFrame ensures xterm's handler runs first.
      requestAnimationFrame(function () {
        if (!isComposing) {
          ta.value = '';
        }
      });
    }, true);

    ta.addEventListener('paste', function () {
      // Clear textarea after xterm has processed the paste.
      requestAnimationFrame(function () {
        if (!isComposing) {
          ta.value = '';
        }
      });
    });

    // Block the commit key after compositionend to prevent double input.
    // Register on the PARENT element (.xterm) in capture phase so our
    // handler fires BEFORE xterm's textarea keydown handler.
    // IMPORTANT: we do NOT block keydown during composition — xterm already
    // ignores keyCode 229, and preventDefault() during composition can
    // break the IME on some browsers.
    termEl.addEventListener('keydown', function (e) {
      // Only intercept keys that target the textarea (IME input focus)
      if (e.target !== ta) {
        return;
      }
      if (justEnded) {
        // Block the commit key's keydown after compositionend.
        // In Chrome, compositionend fires before the commit key's keydown.
        // Without this, xterm would process the commit key (Space, Enter,
        // number, Tab) as a regular keystroke, sending it alongside the
        // composed text (e.g., "你 " instead of "你").
        e.preventDefault();
        e.stopImmediatePropagation();
      }
    }, true);
  })();

  // Fix mobile IME input: number/symbol keyboard + duplicate send prevention
  // The fixIME handler above only blocks the commit key after compositionend.
  // This mobile-specific fix handles:
  // 1. Non-composition input from number/symbol keyboards (xterm misses these)
  // 2. skipInput flag to prevent double-sending via the input event
  // Use matchMedia(pointer:coarse) for reliable touch detection; fall back to
  // ontouchstart+width for older browsers. Avoid false positives on desktop
  // touch-enabled laptops (which have fine pointer = mouse/trackpad).
  var isTouchDevice = (window.matchMedia && window.matchMedia('(pointer: coarse)').matches) ||
      ('ontouchstart' in window && window.innerWidth < 1024);
  (function fixMobileInput() {
    if (!isTouchDevice) {
      return;
    }
    var ta = termEl.querySelector('.xterm-helper-textarea');
    if (ta) {
      ta.setAttribute('autocomplete', 'off');
      ta.setAttribute('autocorrect', 'off');
      ta.setAttribute('autocapitalize', 'off');
      ta.setAttribute('spellcheck', 'false');
      ta.setAttribute('inputmode', 'text');

      // Track composition state
      var isComposing = false;
      // Mark paste/composition handled by xterm to prevent duplicate sends
      var skipInput = false;

      ta.addEventListener('compositionstart', function () {
        isComposing = true;
      }, true);
      ta.addEventListener('compositionend', function () {
        isComposing = false;
        // xterm's compositionHelper delivers the final composed text via
        // term.onData(), so we must NOT send it again. Just mark that
        // the input event should be skipped to avoid double-sending
        // (the input event fires right after compositionend).
        // IMPORTANT: Do NOT clear ta.value here! This handler runs in the
        // capture phase, BEFORE xterm's bubble-phase compositionend handler
        // which reads ta.value. Clearing here would destroy the composed
        // Chinese text before xterm can read it. The unified fixIME's
        // requestAnimationFrame will clear the textarea after xterm reads it.
        var val = ta.value;
        if (val && val.length > 0) {
          skipInput = true;
        }
      }, true);

      // Mark paste as handled by xterm — paste fires no keydown, so
      // xtermHandled would stay false and the input handler would
      // re-send the pasted content (double send bug).
      ta.addEventListener('paste', function () {
        skipInput = true;
      }, true);

      // For non-composition input missed by xterm (mobile number/symbol keyboard)
      var xtermHandled = false;
      ta.addEventListener('keydown', function () {
        if (!isComposing) {
          xtermHandled = true;
        }
      }, true);
      ta.addEventListener('input', function (e) {
        if (isComposing) {
          xtermHandled = false;
          return;
        }
        // Skip if this input was triggered by a paste or compositionend
        // that xterm already handled — prevents double-sending.
        if (skipInput) {
          skipInput = false;
          xtermHandled = false;
          return;
        }
        var val = ta.value;
        if (val && val.length > 0 && !xtermHandled) {
          for (var i = 0; i < val.length; i++) {
            var ch = val[i];
            if (ch === '\n' || ch === '\r' || ch === '\t') {
              continue;
            }
            if (ws && ws.readyState === 1) {
              ws.send(ch);
            }
          }
          ta.value = '';
        }
        xtermHandled = false;
      }, true);
    } else {
      // Retry with back-off, but cap at 25 attempts (~5 seconds)
      if (typeof fixMobileInput._retry === 'undefined') {
        fixMobileInput._retry = 0;
      }
      if (fixMobileInput._retry < 25) {
        fixMobileInput._retry++;
        setTimeout(fixMobileInput, 200);
      }
    }
  })();

  // Scroll thumb: custom indexed slider
  termEl.style.position = 'relative';
  var scrollTrack = document.createElement('div');
  scrollTrack.className = 'xterm-scroll-track';
  scrollTrack.style.cssText =
    'position:absolute;right:0;top:0;bottom:0;width:10px;' +
    'z-index:10;cursor:pointer';
  termEl.appendChild(scrollTrack);
  var scrollThumb = document.createElement('div');
  scrollThumb.style.cssText =
    'position:absolute;right:2px;top:0;width:3px;min-height:28px;' +
    'border-radius:4px;' +
    'background:linear-gradient(180deg,rgba(125,211,252,.25),' +
    'rgba(96,165,250,.35));' +
    'box-shadow:0 0 6px rgba(125,211,252,.1);' +
    'opacity:0;transition:opacity .3s,width .2s,background .2s,' +
    'right .2s,box-shadow .2s';
  scrollTrack.appendChild(scrollThumb);
  var scrollLabel = document.createElement('div');
  scrollLabel.style.cssText =
    'position:absolute;right:18px;padding:3px 10px;border-radius:6px;' +
    'background:rgba(10,12,20,.94);color:#c8d6f0;font-size:10px;' +
    'letter-spacing:.5px;' +
    'font-family:-apple-system,BlinkMacSystemFont,Segoe UI,system-ui,' +
    'sans-serif;pointer-events:none;opacity:0;transition:opacity .25s;' +
    'z-index:11;white-space:nowrap;' +
    'border:1px solid rgba(125,211,252,.12);' +
    'box-shadow:0 2px 12px rgba(0,0,0,.4)';
  scrollTrack.appendChild(scrollLabel);
  var thumbHideTimer = null;
  var thumbDragging = false;

  function updateScrollThumb() {
    var buf = term.buffer.active;
    var total = buf.length;
    var viewY = buf.viewportY;
    var viewH = term.rows;
    if (total <= viewH) {
      scrollThumb.style.opacity = '0';
      scrollLabel.style.opacity = '0';
      return;
    }
    var ratio = viewH / total;
    var thH = Math.max(24, Math.min(termEl.clientHeight * 0.5, termEl.clientHeight * ratio));
    var thTop = (viewY / (total - viewH)) * (termEl.clientHeight - thH);
    scrollThumb.style.height = thH + 'px';
    scrollThumb.style.top = thTop + 'px';
    scrollThumb.style.opacity = '1';
    scrollLabel.textContent = (viewY + 1) + ' / ' + total;
    scrollLabel.style.top = Math.max(0, thTop + thH / 2 - 10) + 'px';
    clearTimeout(thumbHideTimer);
    thumbHideTimer = setTimeout(function () {
      if (!thumbDragging) {
        scrollThumb.style.opacity = '0';
        scrollLabel.style.opacity = '0';
      }
    }, 1500);
  }

  term.onResize(function () {
    setTimeout(updateScrollThumb, 200);
  });

  // Track click - jump to position
  scrollTrack.addEventListener('mousedown', function (e) {
    if (e.target === scrollThumb) {
      return;
    }
    e.preventDefault();
    var buf = term.buffer.active;
    var total = buf.length;
    var viewH = term.rows;
    if (total <= viewH) {
      return;
    }
    var rect = scrollTrack.getBoundingClientRect();
    var clickY = e.clientY - rect.top;
    var targetLine = Math.round((clickY / rect.height) * total);
    try {
      term.scrollToLine(targetLine);
    } catch (_) {}
    updateScrollThumb();
    scrollLabel.style.opacity = '1';
  });

  // Thumb drag - mouse
  scrollThumb.addEventListener('mousedown', function (e) {
    e.preventDefault();
    e.stopPropagation();
    thumbDragging = true;
    scrollThumb.style.background =
      'linear-gradient(180deg,rgba(125,211,252,.55),' +
      'rgba(96,165,250,.65))';
    scrollThumb.style.boxShadow = '0 0 10px rgba(125,211,252,.25)';
    scrollThumb.style.width = '5px';
    scrollThumb.style.right = '1px';
    scrollLabel.style.opacity = '1';
    document.body.style.userSelect = 'none';
    var startY = e.clientY;
    var buf = term.buffer.active;
    var startViewY = buf.viewportY;
    var total = buf.length;
    var viewH = term.rows;
    // Cache layout height at drag start to avoid layout thrashing per move event
    var trackH = termEl.clientHeight;
    function onMove(ev) {
      var dy = ev.clientY - startY;
      var linesPerPx = total / trackH;
      var targetLine = Math.round(startViewY + dy * linesPerPx);
      targetLine = Math.max(0, Math.min(total - viewH, targetLine));
      try {
        term.scrollToLine(targetLine);
      } catch (_) {}
      updateScrollThumb();
      scrollLabel.style.opacity = '1';
    }
    function onUp() {
      thumbDragging = false;
      scrollThumb.style.background =
        'linear-gradient(180deg,rgba(125,211,252,.25),' +
        'rgba(96,165,250,.35))';
      scrollThumb.style.boxShadow = '0 0 6px rgba(125,211,252,.1)';
      scrollThumb.style.width = '3px';
      scrollThumb.style.right = '2px';
      document.body.style.userSelect = '';
      clearTimeout(thumbHideTimer);
      thumbHideTimer = setTimeout(function () {
        scrollThumb.style.opacity = '0';
        scrollLabel.style.opacity = '0';
      }, 1000);
      document.removeEventListener('mousemove', onMove);
      document.removeEventListener('mouseup', onUp);
    }
    document.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup', onUp);
  });

  // Thumb drag - touch
  scrollThumb.addEventListener('touchstart', function (e) {
    e.preventDefault();
    e.stopPropagation();
    thumbDragging = true;
    scrollThumb.style.background =
      'linear-gradient(180deg,rgba(125,211,252,.55),' +
      'rgba(96,165,250,.65))';
    scrollThumb.style.boxShadow = '0 0 10px rgba(125,211,252,.25)';
    scrollThumb.style.width = '5px';
    scrollThumb.style.right = '1px';
    scrollLabel.style.opacity = '1';
    var startY = e.touches[0].clientY;
    var buf = term.buffer.active;
    var startViewY = buf.viewportY;
    var total = buf.length;
    var viewH = term.rows;
    // Cache layout height at drag start to avoid layout thrashing per move event
    var trackH = termEl.clientHeight;
    function onMove(ev) {
      if (!thumbDragging) {
        return;
      }
      ev.preventDefault();
      var dy = ev.touches[0].clientY - startY;
      var linesPerPx = total / trackH;
      var targetLine = Math.round(startViewY + dy * linesPerPx);
      targetLine = Math.max(0, Math.min(total - viewH, targetLine));
      try {
        term.scrollToLine(targetLine);
      } catch (_) {}
      updateScrollThumb();
    }
    function onEnd() {
      thumbDragging = false;
      scrollThumb.style.background =
        'linear-gradient(180deg,rgba(125,211,252,.25),' +
        'rgba(96,165,250,.35))';
      scrollThumb.style.boxShadow = '0 0 6px rgba(125,211,252,.1)';
      scrollThumb.style.width = '3px';
      scrollThumb.style.right = '2px';
      clearTimeout(thumbHideTimer);
      thumbHideTimer = setTimeout(function () {
        scrollThumb.style.opacity = '0';
        scrollLabel.style.opacity = '0';
      }, 1000);
      document.removeEventListener('touchmove', onMove);
      document.removeEventListener('touchend', onEnd);
    }
    document.addEventListener('touchmove', onMove, { passive: false });
    document.addEventListener('touchend', onEnd);
  }, { passive: false });

  // Hover effect
  scrollTrack.addEventListener('mouseenter', function () {
    if (!thumbDragging) {
      scrollThumb.style.width = '5px';
      scrollThumb.style.right = '1px';
    }
    clearTimeout(thumbHideTimer);
    updateScrollThumb();
  });
  scrollTrack.addEventListener('mouseleave', function () {
    if (!thumbDragging) {
      scrollThumb.style.width = '3px';
      scrollThumb.style.right = '2px';
    }
    if (!thumbDragging) {
      thumbHideTimer = setTimeout(function () {
        scrollThumb.style.opacity = '0';
        scrollLabel.style.opacity = '0';
      }, 800);
    }
  });

  // Auto-scroll to bottom on new output (only if already at bottom)
  var userScrolled = false;
  var _scrollRaf = 0;

  function isAtBottom() {
    var buf = term.buffer.active;
    return buf.viewportY + term.rows >= buf.length;
  }

  term.onLineFeed(function () {
    if (!userScrolled) {
      // Coalesce scrollToBottom calls via requestAnimationFrame to avoid
      // per-line reflows during rapid output (e.g. cat large_file)
      if (!_scrollRaf) {
        _scrollRaf = requestAnimationFrame(function () {
          _scrollRaf = 0;
          try {
            term.scrollToBottom();
          } catch (_) {}
        });
      }
    }
  });

  term.onScroll(function () {
    userScrolled = !isAtBottom();
    updateScrollThumb();
  });

  // Any user input resets scroll position to bottom
  term.onData(function () {
    userScrolled = false;
  });

  window.term = term;

  // WebSocket connection
  var wsUrl = (location.protocol === 'https:' ? 'wss:' : 'ws:') +
    '//' + location.host + '/ws/term';
  if (cfg.token) {
    wsUrl += '?token=' + encodeURIComponent(cfg.token);
  }

  var ws = null;
  var reconnectDelay = 1000;
  var reconnectAttempts = 0;
  var MAX_RECONNECT_ATTEMPTS = 50;
  var isReplaying = false;
  var pendingReset = false;

  function doFullClear() {
    term.reset();
    term.clear();
    var vp = termEl.querySelector('.xterm-viewport');
    if (vp) {
      vp.scrollTop = 0;
    }
    userScrolled = false;
  }

  // Binary protocol constants (must match pty.js)
  var FRAME_CTRL = 0x00;
  var FRAME_PTY = 0x01;
  var CTRL_RESET = 0x01;
  var CTRL_REPLAY_START = 0x02;
  var CTRL_REPLAY_END = 0x03;
  var CTRL_PTY_RESIZE = 0x04;

  var _reconnectTimer = null;
  var _isConnecting = false;

  function connectWs() {
    // Prevent concurrent reconnect attempts
    if (_isConnecting) {
      return;
    }
    // Close existing connection before creating a new one
    if (ws) {
      try {
        ws.close();
      } catch (_) {}
      ws = null;
      window.termWs = null;
    }
    // Cancel any pending reconnect timer
    if (_reconnectTimer) {
      clearTimeout(_reconnectTimer);
      _reconnectTimer = null;
    }
    _isConnecting = true;
    try {
      ws = new WebSocket(wsUrl);
    } catch (e) {
      _isConnecting = false;
      // Retry after delay if constructor fails (e.g. invalid URL)
      _reconnectTimer = setTimeout(function () {
        _reconnectTimer = null;
        connectWs();
      }, reconnectDelay);
      reconnectDelay = Math.min(reconnectDelay * 2, 10000);
      return;
    }
    ws.binaryType = 'arraybuffer';

    ws.onopen = function () {
      _isConnecting = false;
      reconnectDelay = 1000;
      reconnectAttempts = 0;
      isReplaying = false;
      sendResize();
    };

    ws.onmessage = function (event) {
      var data = event.data;
      if (!(data instanceof ArrayBuffer)) {
        return;
      }
      var bytes = new Uint8Array(data);
      if (bytes.length === 0) {
        return;
      }

      if (bytes[0] === FRAME_CTRL) {
        // Control message: [0x00][ctrl_type][json payload?]
        if (bytes.length < 2) {
          return;
        }
        var ctrlType = bytes[1];
        var payload = null;
        if (bytes.length > 2) {
          try {
            payload = JSON.parse(new TextDecoder().decode(bytes.slice(2)));
          } catch (_) {}
        }
        if (ctrlType === CTRL_RESET) {
          pendingReset = true;
          doFullClear();
        } else if (ctrlType === CTRL_REPLAY_START) {
          isReplaying = true;
          doFullClear();
        } else if (ctrlType === CTRL_REPLAY_END) {
          isReplaying = false;
          try {
            term.scrollToBottom();
          } catch (_) {}
        } else if (ctrlType === CTRL_PTY_RESIZE && payload) {
          window.ptyCols = payload.cols;
          window.ptyRows = payload.rows;
        }
        return;
      }

      if (bytes[0] === FRAME_PTY) {
        // Clear terminal right before first PTY data after reset
        if (pendingReset) {
          doFullClear();
          pendingReset = false;
        }
        term.write(bytes.slice(1));
      }
    };

    ws.onclose = function (event) {
      _isConnecting = false;
      ws = null;
      window.termWs = null;
      // Do not reconnect on clean shutdown (1000), server shutdown (1001), or auth failure (1008)
      if (event.code === 1000 || event.code === 1001 || event.code === 1008) {
        return;
      }
      if (++reconnectAttempts > MAX_RECONNECT_ATTEMPTS) {
        return;
      }
      var jitter = Math.random() * 500;
      _reconnectTimer = setTimeout(function () {
        _reconnectTimer = null;
        connectWs();
      }, reconnectDelay + jitter);
      reconnectDelay = Math.min(reconnectDelay * 2, 10000);
    };

    ws.onerror = function () {
      ws.close();
    };

    window.termWs = ws;
  }

  function sendResize() {
    if (ws && ws.readyState === 1) {
      ws.send(JSON.stringify({
        type: 'resize',
        cols: term.cols,
        rows: term.rows,
      }));
    }
  }

  // Terminal input -> WebSocket
  term.onData(function (data) {
    if (ws && ws.readyState === 1) {
      ws.send(data);
    }
  });

  // Resize: fit addon -> debounce -> notify server
  var resizeTimer = null;
  term.onResize(function () {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(sendResize, 150);
  });

  // Visibility change: reconnect on foreground after long gap
  var lastVisible = Date.now();
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) {
      var gap = Date.now() - lastVisible;
      if (gap > 10000 && (!ws || ws.readyState !== 1)) {
        // Reset reconnect counter — user has returned, give a fresh attempt cycle
        reconnectAttempts = 0;
        reconnectDelay = 1000;
        connectWs();
      }
    } else {
      lastVisible = Date.now();
    }
  });

  // PC: wheel scroll via xterm API (bypasses mouse tracking mode)
  // Mobile: touch scroll via viewport.scrollTop (native browser redraw, no canvas overlap)
  // Touch events don't trigger mouse tracking mode, so viewport scroll is safe on mobile
  var isMobile = 'ontouchstart' in window && window.innerWidth < 768;
  var hasTouch = 'ontouchstart' in window;
  // Update isMobile on resize so scroll behavior adapts to orientation changes / docking
  window.addEventListener('resize', function () {
    isMobile = hasTouch && window.innerWidth < 768;
  });

  // Always register wheel handler — only act when not on mobile
  termEl.addEventListener('wheel', function (e) {
    if (isMobile) {
      return;
    }
    e.preventDefault();
    e.stopImmediatePropagation();
    var delta = e.deltaY;
    if (delta === 0) {
      return;
    }
    var lines = Math.round(Math.abs(delta) / 40);
    lines = Math.max(1, Math.min(lines, 20));
    if (delta > 0) {
      try {
        term.scrollLines(lines);
      } catch (_) {}
    } else {
      try {
        term.scrollLines(-lines);
      } catch (_) {}
    }
    userScrolled = !isAtBottom();
    updateScrollThumb();
  }, { passive: false, capture: true });

  // Always register touch scroll handlers — only act on mobile
  if (hasTouch) {
    // Lock scrollToBottom during touch + momentum
    var scrollActive = false;
    var origScrollToBottom = term.scrollToBottom;
    term.scrollToBottom = function () {
      if (isMobile && scrollActive) {
        return;
      }
      return origScrollToBottom.apply(this, arguments);
    };

    var tsx = 0;
    var tsy = 0;
    var tly = 0;
    var baseViewportY = 0;
    var scrollPx = 0;
    var rowH = 0;
    var lastTargetLine = -1;
    var velocity = 0;
    var momentumRaf = 0;

    termEl.addEventListener('touchstart', function (e) {
      if (!isMobile) {
        return;
      }
      if (e.touches.length !== 1 || scrollTrack.contains(e.target)) {
        return;
      }
      scrollActive = true;
      if (momentumRaf) {
        cancelAnimationFrame(momentumRaf);
        momentumRaf = 0;
      }
      tsx = e.touches[0].clientX;
      tsy = e.touches[0].clientY;
      tly = tsy;
      scrollPx = 0;
      velocity = 0;
      baseViewportY = term.buffer.active.viewportY;
      lastTargetLine = baseViewportY;
      rowH = termEl.clientHeight / term.rows;
    }, { passive: true });

    termEl.addEventListener('touchmove', function (e) {
      if (!isMobile || !scrollActive || e.touches.length !== 1) {
        return;
      }
      var cy = e.touches[0].clientY;
      var dx = tsx - e.touches[0].clientX;
      var dy = tsy - cy;
      if (Math.abs(dy) > 3 && Math.abs(dy) > Math.abs(dx)) {
        e.preventDefault();
        var sd = tly - cy;
        tly = cy;
        if (sd !== 0) {
          scrollPx += sd;
          velocity = sd;
          if (rowH > 0) {
            var targetLine = baseViewportY + Math.round(scrollPx / rowH);
            targetLine = Math.max(0, Math.min(targetLine, term.buffer.active.length - term.rows));
            if (targetLine !== lastTargetLine) {
              lastTargetLine = targetLine;
              try {
                term.scrollToLine(targetLine);
              } catch (_) {}
              userScrolled = !isAtBottom();
              updateScrollThumb();
            }
          }
        }
      }
    }, { passive: false });

    function momentumStep() {
      velocity *= 0.92;
      if (Math.abs(velocity) < 0.5) {
        scrollActive = false;
        momentumRaf = 0;
        return;
      }
      scrollPx += velocity;
      if (rowH > 0) {
        var targetLine = baseViewportY + Math.round(scrollPx / rowH);
        var maxLine = term.buffer.active.length - term.rows;
        targetLine = Math.max(0, Math.min(targetLine, maxLine));
        if (targetLine !== lastTargetLine) {
          lastTargetLine = targetLine;
          try {
            term.scrollToLine(targetLine);
          } catch (_) {}
          userScrolled = !isAtBottom();
          updateScrollThumb();
        }
        momentumRaf = requestAnimationFrame(momentumStep);
      } else {
        scrollActive = false;
        momentumRaf = 0;
      }
    }

    termEl.addEventListener('touchend', function () {
      if (!isMobile || !scrollActive) {
        return;
      }
      if (Math.abs(velocity) > 3) {
        momentumRaf = requestAnimationFrame(momentumStep);
      } else {
        scrollActive = false;
      }
    }, { passive: true });
    termEl.addEventListener('touchcancel', function () {
      if (!isMobile) {
        return;
      }
      scrollActive = false;
      if (momentumRaf) {
        cancelAnimationFrame(momentumRaf);
        momentumRaf = 0;
      }
    }, { passive: true });
  }

  // Expose for external use (VK input, reconnect, etc.)
  window.connectTermWs = connectWs;
  // Expose fit for mobile tab switch
  window.term.fit = function () {
    try {
      fitAddon.fit();
    } catch (_) {}
  };

  connectWs();
})();
