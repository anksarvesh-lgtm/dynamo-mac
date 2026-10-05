import React, { useState } from 'react';
import { SYSTEM_REQUIREMENTS } from '../../data/liquiddynamoData';
import { soundFx } from '../../utils/audioFeedback';
import { 
  Terminal, 
  Copy, 
  Check, 
  Download, 
  ShieldAlert, 
  Apple, 
  Cpu, 
  ExternalLink, 
  FileCode, 
  CheckCircle2 
} from 'lucide-react';

export const InstallGuide: React.FC = () => {
  const [copiedIndex, setCopiedIndex] = useState<number | null>(null);

  const copyToClipboard = (text: string, index: number) => {
    navigator.clipboard.writeText(text);
    soundFx.playTick();
    setCopiedIndex(index);
    setTimeout(() => setCopiedIndex(null), 2000);
  };

  const gatekeeperCommand = `xattr -dr com.apple.quarantine "/Applications/LiquidDynamo.app"`;

  const buildCommands = `# 1. Clone repository
git clone https://github.com/anksarvesh-lgtm/Liquiddynamo.git
cd Liquiddynamo

# 2. Open project in Xcode
open LiquidDynamo.xcodeproj

# 3. Build & Package DMG
bash build_dmg.sh`;

  return (
    <div className="w-full bg-neutral-900/80 border border-neutral-800 rounded-2xl p-6 lg:p-8 backdrop-blur-xl space-y-8">
      <div>
        <div className="flex items-center gap-2 text-indigo-400 text-xs font-mono font-medium uppercase tracking-wider">
          <Download className="w-4 h-4" />
          <span>Deployment & Local Compilation</span>
        </div>
        <h3 className="text-xl font-bold text-white mt-1">Installation & Source Build Guide</h3>
        <p className="text-sm text-neutral-400 mt-1 max-w-2xl">
          Everything required to run LiquidDynamo on macOS or compile locally from the uploaded Xcode project.
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Release Install Card */}
        <div className="p-6 rounded-2xl bg-neutral-950 border border-neutral-800 flex flex-col justify-between space-y-6">
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2.5">
                <div className="w-8 h-8 rounded-lg bg-indigo-600/20 text-indigo-400 flex items-center justify-center font-bold text-xs">
                  1
                </div>
                <h4 className="font-bold text-base text-white">Precompiled Disk Image (.dmg)</h4>
              </div>
              <span className="text-[11px] font-mono px-2 py-0.5 rounded bg-emerald-500/20 text-emerald-400">
                Recommended
              </span>
            </div>

            <p className="text-xs text-neutral-400 leading-relaxed">
              Download the latest verified release DMG package directly from the repository release tag. Drag <strong>LiquidDynamo.app</strong> into your <code>/Applications</code> folder.
            </p>

            <a
              href="https://github.com/anksarvesh-lgtm/Liquiddynamo/releases"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-medium shadow-md shadow-indigo-600/20 transition-all"
            >
              <Download className="w-4 h-4" />
              <span>Download LiquidDynamo.dmg (GitHub Releases)</span>
              <ExternalLink className="w-3.5 h-3.5 opacity-60" />
            </a>

            {/* Gatekeeper bypass tip */}
            <div className="p-4 rounded-xl bg-amber-500/10 border border-amber-500/30 space-y-2 mt-4">
              <div className="flex items-center justify-between text-xs text-amber-300 font-semibold">
                <span className="flex items-center gap-1.5">
                  <ShieldAlert className="w-4 h-4" /> macOS Gatekeeper Notice
                </span>
                <button
                  onClick={() => copyToClipboard(gatekeeperCommand, 1)}
                  className="flex items-center gap-1 font-mono text-[10px] text-amber-400 hover:text-amber-200"
                >
                  {copiedIndex === 1 ? <Check className="w-3 h-3" /> : <Copy className="w-3 h-3" />}
                  <span>{copiedIndex === 1 ? 'Copied' : 'Copy Command'}</span>
                </button>
              </div>
              <p className="text-[11px] text-neutral-300 leading-relaxed">
                If macOS flags the application as downloaded from an untrusted developer, run this quick command in Terminal:
              </p>
              <code className="block p-2 rounded bg-neutral-900 border border-neutral-800 text-[11px] font-mono text-amber-200 break-all">
                {gatekeeperCommand}
              </code>
            </div>
          </div>
        </div>

        {/* Build from Source Card */}
        <div className="p-6 rounded-2xl bg-neutral-950 border border-neutral-800 flex flex-col justify-between space-y-4">
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2.5">
                <div className="w-8 h-8 rounded-lg bg-neutral-800 text-neutral-300 flex items-center justify-center font-bold text-xs">
                  2
                </div>
                <h4 className="font-bold text-base text-white">Build from Source (Xcode 15+)</h4>
              </div>
              <span className="text-[11px] font-mono px-2 py-0.5 rounded bg-neutral-800 text-neutral-400">
                GPL-3.0
              </span>
            </div>

            <p className="text-xs text-neutral-400 leading-relaxed">
              Compile directly with Xcode Command Line Tools. The repository includes an automated packaging pipeline with <code>build_dmg.sh</code> and <code>Configuration/dmg/dmgbuild_settings.py</code>.
            </p>

            <div className="space-y-2">
              <div className="flex items-center justify-between text-xs font-mono text-neutral-400">
                <span>Terminal Compilation Steps:</span>
                <button
                  onClick={() => copyToClipboard(buildCommands, 2)}
                  className="flex items-center gap-1 text-[11px] text-indigo-400 hover:text-indigo-300"
                >
                  {copiedIndex === 2 ? <Check className="w-3 h-3 text-emerald-400" /> : <Copy className="w-3 h-3" />}
                  <span>{copiedIndex === 2 ? 'Copied' : 'Copy All'}</span>
                </button>
              </div>

              <pre className="p-3.5 rounded-xl bg-neutral-900 border border-neutral-800 text-[11px] font-mono text-neutral-200 overflow-x-auto whitespace-pre">
                <code>{buildCommands}</code>
              </pre>
            </div>
          </div>
        </div>
      </div>

      {/* System Requirements Specs */}
      <div className="p-6 rounded-2xl bg-neutral-950/60 border border-neutral-800 space-y-4">
        <h4 className="text-xs font-semibold text-neutral-300 font-mono uppercase tracking-wider">
          Compatibility & System Specifications
        </h4>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-xs">
          <div className="p-3.5 rounded-xl bg-neutral-900/80 border border-neutral-800">
            <div className="text-[11px] font-mono text-neutral-500 uppercase">Operating System</div>
            <div className="font-medium text-neutral-200 mt-1">{SYSTEM_REQUIREMENTS.os}</div>
            <div className="text-[11px] text-neutral-400 mt-0.5">Compatible with Apple Silicon & Intel</div>
          </div>

          <div className="p-3.5 rounded-xl bg-neutral-900/80 border border-neutral-800">
            <div className="text-[11px] font-mono text-neutral-500 uppercase">Display Compatibility</div>
            <div className="font-medium text-neutral-200 mt-1">MacBook Notch & External Monitors</div>
            <div className="text-[11px] text-neutral-400 mt-0.5">Auto-switches to Floating Pill Island</div>
          </div>

          <div className="p-3.5 rounded-xl bg-neutral-900/80 border border-neutral-800">
            <div className="text-[11px] font-mono text-neutral-500 uppercase">License & Attribution</div>
            <div className="font-medium text-neutral-200 mt-1">{SYSTEM_REQUIREMENTS.license}</div>
            <div className="text-[11px] text-neutral-400 mt-0.5">Upstream: Boring Notch (TheBoredTeam)</div>
          </div>
        </div>
      </div>
    </div>
  );
};
