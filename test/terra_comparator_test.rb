# frozen_string_literal: true

require_relative "test_helper"
require "local_model_evaluation/terra_comparator"

class TerraComparatorTest < Minitest::Test
  def test_computes_frozen_summary
    Dir.mktmpdir do |dir|
      path = File.join(dir, "terra.yml")
      File.write(path, <<~YAML)
        version: 1
        acceptance_contract: AdventureFinder_Phase4_Local_Model_Acceptance_Contract_v0.1
        id: test
        dimension: Combat Emphasis
        metric: Combat Emphasis
        kind: ordinal_1_5
        source:
          accepted_artifact_set: accepted-v1
          artifact_paths: [archive/a.csv]
        malformed_unusable_outputs: 0
        cases:
          - { id: a, adventure: ADV-0001, oracle: 1, terra: 1 }
          - { id: b, adventure: ADV-0002, oracle: 3, terra: 2 }
          - { id: c, adventure: ADV-0003, oracle: 5, terra: 3 }
        summary:
          completed_assessments: 3
          exact: 1
          adjacent: 1
          hard_errors: 1
          malformed_unusable_outputs: 0
      YAML

      comparator = LocalModelEvaluation::TerraComparator.new(path)
      assert_equal 1, comparator.exact_count
      assert_equal 1, comparator.adjacent_count
      assert_equal 1, comparator.hard_error_count
      assert_in_delta 1.0 / 3.0, comparator.exact_rate
    end
  end

  def test_rejects_summary_drift
    Dir.mktmpdir do |dir|
      path = File.join(dir, "terra.yml")
      File.write(path, <<~YAML)
        version: 1
        acceptance_contract: AdventureFinder_Phase4_Local_Model_Acceptance_Contract_v0.1
        id: test
        dimension: Combat Emphasis
        metric: Combat Emphasis
        kind: ordinal_1_5
        source:
          accepted_artifact_set: accepted-v1
          artifact_paths: [archive/a.csv]
        cases:
          - { id: a, adventure: ADV-0001, oracle: 1, terra: 1 }
        summary:
          completed_assessments: 1
          exact: 0
          adjacent: 1
          hard_errors: 0
          malformed_unusable_outputs: 0
      YAML

      error = assert_raises(ArgumentError) { LocalModelEvaluation::TerraComparator.new(path) }
      assert_match(/summary.exact/, error.message)
    end
  end
end
