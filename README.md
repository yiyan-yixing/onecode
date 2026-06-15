# OneCode — AI 原生 IDE

[![Version](https://img.shields.io/badge/version-v0.4.0-blue)](https://github.com/yiyan-yixing/onecode/releases)
[![License](https://img.shields.io/badge/license-MIT-green)](https://github.com/yiyan-yixing/onecode/blob/main/LICENSE)

浏览器里的 AI 开发环境。Docker 一键启动，内置 10 个 Agent 角色，手机也能写代码。

> ⚠️ 本项目仅供个人学习和研究使用，详见 [免责声明](DISCLAIMER.md)。

---

## ✨ 特性

- 🐳 **一键部署** — `curl | bash` 安装，Docker 容器化，不用配环境
- 🤖 **Agent 团队** — `@dev` `@pm` `@qa`… 10 个角色自动路由，一人公司全栈协作
- 📱 **移动端** — 响应式布局 + 虚拟键盘，手机直接写代码
- 🔌 **VS Code 内置** — code-server 一键切换完整 IDE
- 🔀 **双后端** — Claude Code（默认）或 OpenCode（MIT），`--backend` 一键切换

---

## 快速开始

### 一键安装

```bash
# 推荐：通过 GitHub API 下载（不受 DNS 污染和镜像失效影响）
curl -fsSL -H "Accept: application/vnd.github.v3.raw" \
  https://api.github.com/repos/yiyan-yixing/onecode/contents/agent-runtime/bin/install.sh?ref=main | bash

# 或直连 GitHub（海外服务器）
curl -fsSL https://raw.githubusercontent.com/yiyan-yixing/onecode/main/agent-runtime/bin/install.sh | bash
```

安装完成后：

```bash
source ~/.bashrc   # macOS 用 ~/.zshrc
oc remote           # 启动 → 浏览器打开 http://localhost:7681
```

<details>
<summary>下载失败？试试其他方式</summary>

`raw.githubusercontent.com` 在国内常因 DNS 污染报 SSL 错误，第三方镜像也可能失效。以下按稳定性排序：

```bash
# 方法 1：GitHub API（推荐，不经过 raw CDN，最稳定）
curl -fsSL -H "Accept: application/vnd.github.v3.raw" \
  https://api.github.com/repos/yiyan-yixing/onecode/contents/agent-runtime/bin/install.sh?ref=main | bash

# 方法 2：GitHub 镜像（可能失效，优先试 api 方式）
curl -fsSL https://gh-proxy.com/yiyan-yixing/onecode/main/agent-runtime/bin/install.sh | bash
curl -fsSL https://cors.isteed.cc/https://raw.githubusercontent.com/yiyan-yixing/onecode/main/agent-runtime/bin/install.sh | bash

# 方法 3：跳过证书校验（最后手段）
curl -kfsSL https://raw.githubusercontent.com/yiyan-yixing/onecode/main/agent-runtime/bin/install.sh | bash
```

安装脚本内置 5 级降级策略，运行时自动尝试镜像 → 直连 → API → 跳过校验。

</details>

<details>
<summary>安装选项</summary>

```bash
# 预设 API Key（跳过交互式输入）
curl -fsSL -H "Accept: application/vnd.github.v3.raw" \
  https://api.github.com/repos/yiyan-yixing/onecode/contents/agent-runtime/bin/install.sh?ref=main \
  | bash -s -- --api-key sk-ant-xxx

# 使用 OpenAI 兼容 API
... | bash -s -- --api-key sk-xxx --provider openai_compatible --api-base-url https://api.example.com/v1

# 跳过 Docker 安装 | 指定镜像版本
... | bash -s -- --skip-docker
... | bash -s -- --tag 0.4
```

安装过程：检测环境 → 安装 jq/Docker → 拉取镜像 → 安装 `oc` CLI → 交互式配置

</details>

> ⚠️ 镜像中**不包含** Claude Code（专有软件）。首次启动时用户自行从 npm 安装，等效于本机执行 `npm install -g`。详见 [免责声明](DISCLAIMER.md)。

### Docker 直接运行

```bash
docker build -t onecode agent-runtime/

# claude-code 后端（默认，首次启动需等待 ~30s 安装）
docker run -it --rm -e API_KEY=sk-xxx -p 7681:7681 -p 8000:8000 -v $(pwd):/workspace onecode remote

# opencode 后端（MIT，预装在镜像中，即开即用）
docker run -it --rm -e API_KEY=sk-xxx -e BACKEND=opencode -p 7681:7681 -p 8000:8000 -v $(pwd):/workspace onecode remote
```

### 本地开发

```bash
git clone https://github.com/yiyan-yixing/onecode.git && cd onecode
npm install && npm run dev    # → http://localhost:7681
```

前提：[Node.js](https://nodejs.org/) + [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) + API Key

---

## oc 命令

`oc` = OneCode CLI，管理容器化开发环境。

### 常用命令

| 命令 | 说明 |
|------|------|
| `oc` | 交互式 CLI（默认 `oc run`） |
| `oc remote` | Web 终端，浏览器访问 |
| `oc --backend opencode remote` | 使用 OpenCode 后端 |
| `oc ssh <name>` | 给容器开启 SSH |
| `oc shell [name]` | 进入容器 shell |
| `oc stop <name>` | 停止并删除容器 |
| `oc ls` | 列出容器和镜像 |
| `oc config` | 查看/修改配置 |
| `oc help [cmd]` | 查看帮助 |

### 全局选项

| 选项 | 说明 | 默认值 |
|------|------|--------|
| `-n NAME` | 容器名称 | 自动生成 |
| `-d DIR` | 挂载目录 | 当前目录 |
| `-p PORT` | Web 终端端口 | `7681` |
| `-a PORT` | App 服务端口 | `8000` |
| `--backend` | AI 后端：`claude-code` / `opencode` | `claude-code` |
| `--https` | 启用 HTTPS（自签证书） | 关 |
| `--tag TAG` | 镜像版本 | `latest` |

---

## 双后端

OneCode 支持两种 AI 后端，通过 `--backend` 或环境变量 `BACKEND` 切换：

| | Claude Code | OpenCode |
|---|---|---|
| **许可证** | 专有（Anthropic） | MIT |
| **镜像中** | ❌ 运行时安装 | ✅ 预装 |
| **首次启动** | 等待 30-60s | 即开即用 |
| **切换方式** | `--backend claude-code` | `--backend opencode` |
| **配置持久化** | `oc config set backend=claude-code` | `oc config set backend=opencode` |

两者共用同一份配置（`provider` / `api_key` / `model`），无需配两套。

---

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│  OneCode · AI 原生 IDE     v0.4   [Skills▼] [New] [VS Code] │
├──────────┬──────────────────────────────────────────────────┤
│  Files   │                                                    │
│  ~ /src  │   ┌────────────────────────────────────────┐      │
│  /app    │   │    xterm.js Terminal              │      │
│  ...     │   │    (直连 AI 后端 via PTY)           │      │
│──────────│   └────────────────────────────────────────┘      │
│  Agents  │                                                    │
│  👔 CEO  │   ┌────────────────────────────────────────┐      │
│  📋 PM   │   │    Preview (md/code/img)             │      │
│  🎨 Des  │   │                                    │      │
│  💻 Dev  │   └────────────────────────────────────────┘      │
│  ...     │                                                    │
├──────────┴──────────────────────────────────────────────────┤
│  [Terminal]  [Preview]  [Files]  [Agents]    (移动端 Tab)   │
└─────────────────────────────────────────────────────────────┘
```

---

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `API_KEY` | API 密钥 → `ANTHROPIC_API_KEY` | 必填 |
| `API_BASE_URL` | API 地址 → `ANTHROPIC_BASE_URL` | `https://api.anthropic.com` |
| `MODEL` | 模型名 → `ANTHROPIC_MODEL` | `claude-sonnet-4-6` |
| `BACKEND` | AI 后端 | `claude-code` |
| `GATEWAY_HTTPS` | 启用 HTTPS | `0` |
| `TERM_TOKEN` | 终端访问 Token | 空（无需认证） |

优先级：**环境变量 > 配置文件 > 默认值**

---

## 配置

`~/.onecode/settings.json`：

```json
{
  "provider": "anthropic",
  "api_key": "sk-xxx",
  "api_base_url": "https://api.anthropic.com",
  "model": "claude-sonnet-4-6",
  "backend": "claude-code"
}
```

```bash
oc config list              # 查看所有配置
oc config set api_key=sk-xxx   # 设置值
oc config set backend=opencode  # 切换后端
oc config validate          # 校验配置
```

---

## Agent 角色

角色从 `.claude/agents/*.md` 动态加载，无需改前端。文件名即 `@id`（`dev.md` → `@dev`）：

| 角色 | 代号 | 用途 |
|------|------|------|
| 👔 CEO | @ceo | 战略规划、重大决策 |
| 📋 PM | @pm | 需求定义、优先级 |
| 🎨 Designer | @designer | 快速原型、UI/UX |
| 🏛 Architect | @architect | 技术选型、架构评审 |
| 💻 Dev | @dev | 代码编写、Bug 修复 |
| ⚙️ DevOps | @devops | CI/CD、一键部署 |
| 🧪 QA | @qa | 测试用例、质量把关 |
| 📢 Ops | @ops | 内容运营、增长实验 |
| 📊 Data | @data | 埋点设计、效果分析 |
| 💰 Fin | @fin | 记账、现金流追踪 |

**自定义角色**：在项目 `.claude/agents/` 下创建 `.md` 文件即可：

```markdown
---
name: MyAgent
description: 自定义 Agent 描述
tools: Read, Write, Bash
color: green
icon: 🚀
---

系统提示词正文...
```

---

## 项目结构

```
onecode/
├── agent-runtime/
│   ├── gateway/           # Node.js 网关（HTTP + WebSocket + PTY）
│   ├── bin/
│   │   ├── oc             # CLI 主命令
│   │   └── install.sh     # 一键安装脚本
│   ├── Dockerfile
│   └── entrypoint.sh
├── tests/                 # 277 assertions 测试套件
├── DISCLAIMER.md
└── package.json
```

---

## 版本历史

| 版本 | 说明 |
|------|------|
| v0.4.0 | 双后端（claude-code / opencode）、`--backend` 切换、统一配置 |
| v0.3.5 | 动态 Agent 加载、首次引导配置、自动架构检测 |
| v0.2.0 | Gateway + PTY + xterm.js + Agent 侧栏 + oc CLI |
| v0.1.0 | Next.js MVP：Chat + Monaco + @角色名 |

详见 [CHANGELOG.md](CHANGELOG.md)。

---

## License

[MIT](LICENSE) © 2026 yiyan-yixing
