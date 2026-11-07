#!/usr/bin/env bash
# "Update ILoveNotch" for builds made from this checkout. The app's menu bar item runs it, and so
# does `make update`: fast-forward main when that's safe, rebuild, reinstall into /Applications,
# and relaunch. Output goes to ~/Library/Logs/OpenNotch/update.log when the app runs it.
set -euo pipefail
cd "$(dirname "$0")/.."
# Apps don't inherit your shell's PATH; add Homebrew's so make can find xcodegen.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

echo "== $(date): updating from $(pwd)"
branch=$(git rev-parse --abbrev-ref HEAD)
if [[ $branch == main && -z $(git status --porcelain) ]]; then
    git pull --ff-only --quiet || echo "Couldn't fast-forward main; building what's here."
else
    echo "On $branch with local changes or off main: building what's here without pulling."
fi
echo "Building $(git rev-parse --short HEAD) on $branch"
make install
