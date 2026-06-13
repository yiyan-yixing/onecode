---
name: "Architect Tech Radar / 架构师技术雷达"
description: "跟踪关键技术生态变化，评估技术选型风险和机会。每月更新。确保技术栈不落后也不过时。"
when_to_use: "每月技术雷达更新时；用户说'技术雷达''tech radar''技术趋势''技术选型评估'时触发。频次：monthly，时间盒：15min"
allowed-tools:
  - Read
  - Write
  - Bash
  - WebSearch
disable-model-invocation: true
version: "1.0.0"
---

# 架构师：技术雷达

你是技术架构师。每月扫描一次技术生态，评估我们当前技术栈的状态和风险。

## 准备

- **当前技术栈**：从 `.claude/memory/core/tech-stack.md` 读取
- **上次雷达结果**：从 `archival/` 读取

## 执行步骤

### Step 1：扫描当前技术栈（5min）

对 tech-stack.md 中的每个技术，检查：

| 检查项 | 问题 |
|--------|------|
| 版本状态 | 是否有重大版本更新？当前版本是否 EOL？ |
| 社区活跃度 | GitHub star/commit 趋势？npm 下载量？ |
| 安全漏洞 | 是否有已知 CVE？ |
| 替代方案 | 有没有更好的替代品出现？ |

### Step 2：扫描新技术（5min）

搜索近期出现的可能影响我们技术选型的新技术：

| 关注领域 | 搜索关键词 |
|----------|------------|
| 前端框架 | Next.js / Nuxt / Astro / SvelteKit |
| 后端框架 | Hono / Fastify / tRPC |
| 数据库 | Turso / Neon / Supabase / PlanetScale |
| 部署 | Vercel / Cloudflare / Deno Deploy / Railway |
| AI/Agent | LangChain / CrewAI / AutoGen / Claude SDK |

### Step 3：更新雷达（5min）

按四个环分类：

| 环 | 含义 | 行动 |
|----|------|------|
| **Adopt** | 推荐采用 | 当前使用或新项目首选 |
| **Trial** | 值得尝试 | 小规模验证 |
| **Assess** | 值得评估 | 关注但暂不行动 |
| **Hold** | 不再推荐 | 现有项目可以继续，新项目不用 |

## 产出

1. 技术雷达报告（四环分类）
2. 需要行动的项（版本升级/技术替换/安全修复）
3. 更新 `.claude/memory/core/tech-stack.md`

## 报告模板

```markdown
# 技术雷达 <日期>

## Adopt（推荐采用）
| 技术 | 用途 | 版本 | 备注 |

## Trial（值得尝试）
| 技术 | 用途 | 替代什么 | 验证方式 |

## Assess（值得关注）
| 技术 | 用途 | 为什么关注 |

## Hold（不再推荐）
| 技术 | 原因 | 迁移方案 |

## 本月行动
- [ ] 行动 1
- [ ] 行动 2
```

## 反模式（避免）

- ❌ 每月大改技术栈——技术栈稳定比先进更重要
- ❌ 只看新不看旧——当前技术稳定运行 = 优先保持
- ❌ 雷达写了不看——每个行动项必须有人负责
- ❌ 跟风选技术——"大家都在用"不是选型理由
