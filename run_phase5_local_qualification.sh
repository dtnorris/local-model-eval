#!/bin/zsh
set -u

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR" || exit 1

PLAN="${1:-qualification/phase5.yml}"

if [[ ! -x bin/lme-qualify ]]; then
  echo "ERROR: bin/lme-qualify not found or not executable in $(pwd)"
  exit 1
fi

if [[ ! -f "$PLAN" ]]; then
  echo "ERROR: qualification plan not found: $PLAN"
  exit 1
fi

caffeinate -dimsu &
CAFFEINATE_PID=$!
trap 'kill "$CAFFEINATE_PID" 2>/dev/null || true' EXIT

echo "Working directory: $(pwd)"
echo "Qualification plan: $PLAN"
echo "caffeinate active (PID $CAFFEINATE_PID)"
echo

bin/lme-qualify "$PLAN"
