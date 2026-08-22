# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "stringio"

class Phase6ProfileActivationTest < Minitest::Test
  def phase6_manifest(scorer_repo:, env_name: "AF_SERIOUSNESS_GUARDRAIL_PROFILE", env_value: "phase6-v0.3")
    <<~YAML
      name: phase6-remediation-seriousness-adv0040-proxy-weighting-kill-test-v1
      dispatch: pool
      models: [qwen]
      dimension: Seriousness
      adventures: [ADV-0040]
      replicates: 1
      workers: [mac]
      required_worker_labels: [local]
      scorer:
        repo: #{scorer_repo}
        mode: positional
        extra_args: []
      phase6_contract:
        prompt_profile:
          version: #{env_value}
          env_name: #{env_name}
          env_value: #{env_value}
        model_alias: qwen
        ollama_model: qwen3.6:35b-a3b
        case:
          adventure_id: ADV-0040
          adventure_title: Expedition to the Barrier Peaks
        oracle:
          source: frozen-afao-calibration
          score: 3
          visibility: post-run-adjudication-only
        replicate_count: 1
        no_favorable_rerun: true
        external_api_cost_usd: 0.0
    YAML
  end

  def test_phase6_profile_is_fail_closed_and_dimension_specific
    Dir.mktmpdir do |dir|
      path = File.join(dir, "exp.yml")
      File.write(path, phase6_manifest(scorer_repo: "scorer"))
      exp = LocalModelEvaluation::Experiment.new(path)

      assert_equal(
        { "AF_SERIOUSNESS_GUARDRAIL_PROFILE" => "phase6-v0.3" },
        exp.phase6_scorer_env
      )

      bad_path = File.join(dir, "bad.yml")
      File.write(
        bad_path,
        phase6_manifest(
          scorer_repo: "scorer",
          env_name: "AF_LETHALITY_GUARDRAIL_PROFILE",
          env_value: "phase6-v0.2"
        )
      )
      bad = LocalModelEvaluation::Experiment.new(bad_path)
      assert_raises(ArgumentError) { bad.phase6_scorer_env }
    end
  end

  def test_conflicting_worker_profile_is_rejected
    Dir.mktmpdir do |dir|
      path = File.join(dir, "exp.yml")
      File.write(path, phase6_manifest(scorer_repo: "scorer"))
      exp = LocalModelEvaluation::Experiment.new(path)

      error = assert_raises(ArgumentError) do
        exp.effective_scorer_env(
          "AF_LLM_PROVIDER" => "ollama",
          "AF_SERIOUSNESS_GUARDRAIL_PROFILE" => "wrong"
        )
      end

      assert_includes error.message, "conflicts with manifest-declared Phase-6 profile"
    end
  end

  def test_real_runner_receives_manifest_declared_profile
    Dir.mktmpdir do |dir|
      scorer = File.join(dir, "scorer")
      FileUtils.mkdir_p(File.join(scorer, "bin"))
      File.write(File.join(scorer, "bin", "af-score"), <<~'RUBY')
        #!/usr/bin/env ruby
        require "json"
        require "fileutils"
        args = ARGV
        output = args[args.index("--output") + 1]
        FileUtils.mkdir_p(output)
        File.write(
          File.join(output, "profile.json"),
          JSON.generate(
            seriousness: ENV["AF_SERIOUSNESS_GUARDRAIL_PROFILE"],
            provider: ENV["AF_LLM_PROVIDER"]
          )
        )
      RUBY
      FileUtils.chmod("+x", File.join(scorer, "bin", "af-score"))

      exp_path = File.join(dir, "exp.yml")
      File.write(exp_path, phase6_manifest(scorer_repo: scorer))
      exp = LocalModelEvaluation::Experiment.new(exp_path)
      worker = LocalModelEvaluation::Worker.new(
        "mac",
        "base_url" => "http://localhost",
        "labels" => ["local"],
        "scorer_env" => { "AF_LLM_PROVIDER" => "ollama" }
      )
      workers = { "mac" => worker }
      models = { "qwen" => { "ollama_model" => "qwen3.6:35b-a3b" } }
      jobs = LocalModelEvaluation::Scheduler.new(experiment: exp, workers: workers, models: models).jobs

      runner = LocalModelEvaluation::Runner.new(
        experiment: exp,
        workers: workers,
        models: models,
        output_root: File.join(dir, "out"),
        io: StringIO.new
      )
      runner.run(jobs)

      profile_path = File.join(runner.output_dir, "runs", jobs.first.id, "native", "profile.json")
      payload = JSON.parse(File.read(profile_path))
      assert_equal "phase6-v0.3", payload["seriousness"]
      assert_equal "ollama", payload["provider"]
    end
  end
end
