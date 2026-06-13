// OneCode — Claude Code Agent SDK Bridge
// 封装 Agent SDK 流式输出，桥接到 WebSocket
//
// MVP: 使用模拟数据，后续替换为真实 Agent SDK 调用
// 真实 SDK 安装: npm install @anthropic-ai/claude-agent-sdk

// import { query } from "@anthropic-ai/claude-agent-sdk";
import { getAgentPrompt } from "./agent-roles";
import { parseMention } from "./parse-mention";

export interface StreamEvent {
  type:
    | "text"
    | "tool_start"
    | "tool_result"
    | "file_change"
    | "error"
    | "done"
    | "session_init";
  data: unknown;
  timestamp: number;
}

export interface ChatOptions {
  message: string;
  sessionId?: string;
  cwd?: string;
  permissionMode?: "acceptEdits" | "plan" | "auto";
}

/**
 * 发送消息到 Claude Code 并返回流式事件
 *
 * MVP 版本：使用 Agent SDK 的 query() 流式接口
 * 每个事件通过 yield 返回，前端通过 SSE/WebSocket 接收
 */
export async function* streamChat(
  options: ChatOptions
): AsyncGenerator<StreamEvent> {
  const { message, sessionId, cwd, permissionMode = "acceptEdits" } = options;

  // 解析 @角色名
  const parsed = parseMention(message);
  const prompt = parsed.roleId
    ? getAgentPrompt(parsed.roleId, parsed.message || "你好")
    : message;

  try {
    // MVP: 使用模拟流式输出
    // 真实版本将使用 Agent SDK:
    // for await (const message of query({ prompt, options: { ... } })) { ... }

    // 模拟 session 初始化
    yield {
      type: "session_init",
      data: { sessionId: `session-${Date.now()}`, model: "claude-sonnet-4-6" },
      timestamp: Date.now(),
    };

    // 模拟工具调用
    yield {
      type: "tool_start",
      data: { tool: "Read", input: { file_path: "src/app/page.tsx" } },
      timestamp: Date.now(),
    };

    yield {
      type: "tool_result",
      data: { tool: "Read", result: "file content..." },
      timestamp: Date.now(),
    };

    // 模拟文本输出
    yield {
      type: "text",
      data: { text: `收到！我正在处理你的请求...` },
      timestamp: Date.now(),
    };

    // 模拟文件变更
    if (parsed.roleId === "dev" || parsed.roleId === "designer" || !parsed.roleId) {
      yield {
        type: "tool_start",
        data: { tool: "Edit", input: { file_path: "src/app/page.tsx" } },
        timestamp: Date.now(),
      };

      yield {
        type: "file_change",
        data: { filePath: "src/app/page.tsx", tool: "Edit" },
        timestamp: Date.now(),
      };

      yield {
        type: "tool_result",
        data: { tool: "Edit", result: "File updated" },
        timestamp: Date.now(),
      };
    }

    // 完成
    yield {
      type: "done",
      data: { result: "完成", cost: { input: 2000, output: 1500 }, duration: 3000 },
      timestamp: Date.now(),
    };
  } catch (error: any) {
    yield {
      type: "error",
      data: { message: error.message || "Unknown error" },
      timestamp: Date.now(),
    };
  }
}
