@AGENTS.md

# OneCode v2 — Architecture

## Overview

OneCode is an AI-native IDE built on top of Claude Code. The architecture follows the wxyy-sandbox pattern: a Node.js gateway server serves a single-page HTML UI with xterm.js terminal connected to Claude Code via PTY.

## Key Architecture

- **Gateway** (`agent-runtime/gateway/`): Pure Node.js HTTP + WebSocket server
  - `index.js` — Main server, reads `onecode.html`, serves index page
  - `config.js` — Port/path configuration
  - `router.js` — URL routing rules
  - `proxy.js` — Reverse proxy (filebrowser, code-server)
  - `pty.js` — PTY process manager (ring buffer, replay, multi-client)
  - `term-ws.js` — Terminal WebSocket at `/ws/term`
  - `cc-status.js` — Claude Code status API (skills/hooks/plugins/tasks)
  - `static.js` — Static file serving with pre-compression

- **OneCode HTML** (`agent-runtime/gateway/onecode.html`): Single-page app
  - Three-panel layout: Terminal + Preview + Sidebar (Files + Agents)
  - 10 Agent roles with icons, missions, time % badges
  - @角色名 mention system with autocomplete popup
  - Mobile responsive with 4-tab bar (Terminal/Preview/Files/Agents)
  - Virtual keyboard for mobile

- **Docker** (`agent-runtime/Dockerfile`): Containerized Claude Code runtime

## Commands

```bash
node agent-runtime/gateway/index.js    # Start gateway locally
docker build -t onecode agent-runtime/ # Build Docker image
```

## v1 Legacy

The `src/` directory contains the v1 Next.js MVP (deprecated, kept for reference).
