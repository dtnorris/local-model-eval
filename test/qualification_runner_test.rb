# frozen_string_literal: true

require_relative "test_helper"
require "local_model_evaluation/qualification_runner"
require "stringio"
require "csv"

class QualificationRunnerTest < Minitest::Test
  def test_classifies_exact_adjacent_and_hard
    assert_equal ["exact", 0], LocalModelEvaluation::QualificationRunner.classify(3, 3)
    assert_equal ["adjacent", -1], LocalModelEvaluation::QualificationRunner.classify(3, 2)
    assert_equal ["hard", 2], LocalModelEvaluation::QualificationRunner.classify(3, 5)
  end

  def test_dry_run_rejects_paid_worker_before_any_command
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      FileUtils.mkdir_p(File.join(dir, "experiments"))
      File.write(File.join(dir, "config", "workers.yml"), <<~YAML)
        workers:
          mac:
            hourly_rate_usd: 0.25
            labels: [local]
      YAML
      File.write(File.join(dir, "experiments", "case.yml"), <<~YAML)
        name: case
        models: [qwen]
        dimension: Combat Emphasis
        adventures: [ADV-0001]
        replicates: 1
        workers: [mac]
      YAML
      File.write(File.join(dir, "terra.yml"), <<~YAML)
        version: 1
        acceptance_contract: AdventureFinder_Phase4_Local_Model_Acceptance_Contract_v0.1
        id: combat
        dimension: Combat Emphasis
        metric: Combat Emphasis
        kind: ordinal_1_5
        source:
          accepted_artifact_set: accepted-v1
          artifact_paths: [archive/a.csv]
        cases:
          - { id: a, adventure: ADV-0001, oracle: 3, terra: 3 }
        summary:
          completed_assessments: 1
          exact: 1
          adjacent: 0
          hard_errors: 0
          malformed_unusable_outputs: 0
      YAML
      File.write(File.join(dir, "plan.yml"), <<~YAML)
        version: 1
        acceptance_contract: AdventureFinder_Phase4_Local_Model_Acceptance_Contract_v0.1
        name: phase5
        candidates:
          - id: qwen-combat
            model: qwen
            comparator: terra.yml
            cases:
              - comparator_case: a
                manifest: experiments/case.yml
      YAML

      plan = LocalModelEvaluation::QualificationPlan.new(File.join(dir, "plan.yml"))
      runner = LocalModelEvaluation::QualificationRunner.new(plan:, repo_root: dir, dry_run: true)
      error = assert_raises(ArgumentError) { runner.run }
      assert_match(/refuses paid workers/, error.message)
    end
  end

  def test_hard_error_stops_remaining_candidate_cases
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      FileUtils.mkdir_p(File.join(dir, "experiments"))
      File.write(File.join(dir, "config", "workers.yml"), <<~YAML)
        workers:
          mac:
            hourly_rate_usd: 0.0
            labels: [local, apple-silicon]
      YAML

      adventures = %w[ADV-0001 ADV-0002 ADV-0003]
      adventures.each_with_index do |adventure, index|
        File.write(File.join(dir, "experiments", "case#{index + 1}.yml"), <<~YAML)
          name: qwen-combat-case#{index + 1}
          models: [qwen]
          dimension: Combat Emphasis
          adventures: [#{adventure}]
          replicates: 1
          workers: [mac]
        YAML
      end

      File.write(File.join(dir, "terra.yml"), <<~YAML)
        version: 1
        acceptance_contract: AdventureFinder_Phase4_Local_Model_Acceptance_Contract_v0.1
        id: combat
        dimension: Combat Emphasis
        metric: Combat Emphasis
        kind: ordinal_1_5
        source:
          accepted_artifact_set: accepted-v1
          artifact_paths: [archive/a.csv]
        cases:
          - { id: a, adventure: ADV-0001, oracle: 3, terra: 3 }
          - { id: b, adventure: ADV-0002, oracle: 2, terra: 2 }
          - { id: c, adventure: ADV-0003, oracle: 5, terra: 5 }
        summary:
          completed_assessments: 3
          exact: 3
          adjacent: 0
          hard_errors: 0
          malformed_unusable_outputs: 0
      YAML
      File.write(File.join(dir, "plan.yml"), <<~YAML)
        version: 1
        acceptance_contract: AdventureFinder_Phase4_Local_Model_Acceptance_Contract_v0.1
        name: phase5
        candidates:
          - id: qwen-combat
            model: qwen
            comparator: terra.yml
            cases:
              - { comparator_case: a, manifest: experiments/case1.yml }
              - { comparator_case: b, manifest: experiments/case2.yml }
              - { comparator_case: c, manifest: experiments/case3.yml }
      YAML

      calls = []
      fake_command = lambda do |command, chdir:|
        calls << command[1]
        if command[1] == "run"
          manifest = LocalModelEvaluation::Config.load_yaml(command[2])
          output = File.join(chdir, "output", manifest.fetch("name"), "runs", "job", "native", "assessments")
          FileUtils.mkdir_p(output)
          CSV.open(File.join(output, "assessment.csv"), "w") do |csv|
            csv << %w[metric value]
            csv << ["Combat Emphasis", 5] # first oracle is 3 => decisive hard error
          end
        end
        true
      end

      plan = LocalModelEvaluation::QualificationPlan.new(File.join(dir, "plan.yml"))
      output = StringIO.new
      runner = LocalModelEvaluation::QualificationRunner.new(plan:, repo_root: dir, out: output, command_runner: fake_command)
      assert runner.run
      assert_equal ["worker-check", "run"], calls

      summary = File.read(File.join(dir, "output", "qualification", "phase5", "summary.md"))
      assert_includes summary, "QUALIFICATION_STOP_HARD_ERROR"
      results = CSV.read(File.join(dir, "output", "qualification", "phase5", "results.csv"), headers: true)
      assert_equal 1, results.length
      assert_equal "hard", results.first["local_class"]
    end
  end

end
