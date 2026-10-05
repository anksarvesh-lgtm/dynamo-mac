export type ViewMode = 'canvas' | 'sprint' | 'docs' | 'analytics' | 'focus';

export type NodeType = 'service' | 'database' | 'idea' | 'task' | 'decision' | 'output';

export interface CanvasNode {
  id: string;
  title: string;
  description: string;
  type: NodeType;
  x: number;
  y: number;
  color?: string;
  status: 'active' | 'in_review' | 'planned';
  tags: string[];
}

export interface CanvasEdge {
  id: string;
  source: string;
  target: string;
  label?: string;
  dashed?: boolean;
}

export type TaskPriority = 'low' | 'medium' | 'high' | 'urgent';
export type TaskColumn = 'backlog' | 'in_progress' | 'review' | 'done';

export interface ChecklistItem {
  id: string;
  text: string;
  done: boolean;
}

export interface Task {
  id: string;
  title: string;
  description: string;
  column: TaskColumn;
  priority: TaskPriority;
  tags: string[];
  dueDate: string;
  assignee: {
    name: string;
    initials: string;
    color: string;
  };
  checklist: ChecklistItem[];
  createdAt: string;
}

export interface DocumentItem {
  id: string;
  title: string;
  category: 'Specs' | 'RFCs' | 'Guides' | 'Meetings';
  content: string;
  updatedAt: string;
  starred: boolean;
}

export interface AnalyticsMetric {
  id: string;
  date: string;
  sprint: string;
  velocity: number;
  completedTasks: number;
  prMerged: number;
  testPassRate: number;
  responseTimeMs: number;
}

export interface FocusState {
  workMinutes: number;
  breakMinutes: number;
  longBreakMinutes: number;
  sessionsCompletedToday: number;
  totalFocusMinutes: number;
}
