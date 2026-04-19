#!/bin/sh

set -eu

PATH="/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KARABINER_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
LOG_DIR="$KARABINER_DIR/logs"
LOG_FILE="$LOG_DIR/system-sleep.log"

mkdir -p "$LOG_DIR"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  printf '%s %s\n' "$(timestamp)" "$*" >>"$LOG_FILE"
}

log "sleep requested"

/usr/bin/osascript <<'APPLESCRIPT' >>"$LOG_FILE" 2>&1
tell application "System Events" to sleep
APPLESCRIPT
