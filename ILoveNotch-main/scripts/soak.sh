#!/usr/bin/env bash
# Samples the running ILoveNotch's CPU and memory and checks them against the performance gates
# (docs/plan/implementation-plan.md#8-performance-gates):
#
#   scripts/soak.sh          # 10 minutes, a sample every 10 seconds
#   scripts/soak.sh 480      # the 8-hour soak
#
# Leave the notch closed for an idle soak, or use it as usual for an active one. The samples are
# written to build/soak/ as CSV. Memory is the app's footprint (what Activity Monitor shows as
# Memory); the media helper runs in its own process and is reported alongside.
set -euo pipefail
cd "$(dirname "$0")/.."

minutes=${1:-10}
interval=${2:-10}
pid=$(pgrep -x ILoveNotch) || { echo "ILoveNotch isn't running" >&2; exit 1; }
mkdir -p build/soak
csv="build/soak/$(date +%Y%m%d-%H%M%S).csv"
echo "seconds,cpu_percent,footprint_mb,helper_footprint_mb" >"$csv"

# The footprint in MB, from `footprint`'s "Footprint: 42 MB" (or KB, GB) line; 0 if not running.
footprint_mb() {
    [[ -n ${1:-} ]] || { echo 0; return; }
    footprint -p "$1" 2>/dev/null | awk '/Footprint:/ {
        for (i = 1; i <= NF; i++) if ($i == "Footprint:") { value = $(i + 1); unit = $(i + 2) }
        if (unit == "KB") value /= 1024; else if (unit == "GB") value *= 1024
        printf "%.1f\n", value; found = 1; exit }
        END { if (!found) print 0 }'
}

samples=$((minutes * 60 / interval))
echo "Sampling ILoveNotch ($pid) every ${interval}s for $minutes min into $csv"
for ((sample = 0; sample < samples; sample++)); do
    kill -0 "$pid" 2>/dev/null || { echo "ILoveNotch quit during the soak" >&2; exit 1; }
    helper=$(pgrep -f mediaremote-adapter.pl | head -1 || true)
    echo "$((sample * interval)),$(ps -o %cpu= -p "$pid" | tr -d ' '),$(footprint_mb "$pid"),$(footprint_mb "$helper")" >>"$csv"
    sleep "$interval"
done

# Median and 95th-percentile CPU, and memory at the start, end, and peak, against the gates.
tail -n +2 "$csv" | sort -t, -k2 -n | awk -F, -v minutes="$minutes" '
    { cpu[NR] = $2; memory[$1] = $3; if ($3 > peak) peak = $3; helper = $4; if (NR == 1 || $1 < first) first = $1; if ($1 > last) last = $1 }
    END {
        median = cpu[int((NR + 1) / 2)]; p95 = cpu[int(NR * 0.95 + 0.5) > 0 ? int(NR * 0.95 + 0.5) : 1]
        drift = memory[last] - memory[first]
        printf "CPU:     median %.1f%%, p95 %.1f%%   (gate: median <= 0.3%%, p95 <= 1%%, when idle)\n", median, p95
        printf "Memory:  %.1f MB at start, %.1f MB at the end, %.1f MB peak   (gate: <= 120 MB)\n", memory[first], memory[last], peak
        printf "Drift:   %+.1f MB over %d min   (gate: <= 10 MB over 8 hours)\n", drift, minutes
        printf "Helper:  %.1f MB\n", helper
    }'
