---
name: "Dev Code Review Self / 开发者代码自审"
description: "每次 commit 前过一遍自审 checklist：错误处理、边界条件、测试覆盖。10 分钟。"
when_to_use: "每次 commit 前 / 每次 PR 提交前；用户说'自审''review代码''check code'时触发。频次：daily，时间盒：10min"
allowed-tools:
  - Read
  - Bash(git diff*)
  - Bash(git status*)
disable-model-invocation: true
version: "1.0.0"
---

# 开发者：代码自审

你是开发者。一人公司没有第二双眼睛，必须靠工具和流程补位。

## 准备

- **当前变更 diff**：本次修改的代码差异（`git diff`）

## 执行步骤

### Step 1：看整体变更范围（1min）

先不细看代码，浏览变更文件列表和每个文件改了几行。

- 超过 10 个文件 → 考虑拆分提交
- 超过 300 行 → 考虑拆分提交

> 一人公司没有 PR 制约，大的 diff 更容易藏 bug

### Step 2：逐文件过 checklist（5min）

按以下顺序检查：
1. ✅ 错误处理是否完整
2. ✅ 边界条件是否覆盖（空值、0、负数、超大值）
3. ✅ 日志是否够（出问题能定位）
4. ✅ 有没有硬编码/魔法数字
5. ✅ 安全问题（输入校验、SQL 注入、XSS）

> 重点关注错误路径——"happy path"你自己测过了，错误路径往往没有

### Step 3：检查命名和可读性（2min）

3 个月后还能看懂吗？函数名是否准确描述了做的事？

> 3 个月后看代码的人就是你自己，对未来的自己好一点

### Step 4：确认测试覆盖（1min）

新增/修改的逻辑有对应测试吗？测试覆盖了错误路径吗？

> 一人公司没有测试 = 裸奔，线上出问题只有你修

### Step 5：写好 commit message（1min）

Conventional Commits 格式：
- `feat:` 新功能
- `fix:` 修复
- `refactor:` 重构
- `docs:` 文档
- `chore:` 杂务

> commit message 是给未来自己查问题时的线索

## 产出

- 自审通过后提交
- 发现的问题修复

## 反模式（避免）

- ❌ 不看直接 commit（"我先推了再说"）
- ❌ 自审走过场，只扫不改
- ❌ 一次改 20 个文件还觉得没问题
- ❌ 跳过测试覆盖检查
