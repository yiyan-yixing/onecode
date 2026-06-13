"use client";

import React from "react";
import { AGENT_ROLES } from "@/lib/agent-roles";

interface StatusBarProps {
  activeAgent: string | null;
  tokenCount: number;
  fileChangeCount: number;
  sprintName: string;
}

export function StatusBar({
  activeAgent,
  tokenCount,
  fileChangeCount,
  sprintName,
}: StatusBarProps) {
  const agentRole = activeAgent
    ? AGENT_ROLES.find((r) => r.id === activeAgent)
    : null;

  return (
    <div className="flex items-center justify-between border-t bg-muted/30 px-4 py-1.5 text-xs text-muted-foreground">
      <div className="flex items-center gap-4">
        <span>🔄 {sprintName}</span>
        {agentRole && (
          <span className="flex items-center gap-1.5">
            <span
              className="h-2 w-2 rounded-full animate-pulse"
              style={{ backgroundColor: agentRole.color }}
            />
            @{agentRole.nameZh} 活跃
          </span>
        )}
      </div>
      <div className="flex items-center gap-4">
        <span>tokens: {tokenCount.toLocaleString()}</span>
        {fileChangeCount > 0 && (
          <span className="text-blue-500">
            文件: {fileChangeCount} 变更
          </span>
        )}
      </div>
    </div>
  );
}
