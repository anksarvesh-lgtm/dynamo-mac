#!/usr/bin/env bash
# press.sh "<accessibility label>" — clicks an Island control by its VoiceOver label with a real mouse event.
Q="$(dirname "$0")/../../.build/island/qa-input"
P=$("$Q" ax "$1") || { echo "NOT FOUND: $1"; exit 2; }
"$Q" click $P
