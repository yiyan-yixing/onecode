#!/bin/bash
# 一人公司初始化脚本
# 安装框架后，一键初始化你的公司信息
# 用法: bash .claude/init.sh
# 非交互模式: COMPANY_NAME="XX" DIRECTION="XX" bash .claude/init.sh

set -e

# ─── 配置项（支持环境变量预填，交互模式可修改） ───

: "${COMPANY_NAME:=}"
: "${DIRECTION:=}"
: "${TARGET_USER:=}"
: "${HYPOTHESIS:=}"
: "${ADVANTAGE:=}"
: "${PRODUCT_POSITIONING:=}"
: "${FRONTEND:=}"
: "${BACKEND:=}"
: "${DATABASE:=}"
: "${DEPLOY:=}"

echo ""
echo "🏢 一人公司 · 初始化"
echo "===================="
echo ""
echo "以下信息将写入 Agent 记忆系统，所有角色都会读取。"
echo "按回车跳过则使用默认模板值。"
echo ""

# ─── 交互式收集 ───

if [ -z "$COMPANY_NAME" ]; then
  read -rp "📌 公司名称: " COMPANY_NAME
fi
if [ -z "$DIRECTION" ]; then
  read -rp "🧭 创业方向 (如: AI Agent 垂直场景): " DIRECTION
fi
if [ -z "$TARGET_USER" ]; then
  read -rp "👤 目标用户 (如: 中小企业运营人员): " TARGET_USER
fi
if [ -z "$HYPOTHESIS" ]; then
  read -rp "💡 核心假设 (如: 市场需要 AI Agent 自动化客服): " HYPOTHESIS
fi
if [ -z "$ADVANTAGE" ]; then
  read -rp "⚔️  创始人优势 (如: AI Agent 技术深度): " ADVANTAGE
fi
if [ -z "$PRODUCT_POSITIONING" ]; then
  read -rp "🎯 产品定位 (一句话): " PRODUCT_POSITIONING
fi

echo ""
echo "⚡ 技术栈偏好 (回车跳过 = 创业期选型原则)"
if [ -z "$FRONTEND" ]; then
  read -rp "   前端框架 (如: Next.js): " FRONTEND
fi
if [ -z "$BACKEND" ]; then
  read -rp "   后端框架 (如: Hono): " BACKEND
fi
if [ -z "$DATABASE" ]; then
  read -rp "   数据库 (如: Supabase): " DATABASE
fi
if [ -z "$DEPLOY" ]; then
  read -rp "   部署平台 (如: Vercel): " DEPLOY
fi

# ─── 默认值处理 ───

COMPANY_NAME="${COMPANY_NAME:-我的公司}"
DIRECTION="${DIRECTION:-AI Agent}"
TARGET_USER="${TARGET_USER:-待定（需通过 Demo 验证）}"
HYPOTHESIS="${HYPOTHESIS:-市场需要 ${DIRECTION} 解决方案，有人愿意付费}"
ADVANTAGE="${ADVANTAGE:-${DIRECTION} 技术深度}"
PRODUCT_POSITIONING="${PRODUCT_POSITIONING:-找到 ${DIRECTION} 的第一个付费场景}"

# ─── 写入记忆系统 ───

CLAUDE_DIR=".claude"

echo ""
echo "📝 [1/4] 写入项目上下文..."

cat > "${CLAUDE_DIR}/memory/core/project-context.md" << EOF
# 项目上下文

> 此文件由所有 Agent 共享。描述公司/产品的基本信息，每个 Agent 都应该知道。

## 公司

- **名称**：${COMPANY_NAME}
- **阶段**：0→1 创立期
- **模式**：一人公司
- **方向**：${DIRECTION}

## 产品

- **定位**：${PRODUCT_POSITIONING}
- **目标用户**：${TARGET_USER}
- **核心假设**：${HYPOTHESIS}
- **差异化**：创始人有${ADVANTAGE}，能快速出 Demo

## 季度 OKR

- **O**：用 Demo 验证假设，获得第一批付费客户
- **KR1**：3 个场景 Demo，10+ 人看过并给反馈（W4）
- **KR2**：MVP 上线，日活 20+（W8）
- **KR3**：付费客户 1 个（W12）

## 明确不做

- ❌ 通用平台（先做窄场景）
- ❌ ToC 消费级产品（先做 ToB/ToPro）
- ❌ AI 套壳（必须有技术壁垒）
- ❌ 扩团队（先验证再招人）

## 当前瓶颈

- 验证 Problem-Solution Fit
- 需要 Demo 作为销售武器

## 团队角色

| 角色 | 调用 | 核心使命 |
|------|------|----------|
| CEO | @ceo | 战略方向、重大决策 |
| PM | @pm | 做用户真正需要的产品 |
| Designer | @designer | 用最短时间出可感知界面 |
| Dev | @dev | 高质量可持续交付代码 |
| Architect | @architect | 正确的技术选型 |
| QA | @qa | 不让 bug 流入生产 |
| DevOps | @devops | 极致快速的工具链 |
| Ops | @ops | 让产品被需要的人看到 |
| Data | @data | 数据驱动每一个决策 |
| Fin | @fin | 守住现金流生命线 |
EOF
echo "   ✅ project-context.md"

# ─── 写入技术栈 ───

echo "⚙️  [2/4] 写入技术栈..."

TECH_ROWS=""
if [ -n "$FRONTEND" ]; then
  TECH_ROWS="${TECH_ROWS}
| 前端 | ${FRONTEND} | — | 托管优先、生态优先 | — |"
fi
if [ -n "$BACKEND" ]; then
  TECH_ROWS="${TECH_ROWS}
| 后端 | ${BACKEND} | — | 托管优先、速度优先 | — |"
fi
if [ -n "$DATABASE" ]; then
  TECH_ROWS="${TECH_ROWS}
| 数据库 | ${DATABASE} | — | 托管优先、成本优先 | — |"
fi
if [ -n "$DEPLOY" ]; then
  TECH_ROWS="${TECH_ROWS}
| 部署 | ${DEPLOY} | — | push-to-deploy ≤ 10min | — |"
fi

if [ -z "$TECH_ROWS" ]; then
  TECH_ROWS="
| 待定 | — | — | 创业初期，尚未选型 | — |"
fi

cat > "${CLAUDE_DIR}/memory/core/tech-stack.md" << EOF
# 技术栈

> 此文件由所有 Agent 共享。每次技术选型变更时更新。

## 当前技术栈

| 层级 | 技术 | 版本 | 选型理由 | 选型日期 |
|------|------|------|----------|----------|${TECH_ROWS}

## 选型原则

- 托管优先：能用 Vercel/Supabase/Cloudflare 就不自建
- 成本优先：月基础设施 ≤ ¥500
- 速度优先：从 push 到上线 < 10 分钟
- 生态优先：社区大、文档好、出问题能搜到答案

## 选型决策记录

| 编号 | 决策 | 理由 | 日期 | 当前状态 |
|------|------|------|------|----------|
| — | — | — | — | — |
EOF
echo "   ✅ tech-stack.md"

# ─── 重置架构 ───

echo "🏗️  [3/4] 重置架构决策..."

cat > "${CLAUDE_DIR}/memory/core/architecture.md" << EOF
# 架构决策记录

> 此文件由所有 Agent 共享。每次重大架构决策时更新。

## 当前架构

- **阶段**：0→1 创业期
- **模式**：待定（单体 / 微服务 / Serverless）
- **核心约束**：一人公司，极致快速交付

## ADR（Architecture Decision Records）

格式：ADR-<编号> | <标题> | <状态>

### ADR 模板

\`\`\`
## ADR-<N>: <标题>

### 状态
提议 / 已采纳 / 已废弃 / 已替代

### 背景
为什么要做这个决策？

### 决策
我们选择了什么？

### 理由
为什么这么选？考虑了哪些替代方案？

### 后果
这个决策带来的好处和代价？
\`\`\`

### 已记录的 ADR

| 编号 | 标题 | 状态 | 日期 |
|------|------|------|------|
| — | — | — | — |
EOF
echo "   ✅ architecture.md"

# ─── 重置白板 ───

echo "📋 [4/4] 重置共享白板..."

cat > "${CLAUDE_DIR}/blackboard/current-sprint.md" << 'EOF'
# 当前迭代

> 协调者 Agent 维护此文件。所有 Agent 可读取当前迭代状态。

## 迭代信息

| 项目 | 值 |
|------|----|
| 迭代号 | Sprint-0 |
| 起止日期 | — |
| 季度 OKR | O: 用 Demo 验证假设，获得第一批付费客户 |

## 本周目标

```
本周目标：[每周一由 @pm 填写]
成功标准：[具体数字]
时间预算：[小时数]
```

## 任务分配

| 任务 | 负责角色 | 状态 | 交付物 |
|------|----------|------|--------|
| — | — | — | — |

## 进度

| 日期 | 更新内容 | 更新者 |
|------|----------|--------|
| — | 初始化 | @ceo |
EOF

cat > "${CLAUDE_DIR}/blackboard/open-questions.md" << 'EOF'
# 待解决问题

> 任何 Agent 都可以写入新问题，协调者负责分配和推进。

## 问题格式

```
Q<编号> | <提出者> | <日期> | <问题描述> | <严重度：阻断/重要/一般> | <状态：待处理/进行中/已解决>
```

## 问题列表

| 编号 | 提出者 | 日期 | 问题 | 严重度 | 状态 |
|------|--------|------|------|--------|------|

> 新问题追加到表末尾，不要删除已解决问题——它们是决策历史的一部分。
EOF

cat > "${CLAUDE_DIR}/blackboard/challenges.md" << 'EOF'
# 质疑记录

> 按质疑协议执行，记录每次质疑的过程和结果。

## 格式

```
C<编号> | <质疑者> | <被质疑者> | <日期> | <质疑内容> | <严重度> | <结果：通过/修改/打回>
```

## 记录

| 编号 | 质疑者 | 被质疑者 | 日期 | 质疑内容 | 严重度 | 结果 |
|------|--------|----------|------|----------|--------|------|
EOF

cat > "${CLAUDE_DIR}/blackboard/decisions-log.md" << 'EOF'
# 决策日志

> 记录每个重大决策，便于追溯。

## 格式

```
D<编号> | <决策者> | <日期> | <决策内容> | <依据> | <影响范围>
```

## 决策记录

| 编号 | 决策者 | 日期 | 决策 | 依据 | 影响范围 |
|------|--------|------|------|------|----------|
EOF

echo "   ✅ current-sprint.md"
echo "   ✅ open-questions.md"
echo "   ✅ challenges.md"
echo "   ✅ decisions-log.md"

# ─── 清空归档 ───

echo ""
echo "📦 清空归档记忆（保留模板结构）..."

cat > "${CLAUDE_DIR}/memory/archival/decisions/decisions.md" << 'EOF'
# 架构决策归档

> 已完成或已废弃的架构决策存档于此。

## 归档记录

| 编号 | 标题 | 原状态 | 归档原因 | 归档日期 |
|------|------|--------|----------|----------|
EOF

cat > "${CLAUDE_DIR}/memory/archival/lessons/lessons.md" << 'EOF'
# 经验教训

> 每次迭代复盘后的经验教训存档于此。格式：L<编号> | <教训> | <场景> | <如何避免/复用>

## 教训记录

| 编号 | 教训 | 场景 | 如何避免/复用 |
|------|------|------|---------------|
EOF

cat > "${CLAUDE_DIR}/memory/archival/user-research/research.md" << 'EOF'
# 用户调研归档

> 用户访谈、问卷、反馈等调研数据存档于此。

## 调研记录

| 编号 | 方法 | 日期 | 人数 | 关键发现 | 行动 |
|------|------|------|------|----------|------|
EOF

echo "   ✅ archival/decisions/decisions.md"
echo "   ✅ archival/lessons/lessons.md"
echo "   ✅ archival/user-research/research.md"

# ─── 完成 ───

echo ""
echo "🎉 初始化完成！"
echo ""
echo "你的公司信息："
echo "  📌 公司: ${COMPANY_NAME}"
echo "  🧭 方向: ${DIRECTION}"
echo "  🎯 定位: ${PRODUCT_POSITIONING}"
echo "  👤 用户: ${TARGET_USER}"
echo ""
echo "下一步："
echo "  1. 启动 Claude Code"
echo "  2. 输入 @ceo 做季度规划"
echo "  3. 输入 @pm 开始第一个 Sprint"
echo "  4. 输入 @designer 3天出一个Demo"
echo ""
echo "随时可以修改 .claude/memory/core/ 下的文件更新公司信息。"
