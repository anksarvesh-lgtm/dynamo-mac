import React, { useState } from 'react';
import { CanvasNode, CanvasEdge, Task, DocumentItem, AnalyticsMetric } from '../../types';
import { Download, Upload, X, CheckCircle2, AlertTriangle } from 'lucide-react';

interface ExportModalProps {
  isOpen: boolean;
  onClose: () => void;
  data: {
    nodes: CanvasNode[];
    edges: CanvasEdge[];
    tasks: Task[];
    docs: DocumentItem[];
    metrics: AnalyticsMetric[];
  };
  onImportData: (data: {
    nodes: CanvasNode[];
    edges: CanvasEdge[];
    tasks: Task[];
    docs: DocumentItem[];
    metrics: AnalyticsMetric[];
  }) => void;
}

export const ExportModal: React.FC<ExportModalProps> = ({
  isOpen,
  onClose,
  data,
  onImportData
}) => {
  const [importStatus, setImportStatus] = useState<string | null>(null);

  if (!isOpen) return null;

  const handleDownloadBackup = () => {
    const jsonStr = JSON.stringify(data, null, 2);
    const blob = new Blob([jsonStr], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.setAttribute('download', `stratos_workspace_backup_${new Date().toISOString().slice(0, 10)}.json`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (event) => {
      try {
        const parsed = JSON.parse(event.target?.result as string);
        if (parsed.nodes && parsed.tasks && parsed.docs) {
          onImportData(parsed);
          setImportStatus('Workspace restored successfully!');
          setTimeout(() => {
            setImportStatus(null);
            onClose();
          }, 1200);
        } else {
          setImportStatus('Invalid backup file structure.');
        }
      } catch {
        setImportStatus('Error reading file. Ensure valid JSON.');
      }
    };
    reader.readAsText(file);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in">
      <div className="bg-neutral-900 border border-white/10 rounded-xl p-6 max-w-md w-full shadow-2xl">
        <div className="flex items-center justify-between pb-3 border-b border-white/10 mb-4">
          <h3 className="text-sm font-semibold text-white">Workspace Backup & Export</h3>
          <button onClick={onClose} className="text-neutral-400 hover:text-white">
            <X className="w-4 h-4" />
          </button>
        </div>

        <p className="text-xs text-neutral-400 mb-5 leading-relaxed">
          Export your complete workspace state (canvas diagrams, sprint board, documents, and analytics) as portable JSON, or restore from a previous backup.
        </p>

        <div className="space-y-3 mb-6">
          {/* Download JSON Button */}
          <button
            onClick={handleDownloadBackup}
            className="w-full flex items-center justify-between p-3 rounded-lg border border-white/10 bg-neutral-950 hover:bg-neutral-800/60 transition-colors text-left"
          >
            <div className="flex items-center gap-3">
              <div className="p-2 rounded-md bg-indigo-500/10 text-indigo-400">
                <Download className="w-4 h-4" />
              </div>
              <div>
                <div className="text-xs font-medium text-white">Download Complete Backup</div>
                <div className="text-[11px] text-neutral-500 font-mono">
                  {data.nodes.length} nodes · {data.tasks.length} tasks · {data.docs.length} docs
                </div>
              </div>
            </div>
            <span className="text-xs text-indigo-400 font-medium">Export</span>
          </button>

          {/* Import JSON File */}
          <label className="w-full flex items-center justify-between p-3 rounded-lg border border-dashed border-white/20 bg-neutral-950 hover:bg-neutral-800/40 transition-colors cursor-pointer text-left">
            <div className="flex items-center gap-3">
              <div className="p-2 rounded-md bg-emerald-500/10 text-emerald-400">
                <Upload className="w-4 h-4" />
              </div>
              <div>
                <div className="text-xs font-medium text-white">Restore from Backup</div>
                <div className="text-[11px] text-neutral-500">Upload existing .json workspace</div>
              </div>
            </div>
            <input type="file" accept=".json" onChange={handleFileChange} className="hidden" />
            <span className="text-xs text-emerald-400 font-medium">Upload</span>
          </label>
        </div>

        {importStatus && (
          <div className="p-2.5 rounded-lg bg-neutral-950 border border-white/10 text-xs flex items-center gap-2 mb-4">
            {importStatus.includes('successfully') ? (
              <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0" />
            ) : (
              <AlertTriangle className="w-4 h-4 text-amber-400 shrink-0" />
            )}
            <span className={importStatus.includes('successfully') ? 'text-emerald-300' : 'text-amber-300'}>
              {importStatus}
            </span>
          </div>
        )}

        <div className="flex justify-end pt-2 border-t border-white/10">
          <button
            onClick={onClose}
            className="px-4 py-1.5 text-xs font-medium text-neutral-300 hover:text-white bg-neutral-800 rounded-lg hover:bg-neutral-700 transition-colors"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
};
