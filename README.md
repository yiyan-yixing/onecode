# OneCode — AI 原生 IDE

容器化 Claude Code，一条命令启动，内置一人公司 Agent 角色体系。

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│  OneCode · AI 原生 IDE     v0.3   [Skills▼] [New] [VS Code] │
├──────────┬──────────────────────────────────────────────────┤
│  Files   │                                                    │
│  ~ /src  │   ┌────────────────────────────────────────┐      │
│  /app    │   │    xterm.js Terminal              │      │
│  ...     │   │    (直连 Claude Code via PTY)       │      │
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

浏览器打开 http://localhost:7681

---

## 快速开始

### 前提条件

- **Docker** 已安装并运行（[安装 Docker](https://docs.docker.com/engine/install/)）
- **API Key**（Anthropic 或兼容 API）

### 一键安装

```bash
# 克隆仓库
git clone https://github.com/yiyan-yixing/onecode.git
cd onecode

# 一键安装 oc CLI + Docker 镜像
bash agent-runtime/bin/install.sh
```

安装过程中会：
1. 检测环境（OS / 架构）
2. 安装 Docker（如未安装）
3. 拉取镜像 `ghcr.io/yiyan-yixing/onecode:latest`
4. 安装 `oc` 命令到 `~/bin/oc`
5. 保存配置到 `~/.onecode/settings.json`

安装完成后刷新 PATH：

```bash
source ~/.bashrc    # Linux
source ~/.zshrc     # macOS
```

### 手动安装

如果已有 Docker，只想装 `oc` 命令：

```bash
cd onecode
bash agent-runtime/bin/install
# 安装 oc -> ~/bin/oc
source ~/.bashrc
```

### 从源码构建镜像

```bash
# 构建镜像（自动匹配当前架构：Apple Silicon → arm64，Intel → amd64）
docker build -t ghcr.io/yiyan-yixing/onecode:latest agent-runtime/

# 同时打版本 tag
docker build -t ghcr.io/yiyan-yixing/onecode:latest \
             -t ghcr.io/yiyan-yixing/onecode:0.3.5 \
             agent-runtime/

# 在 Intel 机器上强制构建 amd64 镜像
docker build --platform linux/amd64 -t ghcr.io/yiyan-yixing/onecode:latest agent-runtime/
```

> 构建完成后，本地已有同名镜像，`oc` 命令直接可用，无需推送到远端。

---

## 推送镜像到 GHCR

```bash
# 1. 登录 GitHub Container Registry
echo "$GITHUB_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin

# 2. 推送镜像
docker push ghcr.io/yiyan-yixing/onecode:latest
docker push ghcr.io/yiyan-yixing/onecode:0.3.5

# 3. 在 GitHub 仓库 Settings → Packages 中确认镜像可见性为 Public
```

> **权限要求**：需要仓库的 `write:packages` 权限。可在 GitHub Settings → Developer settings → Personal access tokens 创建。

---

## 远端服务器安装

在任意 Linux/macOS 服务器上一键安装：

```bash
# 一键安装（Docker + 镜像 + oc CLI + 配置）
curl -fsSL https://raw.githubusercontent.com/yiyan-yixing/onecode/main/agent-runtime/bin/install.sh | bash

# 带参数安装（跳过交互输入）
curl -fsSL https://raw.githubusercontent.com/yiyan-yixing/onecode/main/agent-runtime/bin/install.sh | \
  bash -s -- --api-key sk-xxx --api-base-url https://api.anthropic.com --model claude-sonnet-4-6

# 私有仓库需提供登录凭据
curl -fsSL https://raw.githubusercontent.com/yiyan-yixing/onecode/main/agent-runtime/bin/install.sh | \
  bash -s -- --registry-user YOUR_USER --registry-pass YOUR_PAT

# 已有 Docker，只装 oc CLI
curl -fsSL https://raw.githubusercontent.com/yiyan-yixing/onecode/main/agent-runtime/bin/install.sh | \
  bash -s -- --skip-docker

# 安装指定版本
curl -fsSL https://raw.githubusercontent.com/yiyan-yixing/onecode/main/agent-runtime/bin/install.sh | \
  bash -s -- --tag 0.3.5
```

安装完成后刷新 PATH：

```bash
source ~/.bashrc    # Linux
source ~/.zshrc     # macOS
```

安装脚本 `install.sh` 支持 `--help` 查看全部选项：

```bash
bash agent-runtime/bin/install.sh --help
```

---

## oc 命令

`oc` 是 OneCode 的简写命令，管理容器化 Claude Code 的一切。

### 命令列表

| 命令 | 说明 |
|------|------|
| `oc` | 交互式 Claude CLI（默认 = `oc run`） |
| `oc remote` | 启动 Web 终端，浏览器访问 |
| `oc ssh <name>` | 给运行中的容器开启 SSH |
| `oc shell [name]` | 进入容器 shell |
| `oc stop <name>` | 停止并删除容器 |
| `oc update` | 拉取最新镜像 + 自更新 CLI |
| `oc ls` | 列出容器和镜像 |
| `oc config` | 查看配置（`~/.onecode/settings.json`） |
| `oc help [cmd]` | 查看帮助 |

### 全局选项

| 选项 | 说明 | 默认值 |
|------|------|--------|
| `-n NAME` | 容器名称 | `oc-<目录>-<pid>-<时间戳>` |
| `-d DIR` | 挂载的本地目录 | 当前目录 |
| `-p PORT` | Web 终端端口 | `7681` |
| `-a PORT` | App 服务端口 | `8000` |
| `-s PORT` | SSH 端口 | `8222` |
| `--tag TAG` | 镜像版本 | `latest` |
| `--https` | 启用 HTTPS（自签证书） | 关 |
| `--debug` | 显示完整 docker 命令 | 关 |

### 典型用法

```bash
# 1. 交互式 CLI — 在当前目录启动 Claude
oc

# 2. Web 终端 — 浏览器打开 http://localhost:7681
oc remote

# 3. 自定义端口 + 目录
oc -p 8080 -d /path/to/project remote

# 4. HTTPS 模式（非 localhost 访问时）
oc --https remote

# 5. 开启 SSH — 从另一台机器用 VS Code 连接
oc ssh my-container
# 然后: ssh -p 8222 node@<ip>

# 6. 进入容器调试
oc shell my-container

# 7. 停止容器
oc stop my-container

# 8. 查看运行中的容器
oc ls

# 9. 更新到最新版本
oc update
```

---

## Docker 直接运行（不用 oc）

```bash
docker run -it --rm \
  -e API_KEY=your-key \
  -e MODEL=claude-sonnet-4-6 \
  -p 7681:7681 \
  -p 8000:8000 \
  -v $(pwd):/workspace \
  ghcr.io/yiyan-yixing/onecode:latest \
  remote
```

| 端口 | 服务 |
|------|------|
| `7681` | Gateway（Web IDE 入口） |
| `8000` | App 服务端口（Agent 启动的 Web 服务） |
| `8222` | SSH（需手动开启） |

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `API_KEY` | API 密钥（映射到 `ANTHROPIC_API_KEY`） | 必填 |
| `API_BASE_URL` | API 地址（映射到 `ANTHROPIC_BASE_URL`） | `https://api.anthropic.com` |
| `MODEL` | 模型名（映射到 `ANTHROPIC_MODEL`） | `GLM-5.1` |
| `GATEWAY_HTTPS` | 启用 HTTPS | `0` |
| `TERM_TOKEN` | 终端访问 Token（留空则无需认证） | 空 |

---

## 配置文件

`oc` 的配置存放在 `~/.onecode/settings.json`：

```json
{
  "API_KEY": "sk-xxx",
  "API_BASE_URL": "https://api.anthropic.com",
  "MODEL": "GLM-5.1"
}
```

优先级：**环境变量 > 配置文件 > 默认值**

---

## 本地开发（无 Docker）

如果已有 Node.js + Claude Code CLI，可直接启动 gateway：

```bash
cd onecode
npm install
npm run dev
# 浏览器打开 http://localhost:7681
```

---

## 核心特性

- **xterm.js 终端** — 直接与 Claude Code 交互，PTY 直连
- **Agent 角色** — 从 `.claude/agents/*.md` 动态加载，终端中输入 `@dev` 自动路由到对应角色
- **@角色名 快捷输入** — 终端中输入 `@dev` 自动路由到对应角色
- **文件浏览器** — 侧栏浏览项目文件，点击预览
- **代码预览** — 语法高亮、Markdown 渲染、图片预览
- **VS Code** — 内置 code-server，浏览器中完整 VS Code 体验
- **移动端支持** — 响应式布局 + 虚拟键盘 + 4-tab 切换
- **CC 状态** — Skills/Hooks/Plugins/Tasks 实时显示

### Agent 角色

Agent 角色从 `.claude/agents/*.md` 文件动态加载，无需修改前端代码即可增减角色。

**定义格式**（YAML frontmatter）：

```markdown
---
name: Dev
description: 一人公司开发者。用于代码编写、架构决策、Bug 修复、发布。用 @dev 调用。
tools: Read, Write, Bash, Grep, Glob
model: sonnet
color: yellow
---

（Agent 的系统提示词正文...）
```

| 字段 | 说明 | 示例 |
|------|------|------|
| `name` | 显示名称（必填，有此字段才算有效 Agent） | `Dev` |
| `description` | 简短描述，显示在 Agent 面板 | `一人公司开发者` |
| `tools` | 可用工具列表 | `Read, Write, Bash` |
| `model` | 使用的模型 | `sonnet` |
| `color` | UI 颜色（支持颜色名或 hex） | `yellow` / `#10B981` |

文件名（去 `.md`）即为 `@id`，如 `dev.md` → `@dev`。

**内置角色**（项目自带的 `.claude/agents/` 目录）：

| 角色 | 代号 | 颜色 |
|------|------|------|
| CEO | @ceo | blue |
| PM | @pm | green |
| Designer | @designer | purple |
| Architect | @architect | indigo |
| Dev | @dev | yellow |
| DevOps | @devops | orange |
| QA | @qa | red |
| Ops | @ops | magenta |
| Data | @data | teal |
| Fin | @fin | cyan |

没有 Agent 时，面板显示空状态提示："在 .claude/agents/ 下创建 .md 文件来添加智能体"。

---

## 项目结构

```
onecode/
├── agent-runtime/              # 运行时核心
│   ├── gateway/                # Node.js 网关
│   │   ├── index.js           # 入口服务器
│   │   ├── onecode.html       # OneCode 品牌 UI
│   │   ├── pty.js             # PTY 进程管理
│   │   ├── term-ws.js         # 终端 WebSocket
│   │   ├── cc-status.js       # Claude Code 状态
│   │   └── ...
│   ├── bin/                    # CLI 工具
│   │   ├── oc                 # OneCode CLI 主命令
│   │   ├── install            # 安装 oc 到 ~/bin/
│   │   ├── install.sh          # 一键安装脚本
│   │   └── start-remote.sh    # 容器内启动脚本
│   ├── Dockerfile              # 镜像定义
│   └── entrypoint.sh           # 入口脚本
└── package.json
```

---

## 验证步骤

在宿主机上验证安装是否成功：

```bash
# 1. 检查 oc 命令
which oc
oc --version

# 2. 检查配置
oc config

# 3. 启动 Web 终端
oc remote

# 4. 浏览器打开
# http://localhost:7681
# 应看到 OneCode 界面：终端 + 文件侧栏 + Agent 列表

# 5. 在终端中测试 Agent 路由
# 输入: @dev 写一个 Hello World
# 应看到 Claude 以开发者角色响应

# 6. 测试 VS Code
# 浏览器打开: http://localhost:7681/vscode/

# 7. 测试文件浏览
# 浏览器打开: http://localhost:7681/files/

# 8. 停止容器
oc stop <container-name>
```

---

## 版本历史

| 版本 | 说明 |
|------|------|
| v0.3.5 | 动态 Agent 加载（.claude/agents/*.md）、oc 首次引导配置、自动架构检测 |
| v0.2.0 | gateway + PTY + xterm.js + Agent 角色侧栏 + oc CLI |
| v0.1.0 | Next.js MVP：Chat + Monaco Editor + @角色名 + 模拟数据 |
