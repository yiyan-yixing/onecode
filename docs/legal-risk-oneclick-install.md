# OneCode 一键安装法律风险说明

> **版本**：v1.0 | **日期**：2026-06-15
> **适用场景**：OneCode 以 `curl | bash` 一键安装脚本分发，供个人使用和学习
> **性质**：本文件为风险识别参考，不构成法律意见。如有正式法律需求，请咨询专业律师。

---

## 0. 写在前面

OneCode 是一个开源的 AI 原生 IDE，以"一条命令启动"为核心体验。但"一键安装"意味着用户在尚未充分了解软件行为的情况下，就授予了脚本执行权限——这带来了一系列法律和合规风险。

本文逐项说明这些风险，并给出可操作的缓解措施。我们的目标不是消灭所有风险（那不可能），而是让风险**可见、可控、可接受**。

---

## 1. 安装脚本的风险

### 1.1 `curl | bash` 模式

**现状**：README 推荐的安装方式是：

```bash
curl -fsSL https://raw.githubusercontent.com/.../install.sh | bash
```

**风险**：

| 风险 | 说明 | 严重程度 |
|------|------|---------|
| 用户无法预审 | 管道直接执行，用户看不到脚本内容 | 中 |
| 中间人篡改 | DNS 劫持或 CDN 被入侵时，可能执行恶意代码 | 低（HTTPS 提供传输安全） |
| 供应链信任 | 用户信任了 GitHub 仓库维护者，但维护者账号被盗时风险出现 | 低 |

**缓解措施**（已部分实施 ✅ / 待实施 📋）：

- ✅ 使用 HTTPS（`curl -fsSL` 默认验证 SSL 证书）
- 📋 在 README 安装命令上方增加安全提示："建议先下载脚本审查后再执行"
- 📋 提供 checksum 文件（`install.sh.sha256`），`cmd_update` 已实现此机制，但首次安装未使用
- 📋 考虑提供 `curl | bash` 之外的推荐安装方式（如 `brew install`）

**建议增加的 README 提示**：

```
> ⚠️ 安全提示：一键安装脚本会执行 sudo 操作（安装 Docker 等依赖）。
> 建议先下载脚本审查内容，确认无误后再执行：
>   curl -fsSL https://...install.sh -o install.sh
>   cat install.sh   # 审查内容
>   bash install.sh
```

### 1.2 脚本执行 sudo 操作

**现状**：`install.sh` 在以下场景需要 root 权限：

- 安装 Docker（Linux：`apt-get install docker-ce` / `yum install docker-ce`）
- 安装 jq（`apt-get install jq` / `yum install jq`）
- 启动 Docker 服务（`systemctl start docker`）

**风险**：

| 风险 | 说明 |
|------|------|
| 系统变更 | 脚本会向系统安装软件包、修改 systemd 服务 |
| 权限提升 | 需要 sudo/root，脚本内的任何错误或恶意代码都以 root 权限执行 |
| 影响范围不可逆 | 安装了 Docker 后不会自动卸载 |

**缓解措施**：

- ✅ 脚本使用 `set -euo pipefail`，出错即停
- ✅ 检测 Docker 已安装后跳过安装步骤
- ✅ macOS 使用 Homebrew cask 安装，无需 sudo
- 📋 在安装开始前打印"本脚本将执行以下操作"清单
- 📋 提供 `--skip-docker` 参数供已有 Docker 的用户跳过（已实现 ✅）

### 1.3 修改用户 shell 配置

**现状**：`install.sh:371-378` 向 `~/.bashrc` / `~/.zshrc` 追加 PATH 设置：

```bash
echo "export PATH=\"${INSTALL_DIR}:\$PATH\"" >> "$SHELL_RC"
```

Apple Silicon 用户还会追加 `DOCKER_DEFAULT_PLATFORM`。

**风险**：

| 风险 | 说明 |
|------|------|
| 重复追加 | 多次运行脚本会产生重复的 export 行 |
| Shell 配置损坏 | 极端情况下（如磁盘满）追加操作可能破坏文件 |
| 用户不知情 | 大多数用户不知道自己的 .bashrc 被修改了 |

**缓解措施**：

- ✅ 使用 `>>` 追加而非覆盖
- 📋 追加前检查是否已存在（`grep -q` 检查）
- 📋 追加时加注释标记，便于用户识别和清理

---

## 2. Docker 容器运行的风险

### 2.1 目录挂载

**现状**：`oc` CLI 默认将当前目录挂载到容器的 `/workspace`：

```bash
-v "${dir}":/workspace
```

同时挂载 SSH 目录（只读）：

```bash
-v "$ssh_dir":/home/work/.ssh:ro
```

**风险**：

| 风险 | 说明 | 严重程度 |
|------|------|---------|
| 文件被 AI 修改/删除 | bypassPermissions 模式下，AI 可不经确认操作挂载目录 | 高 |
| 敏感文件泄露 | `.env`、密钥文件等在挂载目录中时，AI 可读取 | 高 |
| SSH 密钥只读保护 | ✅ 已用 `:ro` 标记，容器内无法修改宿主机 SSH 密钥 | — |

**缓解措施**：

- ✅ SSH 目录只读挂载
- 📋 在首次 `oc remote` 时显示警告："挂载目录中的文件可被 AI 读取和修改"
- 📋 考虑提供 `--safe` 模式，限制 AI 的文件写入范围
- 📋 建议用户不要在挂载目录中存放 `.env`、密钥等敏感文件

### 2.2 bypassPermissions 模式

**现状**：OneCode 在三处硬编码了 `bypassPermissions`：

```
index.js:144    → ptyManager.spawn('claude', ['--permission-mode', 'bypassPermissions'])
entrypoint.sh:57 → exec gosu node "$@" --permission-mode bypassPermissions
Dockerfile:158   → "bypassPermissionsModeAccepted":true
```

这意味着 Claude Code 在容器内**无需用户确认即可执行任何操作**——包括运行 shell 命令、读写文件、安装软件包。

**风险**：

| 风险 | 说明 | 严重程度 |
|------|------|---------|
| AI 执行破坏性操作 | AI 可能执行 `rm -rf`、修改系统文件等 | 高 |
| 意外的 API 费用 | AI 可能产生大量 API 调用 | 中 |
| 责任归属不清 | 用户数据被 AI 损坏时，责任归谁？ | 中 |

**为什么用 bypassPermissions**：

容器本身提供了隔离层——即使 AI 执行了破坏性操作，影响范围理论上限于容器内部。但这层隔离因目录挂载而被打破。

**缓解措施**：

- 📋 **首次启动时显示醒目警告**（最重要）
- 📋 提供"安全模式"选项（`--safe`），保留权限确认
- 📋 在 Web UI 中为危险操作增加二次确认
- 📋 限制 AI 可执行的命令白名单（可选，影响灵活性）

### 2.3 Web 终端默认无认证

**现状**：`config.js:9` — `TERM_TOKEN` 默认为空，意味着任何能访问 7681 端口的人都拥有完整的终端控制权。而 `index.js:148` 绑定的是 `0.0.0.0`：

```javascript
server.listen(config.PORT, '0.0.0.0', () => { ... });
```

**风险**：

| 场景 | 风险 |
|------|------|
| 公网服务器部署 | 任何人可连入终端，以 bypassPermissions 模式控制 AI |
| 局域网部署 | 同网络的其他用户可访问 |
| 端口暴露 | Docker 的 `-p 7681:7681` 将端口映射到所有网络接口 |

**缓解措施**：

- 📋 默认生成随机 `TERM_TOKEN`，强制用户设置
- 📋 默认绑定 `127.0.0.1` 而非 `0.0.0.0`（公网部署需显式 `--public`）
- 📋 在 README 和 `oc remote` 输出中增加安全警告

---

## 3. API Key 处理的风险

### 3.1 明文存储

**现状**：API Key 以明文存储在 `~/.onecode/settings.json`：

```json
{"api_key": "sk-ant-api03-xxxxx"}
```

虽设置了 `chmod 600`，但这仅对本地用户生效。

**风险**：

| 风险 | 说明 |
|------|------|
| 文件泄露 | 备份、同步工具、误上传到 Git 均可能泄露 |
| docker inspect 可见 | 通过 `-e API_KEY=...` 传入的环境变量对同主机用户可见 |
| 多用户系统 | 其他 root 用户可直接读取文件 |

**缓解措施**：

- ✅ `settings.json` 使用 `chmod 600` 限制文件权限
- ✅ `oc config` 命令输出时自动掩码 Key（`****xxxx`）
- ✅ 占位 Key 检测（`is_placeholder_key`）阻止 `sk-xxx` 等无效值
- 📋 使用 `--env-file` 替代 `-e` 传递 Key（不在 `docker inspect` 中暴露）
- 📋 `.gitignore` 中排除 `~/.onecode/` 目录（用户自行配置时提醒）

### 3.2 API Key 传输

**现状**：安装脚本的配置向导中：

```bash
read -rsp "  API Key (input hidden): " API_KEY   # 安装时
read -rsp "  API Key (input hidden) [current: ****]: " new_key  # oc config set
```

用户输入的 Key 随后以明文写入 `settings.json`。

**风险**：

- 脚本内部变量 `API_KEY` 在进程环境内可被 `/proc/$PID/environ` 读取
- 安装过程中的 `echo` 或 `set -x` 调试输出可能泄露 Key

**缓解措施**：

- ✅ 使用 `read -rsp` 隐藏用户输入
- ✅ 安装完成后 unset 临时变量
- 📋 安装脚本中增加 `set +x` 防护（如果启用了调试模式）

---

## 4. 开源合规风险

### 4.1 Docker 镜像中的第三方软件

**现状**：Docker 镜像内打包了多个第三方软件，但未附带它们的 LICENSE 文件。

| 软件 | 协议 | 要求 |
|------|------|------|
| JetBrains Mono 字体 | OFL 1.1 | **必须**保留版权声明和许可证文本 |
| filebrowser | Apache 2.0 | **必须**保留 NOTICE 和 LICENSE |
| code-server | MIT | 应保留 LICENSE（MIT 条款要求） |
| highlight.js | BSD-3-Clause | **必须**保留版权声明和许可证 |
| marked | MIT | 应保留 LICENSE |
| @xterm/xterm | MIT | 应保留 LICENSE |
| node-pty | MIT | 应保留 LICENSE |
| ws | MIT | 应保留 LICENSE |

**风险**：

- OFL 1.1 和 Apache 2.0 对许可证文本有明确要求，未附带的再分发**可能构成协议违约**
- BSD-3-Clause 要求保留版权声明
- MIT 虽宽松，但条款中也写明"本声明应包含在所有副本中"

**缓解措施**：

- 📋 在镜像中添加 `/usr/local/share/licenses/onecode/` 目录，存放所有第三方软件的 LICENSE
- 📋 在项目根目录创建 `THIRD_PARTY_NOTICES.md`，列出所有内嵌软件及其协议
- 📋 Dockerfile 中增加 COPY LICENSE 指令

### 4.2 Claude Code 的再分发

**现状**：`Dockerfile:77` 直接安装了 `@anthropic-ai/claude-code@2.1.177`：

```dockerfile
RUN npm install -g @anthropic-ai/claude-code@2.1.177 \
    --registry=https://registry.npmmirror.com
```

**风险**：

- Anthropic 的 Claude Code 可能有自己的服务条款，限制再分发或商业使用
- 通过 npmmirror 镜像安装，绕过了 npm 官方源，可能违反 Anthropic 的分发条款
- 用户的 API Key 通过 OneCode 间接调用 Claude Code，需要确认不违反 Anthropic ToS

**缓解措施**：

- 📋 审查 `@anthropic-ai/claude-code` 的 npm 包许可证
- 📋 审查 Anthropic 的服务条款中关于第三方工具的条款
- 📋 在文档中明确说明 OneCode 是 Claude Code 的前端包装，用户需自行遵守 Anthropic 的服务条款

---

## 5. 品牌与知识产权风险

### 5.1 "OneCode" 品牌名

**现状**：项目使用 "OneCode" 作为品牌名。

**风险**："OneCode" 在以下领域已有使用：
- 中国移动 OneCode 低代码平台
- 多个同名开源项目（IDE/代码编辑器类别）

**缓解措施**：

- 📋 正式推广前完成商标检索
- 📋 考虑使用限定名称，如 "YiYan OneCode" 或 "OC IDE"
- 📋 如发现冲突，尽早更名（早期成本低）

### 5.2 AI 生成内容的版权

**现状**：用户通过 OneCode + Claude Code 生成的代码，版权归属不明确。

**风险**：

- 中国法律尚未明确 AI 生成物的著作权归属
- Anthropic 服务条款中对输出内容的使用有限制
- 用户将 AI 生成代码用于商业项目，可能面临版权争议

**缓解措施**：

- 📋 在文档中声明：用户应自行判断 AI 生成内容的版权状态
- 📋 声明 OneCode 不对 AI 生成内容的知识产权提供担保

---

## 6. 需要创建的法律文件

基于以上分析，建议创建以下文件：

### 6.1 `DISCLAIMER.md` — 免责声明（必须）

```markdown
# 免责声明

## 性质

OneCode 是一个开源项目，仅供个人学习和研究使用，不构成任何商业服务。

## 风险告知

- **AI 操作风险**：本工具以 bypassPermissions 模式运行 Claude Code，
  AI 可不经用户确认执行 shell 命令、读写文件。使用前请了解此风险，
  并确保挂载目录中没有不可恢复的重要数据。

- **数据安全**：API Key 存储在本地 `~/.onecode/settings.json`，
  请勿将该文件提交到版本控制系统或分享给他人。

- **网络安全**：Web 终端默认无密码保护。如需公网访问，
  请设置 TERM_TOKEN 或使用 HTTPS + 反向代理。

- **安装脚本**：一键安装脚本需要 root/sudo 权限。
  建议先下载脚本审查内容，确认无误后再执行。

## 责任限制

本软件按 MIT 协议"原样"提供，不提供任何明示或暗示的担保。
作者不对因使用本软件造成的任何直接或间接损失负责，包括但不限于：
数据丢失、API 费用、系统损坏、安全事件。

## 第三方服务

OneCode 调用 Anthropic 或其他 LLM API。使用前请阅读并遵守
相应 API 提供商的服务条款。OneCode 不对第三方服务的可用性、
安全性或合规性负责。

## AI 生成内容

通过本工具生成的代码和文本，其版权归属取决于适用法律和
API 提供商的服务条款。用户应自行判断 AI 生成内容的
知识产权状态，OneCode 不对此提供担保。
```

### 6.2 `THIRD_PARTY_NOTICES.md` — 第三方声明（必须）

列出 Docker 镜像中所有内嵌软件的版权和许可证信息。

### 6.3 安装脚本首行警告（必须）

在 `install.sh` 的 banner 之后、正式操作之前，增加：

```bash
echo "⚠️  本脚本将执行以下操作："
echo "  - 安装 Docker（如未安装，需要 sudo 权限）"
echo "  - 安装 jq（配置管理工具）"
echo "  - 拉取 Docker 镜像（约 2GB）"
echo "  - 安装 oc 命令到 ${INSTALL_DIR}"
echo "  - 修改 ~/.bashrc 添加 PATH"
echo ""
echo "如需审查脚本内容，请先下载再执行："
echo "  curl -fsSL <url> -o install.sh && cat install.sh && bash install.sh"
echo ""
read -rp "继续安装？[y/N] " _confirm
[[ "$_confirm" =~ ^[yY] ]] || { echo "已取消"; exit 0; }
```

### 6.4 首次启动警告（必须）

在 `oc remote` 启动成功后，打印安全警告：

```
⚠️  安全提醒：
  1. Web 终端当前无密码保护，请勿在公网暴露 7681 端口
  2. AI 以 bypassPermissions 模式运行，可不经确认执行命令
  3. 挂载目录中的文件可被 AI 读取和修改
  4. 设置 TERM_TOKEN 可保护终端访问（oc config set term_token=xxx）
```

---

## 7. 优先级行动清单

| 优先级 | 行动 | 工作量 | 文件 |
|--------|------|--------|------|
| **P0** | 创建 `DISCLAIMER.md` | 1h | `/DISCLAIMER.md` |
| **P0** | 安装脚本增加确认提示 | 30min | `install.sh` |
| **P0** | `oc remote` 增加安全警告 | 30min | `oc` CLI |
| **P1** | 创建 `THIRD_PARTY_NOTICES.md` | 2h | `/THIRD_PARTY_NOTICES.md` |
| **P1** | Docker 镜像内置 LICENSE 文件 | 1h | `Dockerfile` |
| **P1** | 默认生成 TERM_TOKEN | 1h | `oc` CLI + `install.sh` |
| **P1** | 默认绑定 127.0.0.1 | 30min | `index.js` + `oc` CLI |
| **P2** | API Key 用 `--env-file` 传递 | 1h | `oc` CLI |
| **P2** | 审查 Claude Code 再分发权限 | 调研 | — |
| **P2** | 商标检索 "OneCode" | 调研 | — |
| **P3** | 提供安全模式（保留权限确认） | 3h | `entrypoint.sh` + `index.js` |

---

## 8. 总结

OneCode 的"一键安装"体验是核心卖点，但同时也引入了不容忽视的法律和安全风险。好消息是：**对于个人学习和使用场景，大部分风险可以通过清晰的告知和免责声明来管理**。

核心原则：

1. **知情同意** — 让用户在操作前知道会发生什么
2. **风险可见** — 安全警告不是藏在文档深处的脚注，而是启动时的醒目提示
3. **默认安全** — 无认证不应是默认值，公网暴露不应是无意识的
4. **免责清晰** — 明确声明 OneCode 是工具，不对 AI 行为和第三方服务负责

做到这四点，一键安装的风险就可以控制在一个对个人用户合理的范围内。
