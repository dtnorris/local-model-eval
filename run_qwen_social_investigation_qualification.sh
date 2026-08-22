#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

PLAN="qualification/post-remediation-qwen-v0.1/plan.yml"
SOCIAL_PREFLIGHT="experiments/qualification/qualification-qwen-social-adv0040-remediated-v1.yml"
INVESTIGATION_PREFLIGHT="experiments/qualification/qualification-qwen-investigation-adv0053-remediated-v1.yml"

echo "============================================================"
echo "Qwen Social + Investigation post-remediation qualification"
echo "Maximum local inference calls: 10"
echo "External/API inference cost: $0"
echo "============================================================"
echo

echo "[1/3] Validating frozen qualification plan (zero inference)..."
bin/lme-qualify "$PLAN" --dry-run
echo

echo "[2/3] Checking local worker/model for both frozen profiles..."
bin/lme worker-check "$SOCIAL_PREFLIGHT"
bin/lme worker-check "$INVESTIGATION_PREFLIGHT"
echo

echo "[3/3] Starting qualification..."
echo "Numeric results are adjudicated against archived Terra only after blind local output is persisted."
echo

exec caffeinate -dimsu nice -n 10 bin/lme-qualify "$PLAN"
