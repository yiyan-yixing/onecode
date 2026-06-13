"use client";

import React from "react";
import { Badge } from "@/components/ui/badge";
import { AGENT_ROLES, AgentRole } from "@/lib/agent-roles";

interface AgentPanelProps {
  activeAgent: string | null;
  onAgentSelect: (roleId: string) => void;
}

export function AgentPanel({ activeAgent, onAgentSelect }: AgentPanelProps) {
  return (
    <div className="flex h-full w-56 flex-col border-r bg-muted/20">
      {/* 标题 */}
      <div className="border-b px-4 py-3">
        <h2 className="text-sm font-semibold">Agent 角色</h2>
        <p className="text-xs text-muted-foreground mt-0.5">
          点击调用对应角色
        </p>
      </div>

      {/* 角色列表 */}
      <div className="flex-1 overflow-y-auto py-2">
        {AGENT_ROLES.map((role) => {
          const isActive = activeAgent === role.id;
          return (
            <button
              key={role.id}
              className={`flex w-full items-center gap-3 px-4 py-2.5 text-left transition-colors ${
                isActive
                  ? "bg-accent"
                  : "hover:bg-accent/50"
              }`}
              onClick={() => onAgentSelect(role.id)}
            >
              {/* 图标 */}
              <span className="text-lg">{role.icon}</span>

              {/* 信息 */}
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span
                    className="text-sm font-medium"
                    style={{ color: isActive ? role.color : undefined }}
                  >
                    {role.nameZh}
                  </span>
                  <Badge
                    variant="outline"
                    className="text-[10px] px-1 py-0"
                    style={{ borderColor: role.color, color: role.color }}
                  >
                    {role.timePercent}%
                  </Badge>
                </div>
                <p className="text-xs text-muted-foreground truncate mt-0.5">
                  {role.mission}
                </p>
              </div>

              {/* 活跃指示灯 */}
              {isActive && (
                <span
                  className="h-2 w-2 rounded-full animate-pulse"
                  style={{ backgroundColor: role.color }}
                />
              )}
            </button>
          );
        })}
      </div>

      {/* 底部：Sprint 状态 */}
      <div className="border-t px-4 py-3">
        <div className="text-xs text-muted-foreground">
          <p className="font-medium">当前迭代</p>
          <p>Sprint-0 · 体系搭建中</p>
        </div>
      </div>
    </div>
  );
}
