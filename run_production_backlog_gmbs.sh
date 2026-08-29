#!/bin/bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${LME_REPO:-$SCRIPT_DIR}"
QUEUE_ARG="${1:-}"
CONTROL_DIR="$REPO/output/production-backlog-control"
PAUSE_FILE="$CONTROL_DIR/pause"
CURRENT_FILE="$CONTROL_DIR/current"
FAIL_LOG="$CONTROL_DIR/failures.log"

[[ -n "$QUEUE_ARG" ]] || { echo "Usage: ./run_production_backlog_gmbs.sh production_backlog/QUEUE"; exit 2; }
if [[ "$QUEUE_ARG" = /* ]]; then QUEUE_DIR="$QUEUE_ARG"; else QUEUE_DIR="$REPO/$QUEUE_ARG"; fi
ORDER="$QUEUE_DIR/run_order.txt"
VERIFY="$REPO/verify_production_backlog_gmbs.sh"

cd "$REPO" || exit 1
mkdir -p "$CONTROL_DIR"
[[ -f "$ORDER" ]] || { echo "ERROR: missing $ORDER"; exit 1; }
[[ -x "$VERIFY" ]] || { echo "ERROR: missing/executable verifier $VERIFY"; exit 1; }

if [[ -f "$PAUSE_FILE" ]]; then
  echo "Background production is paused. Resume with:"
  echo "  ./resume_production_backlog_gmbs.sh $QUEUE_ARG"
  exit 0
fi

"$VERIFY" "$QUEUE_ARG" || { echo "ERROR: GMBS backlog preflight failed. No inference launched."; exit 1; }

manifest_status() {
  local manifest="$1"
  ruby - "$manifest" "$REPO/output" <<'RUBY'
require "json"; require "yaml"
manifest, output_root = ARGV
data = YAML.safe_load_file(manifest)
name = data.fetch("name")
metadata = Dir.glob(File.join(output_root, name, "runs", "*", "metadata.json")).sort
if metadata.empty? then print "pending"; exit end
begin
  statuses = metadata.map { |path| JSON.parse(File.read(path))["status"].to_s }
  if statuses.all? { |s| s == "complete" }; print "complete"
  elsif statuses.any? { |s| s == "failed" }; print "failed"
  elsif statuses.any? { |s| s == "running" }; print "running"
  else print "unknown" end
rescue JSON::ParserError
  print "unknown"
end
RUBY
}

if command -v caffeinate >/dev/null 2>&1; then
  caffeinate -dimsu &
  CAFFEINATE_PID=$!
else
  CAFFEINATE_PID=""
  echo "WARNING: caffeinate not found; sleep prevention is not active."
fi

cleanup() {
  rm -f "$CURRENT_FILE"
  if [[ -n "${CAFFEINATE_PID:-}" ]]; then kill "$CAFFEINATE_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT INT TERM

total=$(grep -c '^experiments/' "$ORDER" || true)
new_failures=0
consecutive_failures=0
n=0

echo
echo "INTERRUPTIBLE GM BEGINNER SUITABILITY PRODUCTION"
echo "Queue: $QUEUE_ARG"
echo "Calls in frozen queue: $total"
echo "Pause safely from another terminal:"
echo "  ./pause_production_backlog.sh"
echo 'External/API inference cost: $0'
echo

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  n=$((n + 1))

  if [[ -f "$PAUSE_FILE" ]]; then
    echo
    echo "PAUSE OBSERVED after completed call. No new inference dispatched."
    echo "Resume with: ./resume_production_backlog_gmbs.sh $QUEUE_ARG"
    exit 0
  fi

  status=$(manifest_status "$f")
  case "$status" in
    complete) echo "[$n/$total] SKIP complete: $f"; continue ;;
    failed) echo "[$n/$total] SKIP previously failed (no favorable rerun): $f"; continue ;;
  esac

  {
    echo "queue=$QUEUE_ARG"
    echo "index=$n"
    echo "total=$total"
    echo "manifest=$f"
    echo "started_at=$(date '+%Y-%m-%dT%H:%M:%S%z')"
  } > "$CURRENT_FILE"

  echo
  echo "================================================================"
  echo "[$n/$total] GM BEGINNER SUITABILITY PRODUCTION: $f"
  echo "================================================================"

  command_ok=true
  bin/lme run "$f" || command_ok=false
  status=$(manifest_status "$f")

  if [[ "$command_ok" == true && "$status" == "complete" ]]; then
    consecutive_failures=0
    echo "[$n/$total] COMPLETE"
  else
    new_failures=$((new_failures + 1))
    consecutive_failures=$((consecutive_failures + 1))
    echo "$(date '+%Y-%m-%dT%H:%M:%S%z') $status $f" >> "$FAIL_LOG"
    echo "[$n/$total] FAILURE status=$status"
    echo "New failures this invocation: $new_failures; consecutive: $consecutive_failures"
    if [[ "$consecutive_failures" -ge 2 || "$new_failures" -ge 3 ]]; then
      echo
      echo "CIRCUIT BREAKER: stopping unattended production."
      echo "Reason: >=2 consecutive failures or >=3 total new failures."
      echo "Inspect $FAIL_LOG before resuming."
      exit 1
    fi
  fi

  rm -f "$CURRENT_FILE"
  if [[ -f "$PAUSE_FILE" ]]; then
    echo
    echo "PAUSE OBSERVED after current inference completed and persisted."
    echo "Resume with: ./resume_production_backlog_gmbs.sh $QUEUE_ARG"
    exit 0
  fi
done < "$ORDER"

echo
echo "================================================================"
echo "GM BEGINNER SUITABILITY PRODUCTION QUEUE FINISHED"
echo "================================================================"
echo "Queue: $QUEUE_ARG"
echo "New failures this invocation: $new_failures"
