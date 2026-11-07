# Live Football ⚽

Live FIFA World Cup 2026 scores in your SuperIsland — country flags, goal
celebrations, and the full fixture list.

Inspired by [claudinho](https://github.com/arturogarrido/claudinho), which
brings the same tournament to the terminal.

## What it does

- **Compact pill** — the featured match: flags, score (or kickoff time), and a
  pulsing live minute. When several matches are live it auto-rotates every 10s,
  preferring your favorite team.
- **Goal celebrations** — when a score changes the island pops open with a
  spinning ball and blinking **GOAL!** flash for the scoring side, plus a
  notification (`⚽ GOOOAL — Canada! 🇨🇦 Canada 1–0 Bosnia-Herzegovina 🇧🇦 · 23'`)
  and haptic feedback.
- **Expanded drawer** — featured match with big flags, score, minute, stage,
  and venue; chevrons cycle through matches.
- **Detail panel** — a fixtures browser with **Today / Fixtures / Results**
  tabs, day headers, group/stage labels, live indicators, and a star on your
  favorite team's matches. Tap any row to feature it in the pill. The safari
  button opens the full schedule in your browser.
- **Notch mode** — on notched Macs, home flag + score on the left, score +
  away flag on the right of the hardware notch.

## Data

ESPN's public keyless scoreboard endpoint (same source claudinho uses), polled
every 30s while matches are live (configurable: 15/30/60s), once a minute near
kickoff, and every 5 minutes otherwise. Country flags are ESPN CDN images;
notifications use emoji flags. The fixture window covers 2 days back to 8 days
ahead.

> Independent fan project — not affiliated with FIFA or ESPN. Displays factual
> match data only.

## Settings

- Favorite team (FIFA trigram, e.g. `USA`, `BRA`, `ARG`) — prioritized in the
  pill, starred in lists; optionally restrict kickoff/FT alerts to it.
- Toggles for goal / kickoff / full-time notifications and sound.
- Live refresh interval picker.
