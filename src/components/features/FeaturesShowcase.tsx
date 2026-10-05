import React, { useState } from 'react';
import { soundFx } from '../../utils/audioFeedback';
import { 
  Headphones, 
  Waves, 
  Volume2, 
  FolderDown, 
  Monitor, 
  ShieldCheck, 
  Sparkles, 
  ArrowRight, 
  Check, 
  ExternalLink 
} from 'lucide-react';

export const FeaturesShowcase: React.FC = () => {
  const [activeFeature, setActiveFeature] = useState<number>(0);

  const features = [
    {
      id: 'airpods',
      title: 'AirPods 3D Space Experience',
      badge: 'Hardware Protocol & SceneKit',
      icon: Headphones,
      color: 'indigo',
      tagline: 'Zero-gravity 3D rendered AirPods models set against an interactive cosmic starfield.',
      description: 'Reads battery levels (Left, Right, Case) via IOBluetoothDevice and Apple Accessory Protocol (AAP). Features orbit battery arcs, noise control mode switching (Noise Cancellation, Transparency, Adaptive, and Off), and real-time head-tracking mirror via CMHeadphoneMotionManager.',
      highlights: [
        'Real-time battery readouts with 15% and 5% low-battery warning alerts',
        'Direct Bluetooth Audio HAL plugin bridge for listening mode toggling',
        'Fallbacks for AirPods 1st/2nd Gen, AirPods Pro 1/2, AirPods 3/4, and AirPods Max',
        '60 FPS SceneKit rendering loop with automatic sleep during idle'
      ]
    },
    {
      id: 'liquid-engine',
      title: 'Liquid Island Engine (Metal SDF)',
      badge: 'Metal Compute & Polynomial smin',
      icon: Waves,
      color: 'cyan',
      tagline: 'Organic liquid-like signed-distance field shape emerging from the MacBook notch.',
      description: 'Replaces hard-clipped rectangular frames with an 8-lobe 2D Signed Distance Field (SDF) and polynomial smooth minimum (smin). Features Apple continuous curvature (squircles), normal vector calculation via 2D finite-difference gradient, and 3D specular light reflections.',
      highlights: [
        '8-Lobe geometry: Root, Body, Left Wing, Right Wing, Droplet, and Satellites',
        'Rule 1 guarantee: Notch is a Hole — camera cutout remains pure optical black (#000000)',
        'Zero-cost idle: CADisplayLink pauses and shaders deallocate when inactive',
        'Graceful fallbacks for Reduce Motion and Low Power Mode'
      ]
    },
    {
      id: 'hud-overlays',
      title: 'Seamless System HUD Replacements',
      badge: 'CoreAudio & IOKit Listeners',
      icon: Volume2,
      color: 'amber',
      tagline: 'Replaces clunky macOS square popups with fluid, notch-integrated meter alerts.',
      description: 'Eliminates the jarring default macOS HUD overlays for Volume, Display Brightness, and Keyboard Backlight. Listens directly to CoreAudio hardware notifications and displays a responsive spring alert that dwels for 2.0 seconds and smoothly collapses.',
      highlights: [
        'Sub-16ms latency between keyboard press and notch meter feedback',
        'Volume, Brightness, and Keyboard Backlight unified in the Alert Pop state',
        'Zero background daemon overhead or auxiliary daemons required',
        'Configurable dwell interval and graceful keyboard repeat handling'
      ]
    },
    {
      id: 'shelf',
      title: 'Liquid Shelf & AirDrop Staging Zone',
      badge: 'Drag & Drop File Management',
      icon: FolderDown,
      color: 'emerald',
      tagline: 'Friction-free staging area at the top of your display for dragging files and images.',
      description: 'Positioned right at the physical notch lip, the Liquid Shelf provides a universal drop target for dragging documents, text snippets, and images across multiple desktop spaces or fullscreen apps, with one-click AirDrop transmission to nearby contacts.',
      highlights: [
        'Accessible from any virtual desktop or fullscreen workspace',
        'Instant one-click AirDrop sharing sheet trigger',
        'Multi-file batch drop support with type-specific thumbnail previews',
        'Automatic temporary staging cleanup upon dismiss'
      ]
    },
    {
      id: 'adaptive-geometry',
      title: 'Adaptive Dual Geometry Engine',
      badge: 'Hardware Notch & Floating Pill',
      icon: Monitor,
      color: 'purple',
      tagline: 'Flawlessly transitions between physical MacBook notch and floating Dynamic Island.',
      description: 'Detects the physical display hardware profile: automatically matches the physical cutout geometry on notched MacBook Pro and MacBook Air displays, or transforms into an elegant floating pill on external displays, iMacs, Mac mini, Mac Studio, and Mac Pro.',
      highlights: [
        'NSScreen auxiliary top area measurement for pixel-perfect physical alignment',
        'Multi-monitor awareness: floats smoothly when dragged to external screens',
        'Window layering at NSWindow.Level.statusBar + 1 for seamless overlay',
        'Ignores mouse events during idle to preserve native macOS menu interactions'
      ]
    },
    {
      id: 'privacy',
      title: '100% Local & Privacy-First Architecture',
      badge: 'Zero Telemetry & GPL-3.0',
      icon: ShieldCheck,
      color: 'blue',
      tagline: 'Completely local execution with zero tracking, telemetry, or external network calls.',
      description: 'Built with strict privacy-first engineering: all device scans, media playback observations, and calendar schedules are queried locally via macOS system frameworks. No analytics, tracking IDs, or remote telemetry servers.',
      highlights: [
        'Zero external network requests or analytics trackers',
        'Bluetooth scanning interacts exclusively with your own paired peripherals',
        'Fully audited open source code under GNU General Public License v3.0 (GPL-3.0)',
        'Signed DMG distribution with automated SHA-256 build verification'
      ]
    }
  ];

  return (
    <div className="w-full space-y-6">
      <div className="flex flex-col md:flex-row md:items-end justify-between gap-4">
        <div>
          <span className="text-xs font-mono text-indigo-400 uppercase tracking-wider font-semibold">
            System Capabilities
          </span>
          <h2 className="text-2xl font-bold text-white mt-1">Engineered for Apple Silicon & Intel</h2>
          <p className="text-sm text-neutral-400 mt-1 max-w-2xl">
            LiquidDynamo elevates macOS windowing and hardware capabilities with native Swift, AppKit, Metal 3, and SceneKit.
          </p>
        </div>
      </div>

      {/* Feature Selector Cards Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {features.map((feat, idx) => {
          const Icon = feat.icon;
          const isSelected = activeFeature === idx;
          return (
            <div
              key={feat.id}
              onClick={() => {
                soundFx.playTick();
                setActiveFeature(idx);
              }}
              className={`p-5 rounded-2xl border transition-all cursor-pointer flex flex-col justify-between ${
                isSelected
                  ? 'bg-neutral-850 border-indigo-500/80 shadow-xl shadow-indigo-500/10 ring-1 ring-indigo-500/30'
                  : 'bg-neutral-900/70 border-neutral-800 hover:border-neutral-700 hover:bg-neutral-850/50'
              }`}
            >
              <div>
                <div className="flex items-center justify-between mb-3">
                  <div className={`w-10 h-10 rounded-xl flex items-center justify-center ${
                    isSelected ? 'bg-indigo-600 text-white' : 'bg-neutral-800 text-neutral-300'
                  }`}>
                    <Icon className="w-5 h-5" />
                  </div>
                  <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-neutral-800 text-neutral-400">
                    {feat.badge}
                  </span>
                </div>

                <h3 className="font-semibold text-base text-neutral-100">{feat.title}</h3>
                <p className="text-xs text-neutral-400 mt-1.5 leading-relaxed">{feat.tagline}</p>
              </div>

              <div className="pt-4 mt-4 border-t border-neutral-800/80 flex items-center justify-between text-xs">
                <span className={`font-medium ${isSelected ? 'text-indigo-400' : 'text-neutral-500'}`}>
                  {isSelected ? 'Viewing Details' : 'Click to inspect'}
                </span>
                <ArrowRight className={`w-3.5 h-3.5 transition-transform ${isSelected ? 'translate-x-1 text-indigo-400' : 'text-neutral-600'}`} />
              </div>
            </div>
          );
        })}
      </div>

      {/* Detailed Selected Feature Inspection Panel */}
      <div className="p-6 lg:p-8 rounded-2xl bg-neutral-950/80 border border-neutral-800 space-y-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 pb-4 border-b border-neutral-800">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-indigo-600/20 border border-indigo-500/40 text-indigo-400 flex items-center justify-center">
              {React.createElement(features[activeFeature].icon, { className: 'w-5 h-5' })}
            </div>
            <div>
              <h3 className="text-lg font-bold text-white">{features[activeFeature].title}</h3>
              <p className="text-xs text-neutral-400 font-mono">{features[activeFeature].badge}</p>
            </div>
          </div>
        </div>

        <p className="text-sm text-neutral-300 leading-relaxed max-w-4xl">
          {features[activeFeature].description}
        </p>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-3 pt-2">
          {features[activeFeature].highlights.map((item, i) => (
            <div key={i} className="flex items-start gap-2.5 p-3 rounded-xl bg-neutral-900/60 border border-neutral-800/80">
              <Check className="w-4 h-4 text-emerald-400 flex-shrink-0 mt-0.5" />
              <span className="text-xs text-neutral-300 leading-normal">{item}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
