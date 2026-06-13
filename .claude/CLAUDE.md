# 项目记忆入口

> 此文件加载 core 记忆到每个 session，所有 Agent 共享。

@.claude/memory/core/tech-stack.md
@.claude/memory/core/architecture.md
@.claude/memory/core/project-context.md

## 记忆使用规则

- **core/** — 每个 session 自动加载，只放最关键信息（≤200 行总计）
- **archival/** — Agent 需要时用 Read 读取，不放 core 避免膨胀
- **recall/** — 历史会话摘要，按需检索

## Agent 协作规则

- 所有 Agent 产出写入 `.claude/blackboard/`
- 质疑按 `.claude/agents/challenge-protocol.md` 执行
- 架构决策写入 `.claude/memory/core/architecture.md` 并归档到 `archival/decisions/`
- 经验教训写入 `.claude/memory/archival/lessons/`
