// OneCode — @角色名 语法解析

import { AGENT_ROLES, AgentRole } from "./agent-roles";

export interface ParseResult {
  /** 检测到的角色 ID（如 "dev"），无则为 null */
  roleId: string | null;
  /** 去掉 @角色名 前缀后的纯消息内容 */
  message: string;
  /** 匹配到的角色对象 */
  role: AgentRole | null;
}

/**
 * 解析用户输入中的 @角色名 前缀
 * 支持格式: "@dev 实现登录" / "@pm" / "@designer 3天出Demo"
 * 也支持中文: "@产品经理 排优先级"
 */
export function parseMention(input: string): ParseResult {
  const trimmed = input.trim();

  // 匹配 @英文角色名 或 @中文名
  const mentionRegex = /^@(\S+)\s*([\s\S]*)/;
  const match = trimmed.match(mentionRegex);

  if (!match) {
    return { roleId: null, message: trimmed, role: null };
  }

  const mention = match[1].toLowerCase();
  const restMessage = match[2].trim();

  // 先匹配英文 ID
  const byId = AGENT_ROLES.find((r) => r.id === mention);
  if (byId) {
    return { roleId: byId.id, message: restMessage, role: byId };
  }

  // 再匹配英文名
  const byName = AGENT_ROLES.find((r) => r.name.toLowerCase() === mention);
  if (byName) {
    return { roleId: byName.id, message: restMessage, role: byName };
  }

  // 最后匹配中文名
  const byNameZh = AGENT_ROLES.find((r) => r.nameZh === mention);
  if (byNameZh) {
    return { roleId: byNameZh.id, message: restMessage, role: byNameZh };
  }

  // 没匹配到角色，@xxx 作为普通文本
  return { roleId: null, message: trimmed, role: null };
}

/**
 * 获取所有可补全的角色选项
 */
export function getMentionSuggestions(prefix: string): AgentRole[] {
  if (!prefix) return AGENT_ROLES;
  const lower = prefix.toLowerCase();
  return AGENT_ROLES.filter(
    (r) =>
      r.id.startsWith(lower) ||
      r.name.toLowerCase().startsWith(lower) ||
      r.nameZh.startsWith(prefix)
  );
}
