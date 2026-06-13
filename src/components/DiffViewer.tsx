"use client";

import React from "react";
import { DiffEditor } from "@monaco-editor/react";

interface DiffViewerProps {
  original: string;
  modified: string;
  path: string;
}

export function DiffViewer({ original, modified, path }: DiffViewerProps) {
  const getLanguage = (filePath: string): string => {
    const ext = filePath.split(".").pop()?.toLowerCase();
    const map: Record<string, string> = {
      ts: "typescript",
      tsx: "typescript",
      js: "javascript",
      jsx: "javascript",
      py: "python",
      rs: "rust",
      go: "go",
      md: "markdown",
      json: "json",
      css: "css",
      html: "html",
      yaml: "yaml",
      yml: "yaml",
      sh: "shell",
    };
    return map[ext || ""] || "plaintext";
  };

  return (
    <div className="h-full">
      <div className="flex items-center justify-between border-b bg-muted/30 px-4 py-1">
        <span className="text-xs font-mono text-muted-foreground">
          📝 {path}
        </span>
        <span className="text-xs text-blue-500">Diff Preview</span>
      </div>
      <DiffEditor
        height="calc(100% - 36px)"
        language={getLanguage(path)}
        original={original}
        modified={modified}
        options={{
          readOnly: true,
          fontSize: 14,
          fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
          minimap: { enabled: false },
          scrollBeyondLastLine: false,
          renderSideBySide: true,
        }}
        theme="vs-dark"
      />
    </div>
  );
}
