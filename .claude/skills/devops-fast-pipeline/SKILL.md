---
name: "DevOps Fast Pipeline / 极速交付流水线"
description: "搭建极致快速的开发交付流水线：代码提交 → 自动测试 → 自动部署 → 线上验证，全流程 < 10 分钟。一人公司必备。"
when_to_use: "需要搭建或优化 CI/CD 流水线时；用户说'CI/CD''流水线''部署''自动部署''pipeline''devops'时触发。频次：on-demand，时间盒：60min"
allowed-tools:
  - Read
  - Write
  - Bash
  - Edit
disable-model-invocation: true
version: "1.0.0"
---

# DevOps：极速交付流水线

你是 DevOps 工程师。你的目标：让"从代码到线上"的周期 < 10 分钟，让开发者只关注写代码。

## 准备

- **项目技术栈**：前端/后端/全栈？用什么框架？
- **部署目标**：Vercel/Cloudflare/AWS/其他？
- **当前部署方式**：手动？有没有 CI？

## 执行步骤

### Step 1：选择部署方案（10min）

| 技术栈 | 推荐部署 | 理由 |
|--------|----------|------|
| Next.js / React | Vercel | 零配置部署、Preview 部署、免费层够用 |
| 静态站 / SPA | Cloudflare Pages | 全球 CDN、免费 |
| Serverless | Cloudflare Workers / Vercel Functions | 按调用付费、冷启动快 |
| 全栈 / API | Railway / Fly.io | 简单容器部署、有免费层 |

> 一人公司首选托管平台，不自己运维。

### Step 2：搭建 GitHub Actions CI（15min）

标准 CI 流水线：

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'
      - run: npm ci
      - run: npm test
      - run: npm run build
```

**关键优化**：
- `cache: 'npm'` — 缓存依赖，安装 < 30s
- 只跑必要测试，不要 lint+test+build 全串行

### Step 3：自动部署（15min）

**方式一：平台集成（推荐）**

Vercel / Cloudflare Pages 自动部署：
1. 连接 GitHub 仓库
2. main 分支 → Production 部署
3. PR → Preview 部署
4. 零配置

**方式二：GitHub Actions 部署**

```yaml
# 在 CI job 后加 deploy job
deploy:
  needs: test
  if: github.ref == 'refs/heads/main'
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - run: npm ci && npm run build
    - uses: amondnet/vercel-deployment@v25
      with:
        vercel-token: ${{ secrets.VERCEL_TOKEN }}
```

### Step 4：健康检查（5min）

部署后自动验证：

```bash
# 简单健康检查
curl -f https://your-app.vercel.app/api/health || exit 1
```

Vercel 自带监控，Cloudflare 有 Health Checks。

### Step 5：回滚方案（5min）

| 平台 | 回滚方式 | 耗时 |
|------|----------|------|
| Vercel | 一键回退到上一个部署 | < 30s |
| Cloudflare Pages | `wrangler pages deployment rollback` | < 1min |
| Railway | 回退到上一个 commit 的部署 | < 1min |

> 确保你知道怎么回滚。这是部署的安全网。

### Step 6：监控告警（10min）

最小监控方案：
- **UptimeRobot**（免费）：每 5 分钟检测站点是否在线，下线即通知
- **Sentry**（免费层）：运行时错误自动捕获和通知
- **Vercel Analytics** / **Cloudflare Web Analytics**：性能和访问数据

配置通知渠道：微信/钉钉/Slack/邮件。

## 产出

1. 可运行的 CI/CD 流水线（push → test → deploy < 10 分钟）
2. 健康检查配置
3. 回滚方案文档
4. 监控告警配置

## 速度目标

| 环节 | 目标 | 当前行业平均 | 提升倍数 |
|------|------|--------------|----------|
| push → 测试通过 | 2min | 10-30min | 5-15x |
| 测试通过 → 部署上线 | 3min | 1-2h | 20-40x |
| 发现问题 → 回滚 | 30s | 30-60min | 60-120x |

## 反模式（避免）

- ❌ 自建 CI 服务器（Jenkins）——托管 CI 对一人公司免费够用
- ❌ 部署需要手动审批——你是一个人，审批就是浪费时间
- ❌ 没有回滚方案就上线——出问题只能手忙脚乱
- ❌ 跳过测试直接部署——迟早出事故
- ❌ 监控只看"服务器活着"——要看"用户能不能完成核心流程"
