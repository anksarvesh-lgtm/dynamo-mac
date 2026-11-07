#!/usr/bin/env bash
# End-to-end test of a running DEBUG Island with REAL mouse/keyboard events (needs Accessibility for the terminal).
# It moves the pointer and presses keys — don't use the Mac while it runs. Keystrokes are only typed after
# search is verified open, so nothing leaks into other apps.
set -uo pipefail
cd "$(dirname "$0")/../.."
Q=.build/island/qa-input; R=scripts/island-debug.sh; D="$(getconf DARWIN_USER_TEMP_DIR)island-debug.txt"
PASS=0; FAIL=0
dump() { "$R" dump; sleep 0.25; }
mode() { dump; sed -n 's/^mode=\([a-z]*\).*/\1/p' "$D"; }
field() { dump; grep -o "$1=[^ ]*" "$D" | head -1 | cut -d= -f2; }
check() {
  if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1))
  else echo "  ✗ $1 (got '$2', want '$3')"; FAIL=$((FAIL+1)); grep -E "^trace:|^log:" "$D" | tail -10 | sed 's/^/      /'; fi
}
away() { "$Q" move 300 650; sleep 0.6; }
hover() { "$Q" glide 735 400 735 14 12 8; sleep 0.7; }
center() { "$Q" ax "Island" ; }

echo "Island E2E (real input)"
"$R" clear; "$R" music; away
check "compact with media" "$(mode)" compact
hover;            check "hover expands" "$(mode)" expanded
check "escape armed while expanded" "$(field escapeArmed)" true
check "no focus steal on hover" "$(field key)" false
"$Q" key 53; sleep 0.5; check "Escape collapses" "$(mode)" compact
away;             check "stays compact after leaving" "$(mode)" compact
check "escape disarmed when compact" "$(field escapeArmed)" false
hover; away;      check "hover out collapses" "$(mode)" compact
for i in 1 2 3 4 5 6; do "$Q" glide 735 300 735 14 4 4; "$Q" glide 735 14 735 300 4 4; done; sleep 0.8
check "rapid hover in/out settles" "$(mode)" compact

"$Q" key 49 o; sleep 0.7
if [[ "$(mode)" == search ]]; then
  check "⌥Space opens search" search search
  check "search has keyboard focus" "$(field key)" true
  "$Q" type "timer 1 min"; sleep 0.9
  "$Q" key 125; sleep 0.15; "$Q" key 126; sleep 0.15; "$Q" key 36; sleep 0.7
  check "Return runs action and closes" "$(mode)" compact
  dump; check "timer started from search" "$(grep -E '^(primary|secondaries)=' "$D" | grep -c timer | tr -d ' ')" 1
  check "focus released" "$(field key)" false
else
  check "⌥Space opens search" "$(mode)" search
fi
"$Q" key 49 o; sleep 0.6; "$Q" key 53; sleep 0.5; check "Escape closes search" "$(mode)" compact
"$Q" key 49 o; sleep 0.6; "$Q" click 300 650; sleep 0.6; check "click outside closes search" "$(mode)" compact
"$Q" key 49 o; sleep 0.6; "$Q" key 49 o; sleep 0.6; check "⌥Space toggles search off" "$(mode)" compact

away
L=$("$Q" axdump | grep -o '“Timer[^”]*”' | head -1 | tr -d '“”')
P=$("$Q" ax "$L")
"$Q" glide 300 650 ${P% *} 16 10 10; sleep 0.6
check "hovering a bubble doesn't expand" "$(mode)" compact
"$Q" click ${P% *} 16; sleep 0.5
dump; check "clicking a bubble selects it" "$(sed -n 's/^primary=\(timer\).*/\1/p' "$D")" timer
hover
scripts/qa/press.sh "Pause timer"; sleep 0.4; dump; check "Pause button" "$(sed -n 's/^primary=timer[^ ]* \([a-z]*\)/\1/p' "$D")" low
scripts/qa/press.sh "Resume timer"; sleep 0.4; dump; check "Resume button" "$(sed -n 's/^primary=timer[^ ]* \([a-z]*\)/\1/p' "$D")" normal
scripts/qa/press.sh "Stop timer"; sleep 0.5; dump; check "Stop button" "$(grep -c '^primary=timer' "$D" | tr -d ' ')" 0
check "still expanded under pointer" "$(mode)" expanded
"$Q" click 300 650; sleep 0.6; check "click outside collapses" "$(mode)" compact
"$R" clear; sleep 0.4; away; check "idle when empty" "$(mode)" idle
hover; check "idle hover shows home" "$(mode)" expanded
scripts/qa/press.sh "5m"; sleep 0.5; dump; check "home quick timer" "$(grep -c '^primary=timer' "$D" | tr -d ' ')" 1
away; "$R" clear

echo "Settings"
"$R" music; "$R" set:islandEnabled=0; sleep 0.5
check "disable hides panel" "$(field panelVisible)" false
check "disable unregisters ⌥Space" "$(field hotkey)" none
"$R" set:islandEnabled=1; sleep 0.5; away
check "enable shows panel" "$(field panelVisible)" true
check "enable restores ⌥Space" "$(field hotkey)" "⌥Space"
hover; check "hover works after re-enable" "$(mode)" expanded; away
"$R" set:hoverExpansion=0; sleep 0.3
hover; check "hover disabled: stays compact" "$(mode)" compact
P=$("$Q" ax Island); "$Q" click ${P% *} 14; sleep 0.6; check "click expands" "$(mode)" expanded
away; sleep 0.4; check "leaving collapses click-expanded" "$(mode)" compact
"$R" set:hoverExpansion=1; "$R" set:reduceMotion=1; sleep 0.3
hover; check "reduce motion: hover expands" "$(mode)" expanded; "$Q" key 53; sleep 0.4; check "reduce motion: Escape" "$(mode)" compact
"$R" set:reduceMotion=0; "$R" set:reduceTransparency=1; "$R" set:highContrast=1; hover; check "reduced transparency + contrast" "$(mode)" expanded
away; "$R" set:reduceTransparency=0; "$R" set:highContrast=0; "$R" clear

echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
