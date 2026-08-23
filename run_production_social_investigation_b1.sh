#!/bin/zsh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${LME_REPO:-$SCRIPT_DIR}"
ORDER="$SCRIPT_DIR/production_social_investigation_b1_run_order.txt"
VERIFY="$SCRIPT_DIR/verify_production_social_investigation_b1.sh"
FAILED="$REPO/production_social_investigation_b1_failed.txt"

SOCIAL_ENV="AF_SOCIAL_INTERACTION_GUARDRAIL_PROFILE"
SOCIAL_PROFILE="phase6-v0.3"
INVESTIGATION_ENV="AF_INVESTIGATION_GUARDRAIL_PROFILE"
INVESTIGATION_PROFILE="phase6-v0.4"

cd "$REPO" || { echo "ERROR: Could not find $REPO"; exit 1; }
[[ -x "$VERIFY" ]] || { echo "ERROR: missing/executable verifier $VERIFY"; exit 1; }
[[ -f "$ORDER" ]] || { echo "ERROR: missing $ORDER"; exit 1; }

"$VERIFY" || { echo "ERROR: Social/Investigation production preflight failed. No inference launched."; exit 1; }

total=$(grep -c '^experiments/' "$ORDER" || true)
[[ "$total" -eq 63 ]] || { echo "ERROR: expected 63 run manifests; got $total"; exit 1; }

export "$SOCIAL_ENV=$SOCIAL_PROFILE"
export "$INVESTIGATION_ENV=$INVESTIGATION_PROFILE"

: > "$FAILED"

caffeinate -dimsu &
CAFFEINATE_PID=$!
trap 'kill "$CAFFEINATE_PID" 2>/dev/null || true' EXIT INT TERM

echo
echo "Working directory: $(pwd)"
echo "caffeinate active (PID $CAFFEINATE_PID)"
echo "Model: qwen => qwen3.6:35b-a3b"
echo "Social profile: $SOCIAL_ENV=$SOCIAL_PROFILE"
echo "Investigation profile: $INVESTIGATION_ENV=$INVESTIGATION_PROFILE"
echo "Production cells: 63 (3 accepted AFAO cells protected/skipped)"
echo "External/API inference cost: $0"
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
    echo "Continuing to the next production cell so one source/job does not waste the compute window."
  fi
done < "$ORDER"

echo
echo "================================================================"
echo "SOCIAL + INVESTIGATION PRODUCTION BATCH B1 FINISHED"
echo "================================================================"
if [[ -s "$FAILED" ]]; then
  echo "Some production cells failed. Review: $FAILED"
else
  rm -f "$FAILED"
  echo "No operational failures recorded."
fi
