#!/usr/bin/env bash
# Benchmarks open/close morphs of a running DEBUG Island: Island + WindowServer CPU and frame pacing.
R="$(dirname "$0")/../island-debug.sh"; F="$(getconf DARWIN_USER_TEMP_DIR)island-frames.txt"
CYCLES=${1:-8}
PID=$(pgrep -x Island); WS=$(pgrep -x WindowServer)
"$R" clear; "$R" music; "$R" timer; sleep 0.6
t0=$(ps -o time= -p $PID); w0=$(ps -o time= -p $WS)
"$R" "frames:$(echo "$CYCLES * 1.0 + 0.5" | bc)"
for i in $(seq 1 $CYCLES); do "$R" expand; sleep 0.5; "$R" collapse; sleep 0.5; done
sleep 0.7
t1=$(ps -o time= -p $PID); w1=$(ps -o time= -p $WS)
secs() { echo "$1" | awk -F: '{ if (NF==3) print $1*3600+$2*60+$3; else print $1*60+$2 }'; }
echo "Island CPU: $(echo "$(secs $t1) - $(secs $t0)" | bc)s   WindowServer CPU: $(echo "$(secs $w1) - $(secs $w0)" | bc)s   over ${CYCLES} cycles"
echo "frames: $(cat "$F")"
