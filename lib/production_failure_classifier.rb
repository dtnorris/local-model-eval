# frozen_string_literal: true

require "json"
require "yaml"

module LME
  class ProductionFailureClassifier
    EXPECTED_MODEL_VALIDATION = "expected_model_validation"
    OPERATIONAL_OR_UNKNOWN = "operational_or_unknown"

    EXPECTED_VALIDATION_PATTERNS = [
      /adjacent-lower falsification is required for scores above 1/,
      /adjacent-higher falsification is required for scores below 5/,
      /path_sensitive must be boolean/
    ].freeze

    def initialize(manifest:, output_root:)
      @manifest = manifest
      @output_root = output_root
    end

    def classify
      run_dir = latest_failed_run_dir
      return OPERATIONAL_OR_UNKNOWN unless run_dir

      stderr = read_file(File.join(run_dir, "stderr.log"))
      return OPERATIONAL_OR_UNKNOWN unless expected_validation_stderr?(stderr)

      response_path = provider_response_path(run_dir)
      return OPERATIONAL_OR_UNKNOWN unless response_path

      response = JSON.parse(File.read(response_path))
      choice = Array(response["choices"]).first
      return OPERATIONAL_OR_UNKNOWN unless choice.is_a?(Hash)
      return OPERATIONAL_OR_UNKNOWN unless choice["finish_reason"] == "stop"
      return OPERATIONAL_OR_UNKNOWN unless prompt_usage_plausible?(run_dir, response)

      content = choice.dig("message", "content")
      return OPERATIONAL_OR_UNKNOWN unless content.is_a?(String) && !content.empty?

      parsed = JSON.parse(content)
      dimension = Array(parsed["dimensions"]).first
      return OPERATIONAL_OR_UNKNOWN unless dimension.is_a?(Hash)
      return OPERATIONAL_OR_UNKNOWN unless (1..5).cover?(dimension["score"])

      rationale = dimension["rationale"]
      return OPERATIONAL_OR_UNKNOWN unless rationale.is_a?(String) && !rationale.strip.empty?

      EXPECTED_MODEL_VALIDATION
    rescue JSON::ParserError, Errno::ENOENT, Psych::SyntaxError, KeyError, TypeError
      OPERATIONAL_OR_UNKNOWN
    end

    private

    def experiment_name
      @experiment_name ||= YAML.safe_load_file(@manifest).fetch("name")
    end

    def latest_failed_run_dir
      metadata = Dir.glob(File.join(@output_root, experiment_name, "runs", "*", "metadata.json"))
      failed = metadata.select do |path|
        JSON.parse(File.read(path))["status"].to_s == "failed"
      rescue JSON::ParserError, Errno::ENOENT
        false
      end
      path = failed.max_by { |candidate| File.mtime(candidate) }
      path && File.dirname(path)
    end

    def provider_response_path(run_dir)
      candidates = Dir.glob(File.join(run_dir, "native", "raw", "*", "*", "dimension_*.json"))
      candidates.reject! { |path| path.end_with?("_request.json") }
      candidates.max_by { |path| File.mtime(path) }
    end

    def prompt_usage_plausible?(run_dir, response)
      prompt_tokens = response.dig("usage", "prompt_tokens")
      return false unless prompt_tokens.is_a?(Integer) && prompt_tokens.positive?

      request_path = provider_request_path(run_dir)
      return false unless request_path

      request = JSON.parse(File.read(request_path))
      messages = Array(request.dig("request", "payload", "messages"))
      prompt_chars = messages.sum do |message|
        content = message.is_a?(Hash) ? message["content"] : nil
        content.is_a?(String) ? content.length : 0
      end
      return false if prompt_chars.zero?

      # Very generous sanity bound. Normal prose is only a few characters/token;
      # the 20x ceiling exists only to detect catastrophic server-side context
      # truncation such as a ~150k-character request reported as ~1.6k tokens.
      prompt_chars <= prompt_tokens * 20
    end

    def provider_request_path(run_dir)
      candidates = Dir.glob(File.join(run_dir, "native", "raw", "*", "*", "dimension_*_request.json"))
      candidates.max_by { |path| File.mtime(path) }
    end

    def read_file(path)
      File.read(path)
    rescue Errno::ENOENT
      ""
    end

    def expected_validation_stderr?(stderr)
      lines = stderr.lines.map(&:strip).reject(&:empty?)
      return false if lines.empty?

      messages = lines.flat_map do |line|
        line = line.sub(/\A-\s*/, "").sub(/\AERROR:\s*/, "")
        line.split(/;\s*/).map(&:strip)
      end.reject(&:empty?)

      !messages.empty? && messages.all? do |message|
        EXPECTED_VALIDATION_PATTERNS.any? { |pattern| pattern.match?(message) }
      end
    end
  end
end
