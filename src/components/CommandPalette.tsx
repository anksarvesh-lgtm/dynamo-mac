import React, { useState, useEffect, useRef } from 'react';
import { ViewMode, Task, DocumentItem } from '../types';
import { 
  Search, 
  GitFork, 
  Kanban, 
  FileText, 
  BarChart3, 
  Timer, 
  CheckCircle2, 
  ArrowRight,
  Plus
} from 'lucide-react';

interface CommandPaletteProps {
  isOpen: boolean;
  onClose: () => void;
  onSelectView: (view: ViewMode) => void;
  tasks: Task[];
  docs: DocumentItem[];
  onSelectTask: (task: Task) => void;
  onSelectDoc: (doc: DocumentItem) => void;
  onOpenNewModal: () => void;
}

export const CommandPalette: React.FC<CommandPaletteProps> = ({
  isOpen,
  onClose,
  onSelectView,
  tasks,
  docs,
  onSelectTask,
  onSelectDoc,
  onOpenNewModal
}) => {
  const [query, setQuery] = useState('');
  const [selectedIndex, setSelectedIndex] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (isOpen) {
      setQuery('');
      setSelectedIndex(0);
      setTimeout(() => inputRef.current?.focus(), 50);
    }
  }, [isOpen]);

  // Build searchable items list
  const navActions = [
    { id: 'view-canvas', title: 'Open Flow Canvas', subtitle: 'Interactive node diagramming', category: 'Navigation', icon: <GitFork className="w-4 h-4 text-indigo-400" />, action: () => onSelectView('canvas') },
    { id: 'view-sprint', title: 'Open Sprint Board', subtitle: 'Kanban tasks & checklist tracking', category: 'Navigation', icon: <Kanban className="w-4 h-4 text-emerald-400" />, action: () => onSelectView('sprint') },
    { id: 'view-docs', title: 'Open Docs & Specs', subtitle: 'Markdown engineering docs & RFCs', category: 'Navigation', icon: <FileText className="w-4 h-4 text-sky-400" />, action: () => onSelectView('docs') },
    { id: 'view-analytics', title: 'Open Analytics', subtitle: 'Velocity, test pass rate & metrics', category: 'Navigation', icon: <BarChart3 className="w-4 h-4 text-amber-400" />, action: () => onSelectView('analytics') },
    { id: 'view-focus', title: 'Open Focus Hub', subtitle: 'Pomodoro timer & ambient soundscapes', category: 'Navigation', icon: <Timer className="w-4 h-4 text-rose-400" />, action: () => onSelectView('focus') },
    { id: 'action-new', title: 'Create New Task / Doc', subtitle: 'Add new work item to Stratos', category: 'Action', icon: <Plus className="w-4 h-4 text-violet-400" />, action: () => onOpenNewModal() }
  ];

  const taskActions = tasks.map(t => ({
    id: `task-${t.id}`,
    title: `${t.id}: ${t.title}`,
    subtitle: `${t.column.replace('_', ' ')} · Due ${t.dueDate}`,
    category: 'Tasks',
    icon: <CheckCircle2 className="w-4 h-4 text-neutral-400" />,
    action: () => {
      onSelectView('sprint');
      onSelectTask(t);
    }
  }));

  const docActions = docs.map(d => ({
    id: `doc-${d.id}`,
    title: d.title,
    subtitle: `${d.category} · Updated ${d.updatedAt.slice(0, 10)}`,
    category: 'Documents',
    icon: <FileText className="w-4 h-4 text-neutral-400" />,
    action: () => {
      onSelectView('docs');
      onSelectDoc(d);
    }
  }));

  const allItems = [...navActions, ...taskActions, ...docActions];

  const filteredItems = query.trim() === ''
    ? allItems.slice(0, 12)
    : allItems.filter(item => 
        item.title.toLowerCase().includes(query.toLowerCase()) ||
        item.subtitle.toLowerCase().includes(query.toLowerCase()) ||
        item.category.toLowerCase().includes(query.toLowerCase())
      ).slice(0, 12);

  // Keyboard navigation
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (!isOpen) return;

      if (e.key === 'ArrowDown') {
        e.preventDefault();
        setSelectedIndex(prev => (prev + 1) % (filteredItems.length || 1));
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        setSelectedIndex(prev => (prev - 1 + filteredItems.length) % (filteredItems.length || 1));
      } else if (e.key === 'Enter') {
        e.preventDefault();
        if (filteredItems[selectedIndex]) {
          filteredItems[selectedIndex].action();
          onClose();
        }
      } else if (e.key === 'Escape') {
        onClose();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, filteredItems, selectedIndex, onClose]);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center pt-20 px-4 bg-black/60 backdrop-blur-sm animate-fade-in">
      {/* Click outside to close */}
      <div className="fixed inset-0" onClick={onClose} />

      <div className="relative w-full max-w-xl bg-neutral-900 border border-white/10 rounded-xl shadow-2xl overflow-hidden z-10">
        {/* Search input header */}
        <div className="flex items-center gap-3 px-4 py-3.5 border-b border-white/10 bg-neutral-900/80">
          <Search className="w-5 h-5 text-neutral-400 shrink-0" />
          <input
            ref={inputRef}
            type="text"
            placeholder="Type a command, search tasks, or docs..."
            value={query}
            onChange={(e) => {
              setQuery(e.target.value);
              setSelectedIndex(0);
            }}
            className="w-full bg-transparent text-sm text-white placeholder-neutral-500 focus:outline-none"
          />
          <kbd className="text-[10px] font-mono text-neutral-500 bg-neutral-800 px-2 py-0.5 rounded border border-white/5">
            ESC
          </kbd>
        </div>

        {/* Results List */}
        <div className="max-h-80 overflow-y-auto p-2 space-y-0.5">
          {filteredItems.length === 0 ? (
            <div className="py-8 text-center text-xs text-neutral-500">
              No results found for &ldquo;{query}&rdquo;
            </div>
          ) : (
            filteredItems.map((item, idx) => {
              const isSelected = idx === selectedIndex;
              return (
                <button
                  key={item.id}
                  onClick={() => {
                    item.action();
                    onClose();
                  }}
                  onMouseEnter={() => setSelectedIndex(idx)}
                  className={`w-full text-left px-3 py-2.5 rounded-lg flex items-center justify-between transition-colors ${
                    isSelected ? 'bg-neutral-800 text-white' : 'text-neutral-300 hover:bg-neutral-800/40'
                  }`}
                >
                  <div className="flex items-center gap-3 min-w-0">
                    <div className="shrink-0">{item.icon}</div>
                    <div className="min-w-0">
                      <div className="text-xs font-medium truncate">{item.title}</div>
                      <div className="text-[11px] text-neutral-500 truncate">{item.subtitle}</div>
                    </div>
                  </div>
                  <div className="flex items-center gap-2 shrink-0 ml-3">
                    <span className="text-[10px] text-neutral-500 font-mono uppercase tracking-wider">
                      {item.category}
                    </span>
                    {isSelected && <ArrowRight className="w-3.5 h-3.5 text-indigo-400" />}
                  </div>
                </button>
              );
            })
          )}
        </div>

        {/* Footer shortcuts */}
        <div className="px-4 py-2 border-t border-white/5 bg-neutral-950/60 text-[11px] text-neutral-500 flex items-center justify-between">
          <div className="flex items-center gap-4">
            <span>↑↓ to navigate</span>
            <span>↵ to select</span>
          </div>
          <span>Stratos Studio</span>
        </div>
      </div>
    </div>
  );
};
