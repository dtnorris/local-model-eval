#!/bin/bash
# Generic failure-budget policy for unattended batch runners.
#
# Call batch_failure_policy_init once, then:
#   batch_failure_record_success
#   batch_failure_record_failure "$persisted_status"
#
# batch_failure_action will be one of:
#   continue
#   checkpoint_continue
#   circuit_break_consecutive
#   circuit_break_total

BATCH_CONSECUTIVE_FAILURE_THRESHOLD="${LME_BATCH_CONSECUTIVE_FAILURE_THRESHOLD:-2}"
BATCH_ISOLATED_FAILURE_BUDGET="${LME_BATCH_ISOLATED_FAILURE_BUDGET:-3}"

batch_failure_policy_init() {
  batch_new_failures=0
  batch_total_new_failures=0
  batch_consecutive_failures=0
  batch_failure_budget_checkpoints=0
  batch_last_checkpoint_size=0
  batch_failure_action="continue"
}

batch_failure_record_success() {
  batch_consecutive_failures=0
  batch_failure_action="continue"
}

safe_to_continue_isolated_failures() {
  local persisted_status="${1:-unknown}"
  [[ "$persisted_status" == "failed" ]]
}

checkpoint_failure_budget() {
  batch_last_checkpoint_size="$batch_new_failures"
  batch_failure_budget_checkpoints=$((batch_failure_budget_checkpoints + 1))
  batch_new_failures=0
  batch_failure_action="checkpoint_continue"
}

batch_failure_record_failure() {
  local persisted_status="${1:-unknown}"

  batch_new_failures=$((batch_new_failures + 1))
  batch_total_new_failures=$((batch_total_new_failures + 1))
  batch_consecutive_failures=$((batch_consecutive_failures + 1))
  batch_failure_action="continue"

  if [[ "$batch_consecutive_failures" -ge "$BATCH_CONSECUTIVE_FAILURE_THRESHOLD" ]]; then
    batch_failure_action="circuit_break_consecutive"
  elif [[ "$batch_new_failures" -ge "$BATCH_ISOLATED_FAILURE_BUDGET" ]]; then
    if safe_to_continue_isolated_failures "$persisted_status"; then
      checkpoint_failure_budget
    else
      batch_failure_action="circuit_break_total"
    fi
  fi
}
