---
name: desktop-client-architecture
description: OneCode Desktop 客户端技术架构方案（2026 Q3）— 已被 [[desktop-architecture-review]] 修订
metadata:
  type: project
---

# OneCode Desktop — 技术架构方案

> 目标：制作桌面客户端，管理多个 terminal，一键开启/切换/管理

## 1. 整体架构

```
┌─────────────────────────────────────────────────┐
│              OneCode Desktop (Tauri)             │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │           Frontend (WebView)                │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐      │  │
│  │  │ Term 1  │ │ Term 2  │ │ Term 3  │ ...  │  │
│  │  │ xterm.js│ │ xterm.js│ │ xterm.js│      │  │
│  │  └────┬────┘ └────┬────┘ └────┬────┘      │  │
│  │       │           │           │            │  │
│  │  ┌────▼───────────▼───────────▼────┐      │  │
│  │  │      Terminal Tab Manager       │      │  │
│  │  │  (创建/关闭/切换/重命名/拖拽)   │      │  │
│  │  └────────────┬────────────────────┘      │  │
│  └───────────────┼───────────────────────────┘  │
│                  │ Tauri IPC (invoke)           │
│  ┌───────────────▼───────────────────────────┐  │
│  │        Rust Backend (Core)               │  │
│  │                                          │  │
│  │  ┌──────────────────────────────────┐    │  │
│  │  │     MultiPtyManager              │    │  │
│  │  │  - spawn / kill / restart PTY    │    │  │
│  │  │  - ring buffer per PTY          │    │  │
│  │  │  - process health monitor       │    │  │
│  │  └──────────────────────────────────┘    │  │
│  │                                          │  │
│  │  ┌──────────────────────────────────┐    │  │
│  │  │     SessionStore (SQLite)        │    │  │
│  │  │  - terminal metadata            │    │  │
│  │  │  - session restore on launch     │    │  │
│  │  └──────────────────────────────────┘    │  │
│  │                                          │  │
│  │  ┌──────────────────────────────────┐    │  │
│  │  │     TrayManager                 │    │  │
│  │  │  - 系统托盘常驻                 │    │  │
│  │  │  - 窗口隐藏/显示               │    │  │
│  │  └──────────────────────────────────┘    │  │
│  └──────────────────────────────────────────┘  │
│                                                  │
│  ┌──────────────────────────────────────────┐  │
│  │     RemoteGateway (可选)                  │  │
│  │  WebSocket → 远程 gateway:7681/ws/term    │  │
│  └──────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

**两种连接模式：**

| 模式 | 路径 | 适用场景 |
|------|------|---------|
| **本地模式** | Rust → `portable-pty` → Claude Code PTY | 本地开发，零依赖 |
| **远程模式** | Frontend → WebSocket → gateway `/ws/term` | 连接远程 Docker/云实例 |

MVP 先做本地模式，远程模式作为 M3 附加交付。

## 2. 技术选型论证

### 推荐：Tauri v2

| 维度 | Tauri v2 | Electron 33 | 原生 |
|------|----------|-------------|------|
| 安装包大小 | ~5-8 MB | ~150-200 MB | ~20-50 MB/app |
| 运行时内存 | ~30-50 MB | ~200-400 MB | ~30-80 MB |
| PTY 集成 | Rust 原生 `portable-pty` | 需要 node-pty native addon | 原生 API |
| 前端复用 | ✅ WebView 直接复用 onecode.html 终端逻辑 | ✅ 完全兼容 | ❌ 需重写 |
| macOS + Linux | ✅ 双平台 | ✅ 双平台 | ❌ 两套代码 |
| 安全性 | 权限模型严格，IPC 白名单 | 全权访问 Node.js | 原生权限 |
| 一人公司适配 | ⭐⭐⭐⭐⭐ 学习曲线可控 | ⭐⭐⭐⭐ 生态成熟但包体痛点 | ⭐ 不现实 |

**关键决策理由：**

1. **PTY 是核心**——Rust 侧有 `portable-pty` crate，跨平台 PTY 管理比 node-pty 更干净
2. **一人公司**——5MB vs 200MB 安装包是分发效率的数量级差异
3. **内存**——5 个并发终端 × Electron = 吃掉 1-2GB 内存，Tauri 可以控制在 300MB 内
4. **前端复用**——xterm.js、样式、Agent 加载逻辑均可直接移植到 WebView

### 依赖清单

**Rust 侧：**
- `portable-pty` — 跨平台 PTY（macOS/Linux/Windows）
- `tauri` v2 — 桌面框架
- `serde` / `serde_json` — IPC 序列化
- `rusqlite` — SQLite 会话持久化
- `tokio` — 异步运行时（Tauri v2 内置）
- `tray-icon` — 系统托盘

**前端侧：**
- `@xterm/xterm` + addons — 终端渲染（从 gateway/static/ 复用）
- `marked` + `highlight.js` — Markdown 渲染（复用）
- 无需 React/Vue——纯 Vanilla JS，与现有 onecode.html 一致

## 3. 核心模块设计

### 3.1 MultiPtyManager（Rust 侧）

```rust
// 核心数据结构
struct TerminalSlot {
    id: Uuid,
    label: String,          // 用户可重命名，如 "main", "bugfix-42"
    pty: Box<dyn PtyMaster + Send>,
    reader: BufReader<Box<dyn PtySlave + Send>>,
    cmd: String,            // e.g. "claude"
    args: Vec<String>,
    cwd: PathBuf,
    env: HashMap<String, String>,
    status: SlotStatus,     // Running / Exited(code) / Restarting
    ring_buffer: RingBuffer, // 10MB per slot
    created_at: DateTime<Utc>,
}

enum SlotStatus {
    Running { pid: u32 },
    Exited { code: i32 },
    Restarting,
}

struct MultiPtyManager {
    slots: HashMap<Uuid, TerminalSlot>,
    active_id: Uuid,          // 当前活跃终端
    max_slots: usize,          // 默认 10
    health_check_interval: Duration, // 5s
}
```

**关键行为：**

- `spawn(cmd, args, cwd, env)` → 返回 `Uuid`，自动分配 slot
- `kill(id)` → SIGTERM → 3s → SIGKILL（优雅退出链）
- `restart(id)` → 复用 cmd/args/cwd/env，清空 ring buffer，通知前端 CTRL_RESET
- `resize(id, cols, rows)` → PTY resize
- `write(id, data: Vec<u8>)` → 前端输入写入 PTY
- `read_stream(id)` → 异步流，通过 IPC 事件推送到前端
- `health_check()` — 定时检测僵尸进程（pid 存在但无响应），自动清理

**与现有 pty.js 的对应关系：**

| pty.js (Node) | MultiPtyManager (Rust) | 变化 |
|---------------|----------------------|------|
| 单 ptyProcess | HashMap<Uuid, TerminalSlot> | 1→N |
| _chunks[] ring buffer | RingBuffer per slot | 每 slot 独立 |
| WS broadcast | Tauri IPC events | 通信层替换 |
| auto-restart (10次上限) | auto-restart + 僵尸检测 | 增强健康监控 |

### 3.2 前端终端管理

```javascript
// TerminalTabManager — 管理多个 xterm.js 实例
class TerminalTabManager {
    constructor() {
        this.tabs = new Map();     // id → { xterm, addonFit, ws, status }
        this.activeId = null;
    }

    async createTab(opts = {}) {
        const id = await invoke('pty_spawn', {
            cmd: opts.cmd || 'claude',
            args: opts.args || ['--permission-mode', 'bypassPermissions'],
            cwd: opts.cwd || defaultCwd,
        });
        const xterm = new Terminal({ ...terminalOptions });
        const fitAddon = new FitAddon();
        xterm.loadAddon(fitAddon);
        // ... setup IPC listeners
        this.tabs.set(id, { xterm, fitAddon, status: 'running' });
        this.switchTo(id);
        return id;
    }

    switchTo(id) { /* 显示目标 tab 的 xterm，隐藏其他 */ }
    closeTab(id) { /* invoke('pty_kill', {id}), 清理 xterm */ }
    renameTab(id, label) { /* invoke('pty_rename', {id, label}) */ }
}
```

**Tab UI 设计：**

```
┌─────────────────────────────────────────────────────┐
│ [+] [main●] [bugfix-42●] [refactor○]               │  ← Tab 栏
│─────────────────────────────────────────────────────│
│                                                     │
│  xterm.js 终端内容（当前活跃 tab）                    │
│                                                     │
│                                                     │
└─────────────────────────────────────────────────────┘
  ● = running   ○ = exited   ✕ = close button on hover
```

**快捷键：**
- `Cmd/Ctrl + T` — 新建终端
- `Cmd/Ctrl + W` — 关闭当前终端
- `Cmd/Ctrl + 1~9` — 切换到第 N 个终端
- `Cmd/Ctrl + Shift + [/]` — 上/下一个终端

### 3.3 通信层：Tauri IPC

**前端 → Rust（invoke 命令）：**

| 命令 | 参数 | 返回 |
|------|------|------|
| `pty_spawn` | `{cmd, args, cwd, env}` | `{id, pid}` |
| `pty_kill` | `{id}` | `{ok: bool}` |
| `pty_restart` | `{id}` | `{ok: bool}` |
| `pty_write` | `{id, data: string}` | `{ok: bool}` |
| `pty_resize` | `{id, cols, rows}` | `{ok: bool}` |
| `pty_list` | — | `{slots: [{id, label, status}]}` |
| `pty_rename` | `{id, label}` | `{ok: bool}` |
| `session_restore` | — | `{slots: [...]}` |

**Rust → 前端（IPC 事件推送）：**

| 事件 | payload | 触发时机 |
|------|---------|---------|
| `pty:data:{id}` | `{data: base64_string}` | PTY 有输出 |
| `pty:exit:{id}` | `{code: i32}` | PTY 进程退出 |
| `pty:health` | `{id, status}` | 健康检测状态变更 |
| `pty:replay:{id}` | `{data: base64_string}` | 新客户端连接时回放 |

**数据传输优化：**
- PTY 输出使用 `base64` 编码通过 IPC（Tauri 2.x 的 IPC 底层是系统原生 IPC，非 WebSocket，延迟 < 1ms）
- 批量合并：Rust 侧用 `setImmediate` 等价逻辑（tokio `tick()`）合并短帧
- 与现有二进制协议对齐：保留 `FRAME_CTRL`/`FRAME_PTY` 语义，前端解析逻辑可复用

## 4. 与现有代码的关系

| 现有模块 | 处置 | 理由 |
|----------|------|------|
| `gateway/pty.js` | **重写 → Rust** | 核心变 1→N，协议从 WS 改 IPC |
| `gateway/term-ws.js` | **保留**（远程模式复用） | 远程连接仍走 WS |
| `gateway/index.js` | **保留** | 本地桌面不依赖，但远程 gateway 仍需要 |
| `gateway/onecode.html` | **提取 → 拆分** | 终端逻辑提取为模块，UI 部分改造为 Tab 布局 |
| `gateway/static/` | **复用** | xterm.js/hljs/marked 直接复制到 Tauri 的 `dist/` |
| `gateway/config.js` | **适配** | 增加本地模式配置（默认不启动 HTTP server） |
| `gateway/cc-status.js` | **复用** | Agent 列表逻辑可直接迁移到 Rust 侧的文件读取 |
| `Dockerfile` | **保留不动** | Web 版 + Docker 场景不变 |

**前端代码复用策略：**

```
onecode.html (900+ 行单文件)
    │
    ├── 提取 ──→ src/terminal.js    (xterm 初始化 + 数据协议)
    ├── 提取 ──→ src/agents.js      (Agent 加载 + @mention)
    ├── 提取 ──→ src/preview.js     (Markdown/代码预览)
    ├── 提取 ──→ src/sidebar.js     (文件树 + Agent 列表)
    ├── 新增 ──→ src/tab-manager.js (多终端 Tab 管理)
    ├── 保留 ──→ src/styles.css      (样式复用，扩展 Tab 样式)
    └── 新增 ──→ src/ipc-bridge.js  (Tauri invoke 封装)
```

## 5. 关键技术难点

### 5.1 多 PTY 进程管理

**风险：** 多个 Claude Code 实例同时运行，CPU/内存/端口冲突

**对策：**
- 每个 PTY 独立进程组，Rust 侧追踪 PID
- 设置资源上限：`max_slots = 10`，单 slot 内存 > 2GB 时告警
- Claude Code 默认占用端口递增检测：启动时扫描占用端口，自动调整
- OOM 预防：Rust 侧监控子进程 RSS，超过阈值弹窗提醒用户

### 5.2 僵尸进程清理

**风险：** PTY 进程退出但 PID 未回收，或卡在 D 状态

**对策：**
- `health_check()` 每 5s 轮询：检查 `/proc/{pid}/status`（Linux）或 `ps`（macOS）
- 僵尸检测：进程存在但无 PTY 响应 → SIGTERM → 3s → SIGKILL → 回收 slot
- 前端显示状态：Running(绿) / Exited(灰) / Zombie(红，自动修复中)

### 5.3 PTY 输出流与 Tab 切换

**风险：** 切换 Tab 时，非活跃终端的输出仍在产生，需要缓存

**对策：**
- Rust 侧每个 slot 有独立 ring buffer（10MB）
- 前端切换到某 tab 时，调用 `invoke('pty_replay', {id})` 获取 buffer
- 非活跃 tab 不渲染 xterm（detached from DOM），但持续接收 data 事件更新 buffer
- 重附着时：清空 xterm → 写入 replay → 恢复实时流

### 5.4 会话持久化

**风险：** 应用重启后终端历史丢失

**对策：**
- SQLite (`rusqlite`) 存储 slot 元数据：`{id, label, cmd, args, cwd, env, created_at}`
- Ring buffer 写入磁盘：退出时每个 slot 的 buffer dump 到 `~/.onecode/sessions/{id}.buf`
- 启动时恢复：读取 DB → 重新 spawn PTY → 丢弃历史 buffer（PTY 无法真正恢复状态）
- **设计取舍：** 不追求"恢复终端内容"（与 tmux 不同），只恢复"终端配置"——用户打开同样的终端

### 5.5 前端单文件拆分

**风险：** onecode.html 是 900+ 行单文件，直接迁移会变成巨石

**对策：**
- MVP 阶段允许适度耦合，先跑通再拆分
- 拆分顺序：terminal.js → tab-manager.js → 其余模块
- 不引入构建工具（webpack/vite），保持与现有项目一致的零构建风格
- 用 ES Module `<script type="module">` 组织代码

## 6. 目录结构

```
onecode-desktop/
├── src-tauri/                    # Rust 后端
│   ├── Cargo.toml
│   ├── tauri.conf.json           # Tauri 配置（窗口、权限）
│   ├── capabilities/             # Tauri v2 权限声明
│   │   └── default.json
│   ├── src/
│   │   ├── main.rs               # Tauri 入口
│   │   ├── pty/
│   │   │   ├── mod.rs            # MultiPtyManager
│   │   │   ├── slot.rs           # TerminalSlot + RingBuffer
│   │   │   └── health.rs         # 僵尸进程检测
│   │   ├── session/
│   │   │   ├── mod.rs            # SessionStore
│   │   │   └── schema.rs         # SQLite schema
│   │   ├── tray.rs               # 系统托盘
│   │   ├── commands.rs           # Tauri invoke 命令
│   │   └── events.rs             # IPC 事件定义
│   └── icons/                    # 应用图标
│
├── src/                          # 前端
│   ├── index.html                # 入口 HTML
│   ├── styles.css                # 主样式（复用 + 扩展）
│   ├── terminal.js               # xterm.js 封装
│   ├── tab-manager.js            # 多终端 Tab 管理
│   ├── agents.js                 # Agent 列表 + @mention
│   ├── preview.js                # Markdown/代码预览
│   ├── sidebar.js                # 文件树 + Agent 侧栏
│   ├── ipc-bridge.js             # Tauri invoke 封装
│   └── main.js                   # 应用入口
│
├── static/                       # 静态资源（复用 gateway/static/）
│   ├── xterm.min.js
│   ├── xterm.css
│   ├── addon-fit.min.js
│   ├── addon-web-links.min.js
│   ├── addon-webgl.min.js
│   ├── marked.min.js
│   └── highlight.min.js
│
├── package.json                   # 前端依赖（仅开发时）
└── README.md
```

## 7. 里程碑拆解

### M1（第 1-4 周）：技术验证 + 单终端 MVP

**目标：** 证明 Tauri + PTY + xterm.js 链路可行

| 交付物 | 验收标准 |
|--------|---------|
| Tauri 项目脚手架 | `cargo tauri dev` 可启动空窗口 |
| Rust PTY 模块 | `portable-pty` spawn Claude Code，stdout 可读 |
| IPC 通信 | 前端 invoke → Rust spawn → 事件推送 → 前端渲染 |
| 单终端渲染 | xterm.js 显示 Claude Code 输出，键盘输入可达 PTY |
| 窗口基础 | 标题栏显示 "OneCode Desktop"，可 resize |

**M1 完成标志：** 一个窗口，一个终端，能跑通 Claude Code 完整对话

### M2（第 5-8 周）：多终端管理 + 窗口切换

**目标：** 多终端 Tab 管理核心体验

| 交付物 | 验收标准 |
|--------|---------|
| MultiPtyManager | ≥5 个并发 PTY 稳定运行，无僵尸进程 |
| Tab UI | Tab 栏：创建/关闭/切换/重命名，快捷键 Cmd+1~9 |
| Ring Buffer | 切换 Tab 时 replay 无损，非活跃 tab 后台缓存 |
| 健康监控 | 退出/崩溃的终端自动检测，UI 显示状态，支持 restart |
| 资源控制 | 5 个终端总内存 < 500MB，CPU 空闲时 < 5% |

**M2 完成标志：** 5 个 Claude Code 实例并发，Tab 切换流畅，无数据丢失

### M3（第 9-12 周）：打磨 + 持久化 + 打包分发

**目标：** 生产可用，双平台分发

| 交付物 | 验收标准 |
|--------|---------|
| 系统托盘 | 关闭窗口 → 托盘常驻，托盘菜单：新建/显示/退出 |
| 会话持久化 | 退出时保存终端配置，重启恢复所有终端 |
| 远程模式（可选） | WebSocket 连接远程 gateway，Tab 栏区分本地/远程 |
| macOS dmg | `cargo tauri build` 产出 .dmg，可安装运行 |
| Linux AppImage | 产出 .AppImage，可安装运行 |
| Dogfooding | 团队内部使用 Desktop 版替代 Web 版日常开发 |

**M3 完成标志：** macOS + Linux 安装包可用，日常开发可替代 Web 版

---

## 附录：风险矩阵

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| Tauri v2 API 不稳定 | 中 | 高 | 锁定 minor 版本，跟进 changelog |
| portable-pty macOS 兼容性 | 中 | 高 | M1 前两周验证，备选 `winpty` / `ioctl` 直接调用 |
| 多 PTY 内存爆炸 | 低 | 高 | max_slots 限制 + RSS 监控 + 告警 |
| 前端拆分引入 bug | 中 | 中 | 渐进拆分，每步回归测试 |
| Claude Code 多实例端口冲突 | 低 | 中 | 启动时端口扫描 + 自动偏移 |

**Why:** CEO 决定 Q3 开发 OneCode Desktop 客户端，需要架构师出技术方案指导实施
**How to apply:** 按 M1/M2/M3 里程碑推进，M1 重点验证 PTY 链路，M2 重点多终端管理，M3 重点打磨分发
