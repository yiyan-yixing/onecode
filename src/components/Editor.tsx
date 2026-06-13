"use client";

import React, { useState, useCallback } from "react";
import { MonacoEditor } from "./MonacoEditor";
import { DiffViewer } from "./DiffViewer";

export interface FileTab {
  path: string;
  content: string;
  original?: string; // 有值时显示 diff
}

interface EditorProps {
  tabs: FileTab[];
  activeTab: string | null;
  onTabSelect: (path: string) => void;
  onTabClose: (path: string) => void;
  onFileChange: (path: string, content: string) => void;
}

export function Editor({
  tabs,
  activeTab,
  onTabSelect,
  onTabClose,
  onFileChange,
}: EditorProps) {
  const activeFile = tabs.find((t) => t.path === activeTab);
  const isDiff = activeFile?.original !== undefined;

  return (
    <div className="flex h-full flex-col">
      {/* Tab 栏 */}
      <div className="flex items-center border-b bg-muted/30 px-1">
        {tabs.map((tab) => (
          <button
            key={tab.path}
            className={`group flex items-center gap-1.5 border-r px-3 py-1.5 text-xs font-mono ${
              tab.path === activeTab
                ? "bg-background text-foreground"
                : "text-muted-foreground hover:text-foreground"
            }`}
            onClick={() => onTabSelect(tab.path)}
          >
            {/* 修改标记 */}
            {tab.original !== undefined && (
              <span className="h-2 w-2 rounded-full bg-blue-500" />
            )}
            <span className="max-w-[120px] truncate">
              {tab.path.split("/").pop()}
            </span>
            <button
              className="ml-1 rounded p-0.5 opacity-0 group-hover:opacity-100 hover:bg-muted"
              onClick={(e) => {
                e.stopPropagation();
                onTabClose(tab.path);
              }}
            >
              ✕
            </button>
          </button>
        ))}
      </div>

      {/* 编辑器区 */}
      <div className="flex-1">
        {activeFile ? (
          isDiff ? (
            <DiffViewer
              original={activeFile.original!}
              modified={activeFile.content}
              path={activeFile.path}
            />
          ) : (
            <MonacoEditor
              value={activeFile.content}
              path={activeFile.path}
              onChange={(value) =>
                onFileChange(activeFile.path, value || "")
              }
            />
          )
        ) : (
          <div className="flex h-full items-center justify-center text-muted-foreground">
            <div className="text-center">
              <p className="text-4xl">📝</p>
              <p className="mt-2 text-sm">打开文件或让 Agent 创建文件</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
