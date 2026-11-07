#!/usr/bin/env bash
# prints the running DEBUG Island's mode line
"$(dirname "$0")/../island-debug.sh" dump; sleep 0.25; head -1 "$(getconf DARWIN_USER_TEMP_DIR)island-debug.txt"
