---
name: desktop-code-structure
description: OneCode Desktop 客户端详细目录代码结构设计
metadata:
  type: project
---

# OneCode Desktop — 详细目录代码结构设计

> 基于 [[desktop-client-architecture]] 架构方案，细化到每个文件的职责、签名和代码行数

---

## 总览：现有代码资产盘点

| 文件 | 行数 | 职责 | 去向 |
|------|------|------|------|
| `onecode.html` (HTML/CSS) | ~258 | 布局 + 样式 | → `index.html` + `styles.css` |
| `onecode.html` (Agent JS) | ~135 | Agent 列表 + @mention | → `agents.js` |
| `onecode.html` (CC status JS) | ~75 | 技能/hook/plugin 状态 | → `cc-status.js`（前端） |
| `onecode.html` (Preview JS) | ~135 | Markdown/代码预览 | → `preview.js` |
| `onecode.html` (Sidebar JS) | ~150 | 文件树 + 面包屑 + 导航 | → `sidebar.js` |
| `onecode.html` (Mobile JS) | ~70 | 移动端适配 + 虚拟键盘 | → `mobile.js` |
| `onecode.html` (Resize/Layout) | ~40 | resize handle + 布局 | → `layout.js` |
| `onecode.html` (Key bindings) | ~20 | 快捷键 | → `keybindings.js` |
| `term.js` (xterm init) | ~80 | 终端初始化 + 主题 | → `terminal.js`（核心） |
| `term.js` (WS binary proto) | ~80 | WebSocket 二进制协议 | → `transport-ws.js`（远程） |
| `term.js` (Scroll thumb) | ~170 | 自定义滚动条 | → `scroll-thumb.js` |
| `term.js` (Mobile scroll) | ~100 | 触摸滚动 + 动量 | → `mobile-scroll.js` |
| `term.js` (IME fixes) | ~60 | CJK 输入法修复 | → `ime-fix.js` |
| `pty.js` | 403 | PTY 管理（单实例） | → Rust `pty/mod.rs` 重写 |
| `term-ws.js` | 125 | WS 服务端 | Desktop 不需要（远程模式复用） |
| `cc-status.js` | 432 | 后端状态 API | → Rust `commands.rs` 移植 |
| `index.js` | 236 | 服务器主入口 | Desktop 不需要 |
| `config.js` | 30 | 配置 | → Rust `config.rs` 适配 |
| `proxy.js` | 319 | 反向代理 | Desktop 不需要 |
| `router.js` | 81 | URL 路由 | Desktop 不需要 |
| `static.js` | 136 | 静态文件 | Tauri 自带 |
| **合计** | **~2,700** | | **~55% 复用, ~30% 改造, ~15% 新写** |

---

## 完整目录结构

```
onecode-desktop/
│
├── 📦 package.json                    # 前端依赖 + tauri CLI 脚本
├── 📦 package-lock.json
├── ⚙️ .gitignore
├── ⚙️ .editorconfig
├── 📖 README.md                       # 项目说明 + 构建指南
│
├── src-tauri/                         # ═══ Rust 后端 ═══
│   ├── Cargo.toml                     # 依赖：tauri, portable-pty, rusqlite, serde
│   ├── Cargo.lock
│   ├── build.rs                       # Tauri 构建脚本（自动生成）
│   │
│   ├── tauri.conf.json                # 窗口配置 / 权限 / 打包
│   ├── capabilities/
│   │   └── default.json               # IPC 权限白名单
│   │
│   ├── icons/                         # 应用图标（macOS .icns, Linux .png）
│   │   ├── icon.icns
│   │   ├── icon.png
│   │   └── icon.xpm
│   │
│   └── src/
│       ├── main.rs                    # Tauri 入口
│       ├── lib.rs                     # 模块声明 + Tauri setup
│       │
│       ├── pty/                       # ═══ PTY 管理（核心） ═══
│       │   ├── mod.rs                 # MultiPtyManager
│       │   ├── slot.rs                # TerminalSlot + RingBuffer
│       │   └── health.rs             # 僵尸进程检测 + 资源监控
│       │
│       ├── session/                   # ═══ 会话持久化 ═══
│       │   ├── mod.rs                 # SessionStore
│       │   └── schema.rs             # SQLite schema + 迁移
│       │
│       ├── tray.rs                    # ═══ 系统托盘 ═══
│       │
│       ├── commands.rs                # ═══ Tauri invoke 命令 ═══
│       │
│       ├── events.rs                  # ═══ IPC 事件定义 ═══
│       │
│       ├── config.rs                  # ═══ 应用配置 ═══
│       │
│       └── cc_status.rs              # ═══ Claude Code 状态读取 ═══
│
├── src/                               # ═══ 前端（WebView） ═══
│   ├── index.html                     # 入口 HTML（极简，仅加载模块）
│   ├── styles.css                     # 主样式（复用 onecode.html CSS）
│   │
│   ├── main.js                        # 应用入口：初始化 + 路由
│   ├── ipc-bridge.js                  # Tauri invoke 封装
│   │
│   ├── terminal/                      # ═══ 终端模块 ═══
│   │   ├── terminal.js                # xterm.js 初始化 + 主题
│   │   ├── tab-manager.js             # 多终端 Tab 管理（新增核心）
│   │   ├── scroll-thumb.js            # 自定义滚动条
│   │   ├── ime-fix.js                 # CJK 输入法修复
│   │   └── transport-local.js         # 本地 PTY 通信（IPC bridge）
│   │
│   ├── sidebar/                       # ═══ 侧栏模块 ═══
│   │   ├── sidebar.js                 # 侧栏容器 + toggle
│   │   ├── file-tree.js               # 文件树渲染 + 导航
│   │   ├── agents.js                  # Agent 列表 + @mention
│   │   └── cc-badges.js               # Claude Code 状态徽章
│   │
│   ├── preview/                       # ═══ 预览模块 ═══
│   │   ├── preview.js                 # 预览面板容器
│   │   ├── markdown.js                # Markdown 渲染 + XSS 过滤
│   │   └── code-view.js               # 代码高亮 + 复制
│   │
│   ├── layout/                        # ═══ 布局模块 ═══
│   │   ├── layout.js                  # 三栏布局 + resize handle
│   │   ├── keybindings.js             # 全局快捷键
│   │   └── mobile.js                  # 移动端适配（Tab bar + VK）
│   │
│   └── remote/                        # ═══ 远程模式（M3 可选） ═══
│       └── transport-ws.js            # WebSocket 远程终端通信
│
├── static/                            # ═══ 静态资源（复用 gateway/static/） ═══
│   ├── xterm.min.js
│   ├── xterm.css
│   ├── addon-fit.min.js
│   ├── addon-web-links.min.js
│   ├── addon-webgl.min.js
│   ├── marked.min.js
│   ├── highlight.min.js
│   └── hljs.css
│
└── scripts/                           # ═══ 开发脚本 ═══
    └── copy-static.sh                 # 从 gateway/static/ 复制资源
```

---

## Rust 侧详细设计

### `src-tauri/src/main.rs` — Tauri 入口（~15 行）

```rust
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    onecode_desktop::run();
}
```

### `src-tauri/src/lib.rs` — 模块声明 + Setup（~80 行）

```rust
mod pty;
mod session;
mod tray;
mod commands;
mod events;
mod config;
mod cc_status;

use tauri::Manager;

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            // 初始化 MultiPtyManager（存入 app state）
            let pty_mgr = pty::MultiPtyManager::new(app.handle().clone());
            app.manage(pty_mgr);

            // 初始化 SessionStore
            let session = session::SessionStore::new(app.path().app_data_dir()?);
            app.manage(session);

            // 初始化系统托盘
            tray::setup(app)?;

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::pty_spawn,
            commands::pty_kill,
            commands::pty_restart,
            commands::pty_write,
            commands::pty_resize,
            commands::pty_list,
            commands::pty_rename,
            commands::session_restore,
            commands::session_save,
            commands::cc_status,
        ])
        .run(tauri::generate_context!())
        .expect("failed to run OneCode Desktop");
}
```

### `src-tauri/src/pty/mod.rs` — MultiPtyManager（~180 行）

```rust
use std::collections::HashMap;
use tauri::AppHandle;
use uuid::Uuid;

mod slot;
mod health;

pub use slot::TerminalSlot;

pub struct MultiPtyManager {
    inner: std::sync::Mutex<MultiPtyManagerInner>,
    app: AppHandle,
}

struct MultiPtyManagerInner {
    slots: HashMap<Uuid, TerminalSlot>,
    active_id: Uuid,
    max_slots: usize,               // 默认 10
}

impl MultiPtyManager {
    pub fn new(app: AppHandle) -> Self { /* ... */ }

    /// spawn 创建新终端
    pub fn spawn(&self, cmd: String, args: Vec<String>, cwd: String, env: HashMap<String, String>) -> Result<Uuid> { /* ... */ }

    /// kill 终止终端（SIGTERM → 3s → SIGKILL）
    pub fn kill(&self, id: Uuid) -> Result<()> { /* ... */ }

    /// restart 重启终端（复用 cmd/args/cwd/env）
    pub fn restart(&self, id: Uuid) -> Result<()> { /* ... */ }

    /// write 前端输入写入 PTY
    pub fn write(&self, id: Uuid, data: Vec<u8>) -> Result<()> { /* ... */ }

    /// resize 调整 PTY 大小
    pub fn resize(&self, id: Uuid, cols: u16, rows: u16) -> Result<()> { /* ... */ }

    /// list 列出所有终端状态
    pub fn list(&self) -> Vec<SlotSummary> { /* ... */ }

    /// rename 重命名终端标签
    pub fn rename(&self, id: Uuid, label: String) -> Result<()> { /* ... */ }

    /// replay 获取 ring buffer 内容（Tab 切换时使用）
    pub fn replay(&self, id: Uuid) -> Vec<u8> { /* ... */ }

    /// start_output_reader 启动 PTY 输出读取 → IPC 事件推送
    fn start_output_reader(&self, id: Uuid, pty: Box<dyn portable_pty::MasterPty + Send>) { /* ... */ }
}

pub struct SlotSummary {
    pub id: Uuid,
    pub label: String,
    pub status: String,       // "running" | "exited" | "restarting"
    pub pid: Option<u32>,
    pub exit_code: Option<i32>,
}
```

**对应关系：** `pty.js` 的 `PtyManager` 类 → `MultiPtyManager`
- `PtyManager.spawn()` → `MultiPtyManager.spawn()`
- `PtyManager._createPty()` → `slot::create_pty()`
- `PtyManager._chunks[]` ring buffer → `slot::RingBuffer`
- `PtyManager.restart()` → `MultiPtyManager.restart()`
- `PtyManager.kill()` → `MultiPtyManager.kill()`
- **新增：** 1→N HashMap 管理，active_id 追踪，健康检测

### `src-tauri/src/pty/slot.rs` — TerminalSlot + RingBuffer（~120 行）

```rust
use portable_pty::{MasterPty, Child};
use uuid::Uuid;

pub struct TerminalSlot {
    pub id: Uuid,
    pub label: String,
    pub cmd: String,
    pub args: Vec<String>,
    pub cwd: String,
    pub env: std::collections::HashMap<String, String>,
    pub status: SlotStatus,
    pub ring_buffer: RingBuffer,
    pub created_at: chrono::DateTime<chrono::Utc>,
    // PTY handles（仅 Running 时有值）
    master: Option<Box<dyn MasterPty + Send>>,
    child: Option<Box<dyn Child + Send>>,
}

pub enum SlotStatus {
    Running { pid: u32 },
    Exited { code: i32 },
    Restarting,
}

pub struct RingBuffer {
    chunks: Vec<Vec<u8>>,
    buffer_length: usize,
    max_size: usize,        // 10MB
    dirty: bool,
}

impl RingBuffer {
    pub fn new(max_size: usize) -> Self;
    pub fn push(&mut self, data: Vec<u8>);
    pub fn get_replay(&mut self) -> Vec<u8>;      // 带缓存
    pub fn clear(&mut self);
    pub fn trim(&mut self);                        // 超 1.1x 时裁剪
}
```

**对应关系：** `pty.js` 的 `_chunks[]` + `_bufferLength` + `_flattenAndTrim()` → `RingBuffer`

### `src-tauri/src/pty/health.rs` — 僵尸检测 + 资源监控（~80 行）

```rust
use std::collections::HashMap;
use uuid::Uuid;

/// 每 5s 调用一次，检测所有 slot 的进程状态
pub fn check_health(slots: &HashMap<Uuid, TerminalSlot>) -> Vec<HealthReport> {
    // 1. 检查 /proc/{pid}/status（Linux）或 ps（macOS）
    // 2. 检测僵尸进程（Z 状态）
    // 3. 检测 RSS 超限（>2GB 告警）
    // 4. 返回需要清理的 slot 列表
}

pub struct HealthReport {
    pub id: Uuid,
    pub pid: u32,
    pub is_zombie: bool,
    pub rss_bytes: u64,
    pub action: HealthAction,    // None / Kill / Warn
}

pub enum HealthAction {
    None,
    Kill,            // 自动 SIGKILL
    Warn { msg: String },  // 弹窗提醒用户
}
```

### `src-tauri/src/session/mod.rs` — SessionStore（~100 行）

```rust
mod schema;
use rusqlite::Connection;
use uuid::Uuid;

pub struct SessionStore {
    db: std::sync::Mutex<Connection>,
}

impl SessionStore {
    pub fn new(data_dir: std::path::PathBuf) -> Result<Self>;
    pub fn save_slot(&self, slot: &SlotSummary) -> Result<()>;
    pub fn load_all(&self) -> Result<Vec<PersistentSlot>>;
    pub fn delete_slot(&self, id: Uuid) -> Result<()>;
}

pub struct PersistentSlot {
    pub id: Uuid,
    pub label: String,
    pub cmd: String,
    pub args: Vec<String>,
    pub cwd: String,
    pub env: HashMap<String, String>,
    pub created_at: String,
}
```

### `src-tauri/src/session/schema.rs` — SQLite Schema（~30 行）

```sql
CREATE TABLE IF NOT EXISTS terminals (
    id TEXT PRIMARY KEY,
    label TEXT NOT NULL,
    cmd TEXT NOT NULL,
    args TEXT NOT NULL,    -- JSON array
    cwd TEXT NOT NULL,
    env TEXT NOT NULL,     -- JSON object
    created_at TEXT NOT NULL
);
```

### `src-tauri/src/tray.rs` — 系统托盘（~60 行）

```rust
use tauri::{App, Manager};
use tauri_plugin_tray::{TrayIcon, TrayIconBuilder};

pub fn setup(app: &mut App) -> Result<(), Box<dyn std::error::Error>> {
    // 创建托盘图标
    // 菜单项：显示窗口 / 新建终端 / 退出
    // 点击关闭按钮 → 隐藏到托盘而非退出
}
```

### `src-tauri/src/commands.rs` — Tauri Invoke 命令（~120 行）

```rust
use tauri::State;

#[derive(serde::Serialize, serde::Deserialize)]
pub struct SpawnResult { pub id: String, pub pid: u32 }

#[tauri::command]
pub async fn pty_spawn(
    cmd: String, args: Vec<String>, cwd: String, env: HashMap<String, String>,
    state: State<'_, MultiPtyManager>,
) -> Result<SpawnResult, String> { /* ... */ }

#[tauri::command]
pub async fn pty_kill(id: String, state: State<'_, MultiPtyManager>) -> Result<(), String> { /* ... */ }

#[tauri::command]
pub async fn pty_restart(id: String, state: State<'_, MultiPtyManager>) -> Result<(), String> { /* ... */ }

#[tauri::command]
pub async fn pty_write(id: String, data: String, state: State<'_, MultiPtyManager>) -> Result<(), String> { /* ... */ }

#[tauri::command]
pub async fn pty_resize(id: String, cols: u16, rows: u16, state: State<'_, MultiPtyManager>) -> Result<(), String> { /* ... */ }

#[tauri::command]
pub async fn pty_list(state: State<'_, MultiPtyManager>) -> Result<Vec<SlotSummary>, String> { /* ... */ }

#[tauri::command]
pub async fn pty_rename(id: String, label: String, state: State<'_, MultiPtyManager>) -> Result<(), String> { /* ... */ }

#[tauri::command]
pub async fn session_restore(state: State<'_, SessionStore>) -> Result<Vec<PersistentSlot>, String> { /* ... */ }

#[tauri::command]
pub async fn session_save(slots: Vec<PersistentSlot>, state: State<'_, SessionStore>) -> Result<(), String> { /* ... */ }

#[tauri::command]
pub async fn cc_status(project_dir: String, global_dir: String) -> Result<CcStatus, String> {
    // 移植自 cc-status.js 的 loadCcStatusAsync()
    // 读取 .claude/skills/, .claude/agents/, settings.json 等
}
```

### `src-tauri/src/events.rs` — IPC 事件（~20 行）

```rust
use serde::Serialize;

/// PTY 输出事件（Rust → 前端）
#[derive(Serialize, Clone)]
#[serde(tag = "event", content = "payload")]
pub enum PtyEvent {
    #[serde(rename = "pty:data")]
    Data { id: String, data: String },   // base64

    #[serde(rename = "pty:exit")]
    Exit { id: String, code: i32 },

    #[serde(rename = "pty:health")]
    Health { id: String, status: String },
}
```

### `src-tauri/src/config.rs` — 应用配置（~25 行）

```rust
pub struct AppConfig {
    pub default_cmd: String,         // "claude"
    pub default_args: Vec<String>,   // ["--permission-mode", "bypassPermissions"]
    pub default_cwd: String,          // 工作目录
    pub max_terminals: usize,        // 10
    pub health_check_interval_ms: u64,  // 5000
    pub ring_buffer_max_mb: usize,   // 10
}

impl AppConfig {
    pub fn load() -> Self { /* 从环境变量 + 默认值 */ }
}
```

### `src-tauri/src/cc_status.rs` — Claude Code 状态读取（~150 行）

**对应关系：** `cc-status.js` 的 `loadCcStatusAsync()` → Rust 版本
- 同样的文件系统扫描逻辑（skills/, agents/, settings.json）
- 同样的 cron 表达式计算（`cronNext()`）
- 同样的 TTL 缓存机制
- 用 `rusqlite` + `serde_json` 替代 Node 的 `fs` + `JSON.parse`

---

## 前端侧详细设计

### `src/index.html` — 入口（~40 行）

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>OneCode Desktop</title>
  <link rel="stylesheet" href="styles.css">
  <link rel="stylesheet" href="../static/xterm.css">
  <link rel="stylesheet" href="../static/hljs.css" media="print" onload="this.media='all'">
</head>
<body>
  <div class="app" id="app"></div>
  <script type="module" src="main.js"></script>
</body>
</html>
```

**vs 现有：** onecode.html 的 981 行 → 拆散到各模块，index.html 仅 ~40 行骨架

### `src/styles.css` — 主样式（~260 行）

**来源：** 从 onecode.html `<style>` 段提取，新增 Tab 栏样式

```css
/* ═══ 复用 onecode.html 原有样式 ═══ */
:root { --bg: #080a12; ... }       /* 原 line 10 */
.app { display: flex; ... }         /* 原 line 16-22 */
.hdr { ... }                        /* 原 line 25-28 */
.b { ... }                          /* 原 line 30-33 */
.brand { ... }                      /* 原 line 36-39 */
/* ... 所有原有样式 ... */

/* ═══ 新增：Tab 栏 ═══ */
.tab-bar { display: flex; height: 36px; background: var(--sf); border-bottom: 1px solid var(--bd); }
.tab-item { display: flex; align-items: center; gap: 4px; padding: 0 12px; cursor: pointer;
            border-right: 1px solid var(--bd); color: var(--tx3); transition: all .15s; }
.tab-item.active { background: var(--bg); color: var(--tx); border-bottom: 2px solid var(--ac); }
.tab-item:hover { background: var(--sf2); }
.tab-dot { width: 6px; height: 6px; border-radius: 50%; }       /* 运行中 = 绿, 退出 = 灰 */
.tab-close { width: 14px; height: 14px; border-radius: 3px; opacity: 0; transition: opacity .15s; }
.tab-item:hover .tab-close { opacity: .6; }
.tab-close:hover { background: var(--red); color: #fff; opacity: 1; }
.tab-new { /* + 按钮样式 */ }
```

### `src/main.js` — 应用入口（~50 行）

```javascript
import { initLayout } from './layout/layout.js';
import { initKeybindings } from './layout/keybindings.js';
import { initMobile } from './layout/mobile.js';
import { TabManager } from './terminal/tab-manager.js';
import { initSidebar } from './sidebar/sidebar.js';
import { initPreview } from './preview/preview.js';

// 初始化各模块
const tabManager = new TabManager();
tabManager.init();

initLayout();
initKeybindings(tabManager);
initMobile();
initSidebar();
initPreview();

// 恢复上次会话
tabManager.restore();
```

### `src/ipc-bridge.js` — Tauri IPC 封装（~40 行）

```javascript
const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

export async function ptySpawn(cmd, args, cwd, env) {
    return invoke('pty_spawn', { cmd, args, cwd, env });
}
export async function ptyKill(id) { return invoke('pty_kill', { id }); }
export async function ptyRestart(id) { return invoke('pty_restart', { id }); }
export async function ptyWrite(id, data) { return invoke('pty_write', { id, data }); }
export async function ptyResize(id, cols, rows) { return invoke('pty_resize', { id, cols, rows }); }
export async function ptyList() { return invoke('pty_list'); }
export async function ptyRename(id, label) { return invoke('pty_rename', { id, label }); }
export async function sessionRestore() { return invoke('session_restore'); }

// 监听 Rust → 前端事件
export function onPtyData(id, callback) {
    return listen(`pty:data:${id}`, (event) => callback(event.payload));
}
export function onPtyExit(id, callback) {
    return listen(`pty:exit:${id}`, (event) => callback(event.payload));
}
export function onPtyHealth(callback) {
    return listen('pty:health', (event) => callback(event.payload));
}
```

### `src/terminal/terminal.js` — xterm.js 初始化（~90 行）

**来源：** `term.js` 的 xterm 初始化 + 主题部分

```javascript
import { Terminal } from '../static/xterm.min.js';
import { FitAddon } from '../static/addon-fit.min.js';
import { WebLinksAddon } from '../static/addon-web-links.min.js';

export function createTerminal(containerEl) {
    const term = new Terminal({
        scrollback: 5000,
        fontSize: 13,
        lineHeight: 1.0,
        fontFamily: "'JetBrains Mono','SF Mono','Fira Code',Consolas,monospace",
        theme: { /* 同 term.js 的主题 */ },
        allowProposedApi: true,
    });

    const fitAddon = new FitAddon.FitAddon();
    term.loadAddon(fitAddon);

    const webLinksAddon = new WebLinksAddon.WebLinksAddon();
    term.loadAddon(webLinksAddon);

    term.open(containerEl);
    fitAddon.fit();

    return { term, fitAddon };
}
```

### `src/terminal/tab-manager.js` — 多终端 Tab 管理（~180 行）🔴 核心新增

```javascript
import { createTerminal } from './terminal.js';
import { ScrollThumb } from './scroll-thumb.js';
import { initImeFix } from './ime-fix.js';
import * as ipc from '../ipc-bridge.js';

export class TabManager {
    constructor() {
        this.tabs = new Map();        // id → TabState
        this.activeId = null;
        this.tabBar = null;           // DOM: tab 栏容器
        this.terminalContainer = null; // DOM: 终端渲染区
    }

    async init() {
        // 创建 DOM 结构：tab-bar + terminal-container
        this.tabBar = document.getElementById('tab-bar');
        this.terminalContainer = document.getElementById('terminals');

        // 绑定 + 按钮事件
        document.getElementById('tab-new').onclick = () => this.createTab();

        // 创建默认终端
        await this.createTab({ label: 'main' });
    }

    async createTab(opts = {}) {
        const label = opts.label || `term-${this.tabs.size + 1}`;
        const result = await ipc.ptySpawn(
            opts.cmd || 'claude',
            opts.args || ['--permission-mode', 'bypassPermissions'],
            opts.cwd || process.cwd(),     // ← Tauri 提供
            opts.env || {}
        );
        const id = result.id;

        // 创建 xterm 实例
        const termEl = document.createElement('div');
        termEl.className = 'term-instance';
        termEl.dataset.id = id;
        termEl.style.display = 'none';
        this.terminalContainer.appendChild(termEl);

        const { term, fitAddon } = createTerminal(termEl);
        const scrollThumb = new ScrollThumb(term, termEl);

        // IME 修复
        initImeFix(term, termEl);

        // 监听 PTY 输出
        const unlisten = ipc.onPtyData(id, (payload) => {
            const bytes = base64ToBytes(payload.data);
            term.write(bytes);
        });
        const unlistenExit = ipc.onPtyExit(id, (payload) => {
            this.updateTabStatus(id, 'exited', payload.code);
        });

        // 终端输入 → IPC
        term.onData((data) => {
            ipc.ptyWrite(id, data);
        });

        // Resize 通知
        term.onResize(() => {
            ipc.ptyResize(id, term.cols, term.rows);
        });

        // 保存状态
        const tabState = {
            id, label, term, fitAddon, scrollThumb,
            termEl, unlisten, unlistenExit, status: 'running',
        };
        this.tabs.set(id, tabState);

        // 创建 Tab DOM
        this.addTabDom(id, label, 'running');
        this.switchTo(id);

        return id;
    }

    switchTo(id) {
        // 隐藏所有终端，显示目标
        for (const [tabId, state] of this.tabs) {
            state.termEl.style.display = tabId === id ? '' : 'none';
        }
        // 更新 Tab 栏 active 状态
        this.tabBar.querySelectorAll('.tab-item').forEach(el => {
            el.classList.toggle('active', el.dataset.id === id);
        });
        // Fit 当前终端
        const state = this.tabs.get(id);
        if (state) {
            setTimeout(() => state.fitAddon.fit(), 50);
        }
        this.activeId = id;
    }

    async closeTab(id) {
        await ipc.ptyKill(id);
        const state = this.tabs.get(id);
        if (state) {
            state.term.dispose();
            state.termEl.remove();
            state.unlisten();
            state.unlistenExit();
            this.tabs.delete(id);
            this.removeTabDom(id);
        }
        // 切换到剩余 tab
        if (this.activeId === id) {
            const remaining = [...this.tabs.keys()];
            if (remaining.length > 0) this.switchTo(remaining[0]);
            else this.createTab(); // 至少保留一个
        }
    }

    async restartTab(id) {
        await ipc.ptyRestart(id);
        const state = this.tabs.get(id);
        if (state) {
            state.term.reset();
            state.term.clear();
            this.updateTabStatus(id, 'running');
        }
    }

    async restore() {
        const slots = await ipc.sessionRestore();
        for (const slot of slots) {
            await this.createTab({
                label: slot.label,
                cmd: slot.cmd,
                args: slot.args,
                cwd: slot.cwd,
                env: slot.env,
            });
        }
    }

    // ── DOM 操作 ──

    addTabDom(id, label, status) { /* 创建 tab-item DOM */ }
    removeTabDom(id) { /* 移除 tab-item DOM */ }
    updateTabStatus(id, status, exitCode) { /* 更新 tab dot 颜色 */ }
}
```

### `src/terminal/scroll-thumb.js` — 自定义滚动条（~120 行）

**来源：** `term.js` 的 scroll thumb 段（~170 行精简后）

```javascript
export class ScrollThumb {
    constructor(term, termEl) { /* 创建 scrollTrack + scrollThumb + scrollLabel */ }
    update() { /* 计算 thumb 位置和大小 */ }
    setupDrag() { /* mouse + touch 拖拽 */ }
    setupHover() { /* hover 效果 */ }
}
```

### `src/terminal/ime-fix.js` — CJK 输入法修复（~50 行）

**来源：** `term.js` 的 `fixDesktopPaste` + `fixMobileInput`

```javascript
export function initImeFix(term, termEl) {
    // Desktop: paste 后清空 textarea 防止重复
    // Mobile: composition 期间阻止 keydown，compositionend 后清空
    // 与 term.js 逻辑完全一致，仅适配多实例
}
```

### `src/terminal/transport-local.js` — 本地 PTY 通信（~30 行）

```javascript
// 封装 ipc-bridge 的 PTY 通信为统一接口
// TabManager 直接用 ipc-bridge 即可，此文件仅做抽象层
// 以便 M3 时 transport-ws.js 可以无缝替换

export class LocalTransport {
    constructor(id) { this.id = id; }
    write(data) { return ipc.ptyWrite(this.id, data); }
    resize(cols, rows) { return ipc.ptyResize(this.id, cols, rows); }
    onData(cb) { return ipc.onPtyData(this.id, cb); }
    onExit(cb) { return ipc.onPtyExit(this.id, cb); }
}
```

### `src/sidebar/sidebar.js` — 侧栏容器（~50 行）

**来源：** onecode.html 的 `togSb()`, `sbOn` 逻辑

```javascript
export function initSidebar() {
    // toggle 侧栏
    // Ctrl+B 快捷键
    // 连接文件树和 Agent 列表
}
```

### `src/sidebar/file-tree.js` — 文件树（~130 行）

**来源：** onecode.html 的 `nav()`, `renTree()`, `renBcr()`, `fIcon()`, `fmtSz()` 等

```javascript
export function initFileTree() {
    // 文件树渲染（从 cc-status API 获取目录列表）
    // 面包屑导航
    // 文件类型图标
    // 点击文件 → 预览
}
```

### `src/sidebar/agents.js` — Agent 列表 + @mention（~110 行）

**来源：** onecode.html 的 `renderAgents()`, `showMention()`, `hideMention()` + @mention 键盘导航

```javascript
export function initAgents(tabManager) {
    // 从 cc-status 加载 Agent 列表
    // 渲染 Agent 面板
    // @mention 弹窗 + 键盘导航（↑↓ Enter Tab）
    // 点击 Agent → 向当前终端发送 @roleId
}
```

### `src/sidebar/cc-badges.js` — CC 状态徽章（~60 行）

**来源：** onecode.html 的 `renderCcBadges()`, `renderCcPop()`, `toggleCcPop()`

```javascript
export function initCcBadges() {
    // 定时轮询 cc_status 命令
    // 渲染 skills/hooks/plugins/tasks 徽章
    // 点击徽章 → 弹出详情面板
}
```

### `src/preview/preview.js` — 预览面板（~60 行）

**来源：** onecode.html 的 `openPrev()`, `closePrev()`, `refreshPreview()`

```javascript
export function initPreview() {
    // 打开/关闭预览面板
    // resize handle
    // 文件类型路由 → markdown.js / code-view.js / 图片 / PDF / 二进制
}
```

### `src/preview/markdown.js` — Markdown 渲染（~50 行）

**来源：** onecode.html 的 `marked` 初始化 + `sanitizeHtml()`

```javascript
export function renderMarkdown(text) {
    // XSS 过滤
    // marked.parse() 渲染
    // hljs 代码高亮
}
```

### `src/preview/code-view.js` — 代码高亮（~30 行）

**来源：** onecode.html 的 `hlCode()` + 代码预览渲染

```javascript
export function renderCode(text, lang) {
    // hljs 高亮
    // Copy 按钮
}
```

### `src/layout/layout.js` — 布局（~50 行）

**来源：** onecode.html 的 resize handle + 面板布局

```javascript
export function initLayout() {
    // 三栏布局（Terminal + Preview + Sidebar）
    // resize handle 拖拽
    // 窗口大小变化响应
}
```

### `src/layout/keybindings.js` — 全局快捷键（~30 行）

**来源：** onecode.html 的 keydown 监听 + 新增 Tab 快捷键

```javascript
export function initKeybindings(tabManager) {
    // Cmd/Ctrl + T  → 新建终端
    // Cmd/Ctrl + W  → 关闭当前终端
    // Cmd/Ctrl + 1~9 → 切换终端
    // Cmd/Ctrl + Shift + [/] → 上/下一个终端
    // Cmd/Ctrl + B → 切换侧栏
    // Esc → 关闭预览
}
```

### `src/layout/mobile.js` — 移动端适配（~60 行）

**来源：** onecode.html 的 `mSwitch()`, `chkMob()`, 虚拟键盘逻辑

```javascript
export function initMobile() {
    // 屏幕宽度检测
    // 4-Tab 切换（Terminal/Preview/Files/Agents）
    // 虚拟键盘
    // Swipe 切换
}
```

### `src/remote/transport-ws.js` — 远程终端通信（M3 可选，~80 行）

**来源：** `term.js` 的 WebSocket 连接逻辑

```javascript
// 与现有 term.js 的 WS 二进制协议完全兼容
// 通过 WebSocket 连接远程 gateway:7681/ws/term
// 支持: replay, resize, restart, 二进制帧
```

---

## 配置文件

### `src-tauri/tauri.conf.json`（关键字段）

```json
{
  "productName": "OneCode Desktop",
  "version": "0.1.0",
  "identifier": "com.onecode.desktop",
  "build": { "beforeBuildCommand": "npm run build", "devUrl": "http://localhost:1420" },
  "app": {
    "windows": [{
      "title": "OneCode · AI 原生 IDE",
      "width": 1200, "height": 800,
      "minWidth": 800, "minHeight": 500,
      "decorations": true,
      "transparent": false
    }],
    "trayIcon": { "iconPath": "icons/icon.png", "id": "main-tray" }
  },
  "bundle": {
    "active": true,
    "targets": ["dmg", "appimage", "deb"],
    "icon": ["icons/icon.icns", "icons/icon.png"]
  }
}
```

### `src-tauri/capabilities/default.json`

```json
{
  "identifier": "default",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "shell:allow-open",
    { "identifier": "core:window:allow-close", "allow": [{ "window": "main" }] },
    { "identifier": "core:window:allow-hide", "allow": [{ "window": "main" }] },
    { "identifier": "core:window:allow-show", "allow": [{ "window": "main" }] }
  ]
}
```

### `Cargo.toml`（关键依赖）

```toml
[dependencies]
tauri = { version = "2", features = ["tray-icon"] }
tauri-plugin-shell = "2"
portable-pty = "0.8"
rusqlite = { version = "0.31", features = ["bundled"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
uuid = { version = "1", features = ["v4", "serde"] }
chrono = { version = "0.4", features = ["serde"] }
tokio = { version = "1", features = ["full"] }
base64 = "0.22"
```

---

## 代码量估算

### Rust 侧

| 文件 | 行数 | 新写 | 改造自 | 来源 |
|------|------|------|--------|------|
| `main.rs` | ~15 | ✅ | — | 新 |
| `lib.rs` | ~80 | ✅ | — | 新 |
| `pty/mod.rs` | ~180 | ✅ | pty.js | 重写（1→N） |
| `pty/slot.rs` | ~120 | ✅ | pty.js | 重写（RingBuffer） |
| `pty/health.rs` | ~80 | ✅ | — | 新增 |
| `session/mod.rs` | ~100 | ✅ | — | 新增 |
| `session/schema.rs` | ~30 | ✅ | — | 新增 |
| `tray.rs` | ~60 | ✅ | — | 新增 |
| `commands.rs` | ~120 | ✅ | — | 新增 |
| `events.rs` | ~20 | ✅ | — | 新增 |
| `config.rs` | ~25 | ✅ | config.js | 简化 |
| `cc_status.rs` | ~150 | ⚡ | cc-status.js | 移植 |
| **Rust 小计** | **~980** | | | |

### 前端侧

| 文件 | 行数 | 新写 | 改造自 | 来源 |
|------|------|------|--------|------|
| `index.html` | ~40 | ✅ | — | 新 |
| `styles.css` | ~260 | ⚡ | onecode.html CSS | 提取+新增Tab |
| `main.js` | ~50 | ✅ | — | 新 |
| `ipc-bridge.js` | ~40 | ✅ | — | 新 |
| `terminal/terminal.js` | ~90 | ⚡ | term.js | 提取 |
| `terminal/tab-manager.js` | ~180 | ✅ | — | 🔴核心新增 |
| `terminal/scroll-thumb.js` | ~120 | ⚡ | term.js | 提取 |
| `terminal/ime-fix.js` | ~50 | ⚡ | term.js | 提取 |
| `terminal/transport-local.js` | ~30 | ✅ | — | 新 |
| `sidebar/sidebar.js` | ~50 | ⚡ | onecode.html | 提取 |
| `sidebar/file-tree.js` | ~130 | ⚡ | onecode.html | 提取 |
| `sidebar/agents.js` | ~110 | ⚡ | onecode.html | 提取 |
| `sidebar/cc-badges.js` | ~60 | ⚡ | onecode.html | 提取 |
| `preview/preview.js` | ~60 | ⚡ | onecode.html | 提取 |
| `preview/markdown.js` | ~50 | ⚡ | onecode.html | 提取 |
| `preview/code-view.js` | ~30 | ⚡ | onecode.html | 提取 |
| `layout/layout.js` | ~50 | ⚡ | onecode.html | 提取 |
| `layout/keybindings.js` | ~30 | ⚡ | onecode.html | 提取+扩展 |
| `layout/mobile.js` | ~60 | ⚡ | onecode.html | 提取 |
| `remote/transport-ws.js` | ~80 | ⚡ | term.js | M3提取 |
| **前端小计** | **~1,630** | | | |

### 总量对比

| 类别 | 行数 | 新写 | 改造/提取 | 复用（直接拷贝） |
|------|------|------|-----------|-----------------|
| Rust | ~980 | ~600 | ~380 | 0 |
| 前端 | ~1,630 | ~310 | ~1,240 | 0 |
| 静态资源 | ~0 | 0 | 0 | ~直接拷贝 |
| 配置/脚本 | ~100 | ~100 | 0 | 0 |
| **合计** | **~2,710** | **~1,010 (37%)** | **~1,620 (60%)** | **直接拷贝** |

**新写 vs 改造 vs 复用：** 37% / 60% / 静态资源直接拷贝

---

## 模块依赖图

```
main.js
  ├── layout/layout.js
  ├── layout/keybindings.js ──── terminal/tab-manager.js
  ├── layout/mobile.js
  ├── terminal/tab-manager.js ──── terminal/terminal.js
  │                              ├── terminal/scroll-thumb.js
  │                              ├── terminal/ime-fix.js
  │                              ├── terminal/transport-local.js
  │                              └── ipc-bridge.js
  ├── sidebar/sidebar.js ──── sidebar/file-tree.js
  │                          ├── sidebar/agents.js ──── terminal/tab-manager.js
  │                          └── sidebar/cc-badges.js
  ├── preview/preview.js ──── preview/markdown.js
  │                          └── preview/code-view.js
  └── ipc-bridge.js (底层，被所有模块依赖)
```

**循环依赖避免：**
- `agents.js` 需要 `tab-manager.js`（发送 @mention 到终端）→ 通过回调注入，不直接 import
- `keybindings.js` 需要 `tab-manager.js` → 构造时注入

---

## onecode.html → 模块映射表

| onecode.html 行号范围 | 功能 | 目标文件 |
|----------------------|------|---------|
| 10-257 | `<style>` 全部样式 | `styles.css` |
| 261-316 | 终端面板 HTML + 虚拟键盘 | `index.html` + `layout/mobile.js` |
| 320-344 | Preview + Sidebar HTML | `index.html` |
| 346-367 | Mobile tab bar HTML | `index.html` + `layout/mobile.js` |
| 382-472 | Agent 渲染 + @mention | `sidebar/agents.js` |
| 474-541 | CC status badges | `sidebar/cc-badges.js` |
| 547-605 | auth + sanitize + hlCode | `preview/markdown.js` + `preview/code-view.js` |
| 607-618 | marked 初始化 | `preview/markdown.js` |
| 620-697 | 文件类型 + 图标 + ftype | `sidebar/file-tree.js` |
| 699-767 | 面包屑 + 文件树 + 刷新 | `sidebar/file-tree.js` |
| 769-833 | 移动端适配 | `layout/mobile.js` |
| 841-857 | 快捷键 | `layout/keybindings.js` |
| 859-893 | 虚拟键盘 | `layout/mobile.js` |
| 895-931 | resize handle + swipe | `layout/layout.js` |
| 933-975 | new session + wake lock + refresh | `terminal/tab-manager.js` |

---

**Why:** CEO 要求详细设计 OneCode Desktop 客户端的目录代码结构，为实施阶段提供精确蓝图
**How to apply:** 按 M1 优先实现 Rust `pty/` + 前端 `terminal/`，M2 补齐 `tab-manager.js`，M3 补齐 `session/` + `tray.rs` + `remote/`
