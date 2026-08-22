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
  experiments/nemotron-phase4-gm-prep-adv0288-v1.yml
  experiments/nemotron-phase4-player-agency-adv0287-v1.yml
  experiments/nemotron-phase4-tactical-adv0230-v1.yml
  experiments/qwen-sessions-adv0053-post-scrub-fix-v1.yml
  experiments/qwen-fantastic-weirdness-adv0040-post-scrub-fix-v1.yml
)

for f in "${MANIFESTS[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: Missing manifest: $f"
    exit 1
  fi
done

caffeinate -dimsu &
CAFFEINATE_PID=$!
trap 'kill "$CAFFEINATE_PID" 2>/dev/null || true' EXIT

echo "Working directory: $(pwd)"
echo "caffeinate active (PID $CAFFEINATE_PID)"
echo "Batch jobs: ${#MANIFESTS[@]}"

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
echo "ALL 5 EXPERIMENTS COMPLETE"
echo "================================================================"
