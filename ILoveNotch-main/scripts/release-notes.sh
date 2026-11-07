#!/usr/bin/env bash
# Prints a version's section of CHANGELOG.md, without its heading: the release notes that the update
# prompt and the GitHub release show. Fails when the changelog has no such section.
#
#   scripts/release-notes.sh 1.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

version=${1:?usage: scripts/release-notes.sh <version, for example 1.2.0>}
# From the version's "## [x.y.z]" heading to the next heading, or the link references at the end.
notes=$(awk -v heading="## [$version]" '
    index($0, "## [") == 1 || /^\[[^]]+\]: / { if (found) exit; found = index($0, heading) == 1; next }
    found' CHANGELOG.md)
[[ $notes == *[![:space:]]* ]] || { echo "CHANGELOG.md has no section for $version" >&2; exit 1; }
printf '%s\n' "$notes"
