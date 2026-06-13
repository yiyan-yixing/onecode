# OneCode — AI 原生 IDE

容器化 Claude Code，一条命令启动，内置一人公司 Agent 角色体系。

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│  OneCode · AI 原生 IDE     v0.2   [Skills▼] [New] [VS Code] │
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
bash agent-runtime/bin/cloud-install.sh
```

安装过程中会：
1. 检测环境（OS / 架构）
2. 安装 Docker（如未安装）
3. 拉取镜像 `ghcr.io/yiyan-yixing/agent-runtime:latest`
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
docker build -t ghcr.io/yiyan-yixing/agent-runtime:latest agent-runtime/
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
  -e MODEL=GLM-5.1 \
  -p 7681:7681 \
  -p 8000:8000 \
  -v $(pwd):/workspace \
  ghcr.io/yiyan-yixing/agent-runtime:latest \
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
- **10 Agent 角色** — CEO/PM/设计师/架构师/开发者/DevOps/QA/运营/数据/财务
- **@角色名 快捷输入** — 终端中输入 `@dev` 自动路由到对应角色
- **文件浏览器** — 侧栏浏览项目文件，点击预览
- **代码预览** — 语法高亮、Markdown 渲染、图片预览
- **VS Code** — 内置 code-server，浏览器中完整 VS Code 体验
- **移动端支持** — 响应式布局 + 虚拟键盘 + 4-tab 切换
- **CC 状态** — Skills/Hooks/Plugins/Tasks 实时显示

### Agent 角色

| 角色 | 代号 | 使命 | 时间占比 |
|------|------|------|----------|
| CEO | @ceo | 战略方向、重大决策、全局监控 | 10% |
| 产品经理 | @pm | 做用户真正需要的产品 | 15% |
| 设计师 | @designer | 最短时间把想法变成可感知的界面 | 15% |
| 架构师 | @architect | 做正确的技术选型，防止架构债务 | 5% |
| 开发者 | @dev | 高质量可持续地交付代码 | 25% |
| DevOps | @devops | 极致快速的开发工具链 | 10% |
| 测试 | @qa | 不让 bug 流入生产环境 | 5% |
| 运营 | @ops | 让产品被需要的人看到 | 10% |
| 数据 | @data | 用数据驱动每一个决策 | 10% |
| 财务 | @fin | 守住现金流生命线 | 5% |

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
│   │   ├── cloud-install.sh   # 一键安装脚本
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
| v0.2.0 | gateway + PTY + xterm.js + Agent 角色侧栏 + oc CLI |
| v0.1.0 | Next.js MVP：Chat + Monaco Editor + @角色名 + 模拟数据 |
