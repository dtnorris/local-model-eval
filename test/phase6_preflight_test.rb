# frozen_string_literal: true

require_relative "test_helper"
require "csv"
require "json"
require "stringio"

class Phase6PreflightTest < Minitest::Test
  RULES = LocalModelEvaluation::Phase6Preflight::PROFILE_RULES

  def test_package_preflight_validates_all_25_cases_without_inference
    Dir.mktmpdir do |dir|
      code_root = File.join(dir, "code")
      repo = File.join(code_root, "local-model-eval")
      scorer = File.join(code_root, "af-cli-scoring-utility")
      phase6 = File.join(repo, "experiments", "phase6")
      FileUtils.mkdir_p(phase6)
      FileUtils.mkdir_p(File.join(scorer, "bin"))
      FileUtils.mkdir_p(File.join(repo, "output"))

      write_fake_preflight_scorer(File.join(scorer, "bin", "af-score"))

      index_path = File.join(phase6, "phase6_core_manifest_index_v0.1.csv")
      rows = write_package(phase6, index_path)

      models = { "qwen" => { "ollama_model" => "qwen3.6:35b-a3b" } }
      workers = {
        "mac" => LocalModelEvaluation::Worker.new(
          "mac",
          "base_url" => "http://127.0.0.1:11434",
          "labels" => ["local"],
          "scorer_env" => { "AF_LLM_PROVIDER" => "ollama" }
        )
      }
      io = StringIO.new

      result = LocalModelEvaluation::Phase6Preflight.new(
        index_path: index_path,
        models: models,
        workers: workers,
        output_root: File.join(repo, "output"),
        io: io
      ).run

      assert_equal 25, result.total
      assert_equal 25, result.passed
      assert_equal 0, result.failed
      assert File.file?(result.summary_path)
      assert_equal 25, Dir.glob(File.join(result.render_dir, "*.json")).reject { |p| p == result.summary_path }.length
      assert_includes io.string, "Provider inference calls: 0"

      rows.each do |row|
        exp = LocalModelEvaluation::Experiment.new(File.join(repo, row.fetch("manifest")))
        job = LocalModelEvaluation::Scheduler.new(experiment: exp, workers: workers, models: models).jobs.fetch(0)
        refute File.exist?(File.join(repo, "output", exp.name, "runs", job.id)),
               "preflight must not create normal score run directories"
      end
    end
  end

  private

  def write_package(phase6, index_path)
    headers = %w[
      global_sequence dimension pilot_sequence manifest model_alias ollama_model
      adventure_id adventure_title oracle_score prompt_profile profile_env_name
      replicates role stop_type
    ]
    rows = []
    global = 0

    RULES.each_with_index do |(dimension, rule), dimension_index|
      1.upto(5) do |pilot_sequence|
        global += 1
        adventure_id = format("ADV-%04d", (dimension_index * 10) + pilot_sequence)
        role = "case-#{pilot_sequence}"
        name = "phase6-remediation-#{dimension_index}-#{pilot_sequence}-v1"
        relative = "experiments/phase6/#{name}.yml"
        oracle_score = pilot_sequence

        manifest_path = File.join(File.dirname(index_path), "#{name}.yml")
        File.write(manifest_path, <<~YAML)
          name: #{name}
          dispatch: pool
          models: [qwen]
          dimension: "#{dimension}"
          adventures: [#{adventure_id}]
          replicates: 1
          workers: [mac]
          required_worker_labels: [local]
          scorer:
            repo: ../../../af-cli-scoring-utility
            mode: positional
            extra_args: []
          phase6_contract:
            pilot_case_id: P6-TEST-#{global}
            sequence: #{pilot_sequence}
            role: #{role}
            model_alias: qwen
            ollama_model: qwen3.6:35b-a3b
            prompt_profile:
              version: #{rule.fetch(:env_value)}
              env_name: #{rule.fetch(:env_name)}
              env_value: #{rule.fetch(:env_value)}
            case:
              adventure_id: #{adventure_id}
              adventure_title: Fixture #{global}
            oracle:
              source: frozen-afao-calibration
              score: #{oracle_score}
              visibility: post-run-adjudication-only
            replicate_count: 1
            stop_condition:
              type: exact-or-stop
              action: stop-current-dimension
              rule: fixture
            no_favorable_rerun: true
            external_api_cost_usd: 0.0
          cost_cap_usd: 0.01
        YAML

        rows << {
          "global_sequence" => global,
          "dimension" => dimension,
          "pilot_sequence" => pilot_sequence,
          "manifest" => relative,
          "model_alias" => "qwen",
          "ollama_model" => "qwen3.6:35b-a3b",
          "adventure_id" => adventure_id,
          "adventure_title" => "Fixture #{global}",
          "oracle_score" => oracle_score,
          "prompt_profile" => rule.fetch(:env_value),
          "profile_env_name" => rule.fetch(:env_name),
          "replicates" => 1,
          "role" => role,
          "stop_type" => "exact-or-stop"
        }
      end
    end

    CSV.open(index_path, "w", write_headers: true, headers: headers) do |csv|
      rows.each { |row| csv << headers.map { |h| row.fetch(h) } }
    end
    rows
  end

  def write_fake_preflight_scorer(path)
    rules = RULES.transform_values do |rule|
      {
        "env_name" => rule.fetch(:env_name),
        "env_value" => rule.fetch(:env_value),
        "prompt_marker" => rule.fetch(:prompt_marker),
        "metadata_profile_key" => rule.fetch(:metadata_profile_key),
        "metadata_sha_key" => rule.fetch(:metadata_sha_key)
      }
    end

    File.write(path, <<~RUBY)
      #!/usr/bin/env ruby
      require "json"
      require "fileutils"

      RULES = #{rules.inspect}

      abort "inference path invoked" unless ARGV.include?("--preflight")
      render = ARGV[ARGV.index("--render-preflight") + 1]
      model = ARGV[ARGV.index("--model") + 1]
      dimension = ARGV[ARGV.index("--dimension") + 1]
      output = ARGV[ARGV.index("--output") + 1]
      adventure = ARGV.last
      rule = RULES.fetch(dimension)
      abort "wrong profile activation" unless ENV[rule.fetch("env_name")] == rule.fetch("env_value")
      abort "wrong model" unless model == "qwen3.6:35b-a3b"

      metadata = {
        "prompt_profile" => "\#{dimension.downcase.gsub(/[^a-z]+/, "_")}_guardrail_\#{rule.fetch("env_value")}",
        "experimental" => true,
        "selected_dimension" => dimension,
        rule.fetch("metadata_profile_key") => rule.fetch("env_value"),
        rule.fetch("metadata_sha_key") => "a" * 64
      }
      payload = {
        "adventure_id" => adventure,
        "adventure_title" => "Fixture",
        "source_file" => "/fixture/source.md",
        "source_scope" => "canonical_page_slice",
        "source_warnings" => [],
        "output_root" => output,
        "run_metadata" => metadata,
        "targets" => [
          {
            "group_name" => "fixture",
            "label" => dimension,
            "artifact_name" => "fixture",
            "dimensions" => [dimension],
            "prompt_sha256" => "b" * 64,
            "schema_sha256" => "c" * 64,
            "prompt" => {
              "instructions" => "fixture system",
              "input" => rule.fetch("prompt_marker") + "\\nfixture source"
            },
            "schema" => { "type" => "object" }
          }
        ]
      }
      FileUtils.mkdir_p(File.dirname(render))
      File.write(render, JSON.pretty_generate(payload))
      puts "Preflight: PASS (no model inference)"
      puts "Provider inference calls: 0"
    RUBY
    FileUtils.chmod("+x", path)
  end
end
