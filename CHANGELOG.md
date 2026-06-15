# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-06-15

### Added

- `oc config set` command for updating settings from CLI
- Placeholder API key detection — warns when API key is not configured
- Agent icon system — emoji icons for each agent role
- `gh_fetch` mirror fallback for China network and private repos

### Changed

- Install directory moved to `~/.local/bin/`
- Repository normalized — cleaned v1 Next.js legacy, unified version

## [0.3.5] - 2026-06-13

### Added

- Dynamic agent loading from `.claude/agents/*.md` — add/remove agents without touching frontend code
- `oc` first-run setup — interactive configuration on first launch
- Auto architecture detection — Apple Silicon (arm64) / Intel (amd64)
- `github_fetch` helper for China network and private repos

## [0.2.0] - 2026-06-12

### Added

- Gateway server — pure Node.js HTTP + WebSocket
- PTY process manager — ring buffer, replay, multi-client support
- xterm.js terminal connected to Claude Code via PTY
- Agent role sidebar — dynamic loading from agent definitions
- `@角色名` mention system with autocomplete popup
- `oc` CLI — manage containers, SSH, Web terminal, updates
- Mobile responsive layout with 4-tab bar
- Virtual keyboard for mobile
- Docker containerization with one-command startup

### Changed

- Replaced Next.js frontend with single-page HTML gateway (lighter, faster)

## [0.1.0] - 2026-06-10

### Added

- OneCode MVP — AI Native IDE with Agent roles
- Chat interface with `@角色名` routing
- Monaco Editor integration
- 10 built-in agent roles: CEO, PM, Designer, Architect, Dev, DevOps, QA, Ops, Data, Fin
- Mock data pipeline for agent responses

[0.4.0]: https://github.com/yiyan-yixing/onecode/releases/tag/0.4.0
[0.3.5]: https://github.com/yiyan-yixing/onecode/releases/tag/0.3.5
[0.2.0]: https://github.com/yiyan-yixing/onecode/releases/tag/0.2.0
[0.1.0]: https://github.com/yiyan-yixing/onecode/releases/tag/0.1.0
