import React, { useState } from 'react';
import { Task, TaskColumn, TaskPriority } from '../../types';
import { 
  Plus, 
  Search, 
  CheckSquare, 
  Calendar, 
  AlertCircle, 
  ArrowRight, 
  ArrowLeft,
  X,
  Trash2,
  Filter
} from 'lucide-react';

interface SprintBoardProps {
  tasks: Task[];
  onUpdateTasks: (tasks: Task[]) => void;
  selectedTask?: Task | null;
  onClearSelectedTask?: () => void;
}

export const SprintBoard: React.FC<SprintBoardProps> = ({
  tasks,
  onUpdateTasks,
  selectedTask,
  onClearSelectedTask
}) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [priorityFilter, setPriorityFilter] = useState<'all' | TaskPriority>('all');
  const [activeTask, setActiveTask] = useState<Task | null>(selectedTask || null);
  const [isCreatingTask, setIsCreatingTask] = useState(false);
  const [targetColumn, setTargetColumn] = useState<TaskColumn>('backlog');

  // Form states
  const [formTitle, setFormTitle] = useState('');
  const [formDesc, setFormDesc] = useState('');
  const [formPriority, setFormPriority] = useState<TaskPriority>('medium');
  const [formDueDate, setFormDueDate] = useState('2026-10-15');
  const [formAssigneeName, setFormAssigneeName] = useState('Sarah Chen');
  const [formTags, setFormTags] = useState('Engineering, Infra');

  // New checklist item input inside modal
  const [newChecklistText, setNewChecklistText] = useState('');

  const columns: { id: TaskColumn; label: string; dotColor: string }[] = [
    { id: 'backlog', label: 'Backlog', dotColor: 'bg-neutral-500' },
    { id: 'in_progress', label: 'In Progress', dotColor: 'bg-indigo-500' },
    { id: 'review', label: 'In Review', dotColor: 'bg-amber-500' },
    { id: 'done', label: 'Completed', dotColor: 'bg-emerald-500' }
  ];

  // Filter tasks
  const filteredTasks = tasks.filter(task => {
    const matchesSearch = task.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
                          task.description.toLowerCase().includes(searchQuery.toLowerCase()) ||
                          task.id.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesPriority = priorityFilter === 'all' || task.priority === priorityFilter;
    return matchesSearch && matchesPriority;
  });

  // Move task to next or prev column
  const handleMoveTask = (taskId: string, direction: 'next' | 'prev') => {
    const columnOrder: TaskColumn[] = ['backlog', 'in_progress', 'review', 'done'];
    onUpdateTasks(tasks.map(t => {
      if (t.id !== taskId) return t;
      const currentIndex = columnOrder.indexOf(t.column);
      const newIndex = direction === 'next' 
        ? Math.min(currentIndex + 1, columnOrder.length - 1)
        : Math.max(currentIndex - 1, 0);
      return { ...t, column: columnOrder[newIndex] };
    }));
  };

  // Toggle checklist item
  const handleToggleChecklist = (taskId: string, checkId: string) => {
    const updated = tasks.map(t => {
      if (t.id !== taskId) return t;
      return {
        ...t,
        checklist: t.checklist.map(c => c.id === checkId ? { ...c, done: !c.done } : c)
      };
    });
    onUpdateTasks(updated);
    if (activeTask && activeTask.id === taskId) {
      setActiveTask(updated.find(t => t.id === taskId) || null);
    }
  };

  // Add checklist item to active task
  const handleAddChecklistItem = (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeTask || !newChecklistText.trim()) return;

    const newItem = {
      id: `check-${Date.now()}`,
      text: newChecklistText.trim(),
      done: false
    };

    const updated = tasks.map(t => {
      if (t.id !== activeTask.id) return t;
      return {
        ...t,
        checklist: [...t.checklist, newItem]
      };
    });

    onUpdateTasks(updated);
    setActiveTask(updated.find(t => t.id === activeTask.id) || null);
    setNewChecklistText('');
  };

  // Delete checklist item
  const handleDeleteChecklistItem = (checkId: string) => {
    if (!activeTask) return;
    const updated = tasks.map(t => {
      if (t.id !== activeTask.id) return t;
      return {
        ...t,
        checklist: t.checklist.filter(c => c.id !== checkId)
      };
    });
    onUpdateTasks(updated);
    setActiveTask(updated.find(t => t.id === activeTask.id) || null);
  };

  // Create new task
  const handleCreateTask = (e: React.FormEvent) => {
    e.preventDefault();
    if (!formTitle.trim()) return;

    const assignees = [
      { name: 'Sarah Chen', initials: 'SC', color: 'bg-amber-600' },
      { name: 'Marcus Vance', initials: 'MV', color: 'bg-indigo-600' },
      { name: 'Elena Rostova', initials: 'ER', color: 'bg-emerald-600' },
      { name: 'Devon Lee', initials: 'DL', color: 'bg-violet-600' }
    ];
    const chosenAssignee = assignees.find(a => a.name === formAssigneeName) || assignees[0];

    const newTask: Task = {
      id: `TASK-${Math.floor(100 + Math.random() * 900)}`,
      title: formTitle.trim(),
      description: formDesc.trim(),
      column: targetColumn,
      priority: formPriority,
      tags: formTags.split(',').map(t => t.trim()).filter(Boolean),
      dueDate: formDueDate,
      assignee: chosenAssignee,
      checklist: [
        { id: `c-${Date.now()}-1`, text: 'Initial design review', done: false },
        { id: `c-${Date.now()}-2`, text: 'Unit tests & code coverage', done: false }
      ],
      createdAt: new Date().toISOString().slice(0, 10)
    };

    onUpdateTasks([...tasks, newTask]);
    setIsCreatingTask(false);
    setFormTitle('');
    setFormDesc('');
  };

  // Delete task
  const handleDeleteTask = (taskId: string) => {
    onUpdateTasks(tasks.filter(t => t.id !== taskId));
    if (activeTask?.id === taskId) {
      setActiveTask(null);
      if (onClearSelectedTask) onClearSelectedTask();
    }
  };

  const getPriorityStyle = (priority: TaskPriority) => {
    switch (priority) {
      case 'urgent': return 'text-rose-400 border-rose-500/30 bg-rose-500/10';
      case 'high': return 'text-amber-400 border-amber-500/30 bg-amber-500/10';
      case 'medium': return 'text-sky-400 border-sky-500/30 bg-sky-500/10';
      case 'low': return 'text-neutral-400 border-neutral-700 bg-neutral-800';
    }
  };

  return (
    <div className="flex-1 flex flex-col h-[calc(100vh-3.5rem)] overflow-hidden bg-neutral-950">
      {/* Board Controls Bar */}
      <div className="border-b border-white/10 bg-neutral-900/40 px-6 py-3 flex flex-wrap items-center justify-between gap-4 shrink-0">
        <div className="flex items-center gap-3">
          <div className="relative">
            <Search className="w-3.5 h-3.5 text-neutral-400 absolute left-3 top-1/2 -translate-y-1/2" />
            <input
              type="text"
              placeholder="Search sprint tasks..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-8 pr-3 py-1.5 text-xs bg-neutral-900 border border-white/10 rounded-lg text-white placeholder-neutral-500 focus:outline-none focus:border-indigo-500 w-56"
            />
          </div>

          {/* Priority Filter Tabs */}
          <div className="hidden sm:flex items-center gap-1 p-1 bg-neutral-900 border border-white/5 rounded-lg">
            <Filter className="w-3 h-3 text-neutral-500 ml-1.5 mr-0.5" />
            {(['all', 'urgent', 'high', 'medium', 'low'] as const).map(p => (
              <button
                key={p}
                onClick={() => setPriorityFilter(p)}
                className={`px-2.5 py-1 text-[11px] font-medium rounded-md capitalize transition-colors ${
                  priorityFilter === p
                    ? 'bg-neutral-800 text-white shadow-sm'
                    : 'text-neutral-400 hover:text-neutral-200'
                }`}
              >
                {p}
              </button>
            ))}
          </div>
        </div>

        <div className="flex items-center gap-3 text-xs text-neutral-400">
          <span className="font-mono tabular-nums">{tasks.filter(t => t.column === 'done').length} of {tasks.length} tasks completed</span>
          <button
            onClick={() => {
              setTargetColumn('backlog');
              setIsCreatingTask(true);
            }}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-white bg-indigo-600 rounded-lg hover:bg-indigo-500 transition-colors shadow-sm"
          >
            <Plus className="w-3.5 h-3.5" />
            <span>Add Task</span>
          </button>
        </div>
      </div>

      {/* Kanban Columns Grid */}
      <div className="flex-1 p-6 overflow-x-auto overflow-y-hidden">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-5 min-w-[1000px] h-full">
          {columns.map(col => {
            const colTasks = filteredTasks.filter(t => t.column === col.id);
            return (
              <div 
                key={col.id} 
                className="flex flex-col bg-neutral-900/60 border border-white/10 rounded-xl overflow-hidden h-full shadow-sm"
              >
                {/* Column Header */}
                <div className="p-3.5 border-b border-white/10 bg-neutral-900/80 flex items-center justify-between shrink-0">
                  <div className="flex items-center gap-2">
                    <span className={`w-2 h-2 rounded-full ${col.dotColor}`} />
                    <h3 className="text-xs font-semibold text-white tracking-wide">{col.label}</h3>
                    <span className="text-[11px] font-mono tabular-nums text-neutral-400 ml-1">
                      {colTasks.length}
                    </span>
                  </div>
                  <button
                    onClick={() => {
                      setTargetColumn(col.id);
                      setIsCreatingTask(true);
                    }}
                    className="p-1 text-neutral-400 hover:text-white rounded hover:bg-neutral-800 transition-colors"
                    title={`Add task to ${col.label}`}
                  >
                    <Plus className="w-3.5 h-3.5" />
                  </button>
                </div>

                {/* Cards Container */}
                <div className="flex-1 p-3 overflow-y-auto space-y-3">
                  {colTasks.length === 0 ? (
                    <div className="h-32 border border-dashed border-white/10 rounded-lg flex flex-col items-center justify-center text-center p-4 text-xs text-neutral-500">
                      <span>No tasks in this lane</span>
                      <button
                        onClick={() => {
                          setTargetColumn(col.id);
                          setIsCreatingTask(true);
                        }}
                        className="text-indigo-400 hover:underline mt-1 text-[11px]"
                      >
                        + Create a task
                      </button>
                    </div>
                  ) : (
                    colTasks.map(task => {
                      const completedCount = task.checklist.filter(c => c.done).length;
                      const totalCount = task.checklist.length;
                      const isDone = task.column === 'done';

                      return (
                        <div
                          key={task.id}
                          onClick={() => setActiveTask(task)}
                          className="bg-neutral-900 border border-white/10 hover:border-white/20 rounded-lg p-3.5 transition-all shadow-sm hover:shadow-md cursor-pointer group"
                        >
                          {/* Task Top Meta */}
                          <div className="flex items-center justify-between text-[11px] text-neutral-400 mb-2">
                            <span className="font-mono text-neutral-400 font-semibold">{task.id}</span>
                            <span className={`text-[10px] font-medium px-2 py-0.5 rounded border capitalize ${getPriorityStyle(task.priority)}`}>
                              {task.priority}
                            </span>
                          </div>

                          {/* Title */}
                          <h4 className={`text-xs font-semibold text-white leading-snug mb-2 group-hover:text-indigo-300 transition-colors ${
                            isDone ? 'line-through text-neutral-400' : ''
                          }`}>
                            {task.title}
                          </h4>

                          {/* Description snippet */}
                          <p className="text-[11px] text-neutral-400 line-clamp-2 mb-3">
                            {task.description}
                          </p>

                          {/* Progress Checklist Bar */}
                          {totalCount > 0 && (
                            <div className="mb-3 space-y-1">
                              <div className="flex items-center justify-between text-[10px] text-neutral-400 font-mono">
                                <span className="flex items-center gap-1">
                                  <CheckSquare className="w-3 h-3 text-neutral-500" />
                                  Checklist
                                </span>
                                <span className="tabular-nums">{completedCount}/{totalCount}</span>
                              </div>
                              <div className="w-full h-1 bg-neutral-800 rounded-full overflow-hidden">
                                <div
                                  className="h-full bg-indigo-500 transition-all duration-300"
                                  style={{ width: `${(completedCount / totalCount) * 100}%` }}
                                />
                              </div>
                            </div>
                          )}

                          {/* Bottom Row: Assignee & Due Date & Column Move */}
                          <div className="pt-2 border-t border-white/5 flex items-center justify-between text-[11px] text-neutral-400">
                            <div className="flex items-center gap-2">
                              <div
                                className={`w-5 h-5 rounded-full ${task.assignee.color} flex items-center justify-center text-[9px] font-bold text-white`}
                                title={task.assignee.name}
                              >
                                {task.assignee.initials}
                              </div>
                              <div className="flex items-center gap-1 text-[10px] text-neutral-400">
                                <Calendar className="w-3 h-3 text-neutral-500" />
                                <span>{task.dueDate.slice(5)}</span>
                              </div>
                            </div>

                            {/* Move controls */}
                            <div className="flex items-center gap-1 opacity-70 group-hover:opacity-100 transition-opacity">
                              {task.column !== 'backlog' && (
                                <button
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    handleMoveTask(task.id, 'prev');
                                  }}
                                  className="p-1 text-neutral-400 hover:text-white rounded hover:bg-neutral-800 transition-colors"
                                  title="Move to previous stage"
                                >
                                  <ArrowLeft className="w-3 h-3" />
                                </button>
                              )}
                              {task.column !== 'done' && (
                                <button
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    handleMoveTask(task.id, 'next');
                                  }}
                                  className="p-1 text-neutral-400 hover:text-indigo-400 rounded hover:bg-neutral-800 transition-colors"
                                  title="Advance to next stage"
                                >
                                  <ArrowRight className="w-3 h-3" />
                                </button>
                              )}
                            </div>
                          </div>
                        </div>
                      );
                    })
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Task Detail Modal */}
      {activeTask && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in">
          <div className="bg-neutral-900 border border-white/10 rounded-xl p-6 max-w-xl w-full shadow-2xl max-h-[90vh] overflow-y-auto">
            {/* Modal Header */}
            <div className="flex items-start justify-between pb-4 border-b border-white/10 mb-4">
              <div>
                <div className="flex items-center gap-2 text-xs text-neutral-400 mb-1">
                  <span className="font-mono text-indigo-400 font-semibold">{activeTask.id}</span>
                  <span aria-hidden="true">·</span>
                  <span className="capitalize">{activeTask.column.replace('_', ' ')}</span>
                  <span aria-hidden="true">·</span>
                  <span>Created {activeTask.createdAt}</span>
                </div>
                <h2 className="text-base font-bold text-white">{activeTask.title}</h2>
              </div>
              <button
                onClick={() => setActiveTask(null)}
                className="text-neutral-400 hover:text-white p-1"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Task Info Row */}
            <div className="grid grid-cols-3 gap-3 p-3 bg-neutral-950/60 rounded-lg border border-white/5 text-xs mb-5">
              <div>
                <span className="text-neutral-500 block text-[10px] uppercase font-mono">Assignee</span>
                <span className="text-white font-medium flex items-center gap-1.5 mt-0.5">
                  <span className={`w-3.5 h-3.5 rounded-full ${activeTask.assignee.color} inline-block`} />
                  {activeTask.assignee.name}
                </span>
              </div>
              <div>
                <span className="text-neutral-500 block text-[10px] uppercase font-mono">Priority</span>
                <span className={`capitalize font-medium mt-0.5 inline-block ${getPriorityStyle(activeTask.priority).split(' ')[0]}`}>
                  {activeTask.priority}
                </span>
              </div>
              <div>
                <span className="text-neutral-500 block text-[10px] uppercase font-mono">Due Date</span>
                <span className="text-white font-mono mt-0.5 block">{activeTask.dueDate}</span>
              </div>
            </div>

            {/* Description */}
            <div className="mb-5">
              <h4 className="text-xs font-semibold text-neutral-300 uppercase tracking-wider mb-2 font-mono">
                Description
              </h4>
              <p className="text-xs text-neutral-300 bg-neutral-950 p-3 rounded-lg border border-white/5 leading-relaxed">
                {activeTask.description || 'No description provided.'}
              </p>
            </div>

            {/* Checklist Section */}
            <div className="mb-6">
              <div className="flex items-center justify-between mb-2">
                <h4 className="text-xs font-semibold text-neutral-300 uppercase tracking-wider font-mono">
                  Acceptance Criteria ({activeTask.checklist.filter(c => c.done).length}/{activeTask.checklist.length})
                </h4>
              </div>

              <div className="space-y-2 mb-3">
                {activeTask.checklist.map(item => (
                  <div
                    key={item.id}
                    className="flex items-center justify-between p-2 rounded-lg bg-neutral-950 border border-white/5 text-xs group"
                  >
                    <label className="flex items-center gap-2.5 cursor-pointer flex-1 min-w-0">
                      <input
                        type="checkbox"
                        checked={item.done}
                        onChange={() => handleToggleChecklist(activeTask.id, item.id)}
                        className="rounded border-white/20 bg-neutral-800 text-indigo-600 focus:ring-0 focus:ring-offset-0 cursor-pointer"
                      />
                      <span className={`truncate ${item.done ? 'line-through text-neutral-500' : 'text-neutral-200'}`}>
                        {item.text}
                      </span>
                    </label>
                    <button
                      onClick={() => handleDeleteChecklistItem(item.id)}
                      className="opacity-0 group-hover:opacity-100 text-neutral-500 hover:text-rose-400 p-1 transition-opacity"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                ))}
              </div>

              {/* Add checklist item */}
              <form onSubmit={handleAddChecklistItem} className="flex gap-2">
                <input
                  type="text"
                  placeholder="Add criteria or checklist item..."
                  value={newChecklistText}
                  onChange={(e) => setNewChecklistText(e.target.value)}
                  className="flex-1 bg-neutral-950 border border-white/10 rounded-lg px-3 py-1.5 text-xs text-white placeholder-neutral-500 focus:outline-none focus:border-indigo-500"
                />
                <button
                  type="submit"
                  className="px-3 py-1.5 text-xs bg-neutral-800 hover:bg-neutral-700 text-white rounded-lg transition-colors font-medium"
                >
                  Add
                </button>
              </form>
            </div>

            {/* Modal Footer */}
            <div className="pt-4 border-t border-white/10 flex items-center justify-between">
              <button
                onClick={() => handleDeleteTask(activeTask.id)}
                className="flex items-center gap-1.5 text-xs text-rose-400 hover:text-rose-300 transition-colors"
              >
                <Trash2 className="w-3.5 h-3.5" />
                <span>Delete Task</span>
              </button>

              <div className="flex items-center gap-2">
                <button
                  onClick={() => setActiveTask(null)}
                  className="px-4 py-1.5 text-xs font-medium text-white bg-indigo-600 rounded-lg hover:bg-indigo-500 transition-colors"
                >
                  Close
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Create Task Modal */}
      {isCreatingTask && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in">
          <div className="bg-neutral-900 border border-white/10 rounded-xl p-5 max-w-md w-full shadow-2xl">
            <div className="flex items-center justify-between pb-3 border-b border-white/10 mb-4">
              <h3 className="text-sm font-semibold text-white">Create Sprint Task</h3>
              <button 
                onClick={() => setIsCreatingTask(false)}
                className="text-neutral-400 hover:text-white"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <form onSubmit={handleCreateTask} className="space-y-4">
              <div>
                <label className="block text-xs font-medium text-neutral-300 mb-1">
                  Task Title
                </label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Implement webhook retry processor"
                  value={formTitle}
                  onChange={(e) => setFormTitle(e.target.value)}
                  className="w-full bg-neutral-950 border border-white/10 rounded-lg px-3 py-2 text-xs text-white placeholder-neutral-500 focus:outline-none focus:border-indigo-500"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-neutral-300 mb-1">
                    Column
                  </label>
                  <select
                    value={targetColumn}
                    onChange={(e) => setTargetColumn(e.target.value as TaskColumn)}
                    className="w-full bg-neutral-950 border border-white/10 rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-indigo-500 capitalize"
                  >
                    <option value="backlog">Backlog</option>
                    <option value="in_progress">In Progress</option>
                    <option value="review">In Review</option>
                    <option value="done">Completed</option>
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-medium text-neutral-300 mb-1">
                    Priority
                  </label>
                  <select
                    value={formPriority}
                    onChange={(e) => setFormPriority(e.target.value as TaskPriority)}
                    className="w-full bg-neutral-950 border border-white/10 rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-indigo-500 capitalize"
                  >
                    <option value="low">Low</option>
                    <option value="medium">Medium</option>
                    <option value="high">High</option>
                    <option value="urgent">Urgent</option>
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-neutral-300 mb-1">
                    Assignee
                  </label>
                  <select
                    value={formAssigneeName}
                    onChange={(e) => setFormAssigneeName(e.target.value)}
                    className="w-full bg-neutral-950 border border-white/10 rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-indigo-500"
                  >
                    <option value="Sarah Chen">Sarah Chen</option>
                    <option value="Marcus Vance">Marcus Vance</option>
                    <option value="Elena Rostova">Elena Rostova</option>
                    <option value="Devon Lee">Devon Lee</option>
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-medium text-neutral-300 mb-1">
                    Due Date
                  </label>
                  <input
                    type="date"
                    value={formDueDate}
                    onChange={(e) => setFormDueDate(e.target.value)}
                    className="w-full bg-neutral-950 border border-white/10 rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-indigo-500 font-mono"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-medium text-neutral-300 mb-1">
                  Description
                </label>
                <textarea
                  rows={2}
                  placeholder="Task context, scope, or links..."
                  value={formDesc}
                  onChange={(e) => setFormDesc(e.target.value)}
                  className="w-full bg-neutral-950 border border-white/10 rounded-lg px-3 py-2 text-xs text-white placeholder-neutral-500 focus:outline-none focus:border-indigo-500 resize-none"
                />
              </div>

              <div className="flex justify-end gap-2 pt-2 border-t border-white/10">
                <button
                  type="button"
                  onClick={() => setIsCreatingTask(false)}
                  className="px-3 py-1.5 text-xs text-neutral-400 hover:text-white rounded-lg hover:bg-neutral-800 transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="px-4 py-1.5 text-xs font-medium text-white bg-indigo-600 rounded-lg hover:bg-indigo-500 transition-colors shadow-sm"
                >
                  Create Task
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
