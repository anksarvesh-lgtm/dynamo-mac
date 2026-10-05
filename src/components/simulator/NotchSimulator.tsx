import React, { useState, useEffect } from 'react';
import { 
  IslandState, 
  DisplayMode, 
  ExpandedTab, 
  NoiseControlMode, 
  AlertType 
} from '../../types/liquiddynamo';
import { soundFx } from '../../utils/audioFeedback';
import { 
  Music, 
  Headphones, 
  FolderDown, 
  Calendar, 
  Cpu, 
  Play, 
  Pause, 
  SkipForward, 
  SkipBack, 
  Volume2, 
  VolumeX, 
  BatteryCharging, 
  Share2, 
  Check, 
  RotateCw, 
  Bell, 
  Sliders, 
  Monitor, 
  Layers, 
  Sparkles,
  Zap,
  Info
} from 'lucide-react';

export const NotchSimulator: React.FC = () => {
  const [islandState, setIslandState] = useState<IslandState>('expanded');
  const [displayMode, setDisplayMode] = useState<DisplayMode>('notch');
  const [expandedTab, setExpandedTab] = useState<ExpandedTab>('airpods');
  const [isPlaying, setIsPlaying] = useState<boolean>(true);
  const [trackProgress, setTrackProgress] = useState<number>(45);
  const [noiseMode, setNoiseMode] = useState<NoiseControlMode>('anc');
  const [volumeLevel, setVolumeLevel] = useState<number>(72);
  const [isMuted, setIsMuted] = useState<boolean>(false);
  const [stagedFiles, setStagedFiles] = useState<Array<{ name: string; size: string; type: string }>>([
    { name: 'Architecture_Diagram.pdf', size: '2.4 MB', type: 'doc' },
    { name: 'LiquidDynamo_Mockup.png', size: '4.8 MB', type: 'image' },
  ]);
  const [airDropSent, setAirDropSent] = useState<boolean>(false);
  const [activeAlert, setActiveAlert] = useState<AlertType>('airpods');
  const [soundEnabled, setSoundEnabled] = useState<boolean>(true);

  // Audio synthesis sync
  useEffect(() => {
    soundFx.setEnabled(soundEnabled);
  }, [soundEnabled]);

  // Track progress ticker
  useEffect(() => {
    if (!isPlaying) return;
    const interval = setInterval(() => {
      setTrackProgress(prev => (prev >= 100 ? 0 : prev + 0.8));
    }, 1000);
    return () => clearInterval(interval);
  }, [isPlaying]);

  const handleStateChange = (newState: IslandState) => {
    soundFx.playMorphPop(newState === 'alert' ? 520 : newState === 'expanded' ? 380 : 440);
    setIslandState(newState);
  };

  const handleTriggerAlert = (type: AlertType) => {
    setActiveAlert(type);
    setIslandState('alert');
    if (type === 'airpods') {
      soundFx.playAirPodsChime();
    } else {
      soundFx.playMorphPop(500);
    }
  };

  const handleTriggerAirDrop = () => {
    soundFx.playDropChime();
    setAirDropSent(true);
    setTimeout(() => setAirDropSent(false), 2400);
  };

  const handleAddSampleFile = () => {
    soundFx.playTick();
    const samples = [
      { name: 'LiquidShader.metal', size: '14 KB', type: 'code' },
      { name: 'ReleaseNotes_v2.8.md', size: '8 KB', type: 'doc' },
      { name: 'AppIcon_1024.png', size: '1.2 MB', type: 'image' }
    ];
    const next = samples[stagedFiles.length % samples.length];
    setStagedFiles([...stagedFiles, next]);
  };

  return (
    <div className="w-full bg-neutral-900/90 border border-neutral-800 rounded-2xl overflow-hidden shadow-2xl backdrop-blur-xl">
      {/* Control bar */}
      <div className="flex flex-wrap items-center justify-between gap-4 px-6 py-4 bg-neutral-950/80 border-b border-neutral-800">
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-indigo-500/10 border border-indigo-500/20 text-indigo-400 text-xs font-medium">
            <Sparkles className="w-3.5 h-3.5" />
            <span>Interactive Live Simulator</span>
          </div>
          <span className="text-xs text-neutral-400 hidden sm:inline">
            Experience the 5 dynamic island motion states in real-time
          </span>
        </div>

        <div className="flex items-center gap-2">
          {/* Display mode toggle */}
          <div className="flex items-center bg-neutral-900 border border-neutral-800 rounded-lg p-0.5 text-xs">
            <button
              onClick={() => {
                soundFx.playTick();
                setDisplayMode('notch');
              }}
              className={`flex items-center gap-1.5 px-2.5 py-1 rounded-md transition-all ${
                displayMode === 'notch'
                  ? 'bg-neutral-800 text-white font-medium shadow-sm'
                  : 'text-neutral-400 hover:text-neutral-200'
              }`}
            >
              <Monitor className="w-3.5 h-3.5" />
              <span>MacBook Notch</span>
            </button>
            <button
              onClick={() => {
                soundFx.playTick();
                setDisplayMode('floating');
              }}
              className={`flex items-center gap-1.5 px-2.5 py-1 rounded-md transition-all ${
                displayMode === 'floating'
                  ? 'bg-neutral-800 text-white font-medium shadow-sm'
                  : 'text-neutral-400 hover:text-neutral-200'
              }`}
            >
              <Layers className="w-3.5 h-3.5" />
              <span>Floating Pill</span>
            </button>
          </div>

          {/* Sound Toggle */}
          <button
            onClick={() => setSoundEnabled(!soundEnabled)}
            title={soundEnabled ? 'Mute synthesized UI chimes' : 'Enable synthesized UI chimes'}
            className={`p-1.5 rounded-lg border text-xs transition-colors ${
              soundEnabled
                ? 'bg-indigo-500/10 border-indigo-500/30 text-indigo-400'
                : 'bg-neutral-900 border-neutral-800 text-neutral-500 hover:text-neutral-300'
            }`}
          >
            {soundEnabled ? <Volume2 className="w-4 h-4" /> : <VolumeX className="w-4 h-4" />}
          </button>
        </div>
      </div>

      {/* State Switcher Tabs */}
      <div className="px-6 py-3 bg-neutral-950/40 border-b border-neutral-800/80 flex flex-wrap items-center justify-between gap-3 text-xs">
        <div className="flex items-center gap-1.5">
          <span className="text-neutral-500 font-mono uppercase tracking-wider text-[11px] mr-2">State:</span>
          {(['idle', 'compact', 'minimal', 'expanded', 'alert'] as IslandState[]).map((state) => (
            <button
              key={state}
              onClick={() => handleStateChange(state)}
              className={`px-3 py-1.5 rounded-lg capitalize transition-all font-medium ${
                islandState === state
                  ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/20'
                  : 'bg-neutral-800/60 text-neutral-400 hover:bg-neutral-800 hover:text-neutral-200'
              }`}
            >
              {state === 'alert' ? 'Alert Pop' : state}
            </button>
          ))}
        </div>

        {islandState === 'alert' && (
          <div className="flex items-center gap-1.5">
            <span className="text-neutral-500 text-[11px]">Alert Payload:</span>
            {(['airpods', 'battery', 'volume', 'brightness'] as AlertType[]).map((t) => (
              <button
                key={t}
                onClick={() => handleTriggerAlert(t)}
                className={`px-2 py-1 rounded text-[11px] uppercase tracking-wider font-mono transition-colors ${
                  activeAlert === t
                    ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/40'
                    : 'bg-neutral-800 text-neutral-400 hover:text-neutral-200'
                }`}
              >
                {t}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Realistic Mac Screen Canvas */}
      <div className="relative min-h-[460px] flex flex-col items-center justify-start pt-0 pb-12 px-4 bg-gradient-to-b from-neutral-950 via-neutral-900/60 to-neutral-950 overflow-hidden">
        {/* Subtle macOS Menu Bar Mockup */}
        <div className="w-full flex items-center justify-between px-6 py-1.5 text-[11px] text-neutral-400 font-medium select-none border-b border-white/[0.04] bg-neutral-950/40">
          <div className="flex items-center gap-4">
            <span className="text-neutral-200 font-semibold cursor-pointer"></span>
            <span className="font-semibold text-neutral-200">LiquidDynamo</span>
            <span className="hover:text-neutral-200 cursor-pointer hidden md:inline">File</span>
            <span className="hover:text-neutral-200 cursor-pointer hidden md:inline">Edit</span>
            <span className="hover:text-neutral-200 cursor-pointer hidden md:inline">View</span>
            <span className="hover:text-neutral-200 cursor-pointer hidden md:inline">Window</span>
            <span className="hover:text-neutral-200 cursor-pointer hidden md:inline">Help</span>
          </div>
          <div className="flex items-center gap-3 text-neutral-400">
            <span className="flex items-center gap-1 font-mono text-[10px] text-emerald-400 bg-emerald-500/10 px-1.5 py-0.5 rounded">
              <Zap className="w-2.5 h-2.5" /> 92%
            </span>
            <span className="hidden sm:inline">Mon Oct 5 11:20 AM</span>
          </div>
        </div>

        {/* Physical Camera / Notch Cutout (When in notch mode) */}
        {displayMode === 'notch' && (
          <div className="relative z-30 flex flex-col items-center">
            {/* The Hardware Notch Base */}
            <div className="w-[185px] h-[28px] bg-black rounded-b-2xl flex items-center justify-center gap-3 shadow-md relative">
              {/* Camera lens & green indicator LED */}
              <div className="w-2.5 h-2.5 rounded-full bg-neutral-900 border border-neutral-700/80 flex items-center justify-center">
                <div className="w-1 h-1 rounded-full bg-blue-900/60" />
              </div>
              <div className="w-1 h-1 rounded-full bg-emerald-500/80 animate-pulse" title="Camera/Sensor active" />
            </div>
          </div>
        )}

        {/* The Dynamic Liquid Island Morphing Container */}
        <div 
          className={`relative z-20 transition-all duration-400 ease-[cubic-bezier(0.16,1,0.3,1)] ${
            displayMode === 'notch' ? '-mt-7' : 'mt-4'
          }`}
        >
          {/* 1. IDLE STATE */}
          {islandState === 'idle' && (
            <div 
              onClick={() => handleStateChange('expanded')}
              className={`cursor-pointer transition-all duration-300 ${
                displayMode === 'notch'
                  ? 'w-[185px] h-[32px] bg-black rounded-b-2xl'
                  : 'w-[120px] h-[30px] bg-black rounded-full border border-neutral-800 shadow-xl'
              } flex items-center justify-center text-[11px] text-neutral-600 hover:text-neutral-400 group`}
            >
              <span className="text-[10px] tracking-wide opacity-0 group-hover:opacity-100 transition-opacity">
                Hover or Click
              </span>
            </div>
          )}

          {/* 2. COMPACT STATE (Wings Active) */}
          {islandState === 'compact' && (
            <div 
              onClick={() => handleStateChange('expanded')}
              className={`cursor-pointer bg-black text-white px-3.5 py-1.5 transition-all duration-300 shadow-2xl border border-white/[0.08] flex items-center justify-between gap-4 ${
                displayMode === 'notch'
                  ? 'min-w-[340px] h-[34px] rounded-b-2xl'
                  : 'min-w-[320px] h-[34px] rounded-full'
              }`}
            >
              {/* Left Wing (Leading indicator: Album Art & Track) */}
              <div className="flex items-center gap-2 pl-1">
                <div className="w-5 h-5 rounded-md bg-gradient-to-tr from-rose-500 to-indigo-600 flex items-center justify-center text-[9px] shadow-sm">
                  🎵
                </div>
                <div className="flex flex-col">
                  <span className="text-[11px] font-medium leading-none text-neutral-100">Midnight City</span>
                  <span className="text-[9px] text-neutral-400 leading-tight">M83</span>
                </div>
              </div>

              {/* Hardware Notch Spacer when in notch mode */}
              {displayMode === 'notch' && <div className="w-16 h-2" />}

              {/* Right Wing (Trailing indicator: Animated audio waveforms) */}
              <div className="flex items-center gap-1 pr-1">
                <div className="flex items-center gap-0.5 h-3.5">
                  {[40, 90, 60, 100, 75, 45, 80].map((h, i) => (
                    <span
                      key={i}
                      className="w-0.5 bg-indigo-400 rounded-full animate-pulse"
                      style={{
                        height: isPlaying ? `${h}%` : '20%',
                        animationDuration: `${0.6 + (i % 3) * 0.2}s`
                      }}
                    />
                  ))}
                </div>
                <span className="text-[10px] font-mono text-neutral-400 ml-1.5 tabular-nums">3:18</span>
              </div>
            </div>
          )}

          {/* 3. MINIMAL STATE (Multi-activity: primary + detached satellite bubble) */}
          {islandState === 'minimal' && (
            <div className="flex items-center gap-2.5">
              {/* Primary compact pill */}
              <div 
                onClick={() => handleStateChange('expanded')}
                className={`cursor-pointer bg-black text-white px-3 py-1.5 transition-all shadow-2xl border border-white/[0.08] flex items-center gap-2.5 ${
                  displayMode === 'notch' ? 'rounded-b-2xl h-[34px]' : 'rounded-full h-[34px]'
                }`}
              >
                <div className="w-4 h-4 rounded bg-gradient-to-tr from-amber-500 to-red-500 flex items-center justify-center text-[8px]">
                  📻
                </div>
                <span className="text-[11px] font-medium text-neutral-200">Podcast: Syntax.fm</span>
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-ping" />
              </div>

              {/* Secondary detached satellite bubble */}
              <div 
                onClick={() => handleTriggerAlert('battery')}
                className="cursor-pointer w-8 h-8 rounded-full bg-black border border-white/[0.08] shadow-2xl flex items-center justify-center text-amber-400 hover:border-amber-400/40 transition-colors"
                title="Secondary activity: Timer countdown (14m left)"
              >
                <span className="text-[10px] font-mono font-bold">14m</span>
              </div>
            </div>
          )}

          {/* 4. EXPANDED STATE (Full Interactive Dashboard) */}
          {islandState === 'expanded' && (
            <div 
              className={`bg-black/95 text-white backdrop-blur-2xl transition-all duration-300 border border-white/[0.12] shadow-2xl w-[92vw] max-w-[660px] p-5 ${
                displayMode === 'notch' ? 'rounded-b-3xl rounded-t-lg' : 'rounded-3xl'
              }`}
            >
              {/* Dock Tab Selector */}
              <div className="flex items-center justify-between pb-3.5 mb-4 border-b border-neutral-800/80">
                <div className="flex items-center gap-1.5 overflow-x-auto">
                  {[
                    { id: 'airpods', label: 'AirPods 3D Space', icon: Headphones },
                    { id: 'media', label: 'Now Playing', icon: Music },
                    { id: 'shelf', label: 'Liquid Shelf', icon: FolderDown },
                    { id: 'calendar', label: 'Schedule', icon: Calendar },
                    { id: 'system', label: 'System HUD', icon: Cpu },
                  ].map((tab) => {
                    const Icon = tab.icon;
                    const isActive = expandedTab === tab.id;
                    return (
                      <button
                        key={tab.id}
                        onClick={() => {
                          soundFx.playTick();
                          setExpandedTab(tab.id as ExpandedTab);
                        }}
                        className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all ${
                          isActive
                            ? 'bg-neutral-800 text-white shadow-inner border border-neutral-700/60'
                            : 'text-neutral-400 hover:text-neutral-200 hover:bg-neutral-900'
                        }`}
                      >
                        <Icon className="w-3.5 h-3.5" />
                        <span>{tab.label}</span>
                      </button>
                    );
                  })}
                </div>

                <button
                  onClick={() => handleStateChange('compact')}
                  className="text-neutral-500 hover:text-neutral-300 p-1 text-xs"
                  title="Collapse to Compact Wing"
                >
                  ✕
                </button>
              </div>

              {/* Tab 1: AirPods 3D Space & AAP Protocol */}
              {expandedTab === 'airpods' && (
                <div className="space-y-4">
                  <div className="flex flex-col sm:flex-row items-center justify-between gap-4 p-4 rounded-xl bg-gradient-to-br from-neutral-900/90 to-neutral-950 border border-neutral-800 relative overflow-hidden">
                    {/* Simulated 3D Space background starfield */}
                    <div className="absolute inset-0 bg-[radial-gradient(#ffffff15_1px,transparent_1px)] [background-size:16px_16px] pointer-events-none" />

                    {/* Left: Device graphic & battery arcs */}
                    <div className="flex items-center gap-4 relative z-10">
                      <div className="relative w-16 h-16 rounded-2xl bg-neutral-800/80 border border-neutral-700 flex items-center justify-center shadow-lg group">
                        <Headphones className="w-8 h-8 text-neutral-100 group-hover:scale-110 transition-transform" />
                        <span className="absolute -top-1 -right-1 w-3 h-3 bg-emerald-500 rounded-full border-2 border-black" />
                      </div>

                      <div>
                        <div className="flex items-center gap-2">
                          <h4 className="font-semibold text-sm text-neutral-100">AirPods Pro (2nd Gen)</h4>
                          <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-indigo-500/20 text-indigo-300 border border-indigo-500/30">
                            Spatial Audio
                          </span>
                        </div>
                        <p className="text-xs text-neutral-400 mt-0.5">Head Tracking Active via CoreMotion</p>

                        {/* Orbit battery meters */}
                        <div className="flex items-center gap-3 mt-2 text-xs font-mono">
                          <div className="flex items-center gap-1 text-emerald-400">
                            <span>L:</span>
                            <span className="font-semibold">85%</span>
                          </div>
                          <div className="flex items-center gap-1 text-emerald-400">
                            <span>R:</span>
                            <span className="font-semibold">85%</span>
                          </div>
                          <div className="flex items-center gap-1 text-emerald-400">
                            <span>Case:</span>
                            <span className="font-semibold">94%</span>
                          </div>
                        </div>
                      </div>
                    </div>

                    {/* Right: Quick actions */}
                    <button
                      onClick={() => handleTriggerAlert('airpods')}
                      className="relative z-10 flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-neutral-800 hover:bg-neutral-700 text-xs font-medium text-neutral-200 transition-colors border border-neutral-700/50"
                    >
                      <RotateCw className="w-3.5 h-3.5" />
                      <span>Re-pair / Ping</span>
                    </button>
                  </div>

                  {/* Noise Control Mode Switcher */}
                  <div>
                    <label className="text-[11px] font-mono text-neutral-400 uppercase tracking-wider block mb-2">
                      Listening Mode (HAL Plugin Bridge)
                    </label>
                    <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                      {[
                        { id: 'anc', label: 'Noise Cancellation', desc: 'Active isolation' },
                        { id: 'transparency', label: 'Transparency', desc: 'Hear surroundings' },
                        { id: 'adaptive', label: 'Adaptive', desc: 'Dynamic blending' },
                        { id: 'off', label: 'Off', desc: 'Standard pass' }
                      ].map((mode) => (
                        <button
                          key={mode.id}
                          onClick={() => {
                            soundFx.playTick();
                            setNoiseMode(mode.id as NoiseControlMode);
                          }}
                          className={`p-2.5 rounded-xl text-left border transition-all ${
                            noiseMode === mode.id
                              ? 'bg-indigo-600/20 border-indigo-500/60 text-white'
                              : 'bg-neutral-900 border-neutral-800 text-neutral-400 hover:border-neutral-700'
                          }`}
                        >
                          <div className="text-xs font-medium">{mode.label}</div>
                          <div className="text-[10px] text-neutral-500 mt-0.5">{mode.desc}</div>
                        </button>
                      ))}
                    </div>
                  </div>
                </div>
              )}

              {/* Tab 2: Now Playing Media Hub */}
              {expandedTab === 'media' && (
                <div className="space-y-4">
                  <div className="flex items-center gap-4">
                    <div className="w-16 h-16 rounded-xl bg-gradient-to-tr from-pink-500 via-purple-600 to-indigo-600 flex items-center justify-center text-2xl shadow-xl flex-shrink-0">
                      🎵
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between">
                        <h4 className="text-sm font-semibold truncate text-neutral-100">Midnight City</h4>
                        <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-neutral-800 text-neutral-300">
                          Lossless 24-bit/48kHz
                        </span>
                      </div>
                      <p className="text-xs text-neutral-400 mt-0.5">M83 — Hurry Up, We're Dreaming</p>

                      {/* Scrubber */}
                      <div className="mt-2.5">
                        <div className="w-full bg-neutral-800 h-1.5 rounded-full overflow-hidden">
                          <div
                            className="bg-indigo-500 h-full rounded-full transition-all duration-300"
                            style={{ width: `${trackProgress}%` }}
                          />
                        </div>
                        <div className="flex justify-between text-[10px] font-mono text-neutral-500 mt-1">
                          <span>1:42</span>
                          <span>4:03</span>
                        </div>
                      </div>
                    </div>
                  </div>

                  {/* Transport Controls & Volume */}
                  <div className="flex flex-wrap items-center justify-between gap-4 pt-2 border-t border-neutral-850">
                    <div className="flex items-center gap-2">
                      <button 
                        onClick={() => soundFx.playTick()}
                        className="p-2 rounded-lg hover:bg-neutral-800 text-neutral-300 transition-colors"
                      >
                        <SkipBack className="w-4 h-4" />
                      </button>
                      <button
                        onClick={() => {
                          soundFx.playMorphPop(isPlaying ? 350 : 500);
                          setIsPlaying(!isPlaying);
                        }}
                        className="p-2.5 rounded-full bg-indigo-600 hover:bg-indigo-500 text-white shadow-lg shadow-indigo-600/30 transition-transform active:scale-95"
                      >
                        {isPlaying ? <Pause className="w-4 h-4" /> : <Play className="w-4 h-4 translate-x-0.5" />}
                      </button>
                      <button 
                        onClick={() => soundFx.playTick()}
                        className="p-2 rounded-lg hover:bg-neutral-800 text-neutral-300 transition-colors"
                      >
                        <SkipForward className="w-4 h-4" />
                      </button>
                    </div>

                    {/* Volume Slider */}
                    <div className="flex items-center gap-2 text-neutral-400">
                      <button
                        onClick={() => {
                          soundFx.playTick();
                          setIsMuted(!isMuted);
                        }}
                        className="p-1 hover:text-neutral-200"
                      >
                        {isMuted || volumeLevel === 0 ? <VolumeX className="w-4 h-4" /> : <Volume2 className="w-4 h-4" />}
                      </button>
                      <input
                        type="range"
                        min="0"
                        max="100"
                        value={isMuted ? 0 : volumeLevel}
                        onChange={(e) => {
                          setIsMuted(false);
                          setVolumeLevel(Number(e.target.value));
                          soundFx.playTick();
                        }}
                        className="w-24 accent-indigo-500 cursor-pointer"
                      />
                      <span className="text-xs font-mono w-8 text-right tabular-nums">
                        {isMuted ? '0%' : `${volumeLevel}%`}
                      </span>
                    </div>
                  </div>
                </div>
              )}

              {/* Tab 3: Liquid Shelf & AirDrop */}
              {expandedTab === 'shelf' && (
                <div className="space-y-3">
                  <div className="flex items-center justify-between text-xs">
                    <span className="text-neutral-400">Top-of-screen friction-free staging area:</span>
                    <button
                      onClick={handleAddSampleFile}
                      className="text-indigo-400 hover:text-indigo-300 font-medium"
                    >
                      + Add Staged File
                    </button>
                  </div>

                  {/* Staged file list */}
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                    {stagedFiles.map((file, i) => (
                      <div
                        key={i}
                        className="flex items-center justify-between p-2.5 rounded-xl bg-neutral-900 border border-neutral-800 hover:border-neutral-700 transition-colors"
                      >
                        <div className="flex items-center gap-2.5 truncate">
                          <div className="w-7 h-7 rounded-lg bg-neutral-800 flex items-center justify-center text-xs">
                            {file.type === 'image' ? '🖼️' : file.type === 'code' ? '⚡' : '📄'}
                          </div>
                          <div className="truncate">
                            <div className="text-xs font-medium text-neutral-200 truncate">{file.name}</div>
                            <div className="text-[10px] text-neutral-500 font-mono">{file.size}</div>
                          </div>
                        </div>
                        <button
                          onClick={() => {
                            soundFx.playTick();
                            setStagedFiles(stagedFiles.filter((_, idx) => idx !== i));
                          }}
                          className="text-neutral-500 hover:text-red-400 text-xs px-1"
                        >
                          ✕
                        </button>
                      </div>
                    ))}
                  </div>

                  {/* AirDrop Action */}
                  <div className="pt-2 flex items-center justify-between">
                    <span className="text-[11px] text-neutral-500">
                      {stagedFiles.length} file{stagedFiles.length !== 1 ? 's' : ''} staged for instant dispatch
                    </span>
                    <button
                      onClick={handleTriggerAirDrop}
                      disabled={airDropSent || stagedFiles.length === 0}
                      className={`flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-medium transition-all ${
                        airDropSent
                          ? 'bg-emerald-600 text-white shadow-lg shadow-emerald-600/30'
                          : 'bg-indigo-600 hover:bg-indigo-500 text-white shadow-md shadow-indigo-600/20 active:scale-95'
                      }`}
                    >
                      {airDropSent ? (
                        <>
                          <Check className="w-3.5 h-3.5" />
                          <span>Sent via AirDrop!</span>
                        </>
                      ) : (
                        <>
                          <Share2 className="w-3.5 h-3.5" />
                          <span>AirDrop to Nearby Devices</span>
                        </>
                      )}
                    </button>
                  </div>
                </div>
              )}

              {/* Tab 4: Calendar & Next Meetings */}
              {expandedTab === 'calendar' && (
                <div className="space-y-2.5">
                  <div className="text-xs text-neutral-400 mb-2">Upcoming today (macOS EventKit sync):</div>
                  {[
                    { title: 'LiquidDynamo Architecture Sync', time: '11:30 AM – 12:00 PM', location: 'Google Meet', active: true },
                    { title: 'Metal 3 Shader Optimization Review', time: '2:00 PM – 2:45 PM', location: 'Room Cupertino-A', active: false },
                    { title: 'Sprint 28-RC Tagging & Release', time: '4:30 PM – 5:00 PM', location: 'GitHub Actions', active: false }
                  ].map((evt, i) => (
                    <div
                      key={i}
                      className={`flex items-center justify-between p-3 rounded-xl border transition-all ${
                        evt.active
                          ? 'bg-indigo-500/10 border-indigo-500/30 text-white'
                          : 'bg-neutral-900 border-neutral-800 text-neutral-300'
                      }`}
                    >
                      <div>
                        <div className="text-xs font-semibold flex items-center gap-2">
                          <span>{evt.title}</span>
                          {evt.active && (
                            <span className="text-[10px] font-mono px-1.5 py-0.2 rounded bg-emerald-500/20 text-emerald-300">
                              Starts in 10m
                            </span>
                          )}
                        </div>
                        <div className="text-[11px] text-neutral-400 font-mono mt-0.5">{evt.time} • {evt.location}</div>
                      </div>
                      <button 
                        onClick={() => soundFx.playTick()}
                        className="px-2.5 py-1 rounded bg-neutral-800 hover:bg-neutral-700 text-xs font-medium text-neutral-200"
                      >
                        Join
                      </button>
                    </div>
                  ))}
                </div>
              )}

              {/* Tab 5: System & Power HUD */}
              {expandedTab === 'system' && (
                <div className="space-y-4">
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                    <div className="p-3 rounded-xl bg-neutral-900 border border-neutral-800">
                      <div className="text-[10px] font-mono text-neutral-500 uppercase">CPU Usage</div>
                      <div className="text-lg font-bold text-neutral-100 font-mono mt-0.5">8.4%</div>
                      <div className="text-[10px] text-neutral-400">Idle load: 0.1%</div>
                    </div>
                    <div className="p-3 rounded-xl bg-neutral-900 border border-neutral-800">
                      <div className="text-[10px] font-mono text-neutral-500 uppercase">Unified Memory</div>
                      <div className="text-lg font-bold text-neutral-100 font-mono mt-0.5">14.2 GB</div>
                      <div className="text-[10px] text-neutral-400">Pressure: Green</div>
                    </div>
                    <div className="p-3 rounded-xl bg-neutral-900 border border-neutral-800">
                      <div className="text-[10px] font-mono text-neutral-500 uppercase">MagSafe 3</div>
                      <div className="text-lg font-bold text-emerald-400 font-mono mt-0.5 flex items-center gap-1">
                        <BatteryCharging className="w-4 h-4" /> 67W
                      </div>
                      <div className="text-[10px] text-neutral-400">92% Charged</div>
                    </div>
                    <div className="p-3 rounded-xl bg-neutral-900 border border-neutral-800">
                      <div className="text-[10px] font-mono text-neutral-500 uppercase">Thermal State</div>
                      <div className="text-lg font-bold text-neutral-100 font-mono mt-0.5">Nominal</div>
                      <div className="text-[10px] text-neutral-400">Fan: 0 RPM (Silent)</div>
                    </div>
                  </div>

                  <div className="p-3 rounded-xl bg-neutral-900/60 border border-neutral-800 text-xs text-neutral-400 flex items-center justify-between">
                    <span>Direct IOKit and SMC sensor bridge with zero daemon overhead.</span>
                    <button
                      onClick={() => handleTriggerAlert('volume')}
                      className="text-indigo-400 hover:text-indigo-300 font-mono text-[11px]"
                    >
                      Test Volume HUD Overlay →
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* 5. ALERT POP STATE */}
          {islandState === 'alert' && (
            <div 
              className={`bg-black text-white px-5 py-3 transition-all duration-300 border border-white/[0.15] shadow-2xl flex items-center justify-between gap-4 min-w-[360px] max-w-[440px] animate-in fade-in zoom-in-95 duration-200 ${
                displayMode === 'notch' ? 'rounded-b-2xl' : 'rounded-full'
              }`}
            >
              {activeAlert === 'airpods' && (
                <>
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-full bg-neutral-800 flex items-center justify-center text-white">
                      <Headphones className="w-4 h-4" />
                    </div>
                    <div>
                      <div className="text-xs font-semibold">AirPods Pro Connected</div>
                      <div className="text-[10px] font-mono text-emerald-400">L: 85% • R: 85% • Case: 94%</div>
                    </div>
                  </div>
                  <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
                </>
              )}

              {activeAlert === 'battery' && (
                <>
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-full bg-amber-500/20 text-amber-400 flex items-center justify-center">
                      <Zap className="w-4 h-4" />
                    </div>
                    <div>
                      <div className="text-xs font-semibold text-amber-300">Low Battery Warning (15%)</div>
                      <div className="text-[10px] text-neutral-400">Connect MagSafe charger</div>
                    </div>
                  </div>
                  <button 
                    onClick={() => handleStateChange('compact')}
                    className="text-[11px] px-2.5 py-1 rounded bg-neutral-800 hover:bg-neutral-700 text-neutral-300"
                  >
                    Dismiss
                  </button>
                </>
              )}

              {activeAlert === 'volume' && (
                <>
                  <div className="flex items-center gap-3 flex-1">
                    <Volume2 className="w-4 h-4 text-neutral-300" />
                    <div className="flex-1">
                      <div className="flex justify-between text-[10px] font-mono text-neutral-400 mb-1">
                        <span>Volume Level</span>
                        <span>{volumeLevel}%</span>
                      </div>
                      <div className="w-full bg-neutral-800 h-1.5 rounded-full overflow-hidden">
                        <div className="bg-white h-full rounded-full" style={{ width: `${volumeLevel}%` }} />
                      </div>
                    </div>
                  </div>
                </>
              )}

              {activeAlert === 'brightness' && (
                <>
                  <div className="flex items-center gap-3 flex-1">
                    <span className="text-sm">☀️</span>
                    <div className="flex-1">
                      <div className="flex justify-between text-[10px] font-mono text-neutral-400 mb-1">
                        <span>Display Brightness</span>
                        <span>80%</span>
                      </div>
                      <div className="w-full bg-neutral-800 h-1.5 rounded-full overflow-hidden">
                        <div className="bg-amber-400 h-full rounded-full" style={{ width: '80%' }} />
                      </div>
                    </div>
                  </div>
                </>
              )}
            </div>
          )}
        </div>

        {/* Informative Floating Tooltip on the Simulator Canvas */}
        <div className="mt-auto pt-8 flex items-center gap-2 text-xs text-neutral-500 font-mono select-none">
          <Info className="w-3.5 h-3.5 text-neutral-400" />
          <span>Active State: <strong className="text-indigo-400 uppercase">{islandState}</strong></span>
          <span className="text-neutral-700">•</span>
          <span>Geometry: <strong className="text-neutral-300">{displayMode === 'notch' ? 'Physical Notch Snapped' : 'Floating Pill Island'}</strong></span>
        </div>
      </div>
    </div>
  );
};
