import React, { useState } from 'react';
import { CODE_MODULES } from '../../data/liquiddynamoData';
import { soundFx } from '../../utils/audioFeedback';
import { 
  FolderTree, 
  FileCode, 
  Copy, 
  Check, 
  ShieldAlert, 
  Layers, 
  Code2, 
  Terminal, 
  Folder
} from 'lucide-react';

export const CodebaseExplorer: React.FC = () => {
  const [selectedModuleId, setSelectedModuleId] = useState<string>('features-airpods');
  const [copiedSnippet, setCopiedSnippet] = useState<boolean>(false);

  const currentModule = CODE_MODULES.find(m => m.id === selectedModuleId) || CODE_MODULES[0];

  const handleCopySnippet = () => {
    if (!currentModule.swiftSnippet) return;
    navigator.clipboard.writeText(currentModule.swiftSnippet);
    soundFx.playTick();
    setCopiedSnippet(true);
    setTimeout(() => setCopiedSnippet(false), 2000);
  };

  return (
    <div className="w-full bg-neutral-900/80 border border-neutral-800 rounded-2xl p-6 lg:p-8 backdrop-blur-xl space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 pb-6 border-b border-neutral-800">
        <div>
          <div className="flex items-center gap-2 text-indigo-400 text-xs font-mono font-medium uppercase tracking-wider">
            <FolderTree className="w-4 h-4" />
            <span>Repository Blueprint & Architectural Roles</span>
          </div>
          <h3 className="text-xl font-bold text-white mt-1">Uploaded Codebase Directory Map</h3>
          <p className="text-sm text-neutral-400 mt-1 max-w-2xl">
            Inspect the subsystem partitioning across <code>liquiddinamo/</code>, Metal shaders, helper clients, and packaging automation.
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Module Sidebar (4 cols) */}
        <div className="lg:col-span-4 space-y-2">
          <div className="text-xs font-mono text-neutral-400 uppercase tracking-wider px-2 mb-2">
            Subsystems & Components
          </div>
          {CODE_MODULES.map((mod) => {
            const isSelected = mod.id === selectedModuleId;
            return (
              <button
                key={mod.id}
                onClick={() => {
                  soundFx.playTick();
                  setSelectedModuleId(mod.id);
                }}
                className={`w-full text-left p-3.5 rounded-xl border transition-all flex items-start gap-3 ${
                  isSelected
                    ? 'bg-neutral-850 border-indigo-500/80 text-white shadow-md ring-1 ring-indigo-500/20'
                    : 'bg-neutral-950/60 border-neutral-800 text-neutral-400 hover:border-neutral-700 hover:text-neutral-200'
                }`}
              >
                <Folder className={`w-4 h-4 flex-shrink-0 mt-0.5 ${isSelected ? 'text-indigo-400' : 'text-neutral-500'}`} />
                <div className="min-w-0 flex-1">
                  <div className="text-xs font-semibold truncate text-neutral-200">{mod.name}</div>
                  <div className="text-[11px] font-mono text-neutral-500 truncate mt-0.5">{mod.path}</div>
                </div>
              </button>
            );
          })}
        </div>

        {/* Module Detail (8 cols) */}
        <div className="lg:col-span-8 p-6 rounded-2xl bg-neutral-950 border border-neutral-800 space-y-6">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pb-4 border-b border-neutral-800">
            <div>
              <div className="flex items-center gap-2">
                <h4 className="text-base font-bold text-white">{currentModule.name}</h4>
                <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-indigo-500/20 text-indigo-300 uppercase">
                  {currentModule.category}
                </span>
              </div>
              <p className="text-xs font-mono text-neutral-400 mt-1">{currentModule.path}</p>
            </div>
          </div>

          <p className="text-sm text-neutral-300 leading-relaxed">
            {currentModule.description}
          </p>

          {/* Files List */}
          <div>
            <div className="text-xs font-mono text-neutral-400 uppercase tracking-wider mb-2 flex items-center gap-2">
              <FileCode className="w-3.5 h-3.5 text-neutral-400" />
              <span>Core Files in this Module:</span>
            </div>
            <div className="flex flex-wrap gap-2">
              {currentModule.files.map((file, i) => (
                <span
                  key={i}
                  className="px-2.5 py-1 rounded-lg bg-neutral-900 border border-neutral-800 font-mono text-xs text-neutral-300"
                >
                  {file}
                </span>
              ))}
            </div>
          </div>

          {/* Architectural Invariants */}
          <div className="p-4 rounded-xl bg-neutral-900/60 border border-neutral-800/80 space-y-2">
            <div className="text-xs font-semibold text-neutral-200 flex items-center gap-2">
              <ShieldAlert className="w-4 h-4 text-amber-400" />
              <span>Architectural Invariants & Acceptance Rules</span>
            </div>
            <ul className="space-y-1.5 pl-6 list-disc text-xs text-neutral-400">
              {currentModule.invariants.map((inv, i) => (
                <li key={i}>{inv}</li>
              ))}
            </ul>
          </div>

          {/* Swift Sample Snippet */}
          {currentModule.swiftSnippet && (
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-xs font-mono text-neutral-400 flex items-center gap-1.5">
                  <Terminal className="w-3.5 h-3.5 text-indigo-400" />
                  <span>Key Swift / Metal Pattern</span>
                </span>
                <button
                  onClick={handleCopySnippet}
                  className="flex items-center gap-1 text-[11px] font-mono text-indigo-400 hover:text-indigo-300 transition-colors"
                >
                  {copiedSnippet ? (
                    <>
                      <Check className="w-3 h-3 text-emerald-400" />
                      <span className="text-emerald-400">Copied!</span>
                    </>
                  ) : (
                    <>
                      <Copy className="w-3 h-3" />
                      <span>Copy Snippet</span>
                    </>
                  )}
                </button>
              </div>

              <div className="relative rounded-xl bg-neutral-900 border border-neutral-800 p-4 overflow-x-auto">
                <pre className="font-mono text-xs text-neutral-200 leading-relaxed whitespace-pre">
                  <code>{currentModule.swiftSnippet}</code>
                </pre>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
