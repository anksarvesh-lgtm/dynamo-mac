/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState } from 'react';
import { Header } from './components/Header';
import { NotchSimulator } from './components/simulator/NotchSimulator';
import { GitHubHub } from './components/github/GitHubHub';
import { FeaturesShowcase } from './components/features/FeaturesShowcase';
import { MotionLab } from './components/motion/MotionLab';
import { CodebaseExplorer } from './components/codebase/CodebaseExplorer';
import { DocsPortal } from './components/docs/DocsPortal';
import { InstallGuide } from './components/install/InstallGuide';
import { soundFx } from './utils/audioFeedback';
import { 
  Sparkles, 
  Download, 
  Github, 
  Terminal, 
  Layers, 
  ShieldCheck, 
  Cpu, 
  Waves, 
  ExternalLink,
  ChevronDown
} from 'lucide-react';

export default function App() {
  const [activeSection, setActiveSection] = useState<string>('simulator');

  const scrollToSection = (id: string) => {
    setActiveSection(id);
    const el = document.getElementById(id);
    if (el) {
      el.scrollIntoView({ behavior: 'smooth' });
    }
  };

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100 selection:bg-indigo-500/30 selection:text-indigo-200 font-sans">
      {/* Background Gradient Mesh */}
      <div className="fixed inset-0 pointer-events-none z-0 overflow-hidden">
        <div className="absolute -top-40 left-1/2 -translate-x-1/2 w-[1000px] h-[480px] bg-gradient-to-b from-indigo-600/15 via-purple-600/10 to-transparent blur-3xl opacity-70" />
        <div className="absolute top-[30%] -left-40 w-[600px] h-[400px] bg-cyan-600/10 blur-3xl rounded-full opacity-40" />
        <div className="absolute top-[60%] -right-40 w-[600px] h-[400px] bg-indigo-600/10 blur-3xl rounded-full opacity-40" />
      </div>

      {/* Header */}
      <Header activeSection={activeSection} onNavigate={scrollToSection} />

      <main className="relative z-10 max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-24">
        {/* HERO SECTION */}
        <section className="text-center pt-8 pb-4 space-y-6">
          <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-neutral-900 border border-neutral-800 text-xs text-neutral-300 shadow-inner">
            <span className="flex h-2 w-2 rounded-full bg-emerald-400 animate-pulse" />
            <span className="font-mono text-neutral-400">Target System:</span>
            <span className="font-medium text-neutral-200">macOS 14.0+ (Sonoma & Sequoia)</span>
            <span className="text-neutral-600">•</span>
            <span className="font-mono text-indigo-400">Apple Silicon & Intel</span>
          </div>

          <h1 className="text-4xl sm:text-5xl lg:text-6xl font-extrabold tracking-tight text-white max-w-4xl mx-auto leading-tight">
            A sleek, fluid, and dynamic notch enhancement experience for macOS
          </h1>

          <p className="text-base sm:text-lg text-neutral-400 max-w-3xl mx-auto leading-relaxed">
            Developed by <strong className="text-neutral-200">Agrigence</strong>. Built with native SwiftUI, AppKit, Metal 3 SDF shaders, and SceneKit. 
            Transforms your hardware notch into a high-performance command center for AirPods 3D space, media playback, system HUDs, and friction-free file staging.
          </p>

          {/* Action CTAs */}
          <div className="flex flex-wrap items-center justify-center gap-3 pt-2">
            <button
              onClick={() => {
                soundFx.playMorphPop(500);
                scrollToSection('simulator');
              }}
              className="flex items-center gap-2 px-5 py-3 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-semibold shadow-lg shadow-indigo-600/25 transition-all active:scale-95"
            >
              <Sparkles className="w-4 h-4" />
              <span>Launch Live Simulator</span>
            </button>

            <button
              onClick={() => {
                soundFx.playTick();
                scrollToSection('github');
              }}
              className="flex items-center gap-2 px-5 py-3 rounded-xl bg-neutral-900 hover:bg-neutral-800 border border-neutral-800 text-neutral-200 text-sm font-medium transition-all"
            >
              <Github className="w-4 h-4 text-indigo-400" />
              <span>GitHub Release Details</span>
            </button>

            <button
              onClick={() => {
                soundFx.playTick();
                scrollToSection('specs');
              }}
              className="flex items-center gap-2 px-5 py-3 rounded-xl bg-neutral-900 hover:bg-neutral-800 border border-neutral-800 text-neutral-200 text-sm font-medium transition-all"
            >
              <Layers className="w-4 h-4 text-indigo-400" />
              <span>View Specifications & Audits</span>
            </button>

            <a
              href="https://github.com/anksarvesh-lgtm/Liquiddynamo/releases"
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-2 px-5 py-3 rounded-xl bg-neutral-900 hover:bg-neutral-800 border border-neutral-800 text-neutral-200 text-sm font-medium transition-all"
            >
              <Download className="w-4 h-4 text-emerald-400" />
              <span>Download DMG</span>
            </a>
          </div>

          {/* Key Metric Highlights */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3 max-w-4xl mx-auto pt-6">
            <div className="p-3.5 rounded-xl bg-neutral-900/60 border border-neutral-800/80">
              <div className="text-2xl font-bold font-mono text-white">0.0%</div>
              <div className="text-xs text-neutral-400 mt-0.5">Idle CPU Utilization</div>
            </div>
            <div className="p-3.5 rounded-xl bg-neutral-900/60 border border-neutral-800/80">
              <div className="text-2xl font-bold font-mono text-indigo-400">5</div>
              <div className="text-xs text-neutral-400 mt-0.5">Physical Island States</div>
            </div>
            <div className="p-3.5 rounded-xl bg-neutral-900/60 border border-neutral-800/80">
              <div className="text-2xl font-bold font-mono text-cyan-400">8-Lobe</div>
              <div className="text-xs text-neutral-400 mt-0.5">Metal SDF Geometry</div>
            </div>
            <div className="p-3.5 rounded-xl bg-neutral-900/60 border border-neutral-800/80">
              <div className="text-2xl font-bold font-mono text-emerald-400">GPL-3.0</div>
              <div className="text-xs text-neutral-400 mt-0.5">Open Source Software</div>
            </div>
          </div>
        </section>

        {/* 1. SIMULATOR SECTION */}
        <section id="simulator" className="space-y-4 pt-4">
          <div className="flex items-center justify-between">
            <div>
              <span className="text-xs font-mono text-indigo-400 uppercase tracking-wider font-semibold">
                Interactive Playground
              </span>
              <h2 className="text-2xl font-bold text-white mt-0.5">Dynamic Island Simulator</h2>
            </div>
          </div>
          <NotchSimulator />
        </section>

        {/* 2. GITHUB RELEASE & PROVENANCE HUB */}
        <section id="github" className="space-y-4 pt-4">
          <GitHubHub />
        </section>

        {/* 3. FEATURES SHOWCASE */}
        <section id="features" className="space-y-4 pt-4">
          <FeaturesShowcase />
        </section>

        {/* 3. MOTION & METAL SDF LAB */}
        <section id="physics" className="space-y-4 pt-4">
          <MotionLab />
        </section>

        {/* 4. CODEBASE MAP */}
        <section id="codebase" className="space-y-4 pt-4">
          <CodebaseExplorer />
        </section>

        {/* 5. SPECIFICATIONS & AUDITS */}
        <section id="specs" className="space-y-4 pt-4">
          <DocsPortal />
        </section>

        {/* 6. INSTALLATION GUIDE */}
        <section id="install" className="space-y-4 pt-4">
          <InstallGuide />
        </section>
      </main>

      {/* FOOTER */}
      <footer className="mt-24 border-t border-neutral-800 bg-neutral-950 py-12">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 space-y-6">
          <div className="flex flex-col md:flex-row items-center justify-between gap-6">
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-xl bg-gradient-to-tr from-indigo-600 to-cyan-400 p-[1px]">
                <div className="w-full h-full bg-black rounded-[11px] flex items-center justify-center font-bold text-xs text-white">
                  LD
                </div>
              </div>
              <div>
                <div className="font-bold text-sm text-white">LiquidDynamo</div>
                <div className="text-xs text-neutral-400">Developed by Agrigence</div>
              </div>
            </div>

            <div className="flex flex-wrap items-center gap-4 text-xs text-neutral-400">
              <a 
                href="https://github.com/anksarvesh-lgtm/Liquiddynamo" 
                target="_blank" 
                rel="noopener noreferrer"
                className="hover:text-neutral-200 transition-colors flex items-center gap-1"
              >
                <Github className="w-3.5 h-3.5" />
                <span>GitHub Repository</span>
              </a>
              <span>•</span>
              <a 
                href="https://github.com/anksarvesh-lgtm/Liquiddynamo/releases" 
                target="_blank" 
                rel="noopener noreferrer"
                className="hover:text-neutral-200 transition-colors flex items-center gap-1"
              >
                <Download className="w-3.5 h-3.5" />
                <span>Releases</span>
              </a>
              <span>•</span>
              <span>GPL-3.0 License</span>
            </div>
          </div>

          <div className="pt-6 border-t border-neutral-900 text-xs text-neutral-500 leading-relaxed space-y-2">
            <p>
              LiquidDynamo is open-source software licensed under the <strong>GNU General Public License v3.0 (GPL-3.0)</strong>. 
              Based on the upstream project <strong>Boring Notch</strong> by TheBoredTeam. Modifications, custom Metal signed-distance field shaders, 
              AirPods 3D space integrations, and rebrand architecture are Copyright © 2026 Agrigence.
            </p>
            <p>
              AirPods, macOS, MacBook, Sonoma, Sequoia, SceneKit, AppKit, and Apple Silicon are trademarks of Apple Inc.
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
}
