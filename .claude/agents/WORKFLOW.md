# 一人公司 Agent 协作流程

> 10 个角色，1 条产品闭环 DAG，极致快速地从想法到数据验证。
> 支持：条件分支、质疑协议、共享记忆、DAG 编排。

---

## 产品闭环 DAG

不再是简单线性流水线，而是支持条件分支的有向无环图：

```
@pm 定义需求
  ├── @architect 架构评审 ← 条件：涉及新模块/新依赖/新技术选型
  ├── @data 指标评审 ← 条件：涉及用户可见功能
  │
  └── @designer 出原型
        ├── @dev 实现
        │     └── @qa 测试
        │           ├── @devops 部署 ← 条件：QA 说 Go
        │           └── @dev 修复 ← 条件：QA 说 No-Go（修复后重测）
        │                 └── @qa 回归测试 ← 条件：修复了 P0/P1 bug
        │
        └── @ops 推送用户
              └── @data 收集效果（7天）
                    └── @pm 决策迭代
                          ├── 继续 → 下一迭代
                          ├── 调整 → 改进后下一迭代
                          └── 砍掉 → @ceo 切方向 → 回到 @pm 重新定义
```

### 质疑节点（按 challenge-protocol.md）

```
@pm 出 PRD ──→ @dev 质疑技术可行性 ──→ 通过/修改/打回
            ──→ @data 质疑指标可量化 ──→ 通过/修改/打回

@dev 出技术方案 ──→ @architect 质疑架构合理性 ──→ 通过/修改/打回

@ceo 做重大决策 ──→ @data 质疑数据支撑 ──→ 通过/修改/打回
```

---

## 角色职责速查

| 角色 | 调用 | 做什么 | 不做什么 |
|------|------|--------|----------|
| **CEO** | `@ceo` | 定方向、做决策、监控全局 | 不陷入执行细节 |
| **PM** | `@pm` | 定义需求、排优先级、写 PRD | 不自己当用户 |
| **Designer** | `@designer` | 快速原型、UI/UX、视觉冲击 | 不追求完美拖延交付 |
| **Architect** | `@architect` | 技术选型、架构设计、ADR | 不过度设计 |
| **Dev** | `@dev` | 写代码、修 bug、执行架构 | 不自己选型/自己测自己的代码 |
| **QA** | `@qa` | 测试、找 bug、发布阻断 | 不证明代码没问题 |
| **DevOps** | `@devops` | CI/CD、部署、监控、工具链 | 不自建不需要的基础设施 |
| **Ops** | `@ops` | 推广、内容、增长 | 不追热点偏离定位 |
| **Data** | `@data` | 埋点、分析、效果报告 | 不堆数据不说结论 |
| **Fin** | `@fin` | 记账、现金流、支出审查 | 不混个人和公司支出 |

---

## 快速出 Demo 流程（3 天）

> AI Agent 赛道的铁律：没有 Demo 就没有对话。

```
Day 1: @pm 定场景 + @architect 确认可行性 + @designer 画关键流程
       输入：市场假设 + 技术可行性
       输出：1 页 PRD + 交互原型 + 架构方案

Day 2: @dev 快速实现 + @designer UI 走查 + @qa 快速冒烟测试
       输入：PRD + 交互原型 + 架构方案
       输出：可运行 Demo + 冒烟测试通过

Day 3: @devops 一键部署 + @ops 推给 10 人看 + @data 开始采集
       输入：可运行 Demo
       输出：在线 Demo + 2min 视频 + 10 份反馈 + 数据采集启动
```

### 交接标准

| 交接 | 从 → 到 | 交接物 | 验收条件 |
|------|---------|--------|----------|
| PM → Architect | 需求 → 技术评审 | PRD + 用户故事 | Architect 确认可行 |
| PM → Designer | 需求 → 原型 | PRD + 验收标准 | Designer 确认能出原型 |
| Architect → Dev | 架构 → 实现 | ADR + 架构图 + 接口规范 | Dev 确认能实现 |
| Designer → Dev | 原型 → 代码 | 交互原型 + 设计标注 | Dev 确认与架构一致 |
| Dev → QA | 代码 → 测试 | 代码 + 自审报告 | 代码能跑通核心流程 |
| QA → DevOps | 测试通过 → 部署 | Go 判定 + 测试报告 | QA 说 Go 才能部署 |
| QA → Dev | 测试不通过 → 修复 | No-Go + bug 报告 | P0/P1 必须修复 |
| DevOps → Ops | 部署上线 → 推广 | 在线 URL + 健康检查 | 站点可访问 |
| Ops → Data | 用户来了 → 采集数据 | 推广渠道数据 | 埋点数据开始流入 |
| Data → PM | 数据 → 决策 | 效果分析报告 | 报告有"所以呢"结论 |
| Data → CEO | 数据 → 校准 | 关键指标红/黄/绿 | CEO 根据数据做战略判断 |

---

## 一周一迭代节奏

```
周一（20min）         周三（10min）         周五（20min）
┌──────────┐        ┌──────────┐        ┌──────────────┐
│ 规划本周  │──────→│ 中期检查  │──────→│ 复盘+下周预划 │
│ @pm 主导  │       │ @pm 主导  │       │ @data+@pm 主导│
│ @architect│       │ @dev 反馈 │       │ @ceo 校准    │
│ 可行确认  │       │          │       │              │
└──────────┘        └──────────┘        └──────────────┘
```

### 周一规划

- @pm 从 OKR 提取本周目标
- @architect 确认技术可行性
- @designer + @dev 确认工作量
- @devops 确认部署通道畅通
- @data 确认数据采集就绪
- 质疑：@dev 对 PRD 做技术可行性评审

### 周三检查

- @pm 检查进度
- @dev 反馈技术障碍
- 偏航 → 当天调整，不等到周五

### 周五复盘

- @data 出数据快报
- @pm 判断假设是否成立
- @architect 评估技术债
- @ceo 做战略校准（如需要）
- 定下周方向
- 写入 `.claude/blackboard/current-sprint.md`

---

## 角色协作矩阵

| | PM | Architect | Designer | Dev | QA | DevOps | Ops | Data | CEO | Fin |
|--|----|-----------|----------|-----|----|----|-----|------|-----|-----|
| **PM** | — | 给 PRD 评审 | 给 PRD | 给需求 | 给验收标准 | — | 给推广素材 | 给指标定义 | 汇报进度 | — |
| **Architect** | 给可行性结论 | — | — | 给架构+ADR | — | 给部署架构 | — | — | 给技术风险 | — |
| **Designer** | 确认需求 | — | — | 给原型 | — | — | 给截图视频 | — | — | — |
| **Dev** | 确认可行 | 确认架构 | 确认设计 | — | 给代码 | 给部署包 | — | 给埋点 | — | — |
| **QA** | 给测试结果 | — | — | 给 bug 报告 | — | 给 Go 判定 | — | — | — | — |
| **DevOps** | — | 确认部署架构 | — | 部署服务 | — | — | 给在线 URL | 给采集通道 | — | 给成本数据 |
| **Ops** | 给用户反馈 | — | — | — | — | — | — | 给流量数据 | — | — |
| **Data** | 给效果报告 | — | — | — | — | — | 给增长数据 | — | 给指标报告 | — |
| **CEO** | 给方向 | 给技术方向 | — | — | — | — | — | 给决策 | — | 给预算 |
| **Fin** | — | — | — | — | — | 给支出审批 | — | — | 给现金流 | — |

---

## 记忆读写规则

| Agent | 可写 | 可读 |
|-------|------|------|
| @ceo | blackboard/decisions-log.md, blackboard/open-questions.md | 所有 |
| @pm | blackboard/current-sprint.md | 所有 |
| @architect | memory/core/architecture.md, memory/core/tech-stack.md, archival/decisions/ | 所有 |
| @dev | — | memory/core/, archival/decisions/ |
| @designer | — | memory/core/ |
| @qa | blackboard/challenges.md | memory/core/ |
| @devops | memory/core/tech-stack.md（部署工具部分） | memory/core/ |
| @ops | — | memory/core/ |
| @data | memory/archival/user-research/, blackboard/current-sprint.md（数据部分） | 所有 |
| @fin | — | memory/core/ |

---

## 紧急流程

### P0 Bug 修复

```
@qa 发现 P0 → @dev 立即修复 → @qa 验证 → @devops 热部署
全程 < 1 小时
```

### 方向大转

```
@data 报告假设不成立 → @pm 提出新假设 → @architect 评估技术可行性 → @ceo 批准 → 下一周立刻切方向
不犹豫，不停滞
```

### 机会窗口

```
外部出现大机会 → @ceo 判断是否值得切 → @architect 评估技术可行性 → @pm 评估需求 → 如果 3 天能出 Demo → 立刻启动快速出 Demo 流程
```
