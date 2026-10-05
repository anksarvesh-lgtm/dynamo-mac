import React from 'react';
import { ViewMode } from '../../types';
import { X, GitFork, Kanban, FileText, BarChart3 } from 'lucide-react';

interface NewItemModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSelectAction: (actionType: 'task' | 'node' | 'doc' | 'metric') => void;
  onSwitchView: (view: ViewMode) => void;
}

export const NewItemModal: React.FC<NewItemModalProps> = ({
  isOpen,
  onClose,
  onSelectAction,
  onSwitchView
}) => {
  if (!isOpen) return null;

  const options = [
    {
      type: 'task' as const,
      view: 'sprint' as ViewMode,
      title: 'New Sprint Task',
      desc: 'Create an engineering ticket with checklists, priority & assignee',
      icon: <Kanban className="w-5 h-5 text-emerald-400" />
    },
    {
      type: 'node' as const,
      view: 'canvas' as ViewMode,
      title: 'New Canvas Node',
      desc: 'Add an architecture service, database cluster, or decision block',
      icon: <GitFork className="w-5 h-5 text-indigo-400" />
    },
    {
      type: 'doc' as const,
      view: 'docs' as ViewMode,
      title: 'New Spec or RFC Document',
      desc: 'Draft engineering design document or technical specifications',
      icon: <FileText className="w-5 h-5 text-sky-400" />
    },
    {
      type: 'metric' as const,
      view: 'analytics' as ViewMode,
      title: 'Log Sprint Cycle Metric',
      desc: 'Record velocity, test pass rate, or p99 edge response time',
      icon: <BarChart3 className="w-5 h-5 text-amber-400" />
    }
  ];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in">
      <div className="bg-neutral-900 border border-white/10 rounded-xl p-5 max-w-md w-full shadow-2xl">
        <div className="flex items-center justify-between pb-3 border-b border-white/10 mb-4">
          <h3 className="text-sm font-semibold text-white">Create New Workspace Item</h3>
          <button onClick={onClose} className="text-neutral-400 hover:text-white">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="space-y-2.5 mb-5">
          {options.map((opt) => (
            <button
              key={opt.type}
              onClick={() => {
                onSwitchView(opt.view);
                onSelectAction(opt.type);
                onClose();
              }}
              className="w-full text-left p-3 rounded-lg border border-white/5 bg-neutral-950 hover:bg-neutral-800/60 hover:border-white/20 transition-all flex items-start gap-3.5 group"
            >
              <div className="p-2 rounded-md bg-neutral-900 border border-white/10 shrink-0">
                {opt.icon}
              </div>
              <div className="min-w-0">
                <div className="text-xs font-semibold text-white group-hover:text-indigo-300 transition-colors">
                  {opt.title}
                </div>
                <div className="text-[11px] text-neutral-400 mt-0.5 leading-snug">
                  {opt.desc}
                </div>
              </div>
            </button>
          ))}
        </div>

        <div className="flex justify-end pt-2 border-t border-white/10">
          <button
            onClick={onClose}
            className="px-4 py-1.5 text-xs text-neutral-400 hover:text-white rounded-lg hover:bg-neutral-800 transition-colors"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
  );
};
