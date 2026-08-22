# frozen_string_literal: true

require "csv"
require "fileutils"
require "json"
require "open3"

module LocalModelEvaluation
  class Phase6Preflight
    EXPECTED_CASE_COUNT = 25
    EXPECTED_CASES_PER_DIMENSION = 5

    PROFILE_RULES = {
      "Social Interaction Emphasis" => {
        env_name: "AF_SOCIAL_INTERACTION_GUARDRAIL_PROFILE",
        env_value: "phase6-v0.3",
        prompt_marker: "# Social Interaction Emphasis Cross-Mode Independence Guardrail v0.3",
        metadata_profile_key: "social_interaction_guardrail_profile",
        metadata_sha_key: "social_interaction_guardrail_sha256"
      },
      "Investigation Emphasis" => {
        env_name: "AF_INVESTIGATION_GUARDRAIL_PROFILE",
        env_value: "phase6-v0.4",
        prompt_marker: "# Investigation Emphasis Endpoint Boundary Guardrail v0.4",
        metadata_profile_key: "investigation_guardrail_profile",
        metadata_sha_key: "investigation_guardrail_sha256"
      },
      "Lethality / Failure Severity" => {
        env_name: "AF_LETHALITY_GUARDRAIL_PROFILE",
        env_value: "phase6-v0.2",
        prompt_marker: "# Lethality / Failure Severity Mitigation-Conversion Guardrail v0.2",
        metadata_profile_key: "lethality_guardrail_profile",
        metadata_sha_key: "lethality_guardrail_sha256"
      },
      "Puzzle / Problem-Solving Emphasis" => {
        env_name: "AF_PUZZLE_GUARDRAIL_PROFILE",
        env_value: "phase6-v0.2",
        prompt_marker: "# Puzzle / Problem-Solving Emphasis Low-Anchor Admission Guardrail v0.2",
        metadata_profile_key: "puzzle_guardrail_profile",
        metadata_sha_key: "puzzle_guardrail_sha256"
      },
      "Seriousness" => {
        env_name: "AF_SERIOUSNESS_GUARDRAIL_PROFILE",
        env_value: "phase6-v0.3",
        prompt_marker: "# Seriousness Direct Register-Comparison Decision Guardrail v0.3",
        metadata_profile_key: "seriousness_guardrail_profile",
        metadata_sha_key: "seriousness_guardrail_sha256"
      }
    }.freeze

    FORBIDDEN_PROMPT_TOKENS = [
      "phase6_contract",
      "frozen-afao-calibration",
      "post-run-adjudication-only",
      "no_favorable_rerun",
      "external_api_cost_usd"
    ].freeze

    Result = Struct.new(:total, :passed, :failed, :render_dir, :summary_path, :cases, keyword_init: true)

    class ValidationError < StandardError; end

    def initialize(index_path:, models:, workers:, output_root:, io: $stdout, capture3: Open3.method(:capture3))
      @index_path = File.expand_path(index_path)
      @models = models
      @workers = workers
      @output_root = File.expand_path(output_root)
      @io = io
      @capture3 = capture3
      @repo_root = File.expand_path("../..", File.dirname(@index_path))
    end

    def run
      rows = load_and_validate_index
      render_dir = File.join(@output_root, "phase6-preflight")
      FileUtils.rm_rf(render_dir)
      FileUtils.mkdir_p(render_dir)

      seen_output_paths = {}
      results = rows.map do |row|
        begin
          preflight_case(row, render_dir, seen_output_paths)
        rescue StandardError => e
          {
            "global_sequence" => row["global_sequence"],
            "manifest" => row["manifest"],
            "dimension" => row["dimension"],
            "adventure_id" => row["adventure_id"],
            "status" => "FAIL",
            "error" => "#{e.class}: #{e.message}"
          }
        end
      end

      passed = results.count { |r| r["status"] == "PASS" }
      summary_path = File.join(render_dir, "phase6-preflight-summary.json")
      File.write(
        summary_path,
        JSON.pretty_generate(
          "status" => passed == EXPECTED_CASE_COUNT ? "PASS" : "FAIL",
          "provider_inference_calls" => 0,
          "total" => results.length,
          "passed" => passed,
          "failed" => results.length - passed,
          "cases" => results
        )
      )

      result = Result.new(
        total: results.length,
        passed: passed,
        failed: results.length - passed,
        render_dir: render_dir,
        summary_path: summary_path,
        cases: results
      )
      print_result(result)

      if result.failed.positive?
        failures = results.select { |r| r["status"] == "FAIL" }
        detail = failures.map { |r| "#{r['manifest']}: #{r['error']}" }.join("\n")
        raise ValidationError, "#{result.failed}/#{result.total} Phase-6 preflights failed:\n#{detail}"
      end

      result
    end

    private

    def load_and_validate_index
      raise ValidationError, "Phase-6 manifest index not found: #{@index_path}" unless File.file?(@index_path)

      table = CSV.read(@index_path, headers: true)
      required = %w[
        global_sequence dimension pilot_sequence manifest model_alias ollama_model
        adventure_id adventure_title oracle_score prompt_profile profile_env_name
        replicates role stop_type
      ]
      missing = required - Array(table.headers)
      raise ValidationError, "Phase-6 manifest index missing columns: #{missing.join(', ')}" unless missing.empty?

      rows = table.map(&:to_h)
      unless rows.length == EXPECTED_CASE_COUNT
        raise ValidationError, "expected #{EXPECTED_CASE_COUNT} core manifests, found #{rows.length}"
      end

      sequences = rows.map { |r| Integer(r.fetch("global_sequence")) }
      expected_sequences = (1..EXPECTED_CASE_COUNT).to_a
      raise ValidationError, "global_sequence must be exactly 1..#{EXPECTED_CASE_COUNT}" unless sequences == expected_sequences

      manifests = rows.map { |r| r.fetch("manifest") }
      raise ValidationError, "manifest paths must be unique" unless manifests.uniq.length == manifests.length

      dimensions = rows.group_by { |r| r.fetch("dimension") }
      unless dimensions.keys.sort == PROFILE_RULES.keys.sort
        raise ValidationError, "Phase-6 dimensions do not match the frozen five-dimension set"
      end
      dimensions.each do |dimension, dimension_rows|
        unless dimension_rows.length == EXPECTED_CASES_PER_DIMENSION
          raise ValidationError,
                "#{dimension}: expected #{EXPECTED_CASES_PER_DIMENSION} cases, found #{dimension_rows.length}"
        end
        pilot_sequence = dimension_rows.map { |r| Integer(r.fetch("pilot_sequence")) }
        unless pilot_sequence == (1..EXPECTED_CASES_PER_DIMENSION).to_a
          raise ValidationError, "#{dimension}: pilot_sequence must be exactly 1..#{EXPECTED_CASES_PER_DIMENSION}"
        end
      end

      rows
    rescue CSV::MalformedCSVError, ArgumentError => e
      raise ValidationError, "invalid Phase-6 manifest index: #{e.message}"
    end

    def preflight_case(row, render_dir, seen_output_paths)
      manifest_path = File.expand_path(row.fetch("manifest"), @repo_root)
      raise ValidationError, "manifest not found: #{manifest_path}" unless File.file?(manifest_path)

      experiment = Experiment.new(manifest_path)
      validate_manifest_contract!(row, experiment)

      worker = sole_worker(experiment)
      job = sole_job(experiment)
      scorer_env = experiment.effective_scorer_env(worker.scorer_env)

      run_dir = File.join(@output_root, experiment.name, "runs", job.id)
      native_dir = File.join(run_dir, "native")
      if seen_output_paths[native_dir]
        raise ValidationError, "duplicate intended output path: #{native_dir}"
      end
      seen_output_paths[native_dir] = true
      if File.exist?(run_dir)
        raise ValidationError,
              "score output collision exists: #{run_dir}; remove or adjudicate it before Phase-6 inference"
      end

      render_path = File.join(
        render_dir,
        format("%02d-%s.json", Integer(row.fetch("global_sequence")), experiment.name)
      )
      command = preflight_command(experiment, job, render_path, native_dir)
      stdout, stderr, status = @capture3.call(scorer_env, *command, chdir: experiment.scorer_repo)
      unless status.success?
        raise ValidationError,
              "scorer preflight exited #{status.exitstatus}: #{[stdout, stderr].reject(&:empty?).join(' | ')}"
      end
      unless stdout.include?("Provider inference calls: 0")
        raise ValidationError, "scorer preflight did not prove zero provider inference calls"
      end
      raise ValidationError, "scorer did not write rendered preflight: #{render_path}" unless File.file?(render_path)

      rendered = JSON.parse(File.read(render_path))
      validate_rendered!(row, experiment, native_dir, rendered)

      {
        "global_sequence" => row.fetch("global_sequence"),
        "manifest" => row.fetch("manifest"),
        "experiment" => experiment.name,
        "dimension" => experiment.dimension,
        "adventure_id" => job.adventure,
        "profile_env" => experiment.phase6_scorer_env,
        "intended_output_path" => native_dir,
        "rendered_preflight" => render_path,
        "prompt_sha256" => rendered.dig("targets", 0, "prompt_sha256"),
        "schema_sha256" => rendered.dig("targets", 0, "schema_sha256"),
        "source_file" => rendered["source_file"],
        "source_scope" => rendered["source_scope"],
        "source_warnings" => Array(rendered["source_warnings"]),
        "status" => "PASS"
      }
    rescue JSON::ParserError => e
      raise ValidationError, "invalid rendered preflight JSON: #{e.message}"
    end

    def validate_manifest_contract!(row, experiment)
      contract = experiment.phase6_contract
      raise ValidationError, "#{experiment.name}: missing phase6_contract" unless contract.is_a?(Hash)

      unless experiment.name.start_with?("phase6-remediation-")
        raise ValidationError, "#{experiment.name}: experiment name must start with phase6-remediation-"
      end
      raise ValidationError, "#{experiment.name}: dispatch must be pool" unless experiment.dispatch == "pool"
      raise ValidationError, "#{experiment.name}: expected model [qwen]" unless experiment.models == ["qwen"]
      unless experiment.dimension == row.fetch("dimension")
        raise ValidationError, "#{experiment.name}: dimension disagrees with manifest index"
      end
      unless experiment.adventures == [row.fetch("adventure_id")]
        raise ValidationError, "#{experiment.name}: Adventure ID disagrees with manifest index"
      end
      unless experiment.replicates == 1 && Integer(row.fetch("replicates")) == 1
        raise ValidationError, "#{experiment.name}: exactly one replicate is required"
      end
      unless experiment.worker_names == ["mac"]
        raise ValidationError, "#{experiment.name}: Phase-6 core manifests must use worker mac"
      end
      unless experiment.scorer_mode == "positional"
        raise ValidationError, "#{experiment.name}: Phase-6 preflight requires positional scorer mode"
      end

      model = @models.fetch("qwen") { raise ValidationError, "model alias qwen is not configured" }
      ollama_model = model.fetch("ollama_model").to_s
      unless row.fetch("model_alias") == "qwen" &&
             row.fetch("ollama_model") == ollama_model &&
             contract["model_alias"].to_s == "qwen" &&
             contract["ollama_model"].to_s == ollama_model
        raise ValidationError, "#{experiment.name}: model identity is not frozen to configured qwen"
      end

      case_contract = contract.fetch("case") { raise ValidationError, "#{experiment.name}: missing case contract" }
      unless case_contract["adventure_id"].to_s == row.fetch("adventure_id")
        raise ValidationError, "#{experiment.name}: case Adventure ID disagrees with index"
      end

      oracle = contract.fetch("oracle") { raise ValidationError, "#{experiment.name}: missing oracle contract" }
      unless Integer(oracle.fetch("score")) == Integer(row.fetch("oracle_score"))
        raise ValidationError, "#{experiment.name}: oracle score disagrees with index"
      end
      unless oracle["visibility"].to_s == "post-run-adjudication-only"
        raise ValidationError, "#{experiment.name}: oracle visibility must be post-run-adjudication-only"
      end

      unless contract["replicate_count"] == 1
        raise ValidationError, "#{experiment.name}: phase6_contract replicate_count must be 1"
      end
      unless contract["no_favorable_rerun"] == true
        raise ValidationError, "#{experiment.name}: no_favorable_rerun must be true"
      end
      unless Float(contract["external_api_cost_usd"]) == 0.0
        raise ValidationError, "#{experiment.name}: external_api_cost_usd must be 0"
      end

      profile = contract.fetch("prompt_profile") { raise ValidationError, "#{experiment.name}: missing prompt_profile" }
      unless profile["version"].to_s == row.fetch("prompt_profile") &&
             profile["env_name"].to_s == row.fetch("profile_env_name")
        raise ValidationError, "#{experiment.name}: prompt profile disagrees with manifest index"
      end

      experiment.phase6_scorer_env
    rescue KeyError, ArgumentError => e
      raise ValidationError, "#{experiment.name}: invalid Phase-6 contract: #{e.message}"
    end

    def sole_worker(experiment)
      name = experiment.worker_names.fetch(0)
      @workers.fetch(name) { raise ValidationError, "worker #{name} is not configured" }
    end

    def sole_job(experiment)
      jobs = Scheduler.new(experiment: experiment, workers: @workers, models: @models).jobs
      raise ValidationError, "#{experiment.name}: expected exactly one scheduled job" unless jobs.length == 1
      jobs.first
    end

    def preflight_command(experiment, job, render_path, native_dir)
      exe = File.join(experiment.scorer_repo, "bin", "af-score")
      raise ValidationError, "scorer executable not found: #{exe}" unless File.file?(exe)

      [
        exe,
        "--preflight",
        "--render-preflight", render_path,
        "--model", job.ollama_model,
        "--dimension", experiment.dimension,
        "--output", native_dir,
        job.adventure,
        *experiment.extra_args
      ]
    end

    def validate_rendered!(row, experiment, native_dir, rendered)
      unless rendered["adventure_id"].to_s == row.fetch("adventure_id")
        raise ValidationError, "#{experiment.name}: rendered Adventure ID mismatch"
      end
      unless rendered["source_scope"].to_s == "canonical_page_slice"
        raise ValidationError,
              "#{experiment.name}: expected canonical_page_slice, got #{rendered['source_scope'].inspect}"
      end
      unless rendered["source_file"].is_a?(String) && !rendered["source_file"].empty?
        raise ValidationError, "#{experiment.name}: rendered source file is missing"
      end
      unless File.expand_path(rendered["output_root"].to_s) == File.expand_path(native_dir)
        raise ValidationError, "#{experiment.name}: rendered output root mismatch"
      end

      targets = Array(rendered["targets"])
      raise ValidationError, "#{experiment.name}: expected exactly one rendered target" unless targets.length == 1
      target = targets.first
      unless Array(target["dimensions"]) == [experiment.dimension]
        raise ValidationError, "#{experiment.name}: rendered dimension mismatch"
      end
      unless target["schema"].is_a?(Hash) && !target["schema"].empty?
        raise ValidationError, "#{experiment.name}: schema did not build"
      end
      unless target["prompt_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/) &&
             target["schema_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/)
        raise ValidationError, "#{experiment.name}: prompt/schema SHA is missing or invalid"
      end

      rule = PROFILE_RULES.fetch(experiment.dimension)
      metadata = rendered.fetch("run_metadata")
      unless metadata[rule.fetch(:metadata_profile_key)].to_s == rule.fetch(:env_value)
        raise ValidationError, "#{experiment.name}: active guardrail profile is missing from run metadata"
      end
      unless metadata[rule.fetch(:metadata_sha_key)].to_s.match?(/\A[0-9a-f]{64}\z/)
        raise ValidationError, "#{experiment.name}: active guardrail SHA is missing from run metadata"
      end
      unless metadata["prompt_profile"].to_s.include?(rule.fetch(:env_value))
        raise ValidationError, "#{experiment.name}: prompt_profile does not include the declared Phase-6 version"
      end
      unless metadata["experimental"] == true
        raise ValidationError, "#{experiment.name}: Phase-6 rendered metadata must be experimental"
      end
      unless metadata["selected_dimension"].to_s == experiment.dimension
        raise ValidationError, "#{experiment.name}: selected_dimension metadata mismatch"
      end

      prompt = target.fetch("prompt")
      prompt_text = "#{prompt['instructions']}\n#{prompt['input']}"
      marker = rule.fetch(:prompt_marker)
      unless prompt_text.scan(marker).length == 1
        raise ValidationError, "#{experiment.name}: intended Phase-6 guardrail marker must appear exactly once"
      end
      other_markers = PROFILE_RULES.reject { |dimension, _| dimension == experiment.dimension }
                                   .values.map { |v| v.fetch(:prompt_marker) }
      leaked_marker = other_markers.find { |other| prompt_text.include?(other) }
      if leaked_marker
        raise ValidationError, "#{experiment.name}: unrelated Phase-6 guardrail leaked into prompt: #{leaked_marker}"
      end
      forbidden = FORBIDDEN_PROMPT_TOKENS.find { |token| prompt_text.include?(token) }
      if forbidden
        raise ValidationError, "#{experiment.name}: orchestration/oracle metadata leaked into prompt: #{forbidden}"
      end
    rescue KeyError => e
      raise ValidationError, "#{experiment.name}: incomplete rendered preflight: #{e.message}"
    end

    def print_result(result)
      @io.puts "Phase-6 preflight: #{result.failed.zero? ? 'PASS' : 'FAIL'}"
      @io.puts "Cases: #{result.passed}/#{result.total} passed; #{result.failed} failed"
      @io.puts "Provider inference calls: 0"
      @io.puts "Rendered prompts: #{result.render_dir}"
      @io.puts "Summary: #{result.summary_path}"
    end
  end
end
