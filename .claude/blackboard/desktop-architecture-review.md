---
name: desktop-architecture-review
description: OneCode Desktop 架构评估与修订方案（2026-06-19）
metadata:
  type: project
---

# OneCode Desktop — 架构评估与修订方案

> 评审人: Architect | 日期: 2026-06-19 | 基于: [[desktop-client-architecture]] + [[desktop-code-structure]] + [[desktop-prd]]

---

## 1. 总体评价

### ✅ 做对了的

| 决策 | 评价 |
|------|------|
| Tauri v2 选型 | **正确**。v2 于 2024-10-01 已正式 stable，不存在 beta 风险。5MB vs 200MB 安装包是数量级优势 |
| Rust 侧 portable-pty | **正确**。WezTerm 维护，macOS/Linux 双平台稳定，是 PTY crate 最佳选择 |
| 前端 Vanilla JS | **正确**。与现有 onecode.html 一致，一人公司无精力维护 React 构建链 |
| Ring Buffer per slot | **正确**。从 pty.js 实战验证过的设计，10MB/slot 足够回放 |
| M1/M2/M3 里程碑 | **合理**。技术验证 → 核心功能 → 打磨分发，风险递减 |

### ⚠️ 需要修订的

| 问题 | 严重度 | 影响 |
|------|--------|------|
| IPC 使用 base64 编码 PTY 数据 | 🔴 高 | 性能浪费 33%+，Tauri v2 已有原生二进制传输方案 |
| 单仓库存放 | 🟡 中 | Desktop 与 Web 版代码耦合，构建/发布互相干扰 |
| pty:data:{id} 逐事件推送 | 🟡 中 | 高频输出时 IPC 洪水，需批量合并 |
| MultiPtyManager 使用 Mutex 全局锁 | 🟡 中 | kill/spawn/list 等操作争抢同一把锁，影响切换延迟 |
| 前端 transport-local.js 抽象层过早 | 🟢 低 | MVP 阶段不必要，增加理解成本 |

---

## 2. 🔴 关键修订：IPC 数据传输方案

### 原方案的问题

原架构设计：

```
Rust PTY 输出 → base64 编码 → IPC 事件 → 前端 base64 解码 → xterm.write()
```

**问题：**
- base64 编码/解码是纯 CPU 浪费（33% 体积膨胀 + 编解码开销）
- 每次 PTY 输出都触发一次 IPC 事件，高频时产生 IPC 洪水
- 原方案说"Tauri IPC 底层延迟 < 1ms"，但忽略了序列化开销

### 修订方案：Channel 流式二进制传输

Tauri v2 提供了 [`Channel<T>`](https://v2.tauri.app/develop/calling-rust/#streaming) API 和 [`tauri::ipc::Response`](https://v2.tauri.app/develop/calling-rust/) 原生二进制返回：

```
Rust PTY 输出 → Vec<u8> 批量合并 → Channel<Vec<u8>> 推送 → 前端 Uint8Array → xterm.write()
```

**关键改进：**

1. **去掉 base64** — `Channel<Vec<u8>>` 直接传输二进制，零编解码开销
2. **批量合并** — Rust 侧用 tokio `time::tick(16ms)` 合并短帧，1 次推送 vs N 次
3. **流式推送** — 用 `Channel` 而非 `emit` 事件，前端按需消费

### 修订后的 IPC 命令设计

**前端 → Rust（invoke 命令）：**

| 命令 | 参数 | 返回 | 变化 |
|------|------|------|------|
| `pty_spawn` | `{cmd, args, cwd, env, channel}` | `{id, pid}` | 新增 channel 参数 |
| `pty_kill` | `{id}` | `{ok: bool}` | — |
| `pty_restart` | `{id, channel}` | `{ok: bool}` | 新增 channel 参数 |
| `pty_write` | `{id, data: Uint8Array}` | `{ok: bool}` | data 从 string → Uint8Array |
| `pty_resize` | `{id, cols, rows}` | `{ok: bool}` | — |
| `pty_list` | — | `{slots: [...]}` | — |
| `pty_rename` | `{id, label}` | `{ok: bool}` | — |
| `session_restore` | — | `{slots: [...]}` | — |

**Rust → 前端（Channel 流式推送）：**

| Channel | 数据类型 | 替代原方案 |
|---------|---------|-----------|
| `pty_data_ch` | `Vec<u8>` | ~~`pty:data:{id}` base64 事件~~ |
| `pty_exit_ch` | `{id, code}` | `pty:exit:{id}` 事件（保留 emit，低频不需要 Channel） |

### 代码示例

**Rust 侧：**

```rust
use tauri::ipc::Channel;

#[tauri::command]
async fn pty_spawn(
    cmd: String,
    args: Vec<String>,
    cwd: String,
    env: HashMap<String, String>,
    data_channel: Channel<Vec<u8>>,   // ← 二进制流式推送
    app: AppHandle,
    state: State<'_, MultiPtyManager>,
) -> Result<SpawnResult, String> {
    let id = state.spawn(cmd, args, cwd, env, move |id, chunk: Vec<u8>| {
        let _ = data_channel.send(chunk);  // ← 直接推送 Vec<u8>，零编码
    })?;
    Ok(SpawnResult { id: id.to_string(), pid: 0 })
}
```

**前端侧：**

```javascript
import { Channel } from '@tauri-apps/api/core';

async function createTerminal(id) {
    const dataChannel = new Channel();
    dataChannel.onmessage = (chunk) => {
        // chunk 是 Vec<u8> 反序列化后的 Uint8Array
        term.write(new Uint8Array(chunk));
    };

    const result = await invoke('pty_spawn', {
        cmd: 'claude',
        args: ['--permission-mode', 'bypassPermissions'],
        cwd: defaultCwd,
        env: {},
        dataChannel,   // ← Channel 对象直接传入
    });
}
```

### 性能对比

| 维度 | 原方案（base64 + emit） | 修订方案（Channel + Vec<u8>） |
|------|------------------------|-------------------------------|
| 编码开销 | +33% 体积膨胀 + CPU 编解码 | 零 |
| IPC 频率 | 每次 PTY onData 一次 | 16ms 批量合并 |
| 前端解码 | atob() + Uint8Array 构造 | 直接使用 |
| 内存拷贝 | 3 次（Rust→base64→IPC→JS atob） | 1 次（Rust→IPC→JS） |

---

## 3. 🟡 修订：独立仓库

### 原方案的问题

原设计将 Desktop 代码放在 `onecode-desktop/` 子目录下，与现有 `agent-runtime/` 同仓库：

```
/workspace/                      ← 同一个 git 仓库
├── agent-runtime/               ← Web 版
│   ├── gateway/
│   └── Dockerfile
└── onecode-desktop/             ← Desktop 版（新增）
    ├── src-tauri/
    └── src/
```

**问题：**
- Desktop 和 Web 共享 git 历史，但生命周期不同
- Tauri 构建链（cargo、rustc）与 Node.js 构建链互不相关
- CI/CD 完全不同：Desktop 需要 macOS runner 打 dmg，Web 需要 Docker build
- 发布节奏不同：Desktop 可能周更，Web 可能日更

### 修订方案：独立仓库

```
github.com/onecode/desktop      ← 新仓库（onecode-desktop）
github.com/onecode/onecode      ← 现有仓库（Web 版 + Docker）
```

**共享代码策略：**

| 共享内容 | 方式 | 理由 |
|----------|------|------|
| xterm.js / hljs / marked | 从 gateway/static/ 复制 | 零依赖，纯静态文件 |
| 终端主题色值 | 提取为 `theme.js` 共享 | 几十行，不值得发 npm |
| CSS 变量 | 各自维护，保持视觉一致 | Web 版暗色 vs Desktop 版 Cowork 暖色 |
| pty.js 的 RingBuffer 逻辑 | Rust 重写，不复用 Node 代码 | 语言不同，仅复用设计 |
| cc-status.js 的文件扫描逻辑 | Rust 重写 | 同上 |

**不共享的理由：**
- Desktop 是 Rust+WebView 架构，Web 是 Node.js+Docker 架构
- 共享 npm crate 反而增加协调成本（一人公司）
- 复制静态文件是最简单的共享方式，没有版本同步问题

### 新仓库初始结构

```
onecode-desktop/
├── .github/
│   └── workflows/
│       ├── ci.yml                # Linux + macOS 构建
│       └── release.yml           # 打 dmg + AppImage
├── src-tauri/
│   ├── Cargo.toml
│   ├── tauri.conf.json
│   ├── capabilities/
│   │   └── default.json
│   ├── icons/
│   └── src/
│       ├── main.rs
│       ├── lib.rs
│       ├── pty/
│       │   ├── mod.rs
│       │   ├── slot.rs
│       │   └── health.rs
│       ├── session/
│       │   ├── mod.rs
│       │   └── schema.rs
│       ├── tray.rs
│       ├── commands.rs
│       ├── events.rs
│       └── config.rs
├── src/                          # 前端 WebView
│   ├── index.html
│   ├── styles.css
│   ├── main.js
│   ├── ipc-bridge.js
│   ├── terminal/
│   │   ├── terminal.js
│   │   ├── tab-manager.js
│   │   ├── scroll-thumb.js
│   │   └── ime-fix.js
│   ├── sidebar/
│   │   ├── sidebar.js
│   │   ├── file-tree.js
│   │   ├── agents.js
│   │   └── cc-badges.js
│   ├── preview/
│   │   ├── preview.js
│   │   ├── markdown.js
│   │   └── code-view.js
│   └── layout/
│       ├── layout.js
│       ├── keybindings.js
│       └── mobile.js
├── static/                       # 从 gateway/static/ 复制
│   ├── xterm.min.js + xterm.css
│   ├── addon-fit.min.js
│   ├── addon-web-links.min.js
│   ├── addon-webgl.min.js
│   ├── marked.min.js
│   └── highlight.min.js + hljs.css
├── scripts/
│   └── copy-static.sh            # 从 onecode 主仓库复制静态资源
├── package.json
└── README.md
```

---

## 4. 🟡 修订：MultiPtyManager 并发模型

### 原方案的问题

```rust
pub struct MultiPtyManager {
    inner: std::sync::Mutex<MultiPtyManagerInner>,  // ← 全局一把锁
    app: AppHandle,
}
```

所有操作（spawn/kill/write/resize/list/restart）都争抢同一把 Mutex：
- `write()` 高频（每次键盘输入），`list()` 低频（Tab 状态刷新）
- `kill()` 需要等 `write()` 释放锁，可能延迟 3s+ SIGKILL
- `spawn()` 创建新 PTY 期间阻塞其他所有操作

### 修订方案：读写锁 + 按槽分段

```rust
use tokio::sync::RwLock;

pub struct MultiPtyManager {
    slots: RwLock<HashMap<Uuid, TerminalSlot>>,
    app: AppHandle,
    config: AppConfig,
}

impl MultiPtyManager {
    /// 写入 PTY 输入 — 读锁即可（不修改 HashMap 结构）
    pub async fn write(&self, id: Uuid, data: Vec<u8>) -> Result<()> {
        let slots = self.slots.read().await;
        let slot = slots.get(&id).ok_or("slot not found")?;
        slot.write(data)  // TerminalSlot 内部用独立的 Mutex 保护 PTY handle
    }

    /// 创建终端 — 写锁（修改 HashMap）
    pub async fn spawn(&self, cmd: String, args: Vec<String>, cwd: String, env: HashMap<String, String>) -> Result<Uuid> {
        let mut slots = self.slots.write().await;
        // ... spawn PTY, insert into HashMap
    }

    /// 列出终端 — 读锁即可
    pub async fn list(&self) -> Vec<SlotSummary> {
        let slots = self.slots.read().await;
        slots.values().map(|s| s.summary()).collect()
    }
}
```

**改进：**
- `write()` / `resize()` / `list()` 只需读锁，可并发
- `spawn()` / `kill()` 需写锁，但频率低
- 每个 `TerminalSlot` 的 PTY handle 有独立 Mutex，不同 slot 的 write 不互斥

### TerminalSlot 内部锁

```rust
pub struct TerminalSlot {
    pub id: Uuid,
    pub label: AtomicString,     // 原子操作，无需锁
    pub cmd: String,
    pub args: Vec<String>,
    pub cwd: String,
    pub env: HashMap<String, String>,
    pub status: AtomicSlotStatus, // 原子枚举
    pub ring_buffer: Mutex<RingBuffer>,
    // PTY handles 独立锁
    pty: Mutex<PtyHandles>,
    created_at: DateTime<Utc>,
}

struct PtyHandles {
    master: Box<dyn MasterPty + Send>,
    child: Box<dyn Child + Send>,
}
```

---

## 5. 🟡 修订：PTY 输出流批量推送

### 原方案

PTY 每次 `onData` 回调就触发一次 IPC 事件推送。Claude Code 在生成代码时可能产生大量短帧（每行一个回调），导致 IPC 洪水。

### 修订方案：tokio 批量合并

```rust
pub fn spawn(
    &self,
    cmd: String,
    args: Vec<String>,
    cwd: String,
    env: HashMap<String, String>,
    sender: Channel<Vec<u8>>,
) -> Result<Uuid> {
    let (tx, mut rx) = tokio::sync::mpsc::channel::<Vec<u8>>(256);

    // PTY 读取线程 — 将原始字节发到 channel
    std::thread::spawn(move || {
        let mut reader = pty_reader; // BufReader
        let mut buf = [0u8; 4096];
        loop {
            match reader.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    if tx.send(buf[..n].to_vec()).is_err() {
                        break; // channel closed
                    }
                }
                Err(_) => break,
            }
        }
    });

    // 批量合并 + Channel 推送任务
    let app = self.app.clone();
    tokio::spawn(async move {
        let mut batch = Vec::with_capacity(8192);
        let mut interval = tokio::time::interval(Duration::from_millis(16)); // ~60fps
        interval.tick().await; // 首次立即

        loop {
            tokio::select! {
                Some(chunk) = rx.recv() => {
                    batch.extend_from_slice(&chunk);
                    // 如果批量已超过 32KB，立即推送不等定时器
                    if batch.len() >= 32768 {
                        let _ = sender.send(batch.clone());
                        batch.clear();
                    }
                }
                _ = interval.tick() => {
                    if !batch.is_empty() {
                        let _ = sender.send(batch.clone());
                        batch.clear();
                    }
                }
                else => break, // channel closed
            }
        }
    });
}
```

**关键参数：**
- 合并窗口：16ms（~60fps，与屏幕刷新对齐）
- 立即推送阈值：32KB（大块输出不卡 16ms）
- 与 pty.js 的 `setImmediate` 批量逻辑等价，但用 tokio timer 更精确

---

## 6. 修订后的完整 IPC 架构

```
┌───────────────────────────────────────────────────────┐
│                   Frontend (WebView)                   │
│                                                        │
│  TabManager                                            │
│   ├── createTab() ── invoke('pty_spawn', {channel})   │
│   ├── closeTab() ── invoke('pty_kill', {id})          │
│   ├── switchTo()  ── invoke('pty_replay', {id})       │
│   └── onData()    ── channel.onmessage → xterm.write()│
│                                                        │
│  xterm.js ← Uint8Array ← Channel<Vec<u8>>             │
└─────────────┬──────────────────────┬──────────────────┘
              │ invoke (请求/响应)    │ Channel (流式推送)
              ▼                      ▼
┌───────────────────────────────────────────────────────┐
│                    Rust Backend                         │
│                                                        │
│  commands.rs                                           │
│   ├── pty_spawn(cmd, args, cwd, env, channel)         │
│   ├── pty_kill(id)                                    │
│   ├── pty_restart(id, channel)                        │
│   ├── pty_write(id, data: Vec<u8>)                    │
│   ├── pty_resize(id, cols, rows)                      │
│   ├── pty_list() → Vec<SlotSummary>                   │
│   ├── pty_rename(id, label)                           │
│   └── session_restore() / session_save()              │
│                                                        │
│  MultiPtyManager (RwLock<HashMap<Uuid, TerminalSlot>>) │
│   ├── PTY 读取线程 → mpsc channel → 批量合并任务       │
│   └── Channel<Vec<u8>> 推送到前端                      │
│                                                        │
│  SessionStore (rusqlite)                               │
│  TrayManager (tauri-plugin-tray)                       │
└───────────────────────────────────────────────────────┘
```

---

## 7. 风险重新评估

| 风险 | 原评估 | 修订后评估 | 理由 |
|------|--------|-----------|------|
| Tauri v2 API 不稳定 | 中 | **低** | v2 已于 2024-10 stable，持续点版本更新 |
| portable-pty macOS 兼容性 | 中 | **低** | WezTerm 自用，macOS 是一等公民 |
| IPC base64 性能瓶颈 | 未识别 | **已消除** | Channel<Vec<u8>> 原生二进制 |
| Mutex 全局锁竞争 | 未识别 | **已消除** | RwLock + 按 slot 分段 |
| PTY 高频输出 IPC 洪水 | 未识别 | **已消除** | 16ms 批量合并 + 32KB 立即推送 |
| 仓库耦合 | 未识别 | **已消除** | 独立仓库 |
| 前端 transport 抽象过早 | 低 | **砍掉** | MVP 直接用 Channel，M3 再抽象 |
| rusqlite bundled 编译慢 | 未评估 | **低** | 首次编译 ~2min，后续增量很快 |

---

## 8. 被砍掉的模块

| 原方案模块 | 处置 | 理由 |
|-----------|------|------|
| `transport-local.js` | **砍掉** | Channel 直接用，无需抽象层 |
| `cc_status.rs` (Rust 移植) | **砍掉** | MVP 不需要。Desktop 本地运行，cc-status 通过 invoke 读取文件系统即可 |
| `remote/transport-ws.js` | **推迟到 M3** | 远程模式不在 MVP |
| `events.rs` (PtyEvent enum) | **大幅简化** | Channel 替代了 pty:data 事件，仅保留 pty:exit 事件 |

---

## 9. M1 实施优先级修订

原 M1 目标不变（单终端 MVP），但实施路径微调：

### 第 1 周：项目脚手架

- [ ] 创建 `onecode-desktop` 独立仓库
- [ ] `cargo init` + Tauri v2 脚手架
- [ ] `tauri.conf.json` 窗口配置（1200×800, minWidth 800）
- [ ] 静态资源复制脚本 `scripts/copy-static.sh`
- [ ] CI: GitHub Actions Linux + macOS 构建

### 第 2 周：Rust PTY 核心

- [ ] `pty/slot.rs` — TerminalSlot + RingBuffer
- [ ] `pty/mod.rs` — MultiPtyManager（RwLock 版本）
- [ ] `commands.rs` — pty_spawn + pty_kill + pty_write + pty_resize
- [ ] Channel<Vec<u8>> 批量推送验证

### 第 3 周：前端终端渲染

- [ ] `terminal/terminal.js` — xterm.js 初始化 + 主题
- [ ] `terminal/tab-manager.js` — 单终端版（createTab + onData）
- [ ] `ipc-bridge.js` — invoke + Channel 封装
- [ ] `styles.css` — 从 onecode.html 提取 + Cowork 暖色变量
- [ ] 端到端验证：Rust spawn → PTY 输出 → Channel → xterm.write()

### 第 4 周：打磨 + 验收

- [ ] 键盘输入 → pty_write → PTY 回显 闭环
- [ ] 窗口 resize → pty_resize 闭环
- [ ] PTY 退出检测 + 自动重启
- [ ] 修改 `desktop-client-architecture.md` 和 `desktop-code-structure.md` 反映修订

### M1 完成标志

> 一个窗口，一个终端，能跑通 Claude Code 完整对话，Channel 二进制流无丢失

---

## 10. 修订对现有文档的影响

| 文档 | 需更新内容 |
|------|-----------|
| `desktop-client-architecture.md` | IPC 方案（base64→Channel）、并发模型（Mutex→RwLock）、批量推送 |
| `desktop-code-structure.md` | 砍掉 transport-local.js、简化 events.rs、仓库独立 |
| `desktop-prd.md` | 无需修改（功能需求不变，仅实现方案变化） |
| `desktop-prototype.html` | 无需修改（UI 原型不受影响） |

---

## 附录：关键参考

- [Tauri v2 Streaming 文档](https://v2.tauri.app/develop/calling-rust/#streaming)
- [Tauri v2 Channel API](https://v2.tauri.app/develop/calling-rust/#channel)
- [Tauri v2 System Tray 插件](https://v2.tauri.app/develop/system-tray/)
- [portable-pty crate](https://crates.io/crates/portable-pty) — WezTerm 维护
- [rusqlite bundled](https://crates.io/crates/rusqlite) — 自包含 SQLite

---

**Why:** CEO 要求 Architect 评估并设计 OneCode Desktop 架构，发现原方案的 IPC base64 编码、全局 Mutex、仓库耦合等问题，提出修订方案
**How to apply:** 按修订后的 M1 优先级实施，IPC 用 Channel<Vec<u8>> 替代 base64，独立仓库，RwLock 替代 Mutex
