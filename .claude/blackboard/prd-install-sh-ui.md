# PRD: install.sh 安装界面重设计

> 状态：草稿 | 版本：v0.1 | 日期：2026-06-15

---

## 1. 背景与问题

当前 `install.sh` 安装界面存在以下痛点：

| # | 痛点 | 影响 |
|---|------|------|
| P1 | **步骤标题粗暴** — 用 `=========` 分隔线 + `Step 1/8` 硬编码，视觉噪音大 | 看起来像 90 年代脚本，不够专业 |
| P2 | **进度不可感** — 8 步全跑完才知道成功与否，无整体进度条 | 用户焦虑，不知道还要等多久 |
| P3 | **配置向导割裂** — 盒子框 `╔══╗` 和后续步骤风格不统一 | 风格断裂，新人困惑 |
| P4 | **错误信息散乱** — `err()` 只有红色文字，无明确恢复路径 | 用户卡住不知道怎么办 |
| P5 | **完成画面信息过载** — 塞了 15+ 行命令，关键操作被淹没 | 用户不知道第一步该干嘛 |
| P6 | **无安装耗时提示** — Docker 安装/镜像拉取可能 5-10 分钟，无预估 | 用户以为卡死了 |
| P7 | **backend 未暴露** — `--backend` 选项存在但向导中未体现 | 用户不知道可以选 opencode |

---

## 2. 目标用户

| 角色 | 特征 | 核心诉求 |
|------|------|----------|
| 🌱 新手开发者 | 第一次用，不确定要什么 provider | 引导清晰，默认值安全，出错有解 |
| 🇨🇳 国内用户 | 网络不稳定，可能多次失败 | 降级策略可见，下载进度感知 |
| ⚡ 高级用户 | 带参数安装，想快速完成 | 非交互模式流畅，输出简洁 |

---

## 3. 设计原则

1. **渐进式信息** — 只在需要时显示细节，默认简洁
2. **进度可见** — 每步有状态标记（✓/⏳/✗），总进度可感
3. **错误可恢复** — 失败时给具体操作，不只说 "failed"
4. **首屏即行动** — 完成画面第一条就是用户下一步要做什么

---

## 4. 界面设计

### 4.1 Banner（首屏）

```
  ___              ____          _
 / _ \ _ __   ___ / ___|___   __| | ___
| | | | '_ \ / _ \ |   / _ \ / _` |/ _ \
| |_| | | | |  __/ |__| (_) | (_| |  __/
 \___/|_| |_|\___|\____\___/ \__,_|\___|

  OneCode v0.4.0 — AI Agent Terminal

  AI backend: claude-code (Anthropic Claude) | opencode (MIT)
  Support: Linux amd64/arm64 · macOS Intel/Apple Silicon
```

**改进**：
- 去掉 `Install` 后缀（整个脚本就是安装，不用再说）
- 增加产品一句话定位
- 显示支持的平台

### 4.2 步骤进度条

替换 `========= Step 1/8 =========` 为统一格式：

```
  ── [1/8] 检测环境 ──────────────────────────────────
```

每步完成后在行尾标记状态：

```
  ── [1/8] 检测环境 ──────────────────────── ✓ macOS arm64
  ── [2/8] 安装 jq ──────────────────────── ✓ jq-1.7
  ── [3/8] 安装 Docker ──────────────────── ✓ 27.3.1
  ── [4/8] 启动 Docker ──────────────────── ✓ running
  ── [5/8] 登录镜像仓库 ──────────────────── ✓ skipped
  ── [6/8] 拉取镜像 ──────────────────────── ⏳ pulling...
```

**规则**：
- `✓` 绿色 + 关键版本/状态信息（一行看完）
- `⏳` 黄色 + 进度描述（长操作显示耗时）
- `✗` 红色 + 错误原因 + 恢复操作

### 4.3 长操作进度反馈

Docker 安装和镜像拉取可能很慢，需要感知：

```bash
# Docker 安装（无进度条的 apt/yum）
info "Installing Docker... (usually 1-3 min)"
# 每 5s 打一个点表示还活着
while install_is_running; do
    printf "."; sleep 5
done

# 镜像拉取（docker pull 自带进度条，保持原样）
# 但在拉取前给预估：
info "Pulling image ${image} (usually 1-5 min, depends on network)..."
docker pull --platform "$PLATFORM" "$image"
```

### 4.4 配置向导（重设计）

**现状**：方框 `╔══╗` + 步骤编号混乱（Step 2/3/4 根据 provider 不同）

**新设计**：统一 3 步，与 provider 无关：

```
  ── 配置 ────────────────────────────────────────────

  ? Select your AI provider:
      1) Anthropic Claude (default)
      2) OpenAI Compatible (any OpenAI-format API)
      3) OpenCode (MIT, no API key needed for local models)

    ▸ 1

  ? API Key (Anthropic)
    Get yours at: https://console.anthropic.com/settings/keys
    ▸ sk-ant-••••••••••••••••••••••••••••••••••••••••

  ? Model (press Enter for default)
    Default: claude-sonnet-4-6
    ▸ <Enter>

  ── 配置确认 ─────────────────────────────────────────
    Provider:  Anthropic Claude
    Backend:   claude-code
    Model:     claude-sonnet-4-6
    Config:    ~/.onecode/settings.json
  ──────────────────────────────────────────────────────
```

**关键改进**：
- Provider 选项 3 增加了 OpenCode（MIT），暴露 backend 选择
- API Key 输入时掩码显示（`•` 替代字符），安全
- 确认区一次性展示完整配置
- `openai_compatible` 时多一步 Base URL，但流程结构不变

**openai_compatible 分支**：

```
  ? Select your AI provider:
    ▸ 2

  ? API Base URL
    Example: https://api.example.com/v1
    ▸ https://api.deepseek.com/v1

  ? API Key
    ▸ sk-••••••••••••••••••••••••••••••••••••••••

  ? Model (press Enter for default)
    Default: gpt-4o
    ▸ deepseek-chat

  ── 配置确认 ─────────────────────────────────────────
    Provider:  OpenAI Compatible
    Backend:   claude-code
    API URL:   https://api.deepseek.com/v1
    Model:     deepseek-chat
    Config:    ~/.onecode/settings.json
  ──────────────────────────────────────────────────────
```

**非交互模式**（`--api-key` 等参数已提供时）：

```
  ── 配置 ────────────────────────────────────────────
    Provider:  anthropic (from --provider)
    API Key:   sk-ant-••••••• (from --api-key)
    Model:     claude-sonnet-4-6 (default)
    Backend:   claude-code (default)
    Config:    ~/.onecode/settings.json ✓
```

### 4.5 验证步骤

紧凑化，一行一个检查：

```
  ── 验证 ─────────────────────────────────────────────
    Docker:  ✓ 27.3.1
    Image:   ✓ ghcr.io/yiyan-yixing/onecode:latest
    oc CLI:  ✓ /home/user/.local/bin/oc
    Config:  ✓ /home/user/.onecode/settings.json
```

### 4.6 完成画面（First Run Guide）

**现状**：15+ 行命令列表，首尾被 `=========` 包裹

**新设计**：3 层信息 — 立即行动 > 常用命令 > 参考信息

```
  ╭──────────────────────────────────────────────────╮
  │  ✅ OneCode installed!                            │
  │                                                   │
  │  First run:                                       │
  │    source ~/.bashrc   # load PATH (macOS: ~/.zshrc)│
  │    oc remote          # → http://localhost:7681    │
  │                                                   │
  │  Common commands:                                  │
  │    oc                  interactive AI CLI         │
  │    oc remote           web IDE in browser         │
  │    oc --backend opencode remote  MIT backend      │
  │    oc config list      show all settings           │
  │                                                   │
  │  Config:   ~/.onecode/settings.json               │
  │  CLI:      ~/.local/bin/oc                        │
  │  Docs:     github.com/yiyan-yixing/onecode        │
  ╰──────────────────────────────────────────────────╯
```

**改进**：
- 第一条就是用户要执行的动作（`source` + `oc remote`）
- 常用命令精简到 4 条（不是 10 条）
- 苹果 Silicon 提示只在 arm64 macOS 显示，放在框内
- 右侧注释说明命令用途（不用记）

### 4.7 错误画面

**现状**：`err()` 打一行红字，可能跟着 exit 1

**新设计**：结构化错误 + 恢复路径

```
  ╭─ ERROR ───────────────────────────────────────────╮
  │  ✗ Docker pull failed                             │
  │                                                   │
  │  Reason:                                          │
  │    Network timeout after 120s                     │
  │                                                   │
  │  Recovery:                                        │
  │    1. Check network:  curl -I https://ghcr.io     │
  │    2. Set mirror:     export GH_MIRROR=https://... │
  │    3. Retry:          oc update                    │
  │    4. Manual pull:    docker pull ghcr.io/...      │
  │                                                   │
  │  Full log: /tmp/onecode-install.log               │
  ╰──────────────────────────────────────────────────╯
```

---

## 5. 交互流程图

```
curl | bash
  │
  ▼
show_banner
  │
  ▼
[1/8] 检测环境 ────────── ✓/✗
  │
  ▼
[2/8] 安装 jq ─────────── ✓ (skipped if exists)
  │
  ▼
[3/8] 安装 Docker ──────── ✓/skipped (if --skip-docker or exists)
  │
  ▼
[4/8] 启动 Docker ──────── ✓ (or wait up to 60s on macOS)
  │
  ▼
[5/8] 登录镜像仓库 ──────── ✓/skipped (no creds provided)
  │
  ▼
[6/8] 拉取镜像 ─────────── ⏳ (1-5 min) → ✓/✗
  │
  ▼
[7/8] 安装 oc CLI ──────── ✓
  │
  ▼
[8/8] 配置 ─────────────── 交互向导 / 静默
  │                       ├─ 新用户: 3步向导 (provider → key → model)
  │                       ├─ 升级用户: 迁移 v1→v2, 补缺字段
  │                       └─ --api-key 用户: 静默确认
  │
  ▼
验证 ──────────────────── 4 项检查
  │
  ▼
完成画面 ──────────────── First Run Guide
```

---

## 6. 技术约束与实现建议

| 约束 | 方案 |
|------|------|
| Bash 无进度条 | 用 `printf "."` 心跳 + 耗时预估文案 |
| `╭─╮` 框线在窄终端会断 | 检测 `$COLUMNS`，< 50 时退回 `──` 简洁线 |
| API Key 掩码 `•` | `read -s` 隐藏输入，显示时用 `${key:0:7}••••` 截断 |
| 彩色在管道中失效 | 检测 `[ -t 1 ]`，非终端时自动去色 |
| 长操作超时 | Docker 安装 5min 超时，镜像拉取 10min 超时，超时给恢复路径 |
| macOS `read -rp` | macOS 自带 bash 3.x，`-p` 行为不同；用 `echo; read` 代替 |

### 输出函数重构

```bash
# 状态标记（替换 ok/info/warn/err）
step_ok()    { echo "  ${GREEN}✓${NC} $*"; }
step_wait()  { echo "  ${YELLOW}⏳${NC} $*"; }
step_skip()  { echo "  ${YELLOW}─${NC} $* (skipped)"; }
step_err()   { echo "  ${RED}✗${NC} $*"; }

# 步骤标题（替换 ======== Step X ========）
step_header() {
    local n="$1" total="$2" label="$3"
    echo ""
    echo "  ${CYAN}──${NC} [${n}/${total}] ${label} ${CYAN}$(printf '─%.0s' $(seq 1 $((50 - ${#label}))))${NC}"
}

# 完成画面框
show_box() {
    local width="${1:-55}"
    echo "  ${CYAN}╭$(printf '─%.0s' $(seq 1 $((width-2))))╮${NC}"
    while IFS= read -r line; do
        printf "  ${CYAN}│${NC} %-$(($width-3))s ${CYAN}│${NC}\n" "$line"
    done
    echo "  ${CYAN}╰$(printf '─%.0s' $(seq 1 $((width-2))))╯${NC}"
}
```

---

## 7. 验收标准

| # | 标准 | 优先级 |
|---|------|--------|
| AC1 | `curl | bash` 安装时，每步有 `[n/8]` 标题 + `✓/⏳/✗` 状态 | P0 |
| AC2 | 首次安装（无 config）出现 3 步交互向导 | P0 |
| AC3 | 带参数安装（`--api-key`）全程无交互 | P0 |
| AC4 | 完成画面第一条就是 `source` + `oc remote` | P0 |
| AC5 | API Key 输入不回显明文 | P0 |
| AC6 | Provider 选项包含 OpenCode (MIT) | P1 |
| AC7 | 长操作（Docker安装/镜像拉取）有耗时预估 | P1 |
| AC8 | 错误画面包含 Reason + Recovery + Log路径 | P1 |
| AC9 | 窄终端（<50列）自动退回简洁布局 | P2 |
| AC10 | 管道模式下 `curl | bash > log.txt` 自动去色 | P2 |

---

## 8. 不做

- ❌ 不做 TUI/ncurses 式界面（保持纯 bash 兼容性）
- ❌ 不做安装过程录像/回放
- ❌ 不做卸载脚本（本次不做）
- ❌ 不做多语言（中英同时显示，不做 i18n）
