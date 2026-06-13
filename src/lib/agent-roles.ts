// OneCode — 10 Agent 角色定义
// 从 agents/*.md frontmatter 提取的角色数据

export interface AgentRole {
  id: string;
  name: string;
  nameZh: string;
  mission: string;
  timePercent: number;
  skills: string[];
  color: string;
  icon: string;
}

export const AGENT_ROLES: AgentRole[] = [
  {
    id: "ceo",
    name: "CEO",
    nameZh: "CEO",
    mission: "战略方向、重大决策、全局监控",
    timePercent: 10,
    skills: ["ceo-weekly-review", "ceo-decision-framework", "ceo-quarterly-planning", "ceo-vision-check"],
    color: "#8B5CF6",
    icon: "👔",
  },
  {
    id: "pm",
    name: "PM",
    nameZh: "产品经理",
    mission: "做用户真正需要的产品",
    timePercent: 15,
    skills: ["pm-feature-prioritization", "pm-prd-writing", "pm-mvp-scoping", "pm-user-feedback-loop"],
    color: "#3B82F6",
    icon: "📋",
  },
  {
    id: "designer",
    name: "Designer",
    nameZh: "设计师",
    mission: "用最短时间把想法变成可感知的界面",
    timePercent: 15,
    skills: ["designer-rapid-prototype", "frontend-design"],
    color: "#EC4899",
    icon: "🎨",
  },
  {
    id: "architect",
    name: "Architect",
    nameZh: "架构师",
    mission: "做正确的技术选型，防止架构债务",
    timePercent: 5,
    skills: ["dev-architecture-decision", "architect-tech-radar"],
    color: "#F59E0B",
    icon: "🏗️",
  },
  {
    id: "dev",
    name: "Dev",
    nameZh: "开发者",
    mission: "高质量可持续地交付代码",
    timePercent: 25,
    skills: ["dev-code-review-self", "dev-debug-triage", "dev-release-checklist"],
    color: "#10B981",
    icon: "💻",
  },
  {
    id: "devops",
    name: "DevOps",
    nameZh: "DevOps",
    mission: "极致快速的开发工具链",
    timePercent: 10,
    skills: ["devops-fast-pipeline"],
    color: "#6366F1",
    icon: "🔧",
  },
  {
    id: "qa",
    name: "QA",
    nameZh: "测试",
    mission: "不让 bug 流入生产环境",
    timePercent: 5,
    skills: [],
    color: "#EF4444",
    icon: "🛡️",
  },
  {
    id: "ops",
    name: "Ops",
    nameZh: "运营",
    mission: "让产品被需要的人看到",
    timePercent: 10,
    skills: ["ops-content-calendar", "ops-social-publish", "ops-growth-experiment"],
    color: "#14B8A6",
    icon: "📢",
  },
  {
    id: "data",
    name: "Data",
    nameZh: "数据",
    mission: "用数据驱动每一个决策",
    timePercent: 10,
    skills: ["data-metrics-setup", "data-effect-analysis"],
    color: "#F97316",
    icon: "📊",
  },
  {
    id: "fin",
    name: "Fin",
    nameZh: "财务",
    mission: "守住现金流生命线",
    timePercent: 5,
    skills: ["fin-weekly-bookkeeping", "fin-cashflow-tracking", "fin-expense-review"],
    color: "#84CC16",
    icon: "💰",
  },
];

export function getAgentRole(id: string): AgentRole | undefined {
  return AGENT_ROLES.find((r) => r.id === id);
}

export function getAgentPrompt(roleId: string, userMessage: string): string {
  const role = getAgentRole(roleId);
  if (!role) return userMessage;

  return `你是${role.nameZh}（@${role.id}）。核心使命：${role.mission}。

请以${role.nameZh}的角色视角执行以下任务：
${userMessage}`;
}
