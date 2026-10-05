import React, { useState } from 'react';
import { SPEC_DOCS } from '../../data/liquiddynamoData';
import { soundFx } from '../../utils/audioFeedback';
import { 
  BookOpen, 
  Search, 
  FileText, 
  Tag, 
  Copy, 
  Check, 
  ExternalLink, 
  Calendar 
} from 'lucide-react';

export const DocsPortal: React.FC = () => {
  const [selectedDocId, setSelectedDocId] = useState<string>('readme');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [copiedDoc, setCopiedDoc] = useState<boolean>(false);

  const filteredDocs = SPEC_DOCS.filter(doc => 
    doc.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
    doc.summary.toLowerCase().includes(searchQuery.toLowerCase()) ||
    doc.tags.some(t => t.toLowerCase().includes(searchQuery.toLowerCase()))
  );

  const activeDoc = SPEC_DOCS.find(d => d.id === selectedDocId) || SPEC_DOCS[0];

  const handleCopyContent = () => {
    navigator.clipboard.writeText(activeDoc.content);
    soundFx.playTick();
    setCopiedDoc(true);
    setTimeout(() => setCopiedDoc(false), 2000);
  };

  return (
    <div className="w-full bg-neutral-900/80 border border-neutral-800 rounded-2xl p-6 lg:p-8 backdrop-blur-xl space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 pb-6 border-b border-neutral-800">
        <div>
          <div className="flex items-center gap-2 text-indigo-400 text-xs font-mono font-medium uppercase tracking-wider">
            <BookOpen className="w-4 h-4" />
            <span>Uploaded Specifications & Audits</span>
          </div>
          <h3 className="text-xl font-bold text-white mt-1">Documentation & Specification Archive</h3>
          <p className="text-sm text-neutral-400 mt-1 max-w-2xl">
            Browse full markdown specifications, feasibility spikes, and architecture audits directly from <code>/LiquidDynamo/docs/</code>.
          </p>
        </div>

        {/* Search Input */}
        <div className="relative w-full md:w-64">
          <Search className="w-4 h-4 text-neutral-500 absolute left-3 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            placeholder="Search specs & keywords..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-9 pr-4 py-2 rounded-xl bg-neutral-950 border border-neutral-800 text-xs text-neutral-200 placeholder-neutral-500 focus:outline-none focus:border-indigo-500"
          />
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Document List Sidebar (4 cols) */}
        <div className="lg:col-span-4 space-y-2">
          {filteredDocs.map((doc) => {
            const isSelected = doc.id === activeDoc.id;
            return (
              <button
                key={doc.id}
                onClick={() => {
                  soundFx.playTick();
                  setSelectedDocId(doc.id);
                }}
                className={`w-full text-left p-4 rounded-xl border transition-all ${
                  isSelected
                    ? 'bg-neutral-850 border-indigo-500/80 shadow-md ring-1 ring-indigo-500/20'
                    : 'bg-neutral-950/60 border-neutral-800 hover:border-neutral-700 hover:bg-neutral-850/40'
                }`}
              >
                <div className="flex items-center justify-between">
                  <span className="text-[10px] font-mono text-neutral-500">{doc.date}</span>
                  <div className="flex items-center gap-1">
                    {doc.tags.slice(0, 2).map((tag) => (
                      <span key={tag} className="text-[9px] font-mono px-1.5 py-0.5 rounded bg-neutral-800 text-neutral-400">
                        {tag}
                      </span>
                    ))}
                  </div>
                </div>

                <div className="font-semibold text-xs text-neutral-200 mt-1.5 line-clamp-1">{doc.title}</div>
                <p className="text-[11px] text-neutral-400 mt-1 line-clamp-2 leading-relaxed">{doc.summary}</p>
              </button>
            );
          })}
        </div>

        {/* Document Reader Main (8 cols) */}
        <div className="lg:col-span-8 p-6 lg:p-8 rounded-2xl bg-neutral-950 border border-neutral-800 space-y-6">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-4 border-b border-neutral-800">
            <div>
              <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-indigo-500/20 text-indigo-300">
                {activeDoc.filePath}
              </span>
              <h4 className="text-lg font-bold text-white mt-1.5">{activeDoc.title}</h4>
              <p className="text-xs text-neutral-400 mt-0.5">{activeDoc.subtitle}</p>
            </div>

            <button
              onClick={handleCopyContent}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-neutral-900 hover:bg-neutral-800 border border-neutral-800 text-xs font-mono text-neutral-300 self-start sm:self-auto transition-colors"
            >
              {copiedDoc ? (
                <>
                  <Check className="w-3.5 h-3.5 text-emerald-400" />
                  <span className="text-emerald-400">Copied!</span>
                </>
              ) : (
                <>
                  <Copy className="w-3.5 h-3.5" />
                  <span>Copy Markdown</span>
                </>
              )}
            </button>
          </div>

          {/* Formatted Markdown Content */}
          <div className="prose prose-invert prose-xs max-w-none text-neutral-300 space-y-4 text-xs leading-relaxed">
            <pre className="p-4 rounded-xl bg-neutral-900 border border-neutral-800 overflow-x-auto font-mono text-neutral-200 text-[11px] leading-relaxed whitespace-pre-wrap">
              {activeDoc.content}
            </pre>
          </div>
        </div>
      </div>
    </div>
  );
};
