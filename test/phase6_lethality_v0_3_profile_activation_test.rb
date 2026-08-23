# frozen_string_literal: true

require_relative "test_helper"

class Phase6LethalityV03ProfileActivationTest < Minitest::Test
  def manifest(profile:)
    <<~YAML
      name: phase6-lethality-v0.3-fixture
      dispatch: pool
      models: [qwen]
      dimension: Lethality / Failure Severity
      adventures: [ADV-0277]
      replicates: 1
      workers: [mac]
      required_worker_labels: [local]
      scorer:
        repo: scorer
        mode: positional
        extra_args: []
      phase6_contract:
        prompt_profile:
          version: #{profile}
          env_name: AF_LETHALITY_GUARDRAIL_PROFILE
          env_value: #{profile}
    YAML
  end

  def test_v0_3_is_the_only_active_lethality_phase6_profile
    Dir.mktmpdir do |dir|
      current_path = File.join(dir, "current.yml")
      File.write(current_path, manifest(profile: "phase6-v0.3"))
      current = LocalModelEvaluation::Experiment.new(current_path)
      assert_equal({ "AF_LETHALITY_GUARDRAIL_PROFILE" => "phase6-v0.3" }, current.phase6_scorer_env)

      retired_path = File.join(dir, "retired.yml")
      File.write(retired_path, manifest(profile: "phase6-v0.2"))
      retired = LocalModelEvaluation::Experiment.new(retired_path)
      error = assert_raises(ArgumentError) { retired.phase6_scorer_env }
      assert_includes error.message, "AF_LETHALITY_GUARDRAIL_PROFILE=phase6-v0.3"
    end
  end
end
