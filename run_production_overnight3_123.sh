#!/bin/zsh
set -u

REPO="${LME_REPO:-$HOME/code/local-model-eval}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORDER="$SCRIPT_DIR/production_overnight3_run_order.txt"
VERIFY="$SCRIPT_DIR/verify_production_overnight3_123.sh"
FAILED="$REPO/production_overnight3_failed.txt"

cd "$REPO" || { echo "ERROR: Could not find $REPO"; exit 1; }
[[ -x "$VERIFY" ]] || { echo "ERROR: missing/executable verifier $VERIFY"; exit 1; }
[[ -f "$ORDER" ]] || { echo "ERROR: missing $ORDER"; exit 1; }

# Hard gate: this performs matrix checks, bin/lme plan on all manifests, and worker/model check.
# It never launches inference.
"$VERIFY" || { echo "ERROR: production preflight failed. No inference launched."; exit 1; }

total=$(grep -c '^experiments/' "$ORDER" || true)
[[ "$total" -eq 123 ]] || { echo "ERROR: expected 123 run manifests; got $total"; exit 1; }

: > "$FAILED"

caffeinate -dimsu &
CAFFEINATE_PID=$!
trap 'kill "$CAFFEINATE_PID" 2>/dev/null || true' EXIT INT TERM

echo
echo "Working directory: $(pwd)"
echo "caffeinate active (PID $CAFFEINATE_PID)"
echo "Model: qwen => qwen3.6:35b-a3b"
echo "Production cells: 123 (9 AMC-existing cells protected/skipped)"
echo "Completed jobs are skipped by bin/lme, so this batch is resumable."

n=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  n=$((n + 1))

  echo
  echo "================================================================"
  echo "[$n/$total] PRODUCTION: $f"
  echo "================================================================"

  if ! bin/lme run "$f"; then
    echo "FAILED: $f" | tee -a "$FAILED"
    echo "Continuing to the next production cell so one source/job does not waste the overnight window."
  fi
done < "$ORDER"

echo
echo "================================================================"
echo "OVERNIGHT3 PRODUCTION BATCH FINISHED"
echo "================================================================"
if [[ -s "$FAILED" ]]; then
  echo "Some production cells failed. Review: $FAILED"
else
  rm -f "$FAILED"
  echo "No operational failures recorded."
fi
