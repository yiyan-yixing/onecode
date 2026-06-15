# OneCode 测试指南

> 277 assertions · 13 suites · 0 failures · 零外部依赖

---

## 目录

1. [快速开始](#快速开始)
2. [测试架构](#测试架构)
3. [测试覆盖矩阵](#测试覆盖矩阵)
4. [各模块测试详解](#各模块测试详解)
5. [如何运行](#如何运行)
6. [如何编写新测试](#如何编写新测试)
7. [设计决策与约束](#设计决策与约束)
8. [Docker 内集成测试](#docker-内集成测试)

---

## 快速开始

```bash
# 运行全部测试
npm test

# 只跑 gateway 测试
npm run test:gateway

# 只跑 CLI 测试
npm run test:cli

# 按关键字过滤
node tests/run.js config     # 只跑含 "config" 的测试文件
node tests/run.js router     # 只跑 router 相关
```

---

## 测试架构

```
tests/
├── run.js                    # 测试运行器（自研，零依赖）
├── gateway/                  # Node.js 单元测试
│   ├── helpers.js            # 子进程隔离执行器
│   ├── config.test.js        # 配置加载
│   ├── router.test.js        # URL 路由
│   ├── static.test.js        # 静态文件服务
│   ├── cc-status.test.js     # Claude Code 状态 & cron 解析
│   ├── inject.test.js        # HTML 注入 & CSP
│   ├── pty.test.js           # PTY 管理器 & 二进制协议
│   └── index.test.js         # Gateway 集成（HTTP 端点）
├── cli/                      # Bash 测试
│   ├── config.test.sh        # oc config 命令
│   ├── validation.test.sh    # 输入校验
│   ├── migration.test.sh     # v1→v2 配置迁移
│   ├── provider.test.sh      # Provider 默认值
│   ├── entrypoint.test.sh    # 容器入口点逻辑
│   └── install.test.sh       # 一键安装脚本
└── fixtures/                 # 测试数据（由 static.test.js 动态创建）
```

### 测试运行器原理

`run.js` 是一个自研的轻量测试框架：

- **Node.js 测试**：通过 `require()` 加载 `.test.js` 文件，文件导出一个函数，接收 `TestContext` 对象
- **Bash 测试**：通过子进程执行 `.test.sh`，解析 `PASS` / `FAIL` 行
- **统一输出**：所有结果汇总为 `✓` / `✗` / `○` 格式，最终输出通过/失败统计

### TestContext API

```javascript
module.exports = function (t) {
  t.section('标题');              // 开始一个测试小节
  t.assert(condition, '描述');    // 断言
  t.equal(a, b, '描述');         // 严格相等
  t.deepEqual(a, b, '描述');    // 深度相等（JSON 序列化比较）
  t.notEqual(a, b, '描述');     // 不相等
  t.ok(value, '描述');           // 真值断言
  t.throws(fn, '描述');         // 期望抛出异常
  t.doesNotThrow(fn, '描述');   // 期望不抛出异常
  t.skip('描述');               // 跳过
};
```

---

## 测试覆盖矩阵

| 源文件 | 测试文件 | 覆盖内容 | 断言数 |
|--------|----------|----------|--------|
| `gateway/config.js` | `config.test.js` | 默认值、环境变量覆盖、TOKEN 优先级、类型转换 | 30 |
| `gateway/router.js` | `router.test.js` | 文件浏览器/VSCode/代理/服务路由、SSRF 防护、SW 检测 | 22 |
| `gateway/static.js` | `static.test.js` | JS/CSS/HTML 文件服务、gzip 压缩、404、SW/VSDA 存根 | 20 |
| `gateway/cc-status.js` | `cc-status.test.js` | cron 表达式解析、状态结构加载、服务注册表 | 17 |
| `gateway/inject.js` | `inject.test.js` | HTML 注入、CSP 哈希、HTTPS 模式、nonce 保留 | 10 |
| `gateway/pty.js` | `pty.test.js` | 类结构验证、二进制协议帧、客户端管理、缓冲区 | 25 |
| `gateway/index.js` | `index.test.js` | 模块依赖、API 端点定义、后端选择、优雅关闭 | 17 |
| `bin/oc` | `config.test.sh` | set/get/list/reset、值持久化、掩码显示 | 13 |
| `bin/oc` | `validation.test.sh` | placeholder key、backend、URL、port、platform、key 别名 | 22 |
| `bin/oc` | `migration.test.sh` | v1→v2 迁移、provider 推断、幂等性、异常输入 | 8 |
| `bin/oc` | `provider.test.sh` | Anthropic/OpenAI 默认值、后端默认 | 6 |
| `entrypoint.sh` | `entrypoint.test.sh` | 后端选择、case 分支、环境变量映射、语法检查 | 15 |
| `bin/install.sh` | `install.test.sh` | 语法、版本一致性、步骤完整性、迁移、Apple Silicon | 26 |

**总计：277 assertions**

---

## 各模块测试详解

### 1. gateway/config.js — 配置加载

**测试什么：**

| 测试项 | 验证内容 |
|--------|----------|
| 默认值 | PORT=7681, FB_PORT=8081, VSCODE_PORT=8082, BACKEND=claude-code |
| 环境变量覆盖 | GATEWAY_PORT → PORT, TTYD_TOKEN → TERM_TOKEN 等 |
| TOKEN 优先级 | TERM_TOKEN > TTYD_TOKEN（code 里 `TERM_TOKEN || TTYD_TOKEN`） |
| TTYD_TOKEN 兜底 | 无 TERM_TOKEN 时 TTYD_TOKEN 生效 |
| 导出完整性 | 13 个 key 全部导出 |
| 端口类型转换 | 字符串 "12345" → 数字 12345 |

**怎么测试：** 用子进程加载 config.js，每次传入不同的 `env`，验证输出 JSON。

**为什么用子进程：** config.js 在 `require()` 时读取 `process.env`，Node.js 的 require 缓存导致同一进程内无法重载不同 env。

---

### 2. gateway/router.js — URL 路由

**测试什么：**

| 测试项 | 验证内容 |
|--------|----------|
| `/files/` → filebrowser | port=8081, host=127.0.0.1 |
| `/vscode` → 重定向 | → `/vscode/` |
| `/vscode/*` → code-server | port=8082, prefix=/vscode |
| VSDA stub | vsda_bg.wasm → vsdaStub, vsda.js → vsdaJsStub |
| `/proxy/PORT/` | 路由到指定端口 |
| SSRF 防护 | 拒绝特权端口(<1024)、自身端口(7681)、未注册端口 |
| `/svc/NAME/` | 服务发现，重定向，404 |
| `isServiceWorkerUrl` | service_worker.js / sw.js 识别 |

**怎么测试：** 子进程中 Mock config 和 cc-status，调用 `route()` 函数，验证返回的 target 对象。

---

### 3. gateway/static.js — 静态文件服务

**测试什么：**

| 测试项 | 验证内容 |
|--------|----------|
| JS/CSS/HTML 文件 | 200 状态码，正确内容 |
| gzip 压缩 | Accept-Encoding: gzip → Content-Encoding: gzip |
| 缺失文件 | 404 状态码 |
| 非 static URL | 返回 false，不处理 |
| SW 存根 | install + fetch 处理器，Service-Worker-Allowed 头 |
| VSDA WASM 存根 | 魔数 `\0asm` (0x00 0x61 0x73 0x6d) |
| VSDA JS 存根 | `define()` 函数 |
| 服务未找到 | 404 + 已注册服务列表 |

**怎么测试：** 创建临时 fixture 目录，Mock config 指向它，构造模拟的 req/res 对象，调用 serveStatic 等函数。

---

### 4. gateway/cc-status.js — 状态 & Cron

**测试什么：**

| 测试项 | 验证内容 |
|--------|----------|
| `cronNext('* * * * *')` | 每分钟，返回 `< 1m` 或短时间 |
| `cronNext('0 * * * *')` | 每小时，返回时间字符串 |
| `cronNext('0 0 * * *')` | 每天午夜，返回天数+小时 |
| `cronNext('*/5 * * * *')` | 每 5 分钟 |
| `cronNext('0 9 * * 1-5')` | 工作日 |
| 无效输入 | 空字符串 → `""`，格式错误 → `""`，字段不足 → `""` |
| 不可能日期 | `0 0 31 2 *`（2月31日）→ `""` |
| loadCcStatus | 返回 { skills[], hooks{}, plugins[], tasks[], agents[] } |
| loadSvcRegistry | 返回 {} 对象 |

**怎么测试：** 子进程 Mock config，直接调用 cronNext 和状态加载函数。

---

### 5. gateway/inject.js — HTML 注入

**测试什么：**

| 测试项 | 验证内容 |
|--------|----------|
| 基本注入 | body 变长，包含 `<script>` |
| CSP 哈希 | `sha256-` 前缀 |
| Workbench 模式 | 注入正常 |
| HTTPS 模式 | 移除 serviceWorker 配置，替换为 null |
| 无 head 标签 | 降级注入，仍成功 |
| nonce 保留 | `nonce="abc123"` 出现在注入的 script 标签中 |

**怎么测试：** 子进程加载 inject.js，传入不同 HTML 和选项，验证返回的 body 和 cspHashesStr。

---

### 6. gateway/pty.js — PTY 管理器

**测试什么：**

> **注意**：node-pty 是 C++ 原生模块，在开发机（无 Docker）上不可用。
> 测试策略：**双层设计** — 有原生模块时跑完整测试，没有时降级为源码结构验证。

**有 node-pty 时（Docker 内）：**

| 测试项 | 验证内容 |
|--------|----------|
| 导出方法 | spawn/kill/restart/write/resize/addClient/removeClient |
| encodeCtrl 无负载 | 2 字节: [0x00][0x01] |
| encodeCtrl 有负载 | [0x00][type][JSON payload]，payload 正确 |
| 初始状态 | clients=0, cols=200, rows=50 |
| addClient/removeClient | size 0→1→0 |
| resize | cols/rows 更新 |
| 无 PTY 时安全 | write/kill 不抛异常 |
| 空缓冲区 | buffer.length=0, replay=[0x01] |

**无 node-pty 时（开发机降级）：**

验证源码中包含所有关键结构（class、常量、方法、缓冲区管理、UTF-8 安全处理等 25 项）。

---

### 7. gateway/index.js — 集成测试

**测试什么：**

> 同样依赖 node-pty。降级策略：源码结构验证。

**有 node-pty 时（Docker 内）：**

| 测试项 | 验证内容 |
|--------|----------|
| 启动 | 8 秒内成功监听 |
| `GET /` | 200 + OneCode + xterm |
| `GET /api/cc-status` | 200 + 有效 JSON |
| `POST /api/restart-terminal` | 200 + `{ok:true}` |
| 未知路由 | 404 |

**无 node-pty 时（开发机降级）：**

验证源码中 import 了所有模块、定义了 API 端点、读取 BACKEND、支持双后端、有优雅关闭等 17 项。

---

### 8. bin/oc — CLI 测试

**config.test.sh（13 项）：**

| 测试项 | 验证内容 |
|--------|----------|
| config set api_key | 值写入 settings.json |
| config set model | 值写入 |
| config set backend=opencode | 后端切换写入 |
| config set api_base_url | URL 写入 |
| config set 多个 key | 一次设置多个值 |
| config get model | 返回正确值 + 来源标注 |
| config get api_key | 值掩码显示（****xxxx） |
| config list | 显示所有 key |
| config path | 返回配置文件路径 |
| config validate | 有效配置显示 OK |
| config reset key | 删除单个 key |
| config reset --all | 重置除 api_key 外的所有值 |

**validation.test.sh（22 项）：**

| 测试项 | 验证内容 |
|--------|----------|
| placeholder key 拒绝 | sk-test-key / sk-placeholder / sk-xxx 被拒绝 |
| 空 api_key 拒绝 | 不能设为空 |
| 无效 backend 拒绝 | backend=invalid 被拒绝 |
| 有效 backend 接受 | claude-code / opencode 通过 |
| 无效 URL 拒绝 | not-a-url 被拒绝 |
| 有效 URL 接受 | https://api.anthropic.com 通过 |
| 端口边界 | 0 和 99999 被拒绝，8080 通过 |
| docker_platform | linux/armv7 被拒绝，amd64/arm64 通过 |
| gateway_https | yes 被拒绝，true/false 通过 |
| key 别名 | API_KEY→api_key, MODEL→model, API_BASE_URL→api_base_url |
| 后端优先级 | settings.json 中的值在无 CLI flag 时生效 |

**migration.test.sh（8 项）：**

| 测试项 | 验证内容 |
|--------|----------|
| v1→v2 迁移 | $version=2, provider=anthropic |
| 自定义 URL 推断 | 非 Anthropic URL → provider=openai_compatible |
| v2 幂等性 | 已是 v2 不重新迁移 |
| 空配置 | 不崩溃 |
| 损坏配置 | 不崩溃 |

**provider.test.sh（6 项）：**

| 测试项 | 验证内容 |
|--------|----------|
| Anthropic 默认 URL | api.anthropic.com |
| Anthropic 默认 model | claude-sonnet-4-6 |
| backend 默认 | claude-code |
| openai_compatible 默认 URL | 无（not set） |
| openai_compatible 默认 model | gpt-4o |

**entrypoint.test.sh（15 项）：**

| 测试项 | 验证内容 |
|--------|----------|
| BACKEND 默认值 | claude-code |
| BACKEND=opencode | 正确设置 |
| case claude-code | 匹配 |
| case claude 别名 | 匹配到 claude-code |
| case opencode | 匹配 |
| 未知 backend | 回退到 claude-code |
| CLAUDE_CODE_VERSION | 默认 2.1.177 |
| NPM_REGISTRY | 默认 npmmirror |
| API_BASE_URL → ANTHROPIC_BASE_URL | 映射正确 |
| API_KEY → ANTHROPIC_API_KEY | 映射正确 |
| MODEL → ANTHROPIC_MODEL | 映射正确 |
| DISABLE_AUTOUPDATER | 设为 1 |
| 语法检查 | bash -n 通过 |
| opencode CLI 模式 | 检测到 |
| claude CLI 模式 | 检测到 |

### 9. bin/install.sh — 一键安装脚本

**测试什么：**

| 测试项 | 验证内容 |
|--------|----------|
| 语法检查 | `bash -n` 通过 |
| 可执行权限 | 文件有 +x 权限 |
| `--help` | 显示 Usage / --api-key / --provider / --skip-docker |
| VERSION 一致性 | install.sh 的 VERSION 与 oc CLI 的 OC_VERSION 相同 |
| IMAGE_REPO 一致性 | install.sh 与 oc CLI 的 IMAGE_REPO 相同 |
| REPO_OWNER 一致性 | install.sh 与 oc CLI 的 REPO_OWNER 相同 |
| REPO_NAME 一致性 | install.sh 与 oc CLI 的 REPO_NAME 相同 |
| Provider 默认值一致 | Anthropic URL / Model、OpenAI Model 与 oc CLI 匹配 |
| 8 步完整性 | 检测环境 / 安装 jq / 安装 Docker / 启动 Docker / 登录注册表 / 拉取镜像 / 安装 oc / 配置 |
| v1→v2 迁移 | 脚本包含迁移逻辑 |
| backend 字段 | 配置写入包含 backend |
| Apple Silicon | DOCKER_DEFAULT_PLATFORM + Rosetta 处理 |
| 交互向导 | "Welcome to OneCode" 存在 |
| 验证步骤 | "Verifying installation" 存在 |

**怎么测试：** 纯静态分析 — 语法检查、grep 关键字、版本号/常量交叉比对。不实际执行安装（避免副作用）。

**为什么这样测试：** install.sh 是安装脚本，有副作用（安装 Docker、拉取镜像、写配置），不能在测试中实际运行。静态分析确保脚本结构完整、与 oc CLI 的常量保持同步。

---

## 如何运行

### 本地开发机

```bash
# 完整测试套件（约 30 秒）
npm test

# 指定模块
npm run test:gateway      # 只跑 Node.js gateway 测试
npm run test:cli          # 只跑 Bash CLI 测试

# 按关键字过滤
node tests/run.js config   # 匹配文件名含 "config" 的
node tests/run.js router   # 匹配文件名含 "router" 的
```

### Docker 容器内（完整集成测试）

```bash
# 构建并进入容器
docker build --platform linux/amd64 -t onecode agent-runtime/
docker run --rm -it -v $(pwd):/workspace onecode bash

# 在容器内运行测试（node-pty 可用，所有测试完整执行）
cd /workspace && npm test
```

### CI 环境参考

```yaml
# GitHub Actions 示例
- name: Run Tests
  run: npm test
  # 在 Docker 中运行可获得完整覆盖率（包括 pty 和 index 集成测试）
```

---

## 如何编写新测试

### Node.js 测试（Gateway 模块）

在 `tests/gateway/` 下创建 `your-module.test.js`：

```javascript
'use strict';

/**
 * Tests for gateway/your-module.js
 */
module.exports = function (t) {
  const path = require('path');
  const { runAndParse } = require('./helpers');

  const modulePath = path.resolve(__dirname, '..', '..', 'agent-runtime', 'gateway', 'your-module.js');

  // 如果模块依赖 config/cc-status，需要 Mock
  function runTest(testCode) {
    return runAndParse(`
      const Module = require('module');
      const origReq = Module.prototype.require;
      Module.prototype.require = function(id) {
        if (id === './config') return { /* mock config */ };
        if (id === './cc-status') return { loadSvcRegistry: () => ({}) };
        return origReq.apply(this, arguments);
      };
      const mod = require(${JSON.stringify(modulePath)});
      Module.prototype.require = origReq;
      ${testCode}
    `);
  }

  t.section('功能描述');
  const result = runTest('console.log(JSON.stringify(mod.someFunction("input")));');
  t.ok(result, 'someFunction returns a value');
  t.equal(result, 'expected', 'someFunction returns expected output');
};
```

### Bash 测试（CLI 命令）

在 `tests/cli/` 下创建 `your-test.test.sh`：

```bash
#!/usr/bin/env bash
# Tests for oc CLI — 功能描述
# 输出格式: PASS <描述> 或 FAIL <描述>
set -euo pipefail

# 设置隔离环境
TEST_HOME="/tmp/onecode-test-yourtest-$$"
OC_HOME="$TEST_HOME/.onecode"
OC_CONFIG="$OC_HOME/settings.json"
mkdir -p "$OC_HOME"

OC_SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/agent-runtime/bin/oc"

# 用 env -i 隔离环境变量
run_oc() {
    env -i HOME="$TEST_HOME" OC_HOME="$OC_HOME" PATH="$PATH" \
        USER="$(whoami)" TERM="${TERM:-xterm}" \
        bash "$OC_SCRIPT" "$@" 2>&1 || true
}

# 测试用例
OUTPUT=$(run_oc some-command 2>&1)
if echo "$OUTPUT" | grep -q "expected"; then
    echo "PASS 功能描述"
else
    echo "FAIL 功能描述 — got: $OUTPUT"
fi

# 清理
rm -rf "$TEST_HOME"
```

### 测试命名规范

| 类型 | 命名 | 示例 |
|------|------|------|
| Node.js 单元测试 | `模块名.test.js` | `router.test.js` |
| Bash CLI 测试 | `功能名.test.sh` | `validation.test.sh` |
| 测试 fixture | `tests/fixtures/` 下 | `tests/fixtures/static/` |

---

## 设计决策与约束

### 1. 为什么不用 Jest / Mocha / Vitest？

| 考量 | 决策 |
|------|------|
| 零依赖 | 项目 package.json 无 devDependencies，测试框架也应如此 |
| 子进程隔离 | config.js 在 require 时读 env，需要进程级隔离，Jest 的 jest.mock 无法满足 |
| 轻量 | 251 个断言，30 秒跑完，不需要重型框架 |
| Bash 兼容 | 需要统一运行 Node.js 和 Bash 测试 |

### 2. 为什么用子进程而不是 jest.mock？

```javascript
// ❌ Jest 方式：同一进程，require 缓存导致 env 无法重置
jest.mock('./config');
const config = require('./config'); // 永远返回同一个值

// ✅ 我们的方式：每次子进程都是干净的
const result = runAndParse(`const c = require('config.js'); console.log(JSON.stringify(c));`, {
  GATEWAY_PORT: '9999', // 这次用不同的 env
});
```

### 3. 为什么用临时文件而不是 `node -e`？

```bash
# ❌ node -e 会解释 \n 为换行符，多行 JSON 代码崩溃
node -e "const x = {\n  a: 1\n};"

# ✅ 写入临时文件再执行
echo "const x = { a: 1 };" > /tmp/test.js && node /tmp/test.js
```

### 4. 为什么 Bash 测试用 `env -i`？

```bash
# ❌ 直接运行：宿主机的 MODEL / API_KEY 会泄漏进测试
HOME="$TEST_HOME" bash "$OC_SCRIPT" config get model
# → "claude-sonnet-4-6  (from: env var MODEL)"  ← 宿主机的 MODEL

# ✅ env -i：干净环境，只传入必要变量
env -i HOME="$TEST_HOME" PATH="$PATH" bash "$OC_SCRIPT" config get model
# → "claude-sonnet-4-6  (from: settings.json)"  ← 来自文件，正确
```

### 5. node-pty 不可用时的降级策略

```
开发机（无 node-pty）     Docker 容器（有 node-pty）
┌──────────────────┐     ┌──────────────────┐
│ pty.test.js      │     │ pty.test.js      │
│ → 源码结构验证    │     │ → 完整单元测试    │
│ index.test.js    │     │ index.test.js    │
│ → 源码结构验证    │     │ → HTTP 集成测试   │
│ 其他 5 个文件     │     │ 其他 5 个文件     │
│ → 完整测试 ✅    │     │ → 完整测试 ✅    │
└──────────────────┘     └──────────────────┘
     247 passed               251 passed
      4 skipped                 0 skipped
```

---

## Docker 内集成测试

以下测试只在 Docker 容器内完整运行（node-pty 可用时）：

### pty.test.js 完整模式

```
▸ encodeCtrl 二进制协议
  ✓ 无负载帧: [0x00][0x01] (2 bytes)
  ✓ 有负载帧: [0x00][type][JSON] (payload 正确)

▸ PtyManager 状态管理
  ✓ 初始: clients=0, cols=200, rows=50
  ✓ addClient/removeClient: 0→1→0
  ✓ resize(120, 40): 更新成功
  ✓ 无 PTY 时 write/kill 不崩溃

▸ 缓冲区
  ✓ 空缓冲区: length=0
  ✓ 空回放: [0x01] (1 byte, FRAME_PTY)
```

### index.test.js 完整模式

```
▸ Gateway 启动
  ✓ 8 秒内成功监听

▸ HTTP 端点
  ✓ GET / → 200 + OneCode + xterm
  ✓ GET /api/cc-status → 200 + 有效 JSON
  ✓ POST /api/restart-terminal → 200 + {ok:true}
  ✓ GET /unknown → 404
```

### 在 Docker 中运行完整测试

```bash
# 1. 构建镜像
docker build --platform linux/amd64 -t onecode agent-runtime/

# 2. 挂载源码运行测试
docker run --rm -v $(pwd):/workspace onecode bash -c "cd /workspace && npm test"

# 3. 预期输出: 251 passed, 0 failed, 0 skipped
```

---

## 测试覆盖率总结

```
                    已测试    未测试（需 Docker）    总计
Gateway 模块          7/8        1 (proxy.js)        8
CLI 命令             4/7        3 (ssh/shell/stop)   7
Entrypoint          15/15       0                   15
安装脚本             26/26       0                   26
配置迁移              8/8        0                    8
─────────────────────────────────────────────────────
源码行覆盖（估算）    ~68%       ~32%               100%
功能点覆盖           ~88%       ~12%               100%
关键路径覆盖         ~96%       ~4%                100%
```

### 未覆盖项（需要 Docker / 实际 API Key）

| 模块 | 原因 | 优先级 |
|------|------|--------|
| proxy.js 完整流程 | 需要 filebrowser / code-server 运行 | P1 |
| oc ssh | 需要运行中的容器 + socat | P2 |
| oc shell | 需要运行中的容器 | P2 |
| oc stop | 需要运行中的容器 | P2 |
| oc update | 需要 GitHub API / Docker pull | P3 |
| install.sh 实际执行 | 有副作用（安装软件、写文件），只能静态测试 | P3 |
| 实际 Claude Code 对话 | 需要 API Key + 真实 PTY | P3 |
| OpenCode 后端对话 | 需要 API Key + OpenCode 运行 | P3 |
