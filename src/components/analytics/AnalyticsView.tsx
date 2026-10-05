import React, { useState } from 'react';
import { AnalyticsMetric } from '../../types';
import { 
  TrendingUp, 
  CheckCircle2, 
  GitPullRequest, 
  Clock, 
  Download, 
  Plus, 
  X,
  Activity
} from 'lucide-react';

interface AnalyticsViewProps {
  metrics: AnalyticsMetric[];
  onAddMetric: (metric: AnalyticsMetric) => void;
}

export const AnalyticsView: React.FC<AnalyticsViewProps> = ({
  metrics,
  onAddMetric
}) => {
  const [selectedSprintId, setSelectedSprintId] = useState<string>(
    metrics[metrics.length - 1]?.id || ''
  );
  const [isAddingMetric, setIsAddingMetric] = useState(false);

  // Form states for new metric entry
  const [formSprint, setFormSprint] = useState('Sprint 34');
  const [formVelocity, setFormVelocity] = useState(58);
  const [formCompletedTasks, setFormCompletedTasks] = useState(42);
  const [formPrMerged, setFormPrMerged] = useState(57);
  const [formPassRate, setFormPassRate] = useState(99.9);
  const [formResponseTime, setFormResponseTime] = useState(115);

  const activeMetric = metrics.find(m => m.id === selectedSprintId) || metrics[metrics.length - 1];

  // Export to CSV
  const handleExportCSV = () => {
    const headers = 'Sprint,Date,Velocity(pts),CompletedTasks,PRsMerged,TestPassRate(%),Latency(ms)\n';
    const rows = metrics.map(m => 
      `${m.sprint},${m.date},${m.velocity},${m.completedTasks},${m.prMerged},${m.testPassRate},${m.responseTimeMs}`
    ).join('\n');
    const blob = new Blob([headers + rows], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.setAttribute('download', `stratos_sprint_metrics_${new Date().toISOString().slice(0, 10)}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  const handleCreateMetric = (e: React.FormEvent) => {
    e.preventDefault();
    const newEntry: AnalyticsMetric = {
      id: `m-${Date.now()}`,
      sprint: formSprint,
      date: new Date().toISOString().slice(0, 10),
      velocity: Number(formVelocity),
      completedTasks: Number(formCompletedTasks),
      prMerged: Number(formPrMerged),
      testPassRate: Number(formPassRate),
      responseTimeMs: Number(formResponseTime)
    };
    onAddMetric(newEntry);
    setSelectedSprintId(newEntry.id);
    setIsAddingMetric(false);
  };

  // SVG Chart Geometry calculations
  const maxVelocity = Math.max(...metrics.map(m => m.velocity), 60);
  const chartWidth = 500;
  const chartHeight = 180;
  const paddingX = 40;
  const paddingY = 25;

  const points = metrics.map((m, index) => {
    const x = paddingX + (index / (metrics.length - 1 || 1)) * (chartWidth - 2 * paddingX);
    const y = chartHeight - paddingY - (m.velocity / maxVelocity) * (chartHeight - 2 * paddingY);
    return { x, y, metric: m };
  });

  const lineD = points.length > 0 
    ? points.reduce((acc, p, i) => `${acc} ${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`, '')
    : '';

  const areaD = points.length > 0 
    ? `${lineD} L ${points[points.length - 1].x} ${chartHeight - paddingY} L ${points[0].x} ${chartHeight - paddingY} Z`
    : '';

  return (
    <div className="flex-1 flex flex-col h-[calc(100vh-3.5rem)] overflow-y-auto bg-neutral-950 p-6">
      <div className="max-w-7xl w-full mx-auto space-y-6">
        {/* Top Header & Actions */}
        <div className="flex flex-wrap items-center justify-between gap-4 border-b border-white/10 pb-4">
          <div>
            <h1 className="text-lg font-bold text-white tracking-tight">Engineering Velocity & Observability</h1>
            <p className="text-xs text-neutral-400 mt-0.5">
              Live sprint metrics, production latency benchmarks, and team throughput
            </p>
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={handleExportCSV}
              className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-neutral-300 hover:text-white bg-neutral-900 border border-white/10 rounded-lg hover:bg-neutral-800 transition-colors"
            >
              <Download className="w-3.5 h-3.5" />
              <span>Export CSV</span>
            </button>
            <button
              onClick={() => setIsAddingMetric(true)}
              className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-white bg-indigo-600 rounded-lg hover:bg-indigo-500 transition-colors shadow-sm"
            >
              <Plus className="w-3.5 h-3.5" />
              <span>Log Sprint Entry</span>
            </button>
          </div>
        </div>

        {/* 4 KPI Summary Cards */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {/* Card 1: Velocity */}
          <div className="bg-neutral-900/80 border border-white/10 rounded-xl p-4">
            <div className="flex items-center justify-between text-neutral-400 mb-2">
              <span className="text-xs font-medium">Sprint Velocity</span>
              <TrendingUp className="w-4 h-4 text-indigo-400" />
            </div>
            <div className="flex items-baseline gap-2">
              <span className="text-2xl font-bold font-mono tabular-nums text-white">
                {activeMetric?.velocity || 0}
              </span>
              <span className="text-xs text-neutral-500">story pts</span>
            </div>
            <div className="text-[11px] text-emerald-400 mt-2 flex items-center gap-1">
              <span>+18.2%</span>
              <span className="text-neutral-500">vs 3 sprints ago</span>
            </div>
          </div>

          {/* Card 2: Tasks Done */}
          <div className="bg-neutral-900/80 border border-white/10 rounded-xl p-4">
            <div className="flex items-center justify-between text-neutral-400 mb-2">
              <span className="text-xs font-medium">Completed Tasks</span>
              <CheckCircle2 className="w-4 h-4 text-emerald-400" />
            </div>
            <div className="flex items-baseline gap-2">
              <span className="text-2xl font-bold font-mono tabular-nums text-white">
                {activeMetric?.completedTasks || 0}
              </span>
              <span className="text-xs text-neutral-500">issues</span>
            </div>
            <div className="text-[11px] text-emerald-400 mt-2 flex items-center gap-1">
              <span>94.8%</span>
              <span className="text-neutral-500">completion rate</span>
            </div>
          </div>

          {/* Card 3: Pull Requests */}
          <div className="bg-neutral-900/80 border border-white/10 rounded-xl p-4">
            <div className="flex items-center justify-between text-neutral-400 mb-2">
              <span className="text-xs font-medium">PRs Merged</span>
              <GitPullRequest className="w-4 h-4 text-sky-400" />
            </div>
            <div className="flex items-baseline gap-2">
              <span className="text-2xl font-bold font-mono tabular-nums text-white">
                {activeMetric?.prMerged || 0}
              </span>
              <span className="text-xs text-neutral-500">merged</span>
            </div>
            <div className="text-[11px] text-neutral-400 mt-2 flex items-center gap-1">
              <span className="font-mono tabular-nums">{activeMetric?.testPassRate}%</span>
              <span className="text-neutral-500">CI pass rate</span>
            </div>
          </div>

          {/* Card 4: p99 Latency */}
          <div className="bg-neutral-900/80 border border-white/10 rounded-xl p-4">
            <div className="flex items-center justify-between text-neutral-400 mb-2">
              <span className="text-xs font-medium">p99 Edge Latency</span>
              <Clock className="w-4 h-4 text-amber-400" />
            </div>
            <div className="flex items-baseline gap-2">
              <span className="text-2xl font-bold font-mono tabular-nums text-white">
                {activeMetric?.responseTimeMs || 0}
              </span>
              <span className="text-xs text-neutral-500">ms</span>
            </div>
            <div className="text-[11px] text-emerald-400 mt-2 flex items-center gap-1">
              <span>-28%</span>
              <span className="text-neutral-500">after cache rollout</span>
            </div>
          </div>
        </div>

        {/* Charts Section */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Chart 1: Sprint Velocity Trend Line & Area */}
          <div className="bg-neutral-900/60 border border-white/10 rounded-xl p-5">
            <div className="flex items-center justify-between mb-4">
              <div>
                <h3 className="text-xs font-semibold text-white">Velocity Trajectory</h3>
                <p className="text-[11px] text-neutral-400">Story points completed per 2-week cycle</p>
              </div>
              <div className="flex items-center gap-2 text-[10px] text-neutral-400 font-mono">
                <span className="w-2.5 h-0.5 bg-indigo-500 inline-block" />
                <span>Story Points</span>
              </div>
            </div>

            <div className="w-full overflow-x-auto">
              <svg viewBox={`0 0 ${chartWidth} ${chartHeight}`} className="w-full h-48 overflow-visible">
                <defs>
                  <linearGradient id="velocityGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="#6366f1" stopOpacity="0.35" />
                    <stop offset="100%" stopColor="#6366f1" stopOpacity="0.0" />
                  </linearGradient>
                </defs>

                {/* Horizontal reference grid lines */}
                {[0.25, 0.5, 0.75, 1].map((ratio) => {
                  const y = chartHeight - paddingY - ratio * (chartHeight - 2 * paddingY);
                  return (
                    <g key={ratio}>
                      <line
                        x1={paddingX}
                        y1={y}
                        x2={chartWidth - paddingX}
                        y2={y}
                        stroke="rgba(255, 255, 255, 0.05)"
                        strokeDasharray="4 4"
                      />
                      <text
                        x={paddingX - 8}
                        y={y + 3}
                        fill="#71717a"
                        fontSize="9"
                        textAnchor="end"
                        fontFamily="monospace"
                      >
                        {Math.round(ratio * maxVelocity)}
                      </text>
                    </g>
                  );
                })}

                {/* Area under curve */}
                {areaD && <path d={areaD} fill="url(#velocityGrad)" />}

                {/* Trend line */}
                {lineD && (
                  <path
                    d={lineD}
                    fill="none"
                    stroke="#6366f1"
                    strokeWidth="2.5"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  />
                )}

                {/* Points */}
                {points.map((p) => {
                  const isSelected = p.metric.id === selectedSprintId;
                  return (
                    <g 
                      key={p.metric.id}
                      onClick={() => setSelectedSprintId(p.metric.id)}
                      className="cursor-pointer group"
                    >
                      <circle
                        cx={p.x}
                        cy={p.y}
                        r={isSelected ? 6 : 4}
                        fill={isSelected ? '#818cf8' : '#6366f1'}
                        stroke="#09090b"
                        strokeWidth="2"
                        className="transition-all group-hover:r-6"
                      />
                      <text
                        x={p.x}
                        y={p.y - 10}
                        textAnchor="middle"
                        fill="#ffffff"
                        fontSize="10"
                        fontFamily="monospace"
                        className={`tabular-nums font-semibold transition-opacity ${
                          isSelected ? 'opacity-100' : 'opacity-0 group-hover:opacity-100'
                        }`}
                      >
                        {p.metric.velocity} pts
                      </text>
                      <text
                        x={p.x}
                        y={chartHeight - 8}
                        textAnchor="middle"
                        fill="#a1a1aa"
                        fontSize="9"
                      >
                        {p.metric.sprint.replace('Sprint ', 'S')}
                      </text>
                    </g>
                  );
                })}
              </svg>
            </div>
          </div>

          {/* Chart 2: Comparative Throughput (Tasks vs PRs) */}
          <div className="bg-neutral-900/60 border border-white/10 rounded-xl p-5">
            <div className="flex items-center justify-between mb-4">
              <div>
                <h3 className="text-xs font-semibold text-white">Throughput Distribution</h3>
                <p className="text-[11px] text-neutral-400">Completed items vs merged pull requests</p>
              </div>
              <div className="flex items-center gap-3 text-[10px] text-neutral-400">
                <span className="flex items-center gap-1.5">
                  <span className="w-2.5 h-2.5 rounded-sm bg-emerald-500 inline-block" />
                  <span>Tasks</span>
                </span>
                <span className="flex items-center gap-1.5">
                  <span className="w-2.5 h-2.5 rounded-sm bg-sky-500 inline-block" />
                  <span>PRs</span>
                </span>
              </div>
            </div>

            <div className="space-y-3 pt-2">
              {metrics.map(m => {
                const maxVal = 60;
                const taskPct = (m.completedTasks / maxVal) * 100;
                const prPct = (m.prMerged / maxVal) * 100;

                return (
                  <div key={m.id} className="space-y-1">
                    <div className="flex items-center justify-between text-[11px] text-neutral-400 font-mono">
                      <span>{m.sprint}</span>
                      <span className="tabular-nums">
                        {m.completedTasks} tasks · {m.prMerged} PRs
                      </span>
                    </div>
                    <div className="grid grid-cols-2 gap-2 h-2.5 bg-neutral-950 rounded-full overflow-hidden p-0.5">
                      <div className="bg-neutral-800 rounded-full overflow-hidden">
                        <div
                          className="h-full bg-emerald-500 rounded-full transition-all duration-500"
                          style={{ width: `${taskPct}%` }}
                        />
                      </div>
                      <div className="bg-neutral-800 rounded-full overflow-hidden">
                        <div
                          className="h-full bg-sky-500 rounded-full transition-all duration-500"
                          style={{ width: `${prPct}%` }}
                        />
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>

        {/* Dense Historical Table */}
        <div className="bg-neutral-900/60 border border-white/10 rounded-xl overflow-hidden shadow-sm">
          <div className="p-4 border-b border-white/10 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Activity className="w-4 h-4 text-indigo-400" />
              <h3 className="text-xs font-semibold text-white">Historical Sprint Ledger</h3>
            </div>
            <span className="text-[11px] text-neutral-400 font-mono tabular-nums">
              Showing {metrics.length} recorded cycles
            </span>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse text-xs">
              <thead>
                <tr className="border-b border-white/10 bg-neutral-900/80 text-[10px] uppercase font-mono text-neutral-400">
                  <th className="py-2.5 px-4 font-medium">Sprint</th>
                  <th className="py-2.5 px-4 font-medium">Cycle Date</th>
                  <th className="py-2.5 px-4 font-medium text-right">Velocity</th>
                  <th className="py-2.5 px-4 font-medium text-right">Completed Tasks</th>
                  <th className="py-2.5 px-4 font-medium text-right">PRs Merged</th>
                  <th className="py-2.5 px-4 font-medium text-right">CI Pass Rate</th>
                  <th className="py-2.5 px-4 font-medium text-right">p99 Latency</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-white/5">
                {metrics.map(m => (
                  <tr
                    key={m.id}
                    onClick={() => setSelectedSprintId(m.id)}
                    className={`hover:bg-neutral-800/40 transition-colors cursor-pointer ${
                      m.id === selectedSprintId ? 'bg-neutral-800/60' : ''
                    }`}
                  >
                    <td className="py-2.5 px-4 font-semibold text-white">{m.sprint}</td>
                    <td className="py-2.5 px-4 font-mono text-neutral-400">{m.date}</td>
                    <td className="py-2.5 px-4 font-mono tabular-nums text-right text-indigo-300 font-medium">
                      {m.velocity} pts
                    </td>
                    <td className="py-2.5 px-4 font-mono tabular-nums text-right text-emerald-400">
                      {m.completedTasks}
                    </td>
                    <td className="py-2.5 px-4 font-mono tabular-nums text-right text-sky-400">
                      {m.prMerged}
                    </td>
                    <td className="py-2.5 px-4 font-mono tabular-nums text-right text-neutral-300">
                      {m.testPassRate}%
                    </td>
                    <td className="py-2.5 px-4 font-mono tabular-nums text-right text-amber-300">
                      {m.responseTimeMs} ms
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {/* Add Metric Modal */}
      {isAddingMetric && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in">
          <div className="bg-neutral-900 border border-white/10 rounded-xl p-5 max-w-md w-full shadow-2xl">
            <div className="flex items-center justify-between pb-3 border-b border-white/10 mb-4">
              <h3 className="text-sm font-semibold text-white">Log Sprint Metric</h3>
              <button 
                onClick={() => setIsAddingMetric(false)}
                className="text-neutral-400 hover:text-white"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <form onSubmit={handleCreateMetric} className="space-y-4">
              <div>
                <label className="block text-xs font-medium text-neutral-300 mb-1">
                  Sprint Name
                </label>
                <input
                  type="text"
                  required
                  value={formSprint}
                  onChange={(e) => setFormSprint(e.target.value)}
                  className="w-full bg-neutral-950 border border-white/10 rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-indigo-500"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-neutral-300 mb-1">
                    Velocity (Points)
                  </label>
                  <input
                    type="number"
                    min="1"
                    max="200"
                    value={formVelocity}
                    onChange={(e) => setFormVelocity(Number(e.target.value))}
                    className="w-full bg-neutral-950 border border-white/10 rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-indigo-500 font-mono"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-neutral-300 mb-1">
                    Completed Tasks
                  </label>
                  <input
                    type="number"
                    min="1"
                    max="200"
                    value={formCompletedTasks}
                    onChange={(e) => setFormCompletedTasks(Number(e.target.value))}
                    className="w-full bg-neutral-950 border border-white/10 rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-indigo-500 font-mono"
                  />
                </div>
              </div>

              <div className="grid grid-cols-3 gap-3">
                <div>
                  <label className="block text-xs font-medium text-neutral-300 mb-1">
                    PRs Merged
                  </label>
                  <input
                    type="number"
                    value={formPrMerged}
                    onChange={(e) => setFormPrMerged(Number(e.target.value))}
                    className="w-full bg-neutral-950 border border-white/10 rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-indigo-500 font-mono"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-neutral-300 mb-1">
                    Pass Rate (%)
                  </label>
                  <input
                    type="number"
                    step="0.1"
                    max="100"
                    value={formPassRate}
                    onChange={(e) => setFormPassRate(Number(e.target.value))}
                    className="w-full bg-neutral-950 border border-white/10 rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-indigo-500 font-mono"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-neutral-300 mb-1">
                    p99 Latency (ms)
                  </label>
                  <input
                    type="number"
                    value={formResponseTime}
                    onChange={(e) => setFormResponseTime(Number(e.target.value))}
                    className="w-full bg-neutral-950 border border-white/10 rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-indigo-500 font-mono"
                  />
                </div>
              </div>

              <div className="flex justify-end gap-2 pt-2 border-t border-white/10">
                <button
                  type="button"
                  onClick={() => setIsAddingMetric(false)}
                  className="px-3 py-1.5 text-xs text-neutral-400 hover:text-white rounded-lg hover:bg-neutral-800 transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="px-4 py-1.5 text-xs font-medium text-white bg-indigo-600 rounded-lg hover:bg-indigo-500 transition-colors shadow-sm"
                >
                  Save Entry
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
