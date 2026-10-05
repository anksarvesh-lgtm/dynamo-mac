import React, { useState, useRef, useCallback } from 'react';
import { CanvasNode, CanvasEdge, NodeType } from '../../types';
import { 
  Server, 
  Database, 
  Lightbulb, 
  CheckSquare, 
  HelpCircle, 
  Share2, 
  Plus, 
  ZoomIn, 
  ZoomOut, 
  Maximize2, 
  Trash2, 
  Move,
  Link,
  X
} from 'lucide-react';

interface FlowCanvasProps {
  nodes: CanvasNode[];
  edges: CanvasEdge[];
  onUpdateNodes: (nodes: CanvasNode[]) => void;
  onUpdateEdges: (edges: CanvasEdge[]) => void;
}

export const FlowCanvas: React.FC<FlowCanvasProps> = ({
  nodes,
  edges,
  onUpdateNodes,
  onUpdateEdges
}) => {
  const [zoom, setZoom] = useState(1);
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const [isPanning, setIsPanning] = useState(false);
  const [panStart, setPanStart] = useState({ x: 0, y: 0 });

  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null);
  const [draggingNodeId, setDraggingNodeId] = useState<string | null>(null);
  const [dragOffset, setDragOffset] = useState({ x: 0, y: 0 });

  // Connecting mode
  const [connectingSourceId, setConnectingSourceId] = useState<string | null>(null);

  // New Node Modal
  const [isAddingNode, setIsAddingNode] = useState(false);
  const [newNodeTitle, setNewNodeTitle] = useState('');
  const [newNodeDesc, setNewNodeDesc] = useState('');
  const [newNodeType, setNewNodeType] = useState<NodeType>('service');
  const [newNodeTags, setNewNodeTags] = useState('Service, API');

  const containerRef = useRef<HTMLDivElement>(null);

  const getNodeIcon = (type: NodeType) => {
    switch (type) {
      case 'service': return <Server className="w-4 h-4 text-indigo-400" />;
      case 'database': return <Database className="w-4 h-4 text-emerald-400" />;
      case 'idea': return <Lightbulb className="w-4 h-4 text-amber-400" />;
      case 'task': return <CheckSquare className="w-4 h-4 text-sky-400" />;
      case 'decision': return <HelpCircle className="w-4 h-4 text-rose-400" />;
      case 'output': return <Share2 className="w-4 h-4 text-violet-400" />;
    }
  };

  // Node Dragging
  const handleNodeMouseDown = (e: React.MouseEvent, node: CanvasNode) => {
    e.stopPropagation();
    if (connectingSourceId) {
      // Complete connection
      if (connectingSourceId !== node.id) {
        const edgeExists = edges.some(
          edge => (edge.source === connectingSourceId && edge.target === node.id) ||
                  (edge.source === node.id && edge.target === connectingSourceId)
        );
        if (!edgeExists) {
          const newEdge: CanvasEdge = {
            id: `edge-${Date.now()}`,
            source: connectingSourceId,
            target: node.id,
            label: 'Connection'
          };
          onUpdateEdges([...edges, newEdge]);
        }
      }
      setConnectingSourceId(null);
      return;
    }

    setSelectedNodeId(node.id);
    setDraggingNodeId(node.id);
    setDragOffset({
      x: e.clientX / zoom - node.x,
      y: e.clientY / zoom - node.y
    });
  };

  // Canvas Panning
  const handleCanvasMouseDown = (e: React.MouseEvent) => {
    if (e.button === 0 && !draggingNodeId) {
      setIsPanning(true);
      setPanStart({ x: e.clientX - pan.x, y: e.clientY - pan.y });
      setSelectedNodeId(null);
      setConnectingSourceId(null);
    }
  };

  const handleMouseMove = useCallback((e: React.MouseEvent) => {
    if (draggingNodeId) {
      const newX = Math.round(e.clientX / zoom - dragOffset.x);
      const newY = Math.round(e.clientY / zoom - dragOffset.y);
      onUpdateNodes(
        nodes.map(n => n.id === draggingNodeId ? { ...n, x: Math.max(20, newX), y: Math.max(20, newY) } : n)
      );
    } else if (isPanning) {
      setPan({
        x: e.clientX - panStart.x,
        y: e.clientY - panStart.y
      });
    }
  }, [draggingNodeId, isPanning, dragOffset, zoom, panStart, nodes, onUpdateNodes]);

  const handleMouseUp = () => {
    setDraggingNodeId(null);
    setIsPanning(false);
  };

  // Delete selected node and associated edges
  const handleDeleteNode = (nodeId: string) => {
    onUpdateNodes(nodes.filter(n => n.id !== nodeId));
    onUpdateEdges(edges.filter(e => e.source !== nodeId && e.target !== nodeId));
    if (selectedNodeId === nodeId) setSelectedNodeId(null);
  };

  // Add new node
  const handleCreateNode = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newNodeTitle.trim()) return;

    const tagsArray = newNodeTags.split(',').map(t => t.trim()).filter(Boolean);
    const newNode: CanvasNode = {
      id: `node-${Date.now()}`,
      title: newNodeTitle.trim(),
      description: newNodeDesc.trim() || 'New node element',
      type: newNodeType,
      x: 350 - pan.x / zoom + (Math.random() * 80 - 40),
      y: 250 - pan.y / zoom + (Math.random() * 80 - 40),
      status: 'active',
      tags: tagsArray.length > 0 ? tagsArray : ['Custom']
    };

    onUpdateNodes([...nodes, newNode]);
    setSelectedNodeId(newNode.id);
    setIsAddingNode(false);
    setNewNodeTitle('');
    setNewNodeDesc('');
  };

  // Calculate Bezier Curve between node centers
  const renderEdge = (edge: CanvasEdge) => {
    const sourceNode = nodes.find(n => n.id === edge.source);
    const targetNode = nodes.find(n => n.id === edge.target);
    if (!sourceNode || !targetNode) return null;

    const NODE_WIDTH = 260;
    const NODE_HEIGHT = 120;

    const sourceCenter = { x: sourceNode.x + NODE_WIDTH / 2, y: sourceNode.y + NODE_HEIGHT / 2 };
    const targetCenter = { x: targetNode.x + NODE_WIDTH / 2, y: targetNode.y + NODE_HEIGHT / 2 };

    const dx = targetCenter.x - sourceCenter.x;
    const dy = targetCenter.y - sourceCenter.y;
    const curvature = Math.max(40, Math.min(Math.abs(dx) * 0.5, 180));

    // Choose ports based on relative direction
    let startX = sourceCenter.x;
    let startY = sourceCenter.y;
    let endX = targetCenter.x;
    let endY = targetCenter.y;

    if (Math.abs(dx) > Math.abs(dy)) {
      if (dx > 0) {
        startX = sourceNode.x + NODE_WIDTH;
        endX = targetNode.x;
      } else {
        startX = sourceNode.x;
        endX = targetNode.x + NODE_WIDTH;
      }
    } else {
      if (dy > 0) {
        startY = sourceNode.y + NODE_HEIGHT;
        endY = targetNode.y;
      } else {
        startY = sourceNode.y;
        endY = targetNode.y + NODE_HEIGHT;
      }
    }

    const controlX1 = startX + (dx > 0 ? curvature : -curvature);
    const controlY1 = startY;
    const controlX2 = endX - (dx > 0 ? curvature : -curvature);
    const controlY2 = endY;

    const pathD = `M ${startX} ${startY} C ${controlX1} ${controlY1}, ${controlX2} ${controlY2}, ${endX} ${endY}`;
    const midX = (startX + endX) / 2;
    const midY = (startY + endY) / 2;

    return (
      <g key={edge.id} className="group cursor-pointer">
        <path
          d={pathD}
          fill="none"
          stroke={edge.dashed ? '#64748b' : '#6366f1'}
          strokeWidth="2"
          strokeDasharray={edge.dashed ? '6 6' : undefined}
          markerEnd="url(#arrowhead)"
          className="transition-colors group-hover:stroke-indigo-400"
        />
        {/* Wider transparent path for easy click to delete edge */}
        <path
          d={pathD}
          fill="none"
          stroke="transparent"
          strokeWidth="16"
          onClick={(e) => {
            e.stopPropagation();
            onUpdateEdges(edges.filter(item => item.id !== edge.id));
          }}
        />
        {edge.label && (
          <g transform={`translate(${midX}, ${midY})`}>
            <rect
              x="-48"
              y="-10"
              width="96"
              height="20"
              rx="4"
              fill="#18181b"
              stroke="#27272a"
              strokeWidth="1"
            />
            <text
              textAnchor="middle"
              y="4"
              fill="#a1a1aa"
              fontSize="10"
              fontFamily="monospace"
              className="select-none pointer-events-none"
            >
              {edge.label}
            </text>
          </g>
        )}
      </g>
    );
  };

  return (
    <div className="relative w-full h-[calc(100vh-3.5rem)] overflow-hidden bg-neutral-950 flex flex-col select-none">
      {/* Top Toolbar */}
      <div className="absolute top-4 left-4 z-20 flex items-center gap-2 bg-neutral-900/90 border border-white/10 rounded-lg p-1.5 shadow-lg backdrop-blur-md">
        <button
          onClick={() => setIsAddingNode(true)}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-white bg-indigo-600 rounded-md hover:bg-indigo-500 transition-colors shadow-sm"
        >
          <Plus className="w-3.5 h-3.5" />
          <span>Add Node</span>
        </button>

        <div className="h-4 w-px bg-white/10 mx-1" />

        <button
          onClick={() => setZoom(prev => Math.min(prev + 0.15, 2.0))}
          className="p-1.5 text-neutral-400 hover:text-white rounded-md hover:bg-neutral-800 transition-colors"
          title="Zoom In"
        >
          <ZoomIn className="w-4 h-4" />
        </button>
        <span className="text-[11px] font-mono tabular-nums text-neutral-400 px-1 min-w-[40px] text-center">
          {Math.round(zoom * 100)}%
        </span>
        <button
          onClick={() => setZoom(prev => Math.max(prev - 0.15, 0.4))}
          className="p-1.5 text-neutral-400 hover:text-white rounded-md hover:bg-neutral-800 transition-colors"
          title="Zoom Out"
        >
          <ZoomOut className="w-4 h-4" />
        </button>
        <button
          onClick={() => { setZoom(1); setPan({ x: 0, y: 0 }); }}
          className="p-1.5 text-neutral-400 hover:text-white rounded-md hover:bg-neutral-800 transition-colors"
          title="Reset Canvas View"
        >
          <Maximize2 className="w-4 h-4" />
        </button>
      </div>

      {/* Connection Mode Helper Notification */}
      {connectingSourceId && (
        <div className="absolute top-4 left-1/2 -translate-x-1/2 z-20 bg-indigo-950/90 border border-indigo-500/40 text-indigo-200 text-xs px-4 py-2 rounded-lg shadow-xl backdrop-blur-md flex items-center gap-3">
          <Link className="w-4 h-4 text-indigo-400 animate-pulse" />
          <span>Click any target node to create a connection</span>
          <button 
            onClick={() => setConnectingSourceId(null)}
            className="text-indigo-400 hover:text-white ml-2 text-xs font-mono"
          >
            Cancel
          </button>
        </div>
      )}

      {/* Canvas Meta Legend */}
      <div className="absolute bottom-4 left-4 z-20 hidden md:flex items-center gap-4 bg-neutral-900/80 border border-white/10 rounded-lg px-3 py-2 text-[11px] text-neutral-400 backdrop-blur-sm">
        <div className="flex items-center gap-1.5">
          <Move className="w-3.5 h-3.5 text-neutral-500" />
          <span>Drag node or canvas to navigate</span>
        </div>
        <span className="text-neutral-600">·</span>
        <div className="flex items-center gap-1.5">
          <span className="w-2 h-2 rounded-full bg-indigo-500" />
          <span>{nodes.length} Nodes</span>
        </div>
        <span className="text-neutral-600">·</span>
        <div className="flex items-center gap-1.5">
          <span className="w-2 h-2 rounded-full bg-emerald-500" />
          <span>{edges.length} Connections</span>
        </div>
      </div>

      {/* Main Interactive Canvas Area */}
      <div
        ref={containerRef}
        onMouseDown={handleCanvasMouseDown}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        className={`w-full h-full relative cursor-grab active:cursor-grabbing bg-neutral-950`}
        style={{
          backgroundImage: `radial-gradient(circle, rgba(255, 255, 255, 0.08) 1px, transparent 1px)`,
          backgroundSize: `${24 * zoom}px ${24 * zoom}px`,
          backgroundPosition: `${pan.x}px ${pan.y}px`
        }}
      >
        <div
          className="absolute origin-top-left pointer-events-none"
          style={{
            transform: `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`,
            width: '4000px',
            height: '4000px'
          }}
        >
          {/* SVG Layer for Connections */}
          <svg className="absolute inset-0 w-full h-full overflow-visible pointer-events-auto">
            <defs>
              <marker
                id="arrowhead"
                markerWidth="8"
                markerHeight="6"
                refX="7"
                refY="3"
                orient="auto"
              >
                <polygon points="0 0, 8 3, 0 6" fill="#6366f1" />
              </marker>
            </defs>
            {edges.map(renderEdge)}
          </svg>

          {/* Interactive Nodes */}
          {nodes.map(node => {
            const isSelected = selectedNodeId === node.id;
            const isSource = connectingSourceId === node.id;

            return (
              <div
                key={node.id}
                onMouseDown={(e) => handleNodeMouseDown(e, node)}
                style={{
                  transform: `translate(${node.x}px, ${node.y}px)`,
                  width: '260px'
                }}
                className={`absolute pointer-events-auto bg-neutral-900 border rounded-xl p-3.5 shadow-xl transition-shadow select-none group ${
                  isSelected
                    ? 'border-indigo-500 ring-2 ring-indigo-500/20 shadow-indigo-500/10'
                    : isSource
                    ? 'border-indigo-400 ring-2 ring-indigo-400/40 animate-pulse'
                    : 'border-white/10 hover:border-white/20'
                }`}
              >
                {/* Node Header */}
                <div className="flex items-start justify-between gap-2 mb-2">
                  <div className="flex items-center gap-2">
                    <div className="p-1 rounded-md bg-neutral-800/80 border border-white/5">
                      {getNodeIcon(node.type)}
                    </div>
                    <span className="text-xs font-semibold text-white tracking-tight leading-snug">
                      {node.title}
                    </span>
                  </div>
                  {/* Actions on hover/select */}
                  <div className="flex items-center gap-1 opacity-80 group-hover:opacity-100 transition-opacity">
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        setConnectingSourceId(node.id);
                      }}
                      className="p-1 text-neutral-400 hover:text-indigo-400 rounded hover:bg-neutral-800 transition-colors"
                      title="Connect to another node"
                    >
                      <Link className="w-3.5 h-3.5" />
                    </button>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        handleDeleteNode(node.id);
                      }}
                      className="p-1 text-neutral-400 hover:text-rose-400 rounded hover:bg-neutral-800 transition-colors"
                      title="Delete Node"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>

                {/* Description */}
                <p className="text-[11px] text-neutral-400 line-clamp-2 mb-3 leading-relaxed">
                  {node.description}
                </p>

                {/* Footer with Unboxed Metadata & Status */}
                <div className="pt-2 border-t border-white/5 flex items-center justify-between text-[10px] text-neutral-400">
                  <div className="flex items-center gap-1.5 overflow-hidden">
                    {node.tags.slice(0, 2).map((tag, i) => (
                      <React.Fragment key={tag}>
                        <span className="text-neutral-400 truncate">{tag}</span>
                        {i < Math.min(node.tags.length - 1, 1) && (
                          <span className="text-neutral-600" aria-hidden="true">·</span>
                        )}
                      </React.Fragment>
                    ))}
                  </div>
                  <div className="flex items-center gap-1 shrink-0">
                    <span 
                      className={`w-1.5 h-1.5 rounded-full ${
                        node.status === 'active' 
                          ? 'bg-emerald-500' 
                          : node.status === 'in_review' 
                          ? 'bg-amber-500' 
                          : 'bg-neutral-500'
                      }`}
                    />
                    <span className="text-neutral-400 font-mono text-[9px] uppercase tracking-wider">
                      {node.status.replace('_', ' ')}
                    </span>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Add Node Modal */}
      {isAddingNode && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
          <div className="bg-neutral-900 border border-white/10 rounded-xl p-5 max-w-md w-full shadow-2xl">
            <div className="flex items-center justify-between pb-3 border-b border-white/10 mb-4">
              <h3 className="text-sm font-semibold text-white">Create Canvas Node</h3>
              <button 
                onClick={() => setIsAddingNode(false)}
                className="text-neutral-400 hover:text-white"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <form onSubmit={handleCreateNode} className="space-y-4">
              <div>
                <label className="block text-xs font-medium text-neutral-300 mb-1">
                  Title
                </label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Auth Gateway, Postgres Shard"
                  value={newNodeTitle}
                  onChange={(e) => setNewNodeTitle(e.target.value)}
                  className="w-full bg-neutral-950 border border-white/10 rounded-lg px-3 py-2 text-xs text-white placeholder-neutral-500 focus:outline-none focus:border-indigo-500"
                />
              </div>

              <div>
                <label className="block text-xs font-medium text-neutral-300 mb-1">
                  Node Type
                </label>
                <div className="grid grid-cols-3 gap-2">
                  {(['service', 'database', 'task', 'idea', 'decision', 'output'] as NodeType[]).map(t => (
                    <button
                      type="button"
                      key={t}
                      onClick={() => setNewNodeType(t)}
                      className={`flex items-center gap-2 p-2 rounded-lg border text-xs capitalize transition-colors ${
                        newNodeType === t
                          ? 'border-indigo-500 bg-indigo-500/10 text-white font-medium'
                          : 'border-white/5 bg-neutral-950 text-neutral-400 hover:text-white'
                      }`}
                    >
                      {getNodeIcon(t)}
                      <span>{t}</span>
                    </button>
                  ))}
                </div>
              </div>

              <div>
                <label className="block text-xs font-medium text-neutral-300 mb-1">
                  Description
                </label>
                <textarea
                  rows={2}
                  placeholder="Summary of responsibilities or architectural function..."
                  value={newNodeDesc}
                  onChange={(e) => setNewNodeDesc(e.target.value)}
                  className="w-full bg-neutral-950 border border-white/10 rounded-lg px-3 py-2 text-xs text-white placeholder-neutral-500 focus:outline-none focus:border-indigo-500 resize-none"
                />
              </div>

              <div>
                <label className="block text-xs font-medium text-neutral-300 mb-1">
                  Tags (comma separated)
                </label>
                <input
                  type="text"
                  placeholder="e.g. Go, REST, Infra"
                  value={newNodeTags}
                  onChange={(e) => setNewNodeTags(e.target.value)}
                  className="w-full bg-neutral-950 border border-white/10 rounded-lg px-3 py-2 text-xs text-white placeholder-neutral-500 focus:outline-none focus:border-indigo-500"
                />
              </div>

              <div className="flex justify-end gap-2 pt-2 border-t border-white/10">
                <button
                  type="button"
                  onClick={() => setIsAddingNode(false)}
                  className="px-3 py-1.5 text-xs text-neutral-400 hover:text-white rounded-lg hover:bg-neutral-800 transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="px-4 py-1.5 text-xs font-medium text-white bg-indigo-600 rounded-lg hover:bg-indigo-500 transition-colors shadow-sm"
                >
                  Add Node
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
