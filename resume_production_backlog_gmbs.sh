#!/bin/bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${LME_REPO:-$SCRIPT_DIR}"
QUEUE_ARG="${1:-}"
PAUSE_FILE="$REPO/output/production-backlog-control/pause"
[[ -n "$QUEUE_ARG" ]] || { echo "Usage: ./resume_production_backlog_gmbs.sh production_backlog/QUEUE"; exit 2; }
rm -f "$PAUSE_FILE"
exec "$REPO/run_production_backlog_gmbs.sh" "$QUEUE_ARG"
