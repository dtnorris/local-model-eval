#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"

RUN_ORDER="qualification/levels-qwen-v0.1/run_order.txt"
CRITERIA="qualification/levels-qwen-v0.1/criteria.md"
RUN_ALL=false

if [[ "${1:-}" == "--all" ]]; then
  RUN_ALL=true
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--all]" >&2
  echo "Default: gate after each persisted inference so a semantic miss can stop later compute." >&2
  exit 2
fi

./verify_qwen_levels_qualification.sh

caffeinate -dimsu &
CAFFEINATE_PID=$!
trap 'kill "$CAFFEINATE_PID" 2>/dev/null || true' EXIT

echo
echo "Qwen Levels qualification v0.1"
echo "External/API inference cost: $0.00"
echo "Maximum fresh local inference calls: 3"
if $RUN_ALL; then
  echo "Mode: --all (collect all three diagnostic samples without semantic gates)"
else
  echo "Mode: sequential qualification gates (recommended)"
fi

case_number=0
case_total=$(grep -cve '^$' "$RUN_ORDER")

while IFS= read -r case_manifest; do
  [[ -z "$case_manifest" ]] && continue
  case_number=$((case_number + 1))

  echo
  echo "============================================================"
  echo "Case $case_number/$case_total: $case_manifest"
  echo "============================================================"
  bin/lme run "$case_manifest"

  experiment_name=$(ruby -e 'require "yaml"; puts YAML.safe_load(File.read(ARGV[0]), aliases: true).fetch("name")' "$case_manifest")
  output_dir="output/$experiment_name"

  echo
  echo "Persisted output: $output_dir"
  echo "Frozen comparator: $CRITERIA"
  echo "Do NOT rerun this completed inference because of an unfavorable result."

  if ! $RUN_ALL && (( case_number < case_total )); then
    if [[ ! -t 0 ]]; then
      echo
      echo "STOP: no interactive terminal available for the semantic qualification gate."
      echo "Adjudicate this case against $CRITERIA, then rerun this script to resume; completed jobs should be reused by the harness."
      exit 0
    fi

    echo
    read -r "reply?Continue only if this persisted case PASSES the exact comparator? [y/N] "
    case "$reply" in
      y|Y|yes|YES|Yes)
        ;;
      *)
        echo "Qualification stopped after case $case_number by the predeclared information-gain stop condition."
        exit 0
        ;;
    esac
  fi
done < "$RUN_ORDER"

echo
echo "All planned Levels qualification inferences are persisted."
echo "Adjudicate all completed cases against: $CRITERIA"
echo "LOCAL_QUALIFIED requires all three fresh cases to pass exactly."
