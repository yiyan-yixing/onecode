# OneCode 仓库优化执行清单

> 诊断日期：2026-06-15 | 评分：42/100 | 瓶颈：首屏传达 + 信任信号

## P0 — 立即做（影响首屏传达和信任，1-2 小时内完成）

### 1. 添加 LICENSE 文件 ⏱️ 2min
- [ ] 创建 `LICENSE`（推荐 MIT，与一人公司快速交付一致）
- [ ] README 加 badge: `[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)]`

### 2. 发布第一条 Release ⏱️ 15min
- [ ] 基于 `agent-runtime/VERSION` (0.4.0) 创建 GitHub Release
- [ ] 写 Release Notes（哪怕 3 行也行）
- [ ] README 加 badge: `[![Release](https://img.shields.io/github/v/release/yiyan-yixing/onecode)]`

### 3. 添加 GitHub Topics ⏱️ 2min
- [ ] 在 GitHub 仓库 Settings → Topics 添加：
  `ai`, `claude`, `ide`, `docker`, `cli`, `coding-agent`, `terminal`, `web-ide`, `agent`, `one-person-company`

### 4. 设置 GitHub Description ⏱️ 1min
- [ ] About 描述设为：`AI-native IDE — containerized Claude Code with one command. Built-in agent roles for solo founders.`
- [ ] 添加官网链接（如有）

### 5. README 首屏重构 ⏱️ 45min

**重构后的首屏结构**：

```markdown
# OneCode — AI 原生 IDE

[![Version](https://img.shields.io/github/v/release/yiyan-yixing/onecode)]
[![License](https://img.shields.io/github/license/yiyan-yixing/onecode)]
[![Docker Pulls](https://img.shields.io/docker/pulls/ghcr.io/yiyan-yixing/onecode)]

**一条命令启动 Claude Code，浏览器里写代码。** 容器化、零配置、内置 Agent 角色体系。

![OneCode Demo](docs/demo.gif)

## ✨ 核心特性

- 🚀 **一条命令** — `oc remote` 启动，浏览器打开即用
- 🐳 **容器化** — Docker 一键部署，不用配环境
- 🤖 **Agent 角色** — @dev @pm @designer... 内置一人公司团队
- 📱 **移动端** — 手机也能写代码
- 🔌 **VS Code 内置** — code-server 随时切换

## 快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/yiyan-yixing/onecode/main/agent-runtime/bin/install.sh | bash
```

安装完成后：
```bash
oc remote    # 启动 Web 终端，浏览器打开 http://localhost:7681
```

## 为什么要用 OneCode？

| 没有 OneCode | 有 OneCode |
|-------------|-----------|
| 本地装 Claude Code + 配环境 | `curl | bash` 一条命令 |
| 只有命令行 | 浏览器 IDE + 终端 + 预览 |
| 一个人干所有事 | @dev @pm @qa 角色分工 |
| 换电脑要重新配置 | Docker 到处跑 |
```

**重构要点**：
- Badges 第一行 → 信任信号
- 钩子文案 → 痛点场景 + 一行解决
- **Demo GIF** → 最强转化武器（需录制）
- 核心特性 5 条 → 用户关心的价值
- 一行安装命令 → `curl | bash` 比 `git clone` 短
- 对比表 → 最直观的价值传递

### 6. 录制 Demo GIF ⏱️ 30min
- [ ] 录制 15 秒 Demo：`oc remote` → 浏览器打开 → 终端交互 → Agent 列表
- [ ] 保存到 `docs/demo.gif`
- [ ] 嵌入 README 首屏

---

## P1 — 本周做（影响留存和社区）

### 7. 添加 Changelog ⏱️ 15min
- [ ] 创建 `CHANGELOG.md`
- [ ] 回填 v0.1.0 → v0.3.5 → v0.4.0 的变更
- [ ] 后续每次 Release 同步更新

### 8. 添加 FAQ ⏱️ 20min
- [ ] README 末尾或单独 `docs/FAQ.md`
- [ ] 预设问题：Docker 安装问题、API Key 配置、中国网络、移动端体验

### 9. 添加 Issue 模板 ⏱️ 10min
- [ ] `.github/ISSUE_TEMPLATE/bug_report.yml`
- [ ] `.github/ISSUE_TEMPLATE/feature_request.yml`

### 10. 添加 CONTRIBUTING.md ⏱️ 15min
- [ ] 简单的贡献指南（一人项目不需要复杂流程）

---

## P2 — 有空做（锦上添花）

### 11. OG Image 社交卡片 ⏱️ 30min
- [ ] 制作 1200x630 的社交预览图
- [ ] GitHub Settings → Social Preview 上传

### 12. 贡献者墙 ⏱️ 10min
- [ ] README 末尾加 `all-contributors` bot 或手动致谢

### 13. 跨项目引流 ⏱️ 30min
- [ ] 在 skills 仓库 README 添加 OneCode 链接
- [ ] 在 wxyy-sandbox 仓库添加 OneCode 链接

---

## 预期效果

| 优化项 | 预期提升 |
|--------|----------|
| 首屏 GIF | Star 转化率 2-3x |
| Badges + License | 信任度显著提升 |
| Topics + Description | GitHub 搜索流量 +30-50% |
| 一行安装命令 | 新用户流失率 -50% |
| 对比表 | 价值感知率 +40% |
| 首条 Release | 出现在 GitHub Release feed |
