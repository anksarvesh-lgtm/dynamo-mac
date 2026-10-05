import React, { useState } from 'react';
import { soundFx } from '../../utils/audioFeedback';
import { Activity, Sliders, Waves, Play, RotateCcw, Cpu } from 'lucide-react';

export const MotionLab: React.FC = () => {
  const [selectedSpring, setSelectedSpring] = useState<'expand' | 'collapse' | 'alertPop'>('expand');
  const [smoothingK, setSmoothingK] = useState<number>(24);
  const [testDropletY, setTestDropletY] = useState<number>(38);
  const [isSimulatingTransition, setIsSimulatingTransition] = useState<boolean>(false);
  const [transitionProgress, setTransitionProgress] = useState<number>(0);

  const springs = {
    expand: {
      name: 'expandSpring',
      response: 0.45,
      dampingFraction: 0.75,
      description: 'Weighted expansive momentum for opening full interactive dashboards.'
    },
    collapse: {
      name: 'collapseSpring',
      response: 0.36,
      dampingFraction: 0.86,
      description: 'Critically damped, snappy retraction with zero overshoot oscillation.'
    },
    alertPop: {
      name: 'alertPopSpring',
      response: 0.40,
      dampingFraction: 0.65,
      description: 'Energetic bouncy overshoot for high-priority peripheral and battery notifications.'
    }
  };

  const handleRunSimulation = () => {
    soundFx.playMorphPop(selectedSpring === 'alertPop' ? 520 : 440);
    setIsSimulatingTransition(true);
    setTransitionProgress(0);

    const startTime = performance.now();
    const duration = 650;

    const frame = (now: number) => {
      const elapsed = now - startTime;
      const t = Math.min(1, elapsed / duration);
      setTransitionProgress(t);
      if (t < 1) {
        requestAnimationFrame(frame);
      } else {
        setTimeout(() => setIsSimulatingTransition(false), 300);
      }
    };
    requestAnimationFrame(frame);
  };

  return (
    <div className="w-full bg-neutral-900/80 border border-neutral-800 rounded-2xl p-6 lg:p-8 backdrop-blur-xl space-y-8">
      {/* Title */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 pb-6 border-b border-neutral-800">
        <div>
          <div className="flex items-center gap-2 text-indigo-400 text-xs font-mono font-medium uppercase tracking-wider">
            <Activity className="w-4 h-4" />
            <span>Interactive Motion & Metal SDF Lab</span>
          </div>
          <h3 className="text-xl font-bold text-white mt-1">Physics & Shader Architecture</h3>
          <p className="text-sm text-neutral-400 mt-1 max-w-2xl">
            Simulate the exact iOS spring curves, Signed-Distance Field (SDF) smooth minimum (<code>smin</code>), and 3-phase staggered choreography defined in <code>ISLAND_MOTION_SPEC.md</code>.
          </p>
        </div>

        <button
          onClick={handleRunSimulation}
          disabled={isSimulatingTransition}
          className="flex items-center gap-2 px-4 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 text-white text-xs font-semibold shadow-lg shadow-indigo-600/25 transition-all active:scale-95 self-start md:self-auto"
        >
          <Play className="w-3.5 h-3.5" />
          <span>Run Choreography Cycle</span>
        </button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
        {/* Left Column: Spring Dynamics (7 cols) */}
        <div className="lg:col-span-7 space-y-6">
          <div className="flex items-center justify-between">
            <h4 className="text-sm font-semibold text-neutral-200 flex items-center gap-2">
              <Sliders className="w-4 h-4 text-indigo-400" />
              <span>Apple Continuous Spring Curves</span>
            </h4>
            <span className="text-xs font-mono text-neutral-500">SwiftUI Animation Parameters</span>
          </div>

          {/* Spring Selector Buttons */}
          <div className="grid grid-cols-3 gap-2">
            {(['expand', 'collapse', 'alertPop'] as const).map((key) => {
              const sp = springs[key];
              const isSelected = selectedSpring === key;
              return (
                <button
                  key={key}
                  onClick={() => {
                    soundFx.playTick();
                    setSelectedSpring(key);
                  }}
                  className={`p-3 rounded-xl border text-left transition-all ${
                    isSelected
                      ? 'bg-indigo-600/20 border-indigo-500 text-white shadow-sm'
                      : 'bg-neutral-950/60 border-neutral-800 text-neutral-400 hover:border-neutral-700'
                  }`}
                >
                  <div className="font-mono text-xs font-semibold">{sp.name}</div>
                  <div className="text-[11px] text-neutral-400 font-mono mt-1">
                    r: {sp.response}s • d: {sp.dampingFraction}
                  </div>
                </button>
              );
            })}
          </div>

          {/* Animated Curve Canvas */}
          <div className="p-4 rounded-xl bg-neutral-950 border border-neutral-800 space-y-3">
            <div className="flex items-center justify-between text-xs font-mono text-neutral-400">
              <span>Velocity Curve Simulation: <strong className="text-white">{springs[selectedSpring].name}</strong></span>
              <span className="text-[11px] text-indigo-400">{springs[selectedSpring].description}</span>
            </div>

            {/* SVG Spring Graph */}
            <div className="relative h-32 w-full bg-neutral-900/60 rounded-lg p-2 overflow-hidden border border-neutral-800/80">
              <svg className="w-full h-full overflow-visible" viewBox="0 0 500 100" preserveAspectRatio="none">
                {/* Gridlines */}
                <line x1="0" y1="20" x2="500" y2="20" stroke="#333" strokeDasharray="4 4" strokeWidth="0.8" />
                <line x1="0" y1="80" x2="500" y2="80" stroke="#333" strokeDasharray="4 4" strokeWidth="0.8" />

                {/* Simulated Curve Path */}
                {selectedSpring === 'expand' && (
                  <path
                    d="M 0 80 C 120 80, 180 15, 260 20 C 330 24, 400 20, 500 20"
                    fill="none"
                    stroke="#6366f1"
                    strokeWidth="3"
                  />
                )}
                {selectedSpring === 'collapse' && (
                  <path
                    d="M 0 20 C 100 20, 150 82, 230 80 C 300 79, 400 80, 500 80"
                    fill="none"
                    stroke="#10b981"
                    strokeWidth="3"
                  />
                )}
                {selectedSpring === 'alertPop' && (
                  <path
                    d="M 0 80 C 80 80, 120 5, 180 8 C 240 10, 270 28, 330 20 C 400 17, 450 20, 500 20"
                    fill="none"
                    stroke="#f59e0b"
                    strokeWidth="3"
                  />
                )}

                {/* Progress Marker if simulating */}
                {isSimulatingTransition && (
                  <circle
                    cx={transitionProgress * 500}
                    cy={selectedSpring === 'collapse' ? 80 - transitionProgress * 60 : 20 + (1 - transitionProgress) * 60}
                    r="5"
                    fill="#ffffff"
                    className="shadow-lg"
                  />
                )}
              </svg>
            </div>
          </div>

          {/* Phase-Staggered Content Pipeline */}
          <div className="p-4 rounded-xl bg-neutral-950 border border-neutral-800 space-y-3">
            <h5 className="text-xs font-semibold text-neutral-300 font-mono uppercase tracking-wider">
              3-Phase Choreography Pipeline (Zero Jank Protocol)
            </h5>
            <div className="grid grid-cols-3 gap-2 text-xs">
              <div className={`p-2.5 rounded-lg border transition-all ${
                isSimulatingTransition && transitionProgress < 0.35 
                  ? 'bg-rose-500/20 border-rose-500 text-rose-200' 
                  : 'bg-neutral-900 border-neutral-800 text-neutral-400'
              }`}>
                <div className="font-semibold text-neutral-200">Phase 1: Out</div>
                <div className="text-[10px] font-mono mt-0.5">0.00s – 0.15s</div>
                <div className="text-[11px] text-neutral-400 mt-1">Old content blurs (10pt) & fades to 0.</div>
              </div>

              <div className={`p-2.5 rounded-lg border transition-all ${
                isSimulatingTransition && transitionProgress >= 0.35 && transitionProgress < 0.75 
                  ? 'bg-indigo-500/20 border-indigo-500 text-indigo-200' 
                  : 'bg-neutral-900 border-neutral-800 text-neutral-400'
              }`}>
                <div className="font-semibold text-neutral-200">Phase 2: Morph</div>
                <div className="text-[10px] font-mono mt-0.5">Container Springs</div>
                <div className="text-[11px] text-neutral-400 mt-1">Black capsule changes geometry smoothly.</div>
              </div>

              <div className={`p-2.5 rounded-lg border transition-all ${
                isSimulatingTransition && transitionProgress >= 0.75 
                  ? 'bg-emerald-500/20 border-emerald-500 text-emerald-200' 
                  : 'bg-neutral-900 border-neutral-800 text-neutral-400'
              }`}>
                <div className="font-semibold text-neutral-200">Phase 3: In</div>
                <div className="text-[10px] font-mono mt-0.5">+0.09s delay (0.28s)</div>
                <div className="text-[11px] text-neutral-400 mt-1">New content unblurs after size ≥ 60%.</div>
              </div>
            </div>
          </div>
        </div>

        {/* Right Column: Metal SDF & smin Visualizer (5 cols) */}
        <div className="lg:col-span-5 space-y-6">
          <div className="flex items-center justify-between">
            <h4 className="text-sm font-semibold text-neutral-200 flex items-center gap-2">
              <Waves className="w-4 h-4 text-cyan-400" />
              <span>Metal 2D SDF Smooth Min</span>
            </h4>
            <span className="text-xs font-mono text-cyan-400 font-semibold">k = {smoothingK} pt</span>
          </div>

          {/* Interactive Droplet / Lobe Visualizer */}
          <div className="p-4 rounded-xl bg-neutral-950 border border-neutral-800 flex flex-col items-center justify-center relative min-h-[220px]">
            {/* The Notch Root Lobe */}
            <div className="w-36 h-6 bg-black rounded-b-xl border-x border-b border-neutral-700/60 shadow-lg relative z-10 flex items-center justify-center">
              <span className="text-[9px] font-mono text-neutral-500">Lobe 0 (Notch Lip)</span>
            </div>

            {/* Simulated Viscous Necking via CSS SVG filter or simulated gooey droplet */}
            <div 
              className="relative flex items-center justify-center transition-all duration-150"
              style={{
                marginTop: `${testDropletY - 14}px`,
                filter: `blur(${smoothingK / 8}px) contrast(20)`
              }}
            >
              {/* Droplet Lobe */}
              <div 
                className="w-24 h-16 bg-black rounded-3xl border border-neutral-700 transition-all duration-200 flex items-center justify-center"
                style={{
                  borderRadius: `${Math.max(12, smoothingK)}px`
                }}
              />
            </div>

            {/* Labels overlay */}
            <div className="absolute bottom-2 text-center text-[10px] font-mono text-neutral-500">
              Polynomial Smooth Minimum: <code>smin(d1, d2, {smoothingK})</code>
            </div>
          </div>

          {/* Controls */}
          <div className="space-y-4 p-4 rounded-xl bg-neutral-950 border border-neutral-800">
            <div>
              <div className="flex justify-between text-xs text-neutral-300 font-mono mb-1.5">
                <span>Viscosity Radius (k):</span>
                <span className="text-indigo-400">{smoothingK} pt</span>
              </div>
              <input
                type="range"
                min="8"
                max="36"
                value={smoothingK}
                onChange={(e) => {
                  soundFx.playTick();
                  setSmoothingK(Number(e.target.value));
                }}
                className="w-full accent-indigo-500 cursor-pointer"
              />
              <div className="flex justify-between text-[10px] text-neutral-500 font-mono mt-1">
                <span>8 pt (Settled Definition)</span>
                <span>36 pt (Viscous Birth Swell)</span>
              </div>
            </div>

            <div>
              <div className="flex justify-between text-xs text-neutral-300 font-mono mb-1.5">
                <span>Droplet Separation (Y):</span>
                <span className="text-indigo-400">{testDropletY} pt</span>
              </div>
              <input
                type="range"
                min="10"
                max="70"
                value={testDropletY}
                onChange={(e) => {
                  soundFx.playTick();
                  setTestDropletY(Number(e.target.value));
                }}
                className="w-full accent-indigo-500 cursor-pointer"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
