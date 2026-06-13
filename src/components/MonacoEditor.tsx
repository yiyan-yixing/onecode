"use client";

import React, { useRef, useEffect } from "react";
import Editor, { OnMount } from "@monaco-editor/react";

interface MonacoEditorProps {
  value: string;
  path: string;
  onChange: (value: string) => void;
}

export function MonacoEditor({ value, path, onChange }: MonacoEditorProps) {
  const editorRef = useRef<any>(null);

  const handleMount: OnMount = (editor, monaco) => {
    editorRef.current = editor;

    // 设置主题
    monaco.editor.defineTheme("onecode-dark", {
      base: "vs-dark",
      inherit: true,
      rules: [],
      colors: {
        "editor.background": "#0a0a0a",
        "editor.lineHighlightBackground": "#1a1a2e",
      },
    });
    monaco.editor.setTheme("onecode-dark");
  };

  // 根据文件扩展名推断语言
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
      bash: "shell",
      sql: "sql",
    };
    return map[ext || ""] || "plaintext";
  };

  return (
    <Editor
      height="100%"
      language={getLanguage(path)}
      value={value}
      onChange={(v) => onChange(v || "")}
      onMount={handleMount}
      path={path}
      options={{
        fontSize: 14,
        fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
        minimap: { enabled: false },
        scrollBeyondLastLine: false,
        padding: { top: 16 },
        lineNumbers: "on",
        renderLineHighlight: "all",
        bracketPairColorization: { enabled: true },
        formatOnPaste: true,
        tabSize: 2,
      }}
    />
  );
}
