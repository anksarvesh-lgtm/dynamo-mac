import React, { useState, useEffect, useRef } from 'react';
import { soundEngine } from '../../utils/audioSynthesizer';
import { 
  Play, 
  Pause, 
  RotateCcw, 
  Volume2, 
  VolumeX, 
  Sparkles, 
  Check, 
  Trash2, 
  Plus, 
  CloudRain, 
  Radio, 
  Waves, 
  Wind
} from 'lucide-react';

export const FocusHub: React.FC = () => {
  type Mode = 'focus' | 'short_break' | 'long_break';
  type SoundPreset = 'none' | 'rain' | 'drone' | 'white_noise' | 'waves';

  const [mode, setMode] = useState<Mode>('focus');
  const [timeLeft, setTimeLeft] = useState<number>(25 * 60);
  const [isRunning, setIsRunning] = useState<boolean>(false);

  // Ambient sound
  const [soundPreset, setSoundPreset] = useState<SoundPreset>('none');
  const [volume, setVolume] = useState<number>(0.5);

  // Daily Stats (stored in localStorage)
  const [completedSessions, setCompletedSessions] = useState<number>(() => {
    return parseInt(localStorage.getItem('stratos_focus_sessions') || '3', 10);
  });
  const [totalMinutes, setTotalMinutes] = useState<number>(() => {
    return parseInt(localStorage.getItem('stratos_focus_minutes') || '75', 10);
  });

  // Stray thoughts scratchpad
  const [scratchNotes, setScratchNotes] = useState<{ id: string; text: string; done: boolean }[]>([
    { id: 'n1', text: 'Confirm PgBouncer connection pool max limit with DevOps', done: false },
    { id: 'n2', text: 'Reply to Sarah regarding RFC-042 review comments', done: true }
  ]);
  const [newNoteText, setNewNoteText] = useState('');

  const timerRef = useRef<number | null>(null);

  // Mode durations
  const durations: Record<Mode, number> = {
    focus: 25 * 60,
    short_break: 5 * 60,
    long_break: 15 * 60
  };

  // Timer Tick
  useEffect(() => {
    if (isRunning) {
      timerRef.current = window.setInterval(() => {
        setTimeLeft(prev => {
          if (prev <= 1) {
            handleTimerComplete();
            return 0;
          }
          return prev - 1;
        });
      }, 1000);
    } else {
      if (timerRef.current) clearInterval(timerRef.current);
    }

    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [isRunning, mode]);

  const handleTimerComplete = () => {
    setIsRunning(false);
    soundEngine.playChime('success');

    if (mode === 'focus') {
      const newSessions = completedSessions + 1;
      const newMinutes = totalMinutes + 25;
      setCompletedSessions(newSessions);
      setTotalMinutes(newMinutes);
      localStorage.setItem('stratos_focus_sessions', newSessions.toString());
      localStorage.setItem('stratos_focus_minutes', newMinutes.toString());

      // Suggest short break
      setMode('short_break');
      setTimeLeft(durations.short_break);
    } else {
      setMode('focus');
      setTimeLeft(durations.focus);
    }
  };

  const handleSwitchMode = (newMode: Mode) => {
    setIsRunning(false);
    setMode(newMode);
    setTimeLeft(durations[newMode]);
  };

  const handleReset = () => {
    setIsRunning(false);
    setTimeLeft(durations[mode]);
  };

  // Handle ambient audio presets
  const handleSelectSound = (preset: SoundPreset) => {
    setSoundPreset(preset);
    if (preset === 'none') {
      soundEngine.stopAmbient();
    } else {
      soundEngine.startAmbient(preset, volume);
    }
  };

  const handleVolumeChange = (newVol: number) => {
    setVolume(newVol);
    soundEngine.setMasterVolume(newVol);
  };

  // Scratchpad actions
  const handleAddScratchNote = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newNoteText.trim()) return;
    setScratchNotes([
      ...scratchNotes,
      { id: `note-${Date.now()}`, text: newNoteText.trim(), done: false }
    ]);
    setNewNoteText('');
  };

  const handleToggleNote = (id: string) => {
    setScratchNotes(scratchNotes.map(n => n.id === id ? { ...n, done: !n.done } : n));
  };

  const handleDeleteNote = (id: string) => {
    setScratchNotes(scratchNotes.filter(n => n.id !== id));
  };

  // Geometry for circular timer
  const currentTotal = durations[mode];
  const progressRatio = 1 - timeLeft / currentTotal;
  const radius = 100;
  const circumference = 2 * Math.PI * radius;
  const strokeDashoffset = circumference * (1 - progressRatio);

  const minutes = Math.floor(timeLeft / 60);
  const seconds = timeLeft % 60;
  const formattedTime = `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;

  return (
    <div className="flex-1 flex flex-col h-[calc(100vh-3.5rem)] overflow-y-auto bg-neutral-950 p-6">
      <div className="max-w-5xl w-full mx-auto space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-white/10 pb-4">
          <div>
            <h1 className="text-lg font-bold text-white tracking-tight">Focus & Ambient Studio</h1>
            <p className="text-xs text-neutral-400 mt-0.5">
              Distraction-free Pomodoro cycles and generative psychoacoustic soundscapes
            </p>
          </div>

          <div className="flex items-center gap-4 text-xs font-mono">
            <div className="bg-neutral-900 border border-white/10 rounded-lg px-3 py-1.5 flex items-center gap-2">
              <span className="text-neutral-500">TODAY:</span>
              <span className="text-indigo-400 font-bold tabular-nums">{completedSessions} sessions</span>
              <span className="text-neutral-600">·</span>
              <span className="text-neutral-300 tabular-nums">{totalMinutes} mins</span>
            </div>
          </div>
        </div>

        {/* Central Timer & Ambient Control Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Main Pomodoro Clock Card */}
          <div className="lg:col-span-2 bg-neutral-900/60 border border-white/10 rounded-xl p-8 flex flex-col items-center justify-center relative overflow-hidden shadow-lg">
            {/* Mode Selectors */}
            <div className="flex items-center gap-1.5 p-1 bg-neutral-950 border border-white/10 rounded-lg mb-8 z-10">
              <button
                onClick={() => handleSwitchMode('focus')}
                className={`px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
                  mode === 'focus' ? 'bg-indigo-600 text-white shadow-sm' : 'text-neutral-400 hover:text-white'
                }`}
              >
                Deep Focus (25m)
              </button>
              <button
                onClick={() => handleSwitchMode('short_break')}
                className={`px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
                  mode === 'short_break' ? 'bg-emerald-600 text-white shadow-sm' : 'text-neutral-400 hover:text-white'
                }`}
              >
                Short Break (5m)
              </button>
              <button
                onClick={() => handleSwitchMode('long_break')}
                className={`px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
                  mode === 'long_break' ? 'bg-amber-600 text-white shadow-sm' : 'text-neutral-400 hover:text-white'
                }`}
              >
                Long Break (15m)
              </button>
            </div>

            {/* Circular Progress Display */}
            <div className="relative w-64 h-64 flex items-center justify-center mb-8">
              <svg className="w-full h-full transform -rotate-90">
                {/* Background Ring */}
                <circle
                  cx="128"
                  cy="128"
                  r={radius}
                  fill="transparent"
                  stroke="rgba(255, 255, 255, 0.06)"
                  strokeWidth="8"
                />
                {/* Active Progress Ring */}
                <circle
                  cx="128"
                  cy="128"
                  r={radius}
                  fill="transparent"
                  stroke={mode === 'focus' ? '#6366f1' : mode === 'short_break' ? '#10b981' : '#f59e0b'}
                  strokeWidth="8"
                  strokeDasharray={circumference}
                  strokeDashoffset={strokeDashoffset}
                  strokeLinecap="round"
                  className="transition-all duration-1000 ease-linear"
                />
              </svg>

              {/* Time in Center */}
              <div className="absolute inset-0 flex flex-col items-center justify-center">
                <span className="text-5xl font-mono font-bold tracking-tight text-white tabular-nums">
                  {formattedTime}
                </span>
                <span className="text-xs font-mono uppercase tracking-wider text-neutral-400 mt-2">
                  {mode.replace('_', ' ')}
                </span>
              </div>
            </div>

            {/* Timer Controls */}
            <div className="flex items-center gap-4 z-10">
              <button
                onClick={handleReset}
                className="p-3 rounded-full bg-neutral-800 text-neutral-400 hover:text-white hover:bg-neutral-700 transition-colors"
                title="Reset timer"
              >
                <RotateCcw className="w-4 h-4" />
              </button>

              <button
                onClick={() => {
                  if (!isRunning) soundEngine.playChime('success');
                  setIsRunning(!isRunning);
                }}
                className={`px-8 py-3 rounded-full text-sm font-semibold flex items-center gap-2 shadow-lg transition-all ${
                  isRunning
                    ? 'bg-neutral-800 text-white hover:bg-neutral-700'
                    : 'bg-indigo-600 hover:bg-indigo-500 text-white shadow-indigo-600/30'
                }`}
              >
                {isRunning ? (
                  <>
                    <Pause className="w-4 h-4" />
                    <span>Pause</span>
                  </>
                ) : (
                  <>
                    <Play className="w-4 h-4 fill-white" />
                    <span>Start Session</span>
                  </>
                )}
              </button>
            </div>
          </div>

          {/* Right Column: Generative Ambient Soundscape & Stray Notes */}
          <div className="space-y-6">
            {/* Ambient Soundcard */}
            <div className="bg-neutral-900/60 border border-white/10 rounded-xl p-5 shadow-sm">
              <div className="flex items-center justify-between mb-3">
                <div className="flex items-center gap-2">
                  <Sparkles className="w-4 h-4 text-indigo-400" />
                  <h3 className="text-xs font-semibold text-white">Procedural Soundscape</h3>
                </div>
                <span className="text-[10px] font-mono text-neutral-500">Native Web Audio</span>
              </div>

              <div className="grid grid-cols-2 gap-2 mb-4">
                <button
                  onClick={() => handleSelectSound('rain')}
                  className={`p-2.5 rounded-lg border text-xs flex items-center gap-2 transition-all ${
                    soundPreset === 'rain'
                      ? 'border-indigo-500 bg-indigo-500/10 text-white'
                      : 'border-white/5 bg-neutral-950 text-neutral-400 hover:text-white'
                  }`}
                >
                  <CloudRain className="w-4 h-4 text-sky-400" />
                  <span>Rain Shower</span>
                </button>

                <button
                  onClick={() => handleSelectSound('drone')}
                  className={`p-2.5 rounded-lg border text-xs flex items-center gap-2 transition-all ${
                    soundPreset === 'drone'
                      ? 'border-indigo-500 bg-indigo-500/10 text-white'
                      : 'border-white/5 bg-neutral-950 text-neutral-400 hover:text-white'
                  }`}
                >
                  <Radio className="w-4 h-4 text-violet-400" />
                  <span>Binaural Drone</span>
                </button>

                <button
                  onClick={() => handleSelectSound('waves')}
                  className={`p-2.5 rounded-lg border text-xs flex items-center gap-2 transition-all ${
                    soundPreset === 'waves'
                      ? 'border-indigo-500 bg-indigo-500/10 text-white'
                      : 'border-white/5 bg-neutral-950 text-neutral-400 hover:text-white'
                  }`}
                >
                  <Waves className="w-4 h-4 text-teal-400" />
                  <span>Ocean Swell</span>
                </button>

                <button
                  onClick={() => handleSelectSound('white_noise')}
                  className={`p-2.5 rounded-lg border text-xs flex items-center gap-2 transition-all ${
                    soundPreset === 'white_noise'
                      ? 'border-indigo-500 bg-indigo-500/10 text-white'
                      : 'border-white/5 bg-neutral-950 text-neutral-400 hover:text-white'
                  }`}
                >
                  <Wind className="w-4 h-4 text-neutral-400" />
                  <span>Pink Mask</span>
                </button>
              </div>

              {/* Volume Slider & Mute */}
              <div className="pt-2 border-t border-white/5 flex items-center gap-3">
                <button
                  onClick={() => handleSelectSound(soundPreset === 'none' ? 'rain' : 'none')}
                  className="text-neutral-400 hover:text-white"
                  title={soundPreset === 'none' ? 'Unmute' : 'Mute'}
                >
                  {soundPreset === 'none' ? (
                    <VolumeX className="w-4 h-4 text-neutral-500" />
                  ) : (
                    <Volume2 className="w-4 h-4 text-indigo-400" />
                  )}
                </button>
                <input
                  type="range"
                  min="0"
                  max="1"
                  step="0.05"
                  value={volume}
                  onChange={(e) => handleVolumeChange(Number(e.target.value))}
                  className="w-full accent-indigo-500 cursor-pointer h-1 bg-neutral-800 rounded-lg"
                />
                <span className="text-[10px] font-mono tabular-nums text-neutral-500 w-8 text-right">
                  {Math.round(volume * 100)}%
                </span>
              </div>
            </div>

            {/* Quick Distraction-Free Stray Thought Scratchpad */}
            <div className="bg-neutral-900/60 border border-white/10 rounded-xl p-5 shadow-sm">
              <h3 className="text-xs font-semibold text-white mb-1">Session Scratchpad</h3>
              <p className="text-[11px] text-neutral-400 mb-3">
                Park distracting thoughts here without breaking your flow
              </p>

              <form onSubmit={handleAddScratchNote} className="flex gap-2 mb-3">
                <input
                  type="text"
                  placeholder="Capture quick thought..."
                  value={newNoteText}
                  onChange={(e) => setNewNoteText(e.target.value)}
                  className="flex-1 bg-neutral-950 border border-white/10 rounded-lg px-3 py-1.5 text-xs text-white placeholder-neutral-500 focus:outline-none focus:border-indigo-500"
                />
                <button
                  type="submit"
                  className="p-1.5 bg-neutral-800 text-white rounded-lg hover:bg-neutral-700 transition-colors"
                >
                  <Plus className="w-4 h-4" />
                </button>
              </form>

              <div className="space-y-1.5 max-h-44 overflow-y-auto">
                {scratchNotes.map(n => (
                  <div
                    key={n.id}
                    className="flex items-center justify-between p-2 rounded-lg bg-neutral-950/80 border border-white/5 text-xs group"
                  >
                    <label className="flex items-center gap-2 cursor-pointer flex-1 min-w-0">
                      <button
                        type="button"
                        onClick={() => handleToggleNote(n.id)}
                        className={`w-3.5 h-3.5 rounded border flex items-center justify-center transition-colors ${
                          n.done ? 'bg-indigo-600 border-indigo-600 text-white' : 'border-neutral-600'
                        }`}
                      >
                        {n.done && <Check className="w-2.5 h-2.5" />}
                      </button>
                      <span className={`truncate text-xs ${n.done ? 'line-through text-neutral-500' : 'text-neutral-300'}`}>
                        {n.text}
                      </span>
                    </label>
                    <button
                      onClick={() => handleDeleteNote(n.id)}
                      className="opacity-0 group-hover:opacity-100 text-neutral-500 hover:text-rose-400 p-0.5 transition-opacity"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
