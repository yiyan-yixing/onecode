# 免责声明 / Disclaimer

> 最后更新：2026-06-15

---

## 项目性质

OneCode 是一个开源项目，**仅供个人学习和研究使用**，不构成任何商业服务或产品。

## 与 Anthropic 的关系

OneCode 是由社区开发者独立构建的开源项目，**与 Anthropic PBC 没有任何关联、背书或合作关系**。

- Claude Code CLI 是 Anthropic PBC 的专有软件，其使用受 [Anthropic 服务条款](https://www.anthropic.com/terms) 和 [商业条款](https://www.anthropic.com/legal/commercial-terms) 约束
- OneCode **不在 Docker 镜像中预装 Claude Code**。Claude Code 在容器首次启动时由用户从 npm 官方仓库自行安装，与用户在自己的机器上运行 `npm install -g` 等价
- 用户必须提供自己的 API Key，并自行遵守 Anthropic 的服务条款和认证方式限制
- Anthropic **不允许第三方开发者代路由 Free/Pro/Max 用户的 OAuth 凭据**。OneCode 仅支持 API Key 认证方式

## AI 操作风险

OneCode 以 `bypassPermissions` 模式运行 Claude Code，这意味着：

- AI 可以**不经用户确认**执行 shell 命令、读写文件、安装软件包
- 挂载到容器的目录（`-v` 参数）中的文件可被 AI 读取和修改
- AI 的操作可能导致**数据丢失、文件损坏或意外变更**

**使用前请确保：**

1. 挂载目录中没有不可恢复的重要数据，或已做好备份
2. 了解 `bypassPermissions` 模式的含义
3. 不要在公网暴露 Web 终端端口（7681），除非已设置 `TERM_TOKEN`

## API Key 安全

- API Key 存储在本地 `~/.onecode/settings.json`，文件权限为 `600`
- 请勿将该文件提交到版本控制系统（Git）或分享给他人
- 通过 Docker `-e` 参数传入的 API Key 可能被同主机的其他用户通过 `docker inspect` 看到
- 建议使用 `--env-file` 方式传入 API Key 以减少泄露风险

## 第三方服务

OneCode 调用 Anthropic 或其他 LLM 提供商的 API。使用前请阅读并遵守相应提供商的服务条款。OneCode 不对第三方服务的可用性、安全性或合规性负责。

## AI 生成内容

通过本工具生成的代码和文本，其版权归属取决于适用法律和 API 提供商的服务条款。用户应自行判断 AI 生成内容的知识产权状态，OneCode 不对此提供任何担保。

## 责任限制

本软件按 MIT 协议"原样"提供，不提供任何明示或暗示的担保。作者不对因使用本软件造成的任何直接或间接损失负责，包括但不限于：

- 数据丢失或损坏
- API 调用费用
- 系统损坏或安全事件
- AI 生成内容导致的知识产权争议

## 安装与构建

OneCode 的 Docker 镜像需要用户自行构建（`docker build`）。构建脚本会：

- 安装系统依赖（git、curl、python3 等）
- 安装 filebrowser、code-server 等开源工具
- **不会**预装 Claude Code CLI

建议在构建前审查 `agent-runtime/Dockerfile` 的内容。

---

**如有疑问，请在 [GitHub Issues](https://github.com/yiyan-yixing/onecode/issues) 中提出。**
