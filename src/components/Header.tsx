import React from 'react';
import { soundFx } from '../utils/audioFeedback';
import { 
  Sparkles, 
  Github, 
  Download, 
  ExternalLink, 
  Terminal, 
  Layers, 
  Code 
} from 'lucide-react';

interface HeaderProps {
  activeSection: string;
  onNavigate: (sectionId: string) => void;
}

export const Header: React.FC<HeaderProps> = ({ activeSection, onNavigate }) => {
  const navItems = [
    { id: 'simulator', label: 'Simulator' },
    { id: 'github', label: 'GitHub & Release' },
    { id: 'features', label: 'Features' },
    { id: 'physics', label: 'Physics Lab' },
    { id: 'codebase', label: 'Codebase Map' },
    { id: 'specs', label: 'Specifications' },
    { id: 'install', label: 'Installation' },
  ];

  return (
    <header className="sticky top-0 z-50 w-full border-b border-neutral-800/80 bg-neutral-950/80 backdrop-blur-xl">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between gap-4">
        {/* Brand */}
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded-xl bg-gradient-to-tr from-indigo-600 via-indigo-500 to-cyan-400 p-[1px] shadow-lg shadow-indigo-500/20">
            <div className="w-full h-full bg-black rounded-[11px] flex items-center justify-center">
              <span className="text-white font-black text-sm tracking-tighter">LD</span>
            </div>
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="font-bold text-sm tracking-tight text-white">LiquidDynamo</span>
              <span className="text-[10px] font-mono px-1.5 py-0.2 rounded bg-indigo-500/10 text-indigo-400 border border-indigo-500/20">
                v2.8-rc.1
              </span>
            </div>
            <div className="text-[10px] text-neutral-400 font-medium">by Agrigence</div>
          </div>
        </div>

        {/* Center Nav */}
        <nav className="hidden md:flex items-center gap-1 bg-neutral-900/60 border border-neutral-800/80 p-1 rounded-xl">
          {navItems.map((item) => (
            <button
              key={item.id}
              onClick={() => {
                soundFx.playTick();
                onNavigate(item.id);
              }}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-all ${
                activeSection === item.id
                  ? 'bg-neutral-800 text-white shadow-sm'
                  : 'text-neutral-400 hover:text-neutral-200 hover:bg-neutral-800/40'
              }`}
            >
              {item.label}
            </button>
          ))}
        </nav>

        {/* Right Actions */}
        <div className="flex items-center gap-2.5">
          <a
            href="https://github.com/anksarvesh-lgtm/Liquiddynamo"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-neutral-900 hover:bg-neutral-800 border border-neutral-800 text-xs font-medium text-neutral-300 transition-colors"
          >
            <Github className="w-4 h-4" />
            <span className="hidden sm:inline">GitHub</span>
          </a>

          <a
            href="https://github.com/anksarvesh-lgtm/Liquiddynamo/releases"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-medium shadow-md shadow-indigo-600/20 transition-all active:scale-95"
          >
            <Download className="w-3.5 h-3.5" />
            <span>Get DMG</span>
          </a>
        </div>
      </div>
    </header>
  );
};
