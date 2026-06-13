"use client";

import React, { useState, useRef, useEffect, useCallback } from "react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Badge } from "@/components/ui/badge";
import { AGENT_ROLES, AgentRole } from "@/lib/agent-roles";
import { parseMention, getMentionSuggestions } from "@/lib/parse-mention";

// ─── 类型 ───

export interface ChatMessage {
  id: string;
  role: "user" | "assistant" | "system" | "tool";
  content: string;
  agentRole?: string;
  toolName?: string;
  toolInput?: Record<string, unknown>;
  timestamp: number;
  isStreaming?: boolean;
}

interface ChatProps {
  messages: ChatMessage[];
  onSend: (message: string) => void;
  activeAgent: string | null;
  isStreaming: boolean;
}

// ─── 工具调用可视化 ───

function ToolCallLine({
  toolName,
  toolInput,
}: {
  toolName: string;
  toolInput?: Record<string, unknown>;
}) {
  const iconMap: Record<string, string> = {
    Read: "📖",
    Write: "✏️",
    Edit: "✏️",
    Bash: "▶️",
    Glob: "🔍",
    Grep: "🔍",
    WebSearch: "🌐",
    WebFetch: "🌐",
  };

  const icon = iconMap[toolName] || "🔧";
  const filePath =
    (toolInput?.file_path as string) || (toolInput?.path as string) || "";
  const command = (toolInput?.command as string) || "";

  return (
    <div className="flex items-center gap-2 py-1 text-sm text-muted-foreground">
      <span>{icon}</span>
      <Badge variant="outline" className="font-mono text-xs">
        {toolName}
      </Badge>
      {filePath && (
        <span className="truncate font-mono text-xs">{filePath}</span>
      )}
      {command && (
        <span className="truncate font-mono text-xs">
          {command.slice(0, 80)}
        </span>
      )}
    </div>
  );
}

// ─── 消息气泡 ───

function MessageBubble({ message }: { message: ChatMessage }) {
  if (message.role === "tool") {
    return <ToolCallLine toolName={message.toolName || "Tool"} toolInput={message.toolInput} />;
  }

  const isUser = message.role === "user";
  const agentRole = message.agentRole
    ? AGENT_ROLES.find((r) => r.id === message.agentRole)
    : null;

  return (
    <div
      className={`flex gap-3 ${isUser ? "flex-row-reverse" : ""}`}
    >
      {/* 头像 */}
      <div
        className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-sm ${
          isUser
            ? "bg-primary text-primary-foreground"
            : agentRole
              ? "text-lg"
              : "bg-muted"
        }`}
        style={agentRole ? { backgroundColor: agentRole.color + "20" } : {}}
      >
        {isUser ? "👤" : agentRole?.icon || "🤖"}
      </div>

      {/* 内容 */}
      <div className={`max-w-[80%] space-y-1 ${isUser ? "text-right" : ""}`}>
        {agentRole && (
          <span className="text-xs font-medium" style={{ color: agentRole.color }}>
            @{agentRole.nameZh}
          </span>
        )}
        <div
          className={`rounded-xl px-4 py-2.5 text-sm whitespace-pre-wrap ${
            isUser
              ? "bg-primary text-primary-foreground"
              : "bg-muted text-foreground"
          }`}
        >
          {message.content}
          {message.isStreaming && (
            <span className="ml-1 inline-block h-4 w-1 animate-pulse bg-foreground/50" />
          )}
        </div>
      </div>
    </div>
  );
}

// ─── @角色名 补全 ───

function MentionPopup({
  suggestions,
  onSelect,
  selectedIndex,
}: {
  suggestions: AgentRole[];
  onSelect: (role: AgentRole) => void;
  selectedIndex: number;
}) {
  if (suggestions.length === 0) return null;

  return (
    <div className="absolute bottom-full left-0 mb-1 w-64 rounded-lg border bg-popover p-1 shadow-lg">
      {suggestions.map((role, i) => (
        <button
          key={role.id}
          className={`flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm ${
            i === selectedIndex ? "bg-accent" : "hover:bg-accent/50"
          }`}
          onClick={() => onSelect(role)}
        >
          <span className="text-base">{role.icon}</span>
          <div className="flex-1 text-left">
            <div className="font-medium">{role.nameZh}</div>
            <div className="text-xs text-muted-foreground truncate">
              {role.mission}
            </div>
          </div>
        </button>
      ))}
    </div>
  );
}

// ─── Chat 主组件 ───

export function Chat({ messages, onSend, activeAgent, isStreaming }: ChatProps) {
  const [input, setInput] = useState("");
  const [mentionMode, setMentionMode] = useState(false);
  const [mentionPrefix, setMentionPrefix] = useState("");
  const [mentionIndex, setMentionIndex] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  const mentionSuggestions = mentionMode
    ? getMentionSuggestions(mentionPrefix)
    : [];

  // 自动滚动到底部
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages]);

  // 处理输入变化，检测 @
  const handleInputChange = (value: string) => {
    setInput(value);

    // 检测是否在输入 @角色名
    const cursorPos = inputRef.current?.selectionStart ?? value.length;
    const textBefore = value.slice(0, cursorPos);
    const atMatch = textBefore.match(/@(\S*)$/);

    if (atMatch) {
      setMentionMode(true);
      setMentionPrefix(atMatch[1]);
      setMentionIndex(0);
    } else {
      setMentionMode(false);
    }
  };

  // 选择角色
  const handleMentionSelect = (role: AgentRole) => {
    const cursorPos = inputRef.current?.selectionStart ?? input.length;
    const textBefore = input.slice(0, cursorPos);
    const textAfter = input.slice(cursorPos);
    const newInput = textBefore.replace(/@\S*$/, `@${role.id} `) + textAfter;
    setInput(newInput);
    setMentionMode(false);
    inputRef.current?.focus();
  };

  // 键盘事件
  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (mentionMode && mentionSuggestions.length > 0) {
      if (e.key === "ArrowDown") {
        e.preventDefault();
        setMentionIndex((i) => Math.min(i + 1, mentionSuggestions.length - 1));
        return;
      }
      if (e.key === "ArrowUp") {
        e.preventDefault();
        setMentionIndex((i) => Math.max(i - 1, 0));
        return;
      }
      if (e.key === "Enter" || e.key === "Tab") {
        e.preventDefault();
        handleMentionSelect(mentionSuggestions[mentionIndex]);
        return;
      }
      if (e.key === "Escape") {
        setMentionMode(false);
        return;
      }
    }

    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const handleSend = useCallback(() => {
    const trimmed = input.trim();
    if (!trimmed || isStreaming) return;
    onSend(trimmed);
    setInput("");
    setMentionMode(false);
  }, [input, isStreaming, onSend]);

  // 如果有活跃角色，预填 @角色名
  useEffect(() => {
    if (activeAgent && !input) {
      setInput(`@${activeAgent} `);
      inputRef.current?.focus();
    }
  }, [activeAgent]);

  return (
    <div className="flex h-full flex-col">
      {/* 消息列表 */}
      <ScrollArea className="flex-1 px-4">
        <div ref={scrollRef} className="space-y-4 py-4">
          {messages.length === 0 && (
            <div className="flex h-full items-center justify-center text-muted-foreground">
              <div className="text-center">
                <p className="text-lg font-medium">OneCode</p>
                <p className="text-sm">输入 @角色名 或直接开始对话</p>
              </div>
            </div>
          )}
          {messages.map((msg) => (
            <MessageBubble key={msg.id} message={msg} />
          ))}
        </div>
      </ScrollArea>

      {/* 输入区 */}
      <div className="border-t p-4">
        <div className="relative">
          {/* @补全弹窗 */}
          {mentionMode && (
            <MentionPopup
              suggestions={mentionSuggestions}
              onSelect={handleMentionSelect}
              selectedIndex={mentionIndex}
            />
          )}

          <div className="flex gap-2">
            <Input
              ref={inputRef}
              value={input}
              onChange={(e) => handleInputChange(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="输入消息，@角色名 调用 Agent..."
              disabled={isStreaming}
              className="flex-1"
            />
            <Button onClick={handleSend} disabled={!input.trim() || isStreaming}>
              发送
            </Button>
          </div>

          {isStreaming && (
            <p className="mt-2 text-xs text-muted-foreground animate-pulse">
              Agent 正在思考...
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
