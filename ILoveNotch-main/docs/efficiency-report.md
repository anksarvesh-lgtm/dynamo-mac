# ILoveNotch: efficiency report

Real-world measurements of ILoveNotch running for 20 hours on a working laptop. This file is the raw
content for a designed page. Every number here was measured, and the notes at the end say which
claims are safe to make in public.

---

## At a glance

These are the strongest numbers for a hero section.

| Stat | Value | What it means |
|---|---|---|
| Share of the Mac's total energy | **0.45%** | Over ~18 hours of logged time, across 47 apps |
| CPU when idle | **0.0%** | Measured over 30 seconds with the notch closed |
| Average CPU while the Mac was awake | **0.6% of one core** | About 0.04% of the whole 15-core chip |
| Total CPU time in 20 hours | **2 min 49 s** | Launch included |
| Energy Impact (Activity Monitor's score) | **0.56** | WindowServer: 272. Chrome: 26 |
| Times it kept the Mac awake | **0** | It never blocks sleep |
| Times it woke the Mac from sleep | **0** | It never appears in the system's wake log |
| Memory in active use | **77 MB, flat** | No growth between hour 15 and hour 20 |
| Threads | **9** | |

Taglines the numbers support:

- "Uses about 100× less energy than VS Code and 34× less than Chrome on the same Mac, on the same day."
- "Used less energy than Finder."
- "0.0% CPU at rest."
- "Never keeps your Mac awake."

---

## Test setup

| | |
|---|---|
| Machine | Apple M5 Pro laptop, 15 CPU cores, 24 GB RAM |
| macOS | 26.6.2 (25G83) |
| App | ILoveNotch, release build installed 24 Sep 2026, 20:19 |
| Launched | Thu 24 Sep 2026, 20:19 IST |
| Snapshot taken | Fri 25 Sep 2026, 16:31 IST |
| Total time running | 20 h 12 min |
| Time the Mac was awake | ~8 h 11 min (the rest was lid-closed sleep) |
| Features in use | Notch, Media (now playing + waveform), Usage (Claude, Codex, Copilot) |
| Usage refresh in the background | Off (it refreshes every 5 minutes only while the usage panel is open) |
| Kind of day | A normal heavy work day: VS Code, Chrome, Claude Code sessions, chat apps, music |

When the Mac was awake:

| From | To | Length |
|---|---|---|
| 24 Sep 20:19 | 20:25 | 6 min |
| 24 Sep 21:42 | 25 Sep 02:30 | 4 h 48 min |
| 25 Sep 10:35 | 11:51 | 1 h 17 min |
| 25 Sep 12:36 | 14:07 | 1 h 31 min |
| 25 Sep 16:01 | 16:31 | 29 min |

---

## Battery and energy

Source: macOS's own energy log (powerlog, the data behind Activity Monitor's "12 hr Power" column).
It covers every app over the same window, about 22:00 on 24 Sep to 16:07 on 25 Sep.

### Share of the Mac's total energy

| Rank | App | Share of energy |
|---|---|---|
| 1 | VS Code | 44.81% |
| 2 | macOS system work not billed to any app | 24.54% |
| 3 | Google Chrome | 15.24% |
| 4 | Zalo | 4.06% |
| 5 | Notion | 2.14% |
| 6 | Firefox | 2.01% |
| 7 | WhatsApp | 1.94% |
| 8 | Safari | 0.82% |
| 9 | Spotlight | 0.76% |
| 10 | Aerial wallpaper | 0.65% |
| 11 | Finder | 0.57% |
| 12 | Recordly | 0.56% |
| **13** | **ILoveNotch** | **0.45%** |
| 14 | Text cursor UI (macOS) | 0.30% |
| 15 | Microsoft Excel | 0.29% |
| 19 | Spotify | 0.10% |

47 apps and services appear in the log.

### CPU wakeups

A wakeup is each time an app pulls the processor out of its low-power rest. Fewer wakeups means
better battery life.

| App | Wakeups over the logged window |
|---|---|
| **ILoveNotch** | **1,502** |
| Chrome | 224,112 |
| VS Code | 525,651 |

ILoveNotch caused about 150× fewer wakeups than Chrome.

### Live power sample

Source: `powermetrics`, 6 samples of 5 seconds each, taken at 16:29 while the Mac was in normal use.

| Process | CPU (ms per second) | Energy Impact |
|---|---|---|
| **ILoveNotch** | **1.84** (range 0.67–3.62) | **0.56** (range 0.12–1.30) |
| Chrome (main process only) | 22.6 | 26.2 |
| WindowServer (macOS) | 211.8 | 271.7 |

### GPU

The energy log records 0 J of GPU energy for ILoveNotch, against 293 J for Chrome and 60 J for VS
Code. See the note at the end before using this number.

---

## CPU

| Stat | Value |
|---|---|
| Total CPU time since launch | 2 min 49 s (168.6 s) over 20 h 12 min |
| Average while awake | 0.57% of one core (168.6 s ÷ 8 h 11 min) |
| As a share of the whole chip | ~0.04% (15 cores) |
| Idle, notch closed (30 s sample) | 0.0% CPU, 0 new wakeups |
| Threads | 9 |
| Open files and handles | ~76 |

---

## Memory

| Stat | 11:12, hour 15 | 16:31, hour 20 |
|---|---|---|
| Memory in active use (live heap) | 78.3 MB | 77.0 MB |
| Memory footprint (Activity Monitor's "Memory" column) | 130.5 MB | 162.4 MB |
| Peak footprint since launch | 374.3 MB | 374.3 MB |
| Share of 24 GB RAM (footprint) | 0.5% | 0.7% |

**No leak.** Memory in active use was flat, and even dropped slightly, between hour 15 and hour 20.
The footprint rose because of the one-off spikes explained below: macOS hadn't reclaimed the memory
they freed yet. The fix below removes those spikes.

What the 77 MB holds:

| Part | Size |
|---|---|
| 30 days of Claude usage history, cached so the usage panel opens instantly | ~29 MB |
| AI model price table | 2.1 MB |
| Interface, fonts, icons and macOS frameworks | the rest |

---

## The one spike, found and fixed

**What happened:** the footprint peaked once at **374 MB**. ILoveNotch works out your AI spend by
reading the usage logs Claude Code and Codex keep on your Mac. The reader kept every piece of a log
in memory until it finished the whole file. The biggest log here was 80 MB, and on a fresh launch
the app reads up to 8 logs at once.

**The fix:** the reader now releases memory after each 64 KB piece. It's a 6-line change in one
file, it covers every usage source (Claude, Codex, Grok, pi), and the 55 related tests pass (1 skipped).

Measured on the real logs from this Mac:

| Scenario | Peak memory before | Peak memory after | Saved |
|---|---|---|---|
| Reading the 80 MB active session log | 120 MB | 6 MB | 95% |
| Reading the 8 largest logs at once (fresh launch) | 223 MB | 20 MB | 91% |
| CPU time for the 80 MB log | 0.6 s | 0.6 s | unchanged |

**Status:** fixed in code, not yet in a release. The measurements above come from the version that
still has the spike.

---

## Background helpers

| Helper | What it does | Cost |
|---|---|---|
| Media helper (the system's `perl` running ILoveNotch's script) | Streams now-playing info from macOS | 6.4 MB memory, 0.2 s CPU per run; one copy at a time, restarted cleanly on each wake |
| Audio waveform | Listens to playing audio to animate the waveform | Runs only while Media is on screen and playing: 2 sessions, 4 seconds total in 20 hours |

---

## Sleep behaviour

| Stat | Value |
|---|---|
| Sleep-blocking requests held | 0 |
| Times it woke the Mac | 0 (every wake request came from macOS services: powerd, dasd, mDNSResponder, PowerUIAgent) |
| Sleep cycles survived | 4 lid-closed sleeps plus the overnight maintenance wakes, no restarts or crashes |

---

## Network and disk

| Stat | Value |
|---|---|
| Network connections | ~32 secure connections in the first 15 hours: usage checks for Claude, Codex and Copilot, every 5 minutes, only while the usage panel is open |
| App's own log output | 8 lines in 15 hours |
| Disk reads | 982 MB over the logged window (see below) |

**The next improvement:** most of those disk reads come from re-reading the active Claude session
log (80 MB and growing) on every 5-minute refresh while the usage panel is open. Reading only the
new lines would cut both the disk reads and the ~0.6 s of CPU per refresh to almost zero.

---

## Notes for the designer: which claims are safe

| Claim | OK to use? | Why |
|---|---|---|
| "0.45% of the Mac's energy" / "less than Finder" / "~100× less than VS Code" | Yes, with "on our test Mac" | Real measurements, but they depend on how much each app was used that day |
| "0.0% CPU at rest" | Yes | Measured with the notch closed |
| "Never keeps your Mac awake" / "never wakes your Mac" | Yes | Zero in the system's power log over 20 hours |
| "No memory leaks" | Yes, as "memory stayed flat over 20 hours" | A single 20-hour run, not a guarantee |
| "Uses zero GPU" | **No** | The notch is drawn by macOS (WindowServer), and that cost isn't billed to any single app. Say "no GPU energy of its own" or leave it out |
| "Under 10 MB of memory" | **No** | The footprint is 130–160 MB. Use the energy and CPU numbers as the hero stats instead |
| The 95% / 91% memory savings | Yes, as "after our latest fix" | Only once the fix ships in a release |

---

## How it was measured

| Measurement | Tool |
|---|---|
| CPU time, uptime, memory | `ps`, `footprint`, `heap` (built into macOS) |
| Idle CPU and wakeups | `top` over 30 s |
| Live power | `powermetrics` (6 × 5 s samples) |
| Energy history and ranking | macOS powerlog database (`CurrentPowerlog.PLSQL`) |
| Sleep, wake and sleep-blocking | `pmset -g log`, `pmset -g assertions` |
| App behaviour (audio, network, refreshes) | macOS unified log (`log show`) |
| Memory spike before and after | A benchmark copy of the log reader run on the real 80 MB log and the 8 largest logs, measured with `/usr/bin/time -l` |
