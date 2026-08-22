#!/bin/zsh

set -u

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR" || {
  echo "ERROR: Could not enter script directory: $SCRIPT_DIR"
  exit 1
}

if [[ ! -x bin/lme ]]; then
  echo "ERROR: bin/lme not found or not executable in $(pwd)"
  exit 1
fi

MANIFESTS=(
  experiments/qwen-social-adv0229-upper-control-v1.yml
  experiments/qwen-levels-adv0262-post-scrub-fix-v1.yml
  experiments/qwen-gm-beginner-adv0287-upper-control-v2.yml
)

for f in "${MANIFESTS[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: Missing manifest: $f"
    exit 1
  fi
done

echo "Preflight: checking Qwen/mac worker..."
if ! bin/lme worker-check "${MANIFESTS[1]}"; then
  echo "ERROR: Qwen/mac worker preflight failed."
  exit 1
fi

caffeinate -dimsu &
CAFFEINATE_PID=$!
trap 'kill "$CAFFEINATE_PID" 2>/dev/null || true' EXIT

echo
echo "Working directory: $(pwd)"
echo "caffeinate active (PID $CAFFEINATE_PID)"
echo "Pruned follow-up batch: 3 jobs"

for f in "${MANIFESTS[@]}"; do
  echo
  echo "================================================================"
  echo "RUNNING: $f"
  echo "================================================================"

  if ! bin/lme run "$f"; then
    echo
    echo "ERROR: $f failed operationally; stopping batch."
    exit 1
  fi
done

echo
echo "================================================================"
echo "PRUNED FOLLOW-UP BATCH COMPLETE"
echo "================================================================"
