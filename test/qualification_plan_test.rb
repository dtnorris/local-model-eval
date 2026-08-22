# frozen_string_literal: true

require_relative "test_helper"
require "local_model_evaluation/qualification_plan"

class QualificationPlanTest < Minitest::Test
  def test_requires_complete_comparator_case_coverage
    Dir.mktmpdir do |dir|
      comparator = File.join(dir, "terra.yml")
      File.write(comparator, <<~YAML)
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
          - { id: b, adventure: ADV-0002, oracle: 2, terra: 2 }
        summary:
          completed_assessments: 2
          exact: 2
          adjacent: 0
          hard_errors: 0
          malformed_unusable_outputs: 0
      YAML

      plan = File.join(dir, "plan.yml")
      File.write(plan, <<~YAML)
        version: 1
        acceptance_contract: AdventureFinder_Phase4_Local_Model_Acceptance_Contract_v0.1
        name: phase5
        candidates:
          - id: qwen-combat
            model: qwen
            comparator: terra.yml
            cases:
              - comparator_case: a
                manifest: a.yml
      YAML

      error = assert_raises(ArgumentError) { LocalModelEvaluation::QualificationPlan.new(plan) }
      assert_match(/cover every comparator case/, error.message)
    end
  end

  def test_frozen_exact_deficit_cannot_be_moved
    Dir.mktmpdir do |dir|
      comparator = File.join(dir, "terra.yml")
      File.write(comparator, <<~YAML)
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
          exact: 1
          adjacent: 0
          hard_errors: 0
          malformed_unusable_outputs: 0
      YAML
      plan = File.join(dir, "plan.yml")
      File.write(plan, <<~YAML)
        version: 1
        acceptance_contract: AdventureFinder_Phase4_Local_Model_Acceptance_Contract_v0.1
        name: phase5
        max_exact_deficit_percentage_points: 20
        candidates:
          - id: qwen-combat
            model: qwen
            comparator: terra.yml
            cases:
              - comparator_case: a
                manifest: a.yml
      YAML

      error = assert_raises(ArgumentError) { LocalModelEvaluation::QualificationPlan.new(plan) }
      assert_match(/requires max_exact_deficit/, error.message)
    end
  end
end
