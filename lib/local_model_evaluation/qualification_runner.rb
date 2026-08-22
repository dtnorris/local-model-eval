# frozen_string_literal: true

require "csv"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "time"
require_relative "config"
require_relative "qualification_plan"

module LocalModelEvaluation
  class QualificationRunner
    class OperationalError < StandardError; end

    RESULT_HEADERS = %w[
      candidate_id model dimension case_id adventure oracle terra terra_class
      local local_class delta manifest experiment_output status note
    ].freeze

    attr_reader :plan, :repo_root, :output_dir

    def initialize(plan:, repo_root:, dry_run: false, force: false, out: $stdout, command_runner: nil)
      @plan = plan
      @repo_root = File.expand_path(repo_root)
      @dry_run = dry_run
      @force = force
      @out = out
      @command_runner = command_runner || method(:system_command)
      @output_dir = File.join(@repo_root, "output", "qualification", plan.name)
    end

    def run
      validate_static_inputs!
      print_plan
      return true if @dry_run

      prepare_bundle!
      rows = @force ? [] : load_rows
      write_environment

      plan.candidates.each do |candidate|
        rows = run_candidate(candidate, rows)
        write_results(rows)
        write_summary(rows)
      end

      write_summary(rows)
      true
    rescue OperationalError => e
      @out.puts "OPERATIONAL ERROR: #{e.message}"
      false
    end

    def self.classify(oracle, local)
      delta = Integer(local) - Integer(oracle)
      distance = delta.abs
      klass = if distance.zero?
                "exact"
              elsif distance == 1
                "adjacent"
              else
                "hard"
              end
      [klass, delta]
    end

    private

    def validate_static_inputs!
      workers = load_workers

      plan.candidates.each do |candidate|
        candidate.cases.each do |plan_case|
          comparator_case = candidate.comparator.case_by_id(plan_case.comparator_case_id)
          raise ArgumentError, "missing manifest #{plan_case.manifest_path}" unless File.file?(plan_case.manifest_path)

          manifest = Config.load_yaml(plan_case.manifest_path)
          models = Array(manifest["models"] || manifest["model"]).map(&:to_s)
          raise ArgumentError, "#{plan_case.manifest_path}: qualification manifest must contain only model #{candidate.model}" unless models == [candidate.model]
          raise ArgumentError, "#{plan_case.manifest_path}: dimension mismatch" unless manifest.fetch("dimension").to_s == candidate.comparator.dimension

          adventures = Array(manifest.fetch("adventures")).map(&:to_s)
          raise ArgumentError, "#{plan_case.manifest_path}: qualification manifest must contain only #{comparator_case.adventure}" unless adventures == [comparator_case.adventure]
          raise ArgumentError, "#{plan_case.manifest_path}: qualification manifests must use replicates: 1" unless Integer(manifest.fetch("replicates", 1)) == 1

          worker_names = Array(manifest.fetch("workers")).map(&:to_s)
          raise ArgumentError, "#{plan_case.manifest_path}: workers cannot be empty" if worker_names.empty?
          worker_names.each do |name|
            worker = workers.fetch(name) { raise ArgumentError, "#{plan_case.manifest_path}: unknown worker #{name}" }
            labels = Array(worker["labels"]).map(&:to_s)
            rate = Float(worker.fetch("hourly_rate_usd", 0.0))
            raise ArgumentError, "#{plan_case.manifest_path}: worker #{name} is not labeled local" unless labels.include?("local")
            raise ArgumentError, "#{plan_case.manifest_path}: worker #{name} is paid ($#{rate}/hr); Phase 5 refuses paid workers" if rate.positive?
          end
        end
      end
    end

    def load_workers
      path = File.join(repo_root, "config", "workers.yml")
      raise ArgumentError, "missing #{path}" unless File.file?(path)
      Config.load_yaml(path).fetch("workers")
    end

    def print_plan
      calls = plan.candidates.sum { |candidate| candidate.cases.length }
      @out.puts "Qualification plan: #{plan.name}"
      @out.puts "Candidates: #{plan.candidates.length}"
      @out.puts "Maximum new inference calls: #{calls}"
      @out.puts "Paid worker rate allowed: $0.00/hr"
      @out.puts "Exact-rate deficit limit: #{format('%.1f', plan.max_exact_deficit_percentage_points)} percentage points"
      plan.candidates.each do |candidate|
        c = candidate.comparator
        @out.puts format(
          "  - %s / %s: %d cases; Terra exact %.1f%%; Terra hard %d",
          candidate.model, c.dimension, c.completed_count, c.exact_rate * 100.0, c.hard_error_count
        )
      end
      @out.puts(@dry_run ? "Dry run only; no worker checks or inference will execute." : "")
    end

    def prepare_bundle!
      FileUtils.mkdir_p(File.join(output_dir, "comparators"))
      FileUtils.cp(plan.path, File.join(output_dir, "plan.yml"))
      plan.candidates.each do |candidate|
        FileUtils.cp(candidate.comparator_path, File.join(output_dir, "comparators", "#{candidate.comparator.id}.yml"))
      end
      if @force
        FileUtils.rm_f(File.join(output_dir, "results.csv"))
        FileUtils.rm_f(File.join(output_dir, "summary.md"))
      end
    end

    def write_environment
      head = capture(["git", "rev-parse", "HEAD"], chdir: repo_root).strip
      data = {
        "created_at" => Time.now.iso8601,
        "ruby" => RUBY_DESCRIPTION,
        "repo_root" => repo_root,
        "repo_head" => head,
        "qualification_plan" => plan.name,
        "paid_workers_allowed" => false
      }
      File.write(File.join(output_dir, "environment.json"), JSON.pretty_generate(data) + "\n")
    end

    def run_candidate(candidate, rows)
      comparator = candidate.comparator
      current = rows.select { |row| row["candidate_id"] == candidate.id }
      if decisive_stop?(comparator, current)
        @out.puts "SKIP #{candidate.id}: prior qualification stop remains decisive"
        return rows
      end

      preflight_manifest = candidate.cases.first.manifest_path
      unless completed_case?(current, candidate.cases.first.comparator_case_id)
        @out.puts "Preflight #{candidate.id}"
        ok = @command_runner.call([File.join(repo_root, "bin", "lme"), "worker-check", preflight_manifest], chdir: repo_root)
        raise OperationalError, "worker preflight failed for #{candidate.id}" unless ok
      end

      candidate.cases.each do |plan_case|
        current = rows.select { |row| row["candidate_id"] == candidate.id }
        break if decisive_stop?(comparator, current)
        next if completed_case?(current, plan_case.comparator_case_id)

        comparator_case = comparator.case_by_id(plan_case.comparator_case_id)
        @out.puts "RUN #{candidate.id} / #{comparator_case.id} / #{comparator_case.adventure}"
        ok = @command_runner.call([File.join(repo_root, "bin", "lme"), "run", plan_case.manifest_path], chdir: repo_root)
        raise OperationalError, "bin/lme run failed for #{candidate.id}/#{comparator_case.id}" unless ok

        manifest = Config.load_yaml(plan_case.manifest_path)
        experiment_output = File.join(repo_root, "output", manifest.fetch("name").to_s)
        local_value = extract_metric(experiment_output, comparator.metric)

        if local_value.nil?
          rows << result_row(candidate, comparator_case, plan_case, experiment_output,
                             local: nil, local_class: nil, delta: nil,
                             status: "invalid_output", note: "missing or ambiguous integer metric #{comparator.metric.inspect}")
          write_results(rows)
          @out.puts "STOP #{candidate.id}: invalid/missing structured metric"
          break
        end

        klass, delta = self.class.classify(comparator_case.oracle, local_value)
        rows << result_row(candidate, comparator_case, plan_case, experiment_output,
                           local: local_value, local_class: klass, delta: delta,
                           status: "complete", note: "")
        write_results(rows)

        hard_count = rows.count { |row| row["candidate_id"] == candidate.id && row["status"] == "complete" && row["local_class"] == "hard" }
        if hard_count > comparator.hard_error_count
          @out.puts "STOP #{candidate.id}: local hard errors #{hard_count} exceed Terra allowance #{comparator.hard_error_count}"
          break
        end
      end

      rows
    end

    def result_row(candidate, comparator_case, plan_case, experiment_output, local:, local_class:, delta:, status:, note:)
      {
        "candidate_id" => candidate.id,
        "model" => candidate.model,
        "dimension" => candidate.comparator.dimension,
        "case_id" => comparator_case.id,
        "adventure" => comparator_case.adventure,
        "oracle" => comparator_case.oracle.to_s,
        "terra" => comparator_case.terra.to_s,
        "terra_class" => comparator_case.classification,
        "local" => local&.to_s,
        "local_class" => local_class,
        "delta" => delta&.to_s,
        "manifest" => relative(plan_case.manifest_path),
        "experiment_output" => relative(experiment_output),
        "status" => status,
        "note" => note
      }
    end

    def extract_metric(experiment_output, metric)
      files = Dir.glob(File.join(experiment_output, "runs", "*", "native", "assessments", "*.csv")).sort
      values = files.filter_map do |path|
        row = CSV.foreach(path, headers: true).find { |item| item["metric"] == metric }
        next unless row && row["value"] && !row["value"].empty?
        Integer(row["value"], 10)
      rescue ArgumentError
        nil
      end
      values.length == 1 && (1..5).cover?(values.first) ? values.first : nil
    end

    def completed_case?(rows, case_id)
      rows.any? { |row| row["case_id"] == case_id && %w[complete invalid_output].include?(row["status"]) }
    end

    def decisive_stop?(comparator, rows)
      return true if rows.any? { |row| row["status"] == "invalid_output" }
      hard = rows.count { |row| row["status"] == "complete" && row["local_class"] == "hard" }
      hard > comparator.hard_error_count
    end

    def load_rows
      path = File.join(output_dir, "results.csv")
      return [] unless File.file?(path)
      CSV.read(path, headers: true).map(&:to_h)
    end

    def write_results(rows)
      FileUtils.mkdir_p(output_dir)
      CSV.open(File.join(output_dir, "results.csv"), "w") do |csv|
        csv << RESULT_HEADERS
        rows.each { |row| csv << RESULT_HEADERS.map { |header| row[header] } }
      end
    end

    def write_summary(rows)
      lines = ["# Phase-5 Local Qualification Summary", "", "Plan: `#{plan.name}`", ""]
      plan.candidates.each do |candidate|
        comparator = candidate.comparator
        current = rows.select { |row| row["candidate_id"] == candidate.id }
        status = candidate_status(candidate, current)
        completed = current.select { |row| row["status"] == "complete" }
        exact = completed.count { |row| row["local_class"] == "exact" }
        adjacent = completed.count { |row| row["local_class"] == "adjacent" }
        hard = completed.count { |row| row["local_class"] == "hard" }
        exact_rate = completed.empty? ? nil : exact.to_f / comparator.completed_count
        gap = exact_rate ? (comparator.exact_rate - exact_rate) * 100.0 : nil

        lines << "## #{candidate.id} — #{candidate.model} / #{comparator.dimension}"
        lines << ""
        lines << "- Status: **#{status}**"
        lines << "- Cases complete: #{completed.length}/#{comparator.completed_count}"
        lines << "- Local exact / adjacent / hard: #{exact} / #{adjacent} / #{hard}"
        lines << format("- Terra exact rate: %.1f%%", comparator.exact_rate * 100.0)
        lines << (exact_rate ? format("- Local exact rate on full comparator denominator: %.1f%%", exact_rate * 100.0) : "- Local exact rate: n/a")
        lines << (gap ? format("- Exact-rate deficit vs Terra: %.1f percentage points", gap) : "- Exact-rate deficit vs Terra: n/a")
        lines << "- Terra hard-error allowance: #{comparator.hard_error_count}"
        lines << "- Boundary bias detected: #{boundary_bias?(current) ? 'yes' : 'no'}"
        lines << ""
      end

      lines << "## Interpretation boundary"
      lines << ""
      lines << "This harness automates numeric non-inferiority and operational stop rules only."
      lines << "It does **not** grant `LOCAL_QUALIFIED`: source grounding, canonical-unit correctness, conceptual integrity, and any required matcher/product-impact review remain human adjudications under the frozen acceptance contract."
      lines << ""
      File.write(File.join(output_dir, "summary.md"), lines.join("\n") + "\n")
    end

    def candidate_status(candidate, rows)
      comparator = candidate.comparator
      return "QUALIFICATION_STOP_INVALID_OUTPUT" if rows.any? { |row| row["status"] == "invalid_output" }

      completed = rows.select { |row| row["status"] == "complete" }
      hard = completed.count { |row| row["local_class"] == "hard" }
      return "QUALIFICATION_STOP_HARD_ERROR" if hard > comparator.hard_error_count
      return "QUALIFICATION_INCOMPLETE" unless completed.length == comparator.completed_count

      exact = completed.count { |row| row["local_class"] == "exact" }
      local_exact_rate = exact.to_f / comparator.completed_count
      deficit = (comparator.exact_rate - local_exact_rate) * 100.0
      return "QUALIFICATION_NUMERIC_FAIL_EXACT_DEFICIT" if deficit > plan.max_exact_deficit_percentage_points
      return "QUALIFICATION_NUMERIC_PASS_BIAS_REVIEW_REQUIRED" if boundary_bias?(rows)

      "QUALIFICATION_NUMERIC_PASS_INTEGRITY_REVIEW_REQUIRED"
    end

    def boundary_bias?(rows)
      pairs = rows.filter_map do |row|
        next unless row["status"] == "complete" && row["local_class"] == "adjacent"
        [Integer(row["oracle"]), Integer(row["local"])]
      end
      pairs.tally.values.any? { |count| count >= 2 }
    end

    def relative(path)
      path = File.expand_path(path)
      prefix = repo_root + File::SEPARATOR
      path.start_with?(prefix) ? path.delete_prefix(prefix) : path
    end

    def capture(command, chdir:)
      stdout, _stderr, status = Open3.capture3(*command, chdir: chdir)
      status.success? ? stdout : "unknown"
    rescue Errno::ENOENT
      "unknown"
    end

    def system_command(command, chdir:)
      system(*command, chdir: chdir)
    end
  end
end
