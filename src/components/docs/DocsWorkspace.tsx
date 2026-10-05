import React, { useState } from 'react';
import { DocumentItem } from '../../types';
import { 
  FileText, 
  Plus, 
  Search, 
  Star, 
  Download, 
  Trash2, 
  Eye, 
  Edit3, 
  Columns, 
  Code,
  BookOpen
} from 'lucide-react';

interface DocsWorkspaceProps {
  documents: DocumentItem[];
  onUpdateDocuments: (docs: DocumentItem[]) => void;
  selectedDocId?: string | null;
}

export const DocsWorkspace: React.FC<DocsWorkspaceProps> = ({
  documents,
  onUpdateDocuments,
  selectedDocId
}) => {
  const [activeDocId, setActiveDocId] = useState<string>(
    selectedDocId || documents[0]?.id || ''
  );
  const [viewMode, setViewMode] = useState<'split' | 'edit' | 'preview'>('split');
  const [searchQuery, setSearchQuery] = useState('');
  const [categoryFilter, setCategoryFilter] = useState<string>('All');

  const activeDoc = documents.find(d => d.id === activeDocId) || documents[0];

  const categories = ['All', 'Specs', 'RFCs', 'Guides', 'Meetings'];

  const filteredDocs = documents.filter(doc => {
    const matchesSearch = doc.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
                          doc.content.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesCat = categoryFilter === 'All' || doc.category === categoryFilter;
    return matchesSearch && matchesCat;
  });

  // Create new document
  const handleCreateDocument = () => {
    const newDoc: DocumentItem = {
      id: `doc-${Date.now()}`,
      title: 'Untitled Document',
      category: 'Specs',
      starred: false,
      updatedAt: new Date().toISOString(),
      content: `# Untitled Document\n\nWrite your document here...\n`
    };
    onUpdateDocuments([newDoc, ...documents]);
    setActiveDocId(newDoc.id);
  };

  // Update active doc content or title
  const handleUpdateContent = (content: string) => {
    if (!activeDoc) return;
    onUpdateDocuments(
      documents.map(d => d.id === activeDoc.id ? { ...d, content, updatedAt: new Date().toISOString() } : d)
    );
  };

  const handleUpdateTitle = (title: string) => {
    if (!activeDoc) return;
    onUpdateDocuments(
      documents.map(d => d.id === activeDoc.id ? { ...d, title, updatedAt: new Date().toISOString() } : d)
    );
  };

  const handleToggleStar = (docId: string) => {
    onUpdateDocuments(
      documents.map(d => d.id === docId ? { ...d, starred: !d.starred } : d)
    );
  };

  const handleDeleteDoc = (docId: string) => {
    const remaining = documents.filter(d => d.id !== docId);
    onUpdateDocuments(remaining);
    if (activeDocId === docId && remaining.length > 0) {
      setActiveDocId(remaining[0].id);
    }
  };

  // Template insertion
  const handleInsertTemplate = (type: 'rfc' | 'spec' | 'meeting') => {
    if (!activeDoc) return;
    let template = '';
    if (type === 'rfc') {
      template = `\n\n## Summary\nBrief 2-3 sentence overview.\n\n## Motivation\nWhy are we building this?\n\n## Detailed Design\nArchitecture breakdown and interface contracts.\n\n## Security & Reliability Considerations\nFailure modes and mitigation.`;
    } else if (type === 'spec') {
      template = `\n\n## Target Audience\nWho uses this feature?\n\n## Acceptance Criteria\n- [ ] Scenario 1\n- [ ] Scenario 2\n\n## Non-Goals\nExplicit out-of-scope boundaries.`;
    } else {
      template = `\n\n## Attendees\nSarah, Marcus, Elena\n\n## Agenda\n1. Review sprint commitments\n2. Blockers & dependencies\n\n## Action Items\n- [ ] Elena: Update connection pool\n- [ ] Marcus: Deploy DLQ worker`;
    }
    handleUpdateContent(activeDoc.content + template);
  };

  // Download markdown
  const handleDownloadMarkdown = () => {
    if (!activeDoc) return;
    const blob = new Blob([activeDoc.content], { type: 'text/markdown;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.setAttribute('download', `${activeDoc.title.toLowerCase().replace(/[^a-z0-9]/g, '_')}.md`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  // Word count & read time
  const wordCount = activeDoc ? activeDoc.content.trim().split(/\s+/).filter(Boolean).length : 0;
  const readTimeMin = Math.max(1, Math.ceil(wordCount / 200));

  // Custom Markdown Parser for high fidelity
  const renderMarkdown = (text: string) => {
    const lines = text.split('\n');
    let inCodeBlock = false;
    let codeContent = '';
    const rendered: React.ReactNode[] = [];

    lines.forEach((line, index) => {
      if (line.startsWith('```')) {
        if (inCodeBlock) {
          rendered.push(
            <pre key={`code-${index}`} className="p-3 my-3 rounded-lg bg-neutral-950 border border-white/10 font-mono text-xs text-indigo-300 overflow-x-auto">
              <code>{codeContent.trim()}</code>
            </pre>
          );
          codeContent = '';
          inCodeBlock = false;
        } else {
          inCodeBlock = true;
        }
        return;
      }

      if (inCodeBlock) {
        codeContent += line + '\n';
        return;
      }

      if (line.startsWith('# ')) {
        rendered.push(
          <h1 key={index} className="text-xl font-bold text-white mt-6 mb-3 tracking-tight border-b border-white/10 pb-2">
            {line.replace('# ', '')}
          </h1>
        );
      } else if (line.startsWith('## ')) {
        rendered.push(
          <h2 key={index} className="text-base font-semibold text-white mt-5 mb-2 tracking-tight">
            {line.replace('## ', '')}
          </h2>
        );
      } else if (line.startsWith('### ')) {
        rendered.push(
          <h3 key={index} className="text-sm font-semibold text-neutral-200 mt-4 mb-2">
            {line.replace('### ', '')}
          </h3>
        );
      } else if (line.startsWith('- [x] ') || line.startsWith('- [ ] ')) {
        const isChecked = line.startsWith('- [x] ');
        const itemText = line.replace(/- \[[ x]\] /, '');
        rendered.push(
          <div key={index} className="flex items-center gap-2 my-1 text-xs text-neutral-300">
            <input 
              type="checkbox" 
              checked={isChecked} 
              readOnly 
              className="rounded border-white/20 bg-neutral-800 text-indigo-500 pointer-events-none" 
            />
            <span className={isChecked ? 'line-through text-neutral-500' : ''}>{itemText}</span>
          </div>
        );
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        rendered.push(
          <li key={index} className="text-xs text-neutral-300 ml-4 list-disc my-0.5">
            {line.replace(/^[-*] /, '')}
          </li>
        );
      } else if (line.startsWith('> ')) {
        rendered.push(
          <blockquote key={index} className="pl-3 border-l-2 border-indigo-500 text-xs italic text-neutral-400 my-2">
            {line.replace('> ', '')}
          </blockquote>
        );
      } else if (line.startsWith('---')) {
        rendered.push(<hr key={index} className="my-4 border-white/10" />);
      } else if (line.trim() === '') {
        rendered.push(<div key={index} className="h-2" />);
      } else {
        // Normal paragraph with basic bold/inline code formatting
        rendered.push(
          <p key={index} className="text-xs text-neutral-300 leading-relaxed my-1">
            {line}
          </p>
        );
      }
    });

    return rendered;
  };

  return (
    <div className="flex-1 flex h-[calc(100vh-3.5rem)] overflow-hidden bg-neutral-950">
      {/* Left Sidebar: Document List */}
      <div className="w-72 border-r border-white/10 bg-neutral-900/60 flex flex-col shrink-0">
        {/* Sidebar Header */}
        <div className="p-3.5 border-b border-white/10 space-y-2.5 shrink-0">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <BookOpen className="w-4 h-4 text-sky-400" />
              <span className="text-xs font-semibold text-white">Docs & Specs</span>
            </div>
            <button
              onClick={handleCreateDocument}
              className="flex items-center gap-1 px-2 py-1 text-xs bg-indigo-600 text-white rounded hover:bg-indigo-500 transition-colors shadow-sm"
              title="Create New Document"
            >
              <Plus className="w-3.5 h-3.5" />
              <span>New</span>
            </button>
          </div>

          {/* Search */}
          <div className="relative">
            <Search className="w-3.5 h-3.5 text-neutral-500 absolute left-2.5 top-1/2 -translate-y-1/2" />
            <input
              type="text"
              placeholder="Search docs..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-8 pr-2.5 py-1 text-xs bg-neutral-950 border border-white/10 rounded-md text-white placeholder-neutral-500 focus:outline-none focus:border-indigo-500"
            />
          </div>

          {/* Category Tabs */}
          <div className="flex items-center gap-1 overflow-x-auto no-scrollbar pt-0.5">
            {categories.map(cat => (
              <button
                key={cat}
                onClick={() => setCategoryFilter(cat)}
                className={`px-2 py-0.5 text-[11px] rounded transition-colors whitespace-nowrap ${
                  categoryFilter === cat
                    ? 'bg-neutral-800 text-white font-medium'
                    : 'text-neutral-400 hover:text-neutral-200'
                }`}
              >
                {cat}
              </button>
            ))}
          </div>
        </div>

        {/* Documents Scrollable List */}
        <div className="flex-1 overflow-y-auto p-2 space-y-1">
          {filteredDocs.length === 0 ? (
            <div className="py-8 text-center text-xs text-neutral-500">
              No documents found
            </div>
          ) : (
            filteredDocs.map(doc => {
              const isActive = doc.id === activeDoc?.id;
              return (
                <div
                  key={doc.id}
                  onClick={() => setActiveDocId(doc.id)}
                  className={`w-full text-left p-2.5 rounded-lg transition-all cursor-pointer group flex items-start justify-between gap-2 ${
                    isActive
                      ? 'bg-neutral-800 text-white shadow-sm'
                      : 'text-neutral-300 hover:bg-neutral-800/40'
                  }`}
                >
                  <div className="min-w-0 flex-1">
                    <div className="text-xs font-medium truncate leading-snug">
                      {doc.title || 'Untitled Document'}
                    </div>
                    {/* Unboxed metadata with typographic separator */}
                    <div className="text-[11px] text-neutral-400 mt-1 flex items-center gap-1.5">
                      <span>{doc.category}</span>
                      <span aria-hidden="true">·</span>
                      <span className="font-mono text-[10px]">{doc.updatedAt.slice(0, 10)}</span>
                    </div>
                  </div>

                  <div className="flex items-center gap-1 shrink-0 pt-0.5">
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        handleToggleStar(doc.id);
                      }}
                      className={`p-1 rounded hover:bg-neutral-700/50 transition-colors ${
                        doc.starred ? 'text-amber-400' : 'text-neutral-400 hover:text-neutral-200'
                      }`}
                      title={doc.starred ? 'Starred' : 'Star document'}
                    >
                      <Star className={`w-3.5 h-3.5 ${doc.starred ? 'fill-amber-400' : ''}`} />
                    </button>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        handleDeleteDoc(doc.id);
                      }}
                      className="p-1 rounded text-neutral-400 hover:text-rose-400 opacity-0 group-hover:opacity-100 hover:bg-neutral-700/50 transition-all"
                      title="Delete document"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>
              );
            })
          )}
        </div>
      </div>

      {/* Main Document Workspace */}
      {activeDoc ? (
        <div className="flex-1 flex flex-col h-full overflow-hidden bg-neutral-950">
          {/* Document Top Bar */}
          <div className="px-6 py-3 border-b border-white/10 bg-neutral-900/40 flex items-center justify-between gap-4 shrink-0">
            {/* Title editing */}
            <div className="flex-1 min-w-0">
              <input
                type="text"
                value={activeDoc.title}
                onChange={(e) => handleUpdateTitle(e.target.value)}
                className="w-full bg-transparent text-sm font-bold text-white focus:outline-none focus:border-b focus:border-indigo-500"
                placeholder="Document title..."
              />
              <div className="text-[11px] text-neutral-400 flex items-center gap-2 mt-0.5">
                <span className="font-mono">{wordCount} words</span>
                <span aria-hidden="true">·</span>
                <span>{readTimeMin} min read</span>
                <span aria-hidden="true">·</span>
                <span className="font-mono">Updated {activeDoc.updatedAt.slice(0, 16).replace('T', ' ')}</span>
              </div>
            </div>

            {/* Actions: View toggle, template insert, download */}
            <div className="flex items-center gap-2 shrink-0">
              {/* Template shortcuts */}
              <div className="hidden lg:flex items-center gap-1 border-r border-white/10 pr-2">
                <button
                  onClick={() => handleInsertTemplate('rfc')}
                  className="px-2 py-1 text-[11px] text-neutral-400 hover:text-white hover:bg-neutral-800 rounded transition-colors"
                >
                  + RFC
                </button>
                <button
                  onClick={() => handleInsertTemplate('spec')}
                  className="px-2 py-1 text-[11px] text-neutral-400 hover:text-white hover:bg-neutral-800 rounded transition-colors"
                >
                  + Spec
                </button>
                <button
                  onClick={() => handleInsertTemplate('meeting')}
                  className="px-2 py-1 text-[11px] text-neutral-400 hover:text-white hover:bg-neutral-800 rounded transition-colors"
                >
                  + Notes
                </button>
              </div>

              {/* View Mode Toggle */}
              <div className="flex items-center p-1 bg-neutral-900 border border-white/10 rounded-lg">
                <button
                  onClick={() => setViewMode('edit')}
                  className={`p-1.5 rounded-md transition-colors ${
                    viewMode === 'edit' ? 'bg-neutral-800 text-white' : 'text-neutral-400 hover:text-white'
                  }`}
                  title="Editor Only"
                >
                  <Edit3 className="w-3.5 h-3.5" />
                </button>
                <button
                  onClick={() => setViewMode('split')}
                  className={`p-1.5 rounded-md transition-colors ${
                    viewMode === 'split' ? 'bg-neutral-800 text-white' : 'text-neutral-400 hover:text-white'
                  }`}
                  title="Split View"
                >
                  <Columns className="w-3.5 h-3.5" />
                </button>
                <button
                  onClick={() => setViewMode('preview')}
                  className={`p-1.5 rounded-md transition-colors ${
                    viewMode === 'preview' ? 'bg-neutral-800 text-white' : 'text-neutral-400 hover:text-white'
                  }`}
                  title="Preview Only"
                >
                  <Eye className="w-3.5 h-3.5" />
                </button>
              </div>

              <button
                onClick={handleDownloadMarkdown}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-neutral-300 hover:text-white bg-neutral-800/80 hover:bg-neutral-800 border border-white/10 rounded-lg transition-colors"
                title="Download Markdown"
              >
                <Download className="w-3.5 h-3.5" />
                <span className="hidden sm:inline">Export</span>
              </button>
            </div>
          </div>

          {/* Document Content Panes */}
          <div className="flex-1 flex overflow-hidden">
            {/* Markdown Textarea Editor */}
            {(viewMode === 'edit' || viewMode === 'split') && (
              <div className={`h-full flex flex-col ${viewMode === 'split' ? 'w-1/2 border-r border-white/10' : 'w-full'}`}>
                <textarea
                  value={activeDoc.content}
                  onChange={(e) => handleUpdateContent(e.target.value)}
                  placeholder="Type markdown content here..."
                  className="flex-1 w-full bg-neutral-950 p-6 text-xs text-neutral-200 font-mono leading-relaxed resize-none focus:outline-none selection:bg-indigo-500/30"
                  spellCheck="false"
                />
              </div>
            )}

            {/* Markdown Live Preview */}
            {(viewMode === 'preview' || viewMode === 'split') && (
              <div className={`h-full overflow-y-auto p-8 bg-neutral-950 ${viewMode === 'split' ? 'w-1/2' : 'w-full'}`}>
                <div className="max-w-2xl mx-auto prose prose-invert">
                  {renderMarkdown(activeDoc.content)}
                </div>
              </div>
            )}
          </div>
        </div>
      ) : (
        <div className="flex-1 flex flex-col items-center justify-center text-center p-8 text-neutral-500">
          <FileText className="w-8 h-8 mb-2 text-neutral-600" />
          <p className="text-sm font-medium">Select or create a document</p>
        </div>
      )}
    </div>
  );
};
