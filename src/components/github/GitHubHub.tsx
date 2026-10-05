import React, { useState } from 'react';
import { soundFx } from '../../utils/audioFeedback';
import { 
  Github, 
  GitCommit, 
  GitPullRequest, 
  Tag, 
  Download, 
  ExternalLink, 
  Copy, 
  Check, 
  Terminal, 
  AlertCircle, 
  Sparkles, 
  Music, 
  Calendar, 
  Sliders, 
  Bell, 
  BatteryCharging, 
  Headphones, 
  FileCode, 
  CheckCircle2, 
  Star 
} from 'lucide-react';

export const GitHubHub: React.FC = () => {
  const [copiedKey, setCopiedKey] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<'release' | 'commits' | 'prerelease' | 'cli' | 'badges'>('release');

  const copyToClipboard = (text: string, key: string) => {
    navigator.clipboard.writeText(text);
    soundFx.playTick();
    setCopiedKey(key);
    setTimeout(() => setCopiedKey(null), 2000);
  };

  const directCommits = [
    {
      sha: '7f9a2b1',
      message: 'feat: Liquid Island 8-lobe signed-distance field Metal shader engine',
      author: 'Agrigence',
      date: 'Oct 4, 2026',
      tag: 'Core'
    },
    {
      sha: '83c4e12',
      message: 'feat: AirPods 3D Space zero-gravity SceneKit renderer & AAP battery arcs',
      author: 'Agrigence',
      date: 'Oct 4, 2026',
      tag: 'Hardware'
    },
    {
      sha: '51d8f99',
      message: 'chore: rebrand to LiquidDynamo with com.agrigence.liquiddynamo bundle ID',
      author: 'Agrigence',
      date: 'Oct 4, 2026',
      tag: 'Rebrand'
    },
    {
      sha: '992a014',
      message: 'fix: smooth brightness stepping and CoreAudio hardware OSD latency',
      author: 'benjaminfrombe',
      date: 'Sep 25, 2026',
      tag: 'OSD'
    },
    {
      sha: '24b61cf',
      message: 'feat: Google Meet and Zoom 1-click meeting join from EventKit calendar',
      author: 'Subhanshu20101',
      date: 'Sep 24, 2026',
      tag: 'Calendar'
    },
    {
      sha: '3c190ee',
      message: 'feat: dynamic audio output route picker & captured audio waveform visualizer',
      author: 'colinchambachan',
      date: 'Sep 23, 2026',
      tag: 'Media'
    },
    {
      sha: '407d58a',
      message: 'ci: dmgbuild standalone DMG release packaging with background artwork',
      author: 'Agrigence',
      date: 'Sep 22, 2026',
      tag: 'CI/CD'
    }
  ];

  const releaseBadgesMarkdown = `[![Latest Release](https://img.shields.io/github/v/release/anksarvesh-lgtm/Liquiddynamo?style=flat-square&color=indigo)](https://github.com/anksarvesh-lgtm/Liquiddynamo/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?style=flat-square)](https://github.com/anksarvesh-lgtm/Liquiddynamo)
[![Arch](https://img.shields.io/badge/arch-Apple%20Silicon%20%7C%20Intel-informational?style=flat-square)](https://github.com/anksarvesh-lgtm/Liquiddynamo)
[![License](https://img.shields.io/badge/license-GPL--3.0-green?style=flat-square)](https://github.com/anksarvesh-lgtm/Liquiddynamo/blob/main/LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/anksarvesh-lgtm/Liquiddynamo?style=flat-square&color=yellow)](https://github.com/anksarvesh-lgtm/Liquiddynamo/stargazers)`;

  const cliCommands = `# Download the latest DMG release with GitHub CLI
gh release download --repo anksarvesh-lgtm/Liquiddynamo --pattern "*.dmg"

# Clone repository for local inspection & building
git clone https://github.com/anksarvesh-lgtm/Liquiddynamo.git

# View repository details directly in terminal
gh repo view anksarvesh-lgtm/Liquiddynamo`;

  return (
    <div className="w-full bg-neutral-900/80 border border-neutral-800 rounded-2xl p-6 lg:p-8 backdrop-blur-xl space-y-6">
      {/* Top Banner */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 pb-6 border-b border-neutral-800">
        <div>
          <div className="flex items-center gap-2 text-indigo-400 text-xs font-mono font-medium uppercase tracking-wider">
            <Github className="w-4 h-4" />
            <span>GitHub Repository & Release Inspector</span>
          </div>
          <h3 className="text-xl font-bold text-white mt-1">anksarvesh-lgtm / Liquiddynamo</h3>
          <p className="text-sm text-neutral-400 mt-1 max-w-2xl">
            Explore release artifacts, direct commit provenance, what's new changelog, and developer automation tools.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <a
            href="https://github.com/anksarvesh-lgtm/Liquiddynamo"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-1.5 px-3.5 py-2 rounded-xl bg-neutral-800 hover:bg-neutral-700 text-xs font-semibold text-white transition-colors border border-neutral-700/60"
          >
            <Github className="w-4 h-4" />
            <span>View on GitHub</span>
            <ExternalLink className="w-3.5 h-3.5 opacity-60" />
          </a>

          <a
            href="https://github.com/anksarvesh-lgtm/Liquiddynamo/releases"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-1.5 px-3.5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-xs font-semibold text-white shadow-md shadow-indigo-600/20 transition-all active:scale-95"
          >
            <Download className="w-4 h-4" />
            <span>Releases</span>
          </a>
        </div>
      </div>

      {/* Release Notice Banner: Pre-release & No PRs */}
      <div className="p-4 rounded-xl bg-neutral-950 border border-amber-500/30 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
        <div className="flex items-start gap-3">
          <div className="w-8 h-8 rounded-lg bg-amber-500/20 text-amber-400 flex items-center justify-center flex-shrink-0 mt-0.5">
            <AlertCircle className="w-4 h-4" />
          </div>
          <div>
            <div className="flex items-center gap-2 flex-wrap">
              <span className="text-xs font-mono font-semibold px-2 py-0.5 rounded bg-amber-500/20 text-amber-300 border border-amber-500/30">
                Tag: v2.8-rc.1 (Pre-release)
              </span>
              <span className="text-[11px] text-neutral-400 font-mono">Channel: Beta / Release Candidate</span>
            </div>
            <p className="text-xs text-neutral-200 font-medium mt-1">
              "There were no pull requests associated with the commits included in this release."
            </p>
            <p className="text-[11px] text-neutral-400 mt-0.5">
              GitHub currently flags this as a <strong>Pre-release only</strong> due to the <code>-rc.1</code> semantic identifier and upstream PR-gate configuration.
            </p>
          </div>
        </div>

        <button
          onClick={() => {
            soundFx.playTick();
            setActiveTab('prerelease');
          }}
          className="text-xs font-mono text-amber-400 hover:text-amber-300 whitespace-nowrap self-end sm:self-center underline underline-offset-4"
        >
          Why Pre-release Only? →
        </button>
      </div>

      {/* Navigation Subtabs */}
      <div className="flex items-center gap-2 border-b border-neutral-800 pb-3 overflow-x-auto">
        {[
          { id: 'release', label: "What's New in Release", icon: Sparkles },
          { id: 'prerelease', label: 'Why Pre-release Only?', icon: AlertCircle },
          { id: 'commits', label: 'Included Commits (No PRs)', icon: GitCommit },
          { id: 'cli', label: 'GitHub CLI & Clone', icon: Terminal },
          { id: 'badges', label: 'README Badges', icon: FileCode },
        ].map((tab) => {
          const Icon = tab.icon;
          const isActive = activeTab === tab.id;
          return (
            <button
              key={tab.id}
              onClick={() => {
                soundFx.playTick();
                setActiveTab(tab.id as typeof activeTab);
              }}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all ${
                isActive
                  ? 'bg-neutral-800 text-white shadow-sm border border-neutral-700/60'
                  : 'text-neutral-400 hover:text-neutral-200 hover:bg-neutral-850'
              }`}
            >
              <Icon className="w-3.5 h-3.5" />
              <span>{tab.label}</span>
            </button>
          );
        })}
      </div>

      {/* TAB 1: WHAT'S NEW IN RELEASE */}
      {activeTab === 'release' && (
        <div className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <div className="p-4 rounded-xl bg-neutral-950 border border-neutral-800 space-y-2">
              <div className="flex items-center gap-2 text-indigo-400 text-xs font-semibold">
                <Music className="w-4 h-4" />
                <span>Music & Media Player</span>
              </div>
              <ul className="text-xs text-neutral-300 space-y-1.5 list-disc pl-4">
                <li><strong>Compact player layout</strong> with active output device router.</li>
                <li><strong>Real-time audio waveform</strong> with low-overhead frequency capture on macOS 14.2+.</li>
                <li><strong>Synced lyrics</strong> with responsive line-by-line scroll pacing.</li>
                <li>Horizontal swipe gestures for rapid transport scrubbing.</li>
              </ul>
            </div>

            <div className="p-4 rounded-xl bg-neutral-950 border border-neutral-800 space-y-2">
              <div className="flex items-center gap-2 text-cyan-400 text-xs font-semibold">
                <Headphones className="w-4 h-4" />
                <span>AirPods 3D Space & Metal SDF</span>
              </div>
              <ul className="text-xs text-neutral-300 space-y-1.5 list-disc pl-4">
                <li>Zero-gravity 3D rendered AirPods models in SceneKit with cosmic starfield.</li>
                <li>Orbit battery arcs with AAP protocol low-charge alerts.</li>
                <li>Metal 8-lobe Signed Distance Field (SDF) continuous squircle morphing.</li>
                <li>Noise control mode switching (ANC, Transparency, Adaptive, Off).</li>
              </ul>
            </div>

            <div className="p-4 rounded-xl bg-neutral-950 border border-neutral-800 space-y-2">
              <div className="flex items-center gap-2 text-emerald-400 text-xs font-semibold">
                <Calendar className="w-4 h-4" />
                <span>Calendar & Reminders</span>
              </div>
              <ul className="text-xs text-neutral-300 space-y-1.5 list-disc pl-4">
                <li>Direct 1-click meeting join (Google Meet, Zoom, Teams, Webex).</li>
                <li>Weekly view with configurable first-day-of-week preference.</li>
                <li>Vertical scroll date picker with EventKit calendar synchronization.</li>
                <li>All-day reminder reliability across time zone boundaries.</li>
              </ul>
            </div>

            <div className="p-4 rounded-xl bg-neutral-950 border border-neutral-800 space-y-2">
              <div className="flex items-center gap-2 text-amber-400 text-xs font-semibold">
                <Sliders className="w-4 h-4" />
                <span>OSD & System Overlays</span>
              </div>
              <ul className="text-xs text-neutral-300 space-y-1.5 list-disc pl-4">
                <li>Smoother brightness stepping with reduced jump artifacting.</li>
                <li>BetterDisplay and Lunar real-time event streaming.</li>
                <li>Zero-latency CoreAudio hardware key event interception.</li>
              </ul>
            </div>

            <div className="p-4 rounded-xl bg-neutral-950 border border-neutral-800 space-y-2">
              <div className="flex items-center gap-2 text-rose-400 text-xs font-semibold">
                <Bell className="w-4 h-4" />
                <span>Notification Mirroring</span>
              </div>
              <ul className="text-xs text-neutral-300 space-y-1.5 list-disc pl-4">
                <li>Mirrors visible system notification banners inside the notch.</li>
                <li>App filtering: configure notifications per application.</li>
                <li>Multi-notification queueing in the expanded island.</li>
                <li>Accessibility-aware authorization checks.</li>
              </ul>
            </div>

            <div className="p-4 rounded-xl bg-neutral-950 border border-neutral-800 space-y-2">
              <div className="flex items-center gap-2 text-purple-400 text-xs font-semibold">
                <BatteryCharging className="w-4 h-4" />
                <span>Power & Thermal State</span>
              </div>
              <ul className="text-xs text-neutral-300 space-y-1.5 list-disc pl-4">
                <li>Connected power adapter charging wattage (e.g. 67W / 96W / 140W).</li>
                <li>Discharge time estimates alongside time-to-full charge.</li>
                <li>Battery maximum-capacity health diagnostic readout.</li>
              </ul>
            </div>
          </div>
        </div>
      )}

      {/* TAB: WHY PRE-RELEASE ONLY & HOW TO PROMOTE */}
      {activeTab === 'prerelease' && (
        <div className="space-y-6">
          <div className="p-5 rounded-2xl bg-neutral-950 border border-neutral-800 space-y-4">
            <div className="flex items-center gap-2 text-amber-400 text-xs font-semibold">
              <AlertCircle className="w-4 h-4" />
              <span>Why GitHub Restricts to "Pre-release" and Reports "No Pull Requests"</span>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs text-neutral-300">
              <div className="p-4 rounded-xl bg-neutral-900/70 border border-neutral-800 space-y-2">
                <h5 className="font-semibold text-white">1. Semantic Version Tag Suffix (-rc.1)</h5>
                <p className="text-neutral-400 leading-relaxed">
                  According to Semantic Versioning (SemVer 2.0.0), any tag containing a hyphen and pre-release identifier like <code>-rc.1</code>, <code>-beta</code>, or <code>-alpha</code> is classified by GitHub as a <strong>Pre-release</strong>. GitHub automatically checks the "Set as a pre-release" box.
                </p>
              </div>

              <div className="p-4 rounded-xl bg-neutral-900/70 border border-neutral-800 space-y-2">
                <h5 className="font-semibold text-white">2. Upstream Release Workflow PR Gate</h5>
                <p className="text-neutral-400 leading-relaxed">
                  In <code>.github/workflows/release.yml</code>, stable releases require an open Pull Request from <code>dev</code> into <code>main</code> (<em>"Expected exactly one open dev-to-main release PR"</em>). Because this release was built directly from commits on <code>main</code> without a PR, GitHub treated it as an unmerged Pre-release.
                </p>
              </div>
            </div>
          </div>

          {/* How to allow full release */}
          <div className="p-5 rounded-2xl bg-neutral-950 border border-neutral-800 space-y-4">
            <h4 className="text-sm font-bold text-white flex items-center gap-2">
              <Sparkles className="w-4 h-4 text-indigo-400" />
              <span>How to Promote to a Full Stable Release on GitHub</span>
            </h4>

            <div className="space-y-4 text-xs">
              {/* Option 1: GitHub Web UI */}
              <div className="p-4 rounded-xl bg-neutral-900 border border-neutral-800 space-y-2">
                <div className="flex items-center justify-between">
                  <span className="font-semibold text-white">Option 1: Using GitHub Web UI</span>
                  <a
                    href="https://github.com/anksarvesh-lgtm/Liquiddynamo/releases"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-indigo-400 hover:text-indigo-300 font-mono text-[11px] flex items-center gap-1"
                  >
                    <span>Open Releases Page</span>
                    <ExternalLink className="w-3 h-3" />
                  </a>
                </div>
                <ol className="list-decimal pl-5 space-y-1 text-neutral-300 leading-relaxed">
                  <li>Navigate to <strong>GitHub &gt; Releases</strong>.</li>
                  <li>Click the <strong>Edit</strong> (pencil) button on release <code>v2.8-rc.1</code>.</li>
                  <li>Scroll to the checkboxes at the bottom: <strong>Uncheck "Set as a pre-release"</strong>.</li>
                  <li>Check <strong>"Set as the latest release"</strong>.</li>
                  <li>Click <strong>Update release</strong>. It will immediately show as the official green <strong>Latest</strong> release!</li>
                </ol>
              </div>

              {/* Option 2: GitHub CLI */}
              <div className="p-4 rounded-xl bg-neutral-900 border border-neutral-800 space-y-2">
                <div className="flex items-center justify-between">
                  <span className="font-semibold text-white">Option 2: One-line Command with GitHub CLI</span>
                  <button
                    onClick={() => copyToClipboard('gh release edit v2.8-rc.1 --prerelease=false --latest', 'gh-cli-promote')}
                    className="text-indigo-400 hover:text-indigo-300 font-mono text-[11px] flex items-center gap-1"
                  >
                    {copiedKey === 'gh-cli-promote' ? <Check className="w-3 h-3 text-emerald-400" /> : <Copy className="w-3 h-3" />}
                    <span>{copiedKey === 'gh-cli-promote' ? 'Copied' : 'Copy Command'}</span>
                  </button>
                </div>
                <pre className="p-2.5 rounded bg-black/60 font-mono text-[11px] text-amber-200 overflow-x-auto">
                  <code>gh release edit v2.8-rc.1 --prerelease=false --latest</code>
                </pre>
              </div>

              {/* Option 3: Clean Stable Tag */}
              <div className="p-4 rounded-xl bg-neutral-900 border border-neutral-800 space-y-2">
                <div className="flex items-center justify-between">
                  <span className="font-semibold text-white">Option 3: Create Clean Stable Release Tag (e.g. v2.8.0 or v1.4.0)</span>
                  <button
                    onClick={() => copyToClipboard('gh release create v2.8.0 ./LiquidDynamo.dmg --title "LiquidDynamo v2.8.0" --latest', 'gh-cli-create')}
                    className="text-indigo-400 hover:text-indigo-300 font-mono text-[11px] flex items-center gap-1"
                  >
                    {copiedKey === 'gh-cli-create' ? <Check className="w-3 h-3 text-emerald-400" /> : <Copy className="w-3 h-3" />}
                    <span>{copiedKey === 'gh-cli-create' ? 'Copied' : 'Copy Command'}</span>
                  </button>
                </div>
                <pre className="p-2.5 rounded bg-black/60 font-mono text-[11px] text-emerald-200 overflow-x-auto">
                  <code>gh release create v2.8.0 ./LiquidDynamo.dmg --title "LiquidDynamo v2.8.0" --latest</code>
                </pre>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* TAB 2: INCLUDED COMMITS (NO PRS) */}
      {activeTab === 'commits' && (
        <div className="space-y-3">
          <div className="text-xs text-neutral-400 font-mono flex items-center justify-between">
            <span>Direct Commits in Tagged Release:</span>
            <span className="text-indigo-400">Target Branch: main</span>
          </div>

          <div className="rounded-xl bg-neutral-950 border border-neutral-800 divide-y divide-neutral-900">
            {directCommits.map((c) => (
              <div key={c.sha} className="p-3.5 flex flex-col sm:flex-row sm:items-center justify-between gap-3 hover:bg-neutral-900/40 transition-colors">
                <div className="flex items-start sm:items-center gap-3">
                  <span className="font-mono text-xs text-indigo-400 px-2 py-0.5 rounded bg-indigo-500/10 border border-indigo-500/20">
                    {c.sha}
                  </span>
                  <div>
                    <div className="text-xs font-medium text-neutral-200">{c.message}</div>
                    <div className="text-[11px] text-neutral-500 font-mono mt-0.5">
                      by {c.author} • {c.date}
                    </div>
                  </div>
                </div>

                <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-neutral-800 text-neutral-400 self-start sm:self-center">
                  {c.tag}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* TAB 3: GITHUB CLI & CLONE */}
      {activeTab === 'cli' && (
        <div className="space-y-4">
          <div className="flex items-center justify-between text-xs font-mono text-neutral-400">
            <span>Commands for Terminal & GitHub CLI:</span>
            <button
              onClick={() => copyToClipboard(cliCommands, 'cli')}
              className="flex items-center gap-1 text-indigo-400 hover:text-indigo-300"
            >
              {copiedKey === 'cli' ? <Check className="w-3.5 h-3.5 text-emerald-400" /> : <Copy className="w-3.5 h-3.5" />}
              <span>{copiedKey === 'cli' ? 'Copied All' : 'Copy Commands'}</span>
            </button>
          </div>

          <pre className="p-4 rounded-xl bg-neutral-950 border border-neutral-800 font-mono text-xs text-neutral-200 overflow-x-auto whitespace-pre leading-relaxed">
            <code>{cliCommands}</code>
          </pre>
        </div>
      )}

      {/* TAB 4: README BADGES */}
      {activeTab === 'badges' && (
        <div className="space-y-4">
          <div className="flex items-center justify-between text-xs font-mono text-neutral-400">
            <span>Shields.io Badges for GitHub README.md:</span>
            <button
              onClick={() => copyToClipboard(releaseBadgesMarkdown, 'badges')}
              className="flex items-center gap-1 text-indigo-400 hover:text-indigo-300"
            >
              {copiedKey === 'badges' ? <Check className="w-3.5 h-3.5 text-emerald-400" /> : <Copy className="w-3.5 h-3.5" />}
              <span>{copiedKey === 'badges' ? 'Copied Markdown' : 'Copy Badge Markdown'}</span>
            </button>
          </div>

          <div className="p-4 rounded-xl bg-neutral-950 border border-neutral-800 space-y-3">
            <div className="text-xs text-neutral-400 font-mono">Live Visual Badge Preview:</div>
            <div className="flex flex-wrap gap-2 pt-1">
              <span className="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-mono bg-indigo-600 text-white font-medium shadow-sm">
                release: v2.8-rc.1
              </span>
              <span className="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-mono bg-neutral-800 text-neutral-300">
                platform: macOS 14+
              </span>
              <span className="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-mono bg-blue-900/60 text-blue-200 border border-blue-700/50">
                arch: Apple Silicon | Intel
              </span>
              <span className="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-mono bg-emerald-900/60 text-emerald-200 border border-emerald-700/50">
                license: GPL-3.0
              </span>
            </div>

            <pre className="p-3 rounded-lg bg-neutral-900 border border-neutral-800 font-mono text-[11px] text-neutral-300 overflow-x-auto whitespace-pre mt-3">
              <code>{releaseBadgesMarkdown}</code>
            </pre>
          </div>
        </div>
      )}
    </div>
  );
};
