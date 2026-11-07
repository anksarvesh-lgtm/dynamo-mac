#!/usr/bin/env bash
set -euo pipefail

file="/Users/ying/Documents/AI/CodeIsland/ClaudeIsland/UI/Views/CompletionPanel/ClaudeStopVariantView.swift"

if ! grep -q 'text: promptText,' "$file"; then
  echo "promptText row not found"
  exit 1
fi

if ! grep -A4 'text: promptText,' "$file" | grep -q 'lineLimit: 1'; then
  echo "expected promptText lineLimit: 1"
  exit 1
fi

if ! grep -q 'text: responseText,' "$file"; then
  echo "responseText row not found"
  exit 1
fi

if ! grep -A4 'text: responseText,' "$file" | grep -q 'lineLimit: 3'; then
  echo "expected responseText lineLimit: 3"
  exit 1
fi

echo "completion panel layout checks passed"
