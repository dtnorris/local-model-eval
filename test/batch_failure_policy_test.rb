# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "shellwords"

class BatchFailurePolicyTest < Minitest::Test
  POLICY = File.expand_path("../lib/batch_failure_policy.sh", __dir__)

  def run_policy(body)
    script = <<~BASH
      set -u
      source #{Shellwords.escape(POLICY)}
      batch_failure_policy_init
      #{body}
    BASH
    Open3.capture3("bash", "-c", script)
  end

  def test_two_consecutive_failures_still_circuit_break
    stdout, stderr, status = run_policy(<<~'BASH')
      batch_failure_record_failure failed
      printf '%s\n' "$batch_failure_action"
      batch_failure_record_failure failed
      printf '%s\n' "$batch_failure_action"
    BASH

    assert status.success?, stderr
    assert_equal ["continue", "circuit_break_consecutive"], stdout.lines.map(&:strip)
  end

  def test_three_isolated_persisted_failures_checkpoint_and_continue
    stdout, stderr, status = run_policy(<<~'BASH')
      batch_failure_record_failure failed
      batch_failure_record_success
      batch_failure_record_failure failed
      batch_failure_record_success
      batch_failure_record_failure failed
      printf '%s,%s,%s,%s\n' \
        "$batch_failure_action" \
        "$batch_new_failures" \
        "$batch_total_new_failures" \
        "$batch_failure_budget_checkpoints"
    BASH

    assert status.success?, stderr
    assert_equal "checkpoint_continue,0,3,1", stdout.strip
  end

  def test_checkpoint_reset_allows_another_isolated_failure_window
    stdout, stderr, status = run_policy(<<~'BASH')
      for _ in 1 2 3; do
        batch_failure_record_failure failed
        batch_failure_record_success
      done
      batch_failure_record_failure failed
      printf '%s,%s,%s,%s\n' \
        "$batch_failure_action" \
        "$batch_new_failures" \
        "$batch_total_new_failures" \
        "$batch_failure_budget_checkpoints"
    BASH

    assert status.success?, stderr
    assert_equal "continue,1,4,1", stdout.strip
  end

  def test_total_budget_circuit_breaks_when_failure_is_not_safely_persisted
    stdout, stderr, status = run_policy(<<~'BASH')
      batch_failure_record_failure failed
      batch_failure_record_success
      batch_failure_record_failure failed
      batch_failure_record_success
      batch_failure_record_failure unknown
      printf '%s,%s,%s\n' \
        "$batch_failure_action" \
        "$batch_new_failures" \
        "$batch_failure_budget_checkpoints"
    BASH

    assert status.success?, stderr
    assert_equal "circuit_break_total,3,0", stdout.strip
  end

  def test_expected_model_failure_resets_consecutive_operational_failures
    stdout, stderr, status = run_policy(<<~'BASH')
      batch_failure_record_failure failed
      batch_failure_record_expected_model_failure failed
      printf '%s,%s,%s\n' \
        "$batch_failure_action" \
        "$batch_consecutive_failures" \
        "$batch_total_new_failures"
    BASH

    assert status.success?, stderr
    assert_equal "continue,0,2", stdout.strip
  end

  def test_expected_model_failures_still_count_toward_checkpoint_reporting
    stdout, stderr, status = run_policy(<<~'BASH')
      batch_failure_record_expected_model_failure failed
      batch_failure_record_expected_model_failure failed
      batch_failure_record_expected_model_failure failed
      printf '%s,%s,%s,%s\n' \
        "$batch_failure_action" \
        "$batch_new_failures" \
        "$batch_total_new_failures" \
        "$batch_failure_budget_checkpoints"
    BASH

    assert status.success?, stderr
    assert_equal "checkpoint_continue,0,3,1", stdout.strip
  end

end
