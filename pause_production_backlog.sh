#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${LME_REPO:-$SCRIPT_DIR}"
CONTROL_DIR="$REPO/output/production-backlog-control"
PAUSE_FILE="$CONTROL_DIR/pause"
CURRENT_FILE="$CONTROL_DIR/current"

mkdir -p "$CONTROL_DIR"
date '+%Y-%m-%dT%H:%M:%S%z' > "$PAUSE_FILE"

echo "Graceful pause requested."
if [[ -f "$CURRENT_FILE" ]]; then
  echo "The current inference will NOT be killed. Production will stop after it persists."
  echo
  cat "$CURRENT_FILE"
else
  echo "No active background-production call is recorded. The next runner launch will remain paused."
fi
