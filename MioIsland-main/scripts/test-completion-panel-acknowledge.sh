#!/usr/bin/env bash
set -euo pipefail

root="/Users/ying/Documents/AI/CodeIsland"
loc="$root/ClaudeIsland/Core/Localization.swift"
claude="$root/ClaudeIsland/UI/Views/CompletionPanel/ClaudeStopVariantView.swift"
subagent="$root/ClaudeIsland/UI/Views/CompletionPanel/SubagentDoneVariantView.swift"

rg -n 'static var qrAcknowledge:' "$loc" >/dev/null
rg -n 'L10n\.qrAcknowledge' "$claude" >/dev/null
rg -n 'L10n\.qrAcknowledge' "$subagent" >/dev/null

echo "completion panel acknowledge button wiring looks present"
