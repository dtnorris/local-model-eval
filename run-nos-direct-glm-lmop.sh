#!/bin/zsh
set -euo pipefail

MANIFEST="experiments/nos-direct-glm-calibration-v0.1/02-adv0262-lost-mine-of-phandelver.yml"

if [[ -n "${AF_NOS_TWO_STAGE_PROFILE:-}" ]]; then
  echo "ERROR: AF_NOS_TWO_STAGE_PROFILE is set in the parent shell; this direct experiment requires it unset." >&2
  exit 1
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: missing manifest: $MANIFEST" >&2
  exit 1
fi

echo "=== Plan ==="
env -u AF_NOS_TWO_STAGE_PROFILE bin/lme plan "$MANIFEST"

echo "=== Worker check ==="
env -u AF_NOS_TWO_STAGE_PROFILE bin/lme worker-check "$MANIFEST"

echo "=== Run exactly once ==="
caffeinate -dimsu \
  env -u AF_NOS_TWO_STAGE_PROFILE \
  bin/lme run "$MANIFEST"
