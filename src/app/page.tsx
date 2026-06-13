"use client";

import React, { useState, useCallback } from "react";
import { AgentPanel } from "@/components/AgentPanel";
import { Editor, FileTab } from "@/components/Editor";
import { Chat, ChatMessage } from "@/components/Chat";
import { StatusBar } from "@/components/StatusBar";
import { parseMention } from "@/lib/parse-mention";

// ─── 主工作区 ───

export default function Home() {
  // Agent 状态
  const [activeAgent, setActiveAgent] = useState<string | null>(null);

  // Chat 状态
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [isStreaming, setIsStreaming] = useState(false);

  // Editor 状态
  const [fileTabs, setFileTabs] = useState<FileTab[]>([]);
  const [activeTab, setActiveTab] = useState<string | null>(null);

  // 统计
  const [tokenCount, setTokenCount] = useState(0);
  const [fileChangeCount, setFileChangeCount] = useState(0);

  // ─── 发送消息 ───
  const handleSend = useCallback(
    (content: string) => {
      // 解析 @角色名
      const parsed = parseMention(content);

      // 添加用户消息
      const userMsg: ChatMessage = {
        id: `msg-${Date.now()}`,
        role: "user",
        content,
        agentRole: parsed.roleId ?? undefined,
        timestamp: Date.now(),
      };
      setMessages((prev) => [...prev, userMsg]);

      // 设置活跃角色
      if (parsed.roleId) {
        setActiveAgent(parsed.roleId);
      }

      // 模拟 Agent 响应（MVP — 后续替换为真实 Agent SDK 调用）
      setIsStreaming(true);

      setTimeout(() => {
        // 模拟流式响应
        const agentRole = parsed.roleId || "dev";
        const agentNames: Record<string, string> = {
          ceo: "CEO",
          pm: "产品经理",
          designer: "设计师",
          architect: "架构师",
          dev: "开发者",
          devops: "DevOps",
          qa: "测试",
          ops: "运营",
          data: "数据分析师",
          fin: "财务",
        };

        // 模拟工具调用
        const toolMsg: ChatMessage = {
          id: `msg-${Date.now()}-tool`,
          role: "tool",
          content: "",
          toolName: "Read",
          toolInput: { file_path: "src/app/page.tsx" },
          timestamp: Date.now(),
        };
        setMessages((prev) => [...prev, toolMsg]);

        setTimeout(() => {
          // 模拟文件变更
          const editMsg: ChatMessage = {
            id: `msg-${Date.now()}-edit`,
            role: "tool",
            content: "",
            toolName: "Edit",
            toolInput: { file_path: "src/app/page.tsx" },
            timestamp: Date.now(),
          };
          setMessages((prev) => [...prev, editMsg]);
          setFileChangeCount((c) => c + 1);

          // 添加 diff 文件 Tab
          setFileTabs((prev) => [
            ...prev,
            {
              path: "src/app/page.tsx",
              content: '// OneCode - AI Native IDE\nexport default function Home() {\n  return <div>Hello OneCode</div>;\n}\n',
              original: "// original content",
            },
          ]);
          setActiveTab("src/app/page.tsx");

          // 最终文本响应
          setTimeout(() => {
            const responseMsg: ChatMessage = {
              id: `msg-${Date.now()}-response`,
              role: "assistant",
              content: `收到！我是${agentNames[agentRole] || "开发者"}，正在处理你的请求。\n\n已完成文件修改，请在编辑器中查看 diff。`,
              agentRole: parsed.roleId ?? undefined,
              timestamp: Date.now(),
            };
            setMessages((prev) => [...prev, responseMsg]);
            setIsStreaming(false);
            setTokenCount((t) => t + 8200);
          }, 800);
        }, 600);
      }, 400);
    },
    []
  );

  // ─── Agent 面板选择 ───
  const handleAgentSelect = useCallback((roleId: string) => {
    setActiveAgent(roleId);
  }, []);

  // ─── Editor 操作 ───
  const handleTabSelect = useCallback((path: string) => {
    setActiveTab(path);
  }, []);

  const handleTabClose = useCallback(
    (path: string) => {
      setFileTabs((prev) => prev.filter((t) => t.path !== path));
      if (activeTab === path) {
        setActiveTab(fileTabs.length > 1 ? fileTabs.find((t) => t.path !== path)?.path || null : null);
      }
    },
    [activeTab, fileTabs]
  );

  const handleFileChange = useCallback((path: string, content: string) => {
    setFileTabs((prev) =>
      prev.map((t) => (t.path === path ? { ...t, content } : t))
    );
  }, []);

  return (
    <div className="flex h-screen flex-col bg-background text-foreground">
      {/* 顶栏 */}
      <header className="flex items-center justify-between border-b px-4 py-2">
        <div className="flex items-center gap-2">
          <span className="text-lg font-bold">OneCode</span>
          <span className="text-xs text-muted-foreground">AI 原生 IDE</span>
        </div>
        <div className="flex items-center gap-3 text-xs text-muted-foreground">
          <span>v0.1.0 MVP</span>
        </div>
      </header>

      {/* 主工作区 */}
      <div className="flex flex-1 overflow-hidden">
        {/* 左侧：Agent 面板 */}
        <AgentPanel
          activeAgent={activeAgent}
          onAgentSelect={handleAgentSelect}
        />

        {/* 中间：编辑器 */}
        <div className="flex flex-1 flex-col">
          <Editor
            tabs={fileTabs}
            activeTab={activeTab}
            onTabSelect={handleTabSelect}
            onTabClose={handleTabClose}
            onFileChange={handleFileChange}
          />
        </div>

        {/* 右侧：Chat（可拖拽调整，MVP 固定宽度） */}
        <div className="flex w-[420px] flex-col border-l">
          <Chat
            messages={messages}
            onSend={handleSend}
            activeAgent={activeAgent}
            isStreaming={isStreaming}
          />
        </div>
      </div>

      {/* 底部状态栏 */}
      <StatusBar
        activeAgent={activeAgent}
        tokenCount={tokenCount}
        fileChangeCount={fileChangeCount}
        sprintName="Sprint-0"
      />
    </div>
  );
}
