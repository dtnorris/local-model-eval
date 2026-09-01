# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "yaml"
require_relative "../lib/production_failure_classifier"

class ProductionFailureClassifierTest < Minitest::Test
  EXPECTED = LME::ProductionFailureClassifier::EXPECTED_MODEL_VALIDATION
  UNKNOWN = LME::ProductionFailureClassifier::OPERATIONAL_OR_UNKNOWN

  def classify(finish_reason: "stop", dimension: base_dimension, stderr:, prompt_tokens: 2_000, prompt_chars: 10_000)
    Dir.mktmpdir do |dir|
      manifest = File.join(dir, "experiment.yml")
      output_root = File.join(dir, "output")
      name = "fixture-experiment"
      File.write(manifest, {"name" => name}.to_yaml)

      run_dir = File.join(output_root, name, "runs", "job-1")
      raw_dir = File.join(run_dir, "native", "raw", "ADV-0001", "stamp")
      FileUtils.mkdir_p(raw_dir)
      File.write(File.join(run_dir, "metadata.json"), JSON.generate("status" => "failed"))
      File.write(File.join(run_dir, "stderr.log"), stderr)

      request = {
        "request" => {
          "payload" => {
            "messages" => [{"role" => "user", "content" => "x" * prompt_chars}]
          }
        }
      }
      File.write(File.join(raw_dir, "dimension_gm_beginner_suitability_request.json"), JSON.generate(request))

      response = {
        "usage" => {"prompt_tokens" => prompt_tokens},
        "choices" => [{
          "finish_reason" => finish_reason,
          "message" => {"content" => JSON.generate("dimensions" => [dimension])}
        }]
      }
      File.write(File.join(raw_dir, "dimension_gm_beginner_suitability.json"), JSON.generate(response))

      return LME::ProductionFailureClassifier.new(manifest: manifest, output_root: output_root).classify
    end
  end

  def base_dimension
    {
      "dimension" => "GM Beginner Suitability",
      "score" => 4,
      "rationale" => "Substantive rationale",
      "adjacent_lower_reason" => "Lower falsification",
      "adjacent_higher_reason" => "Higher falsification",
      "path_sensitive" => false
    }
  end

  def test_missing_adjacent_falsifications_are_expected_terminal_model_failure
    stderr = <<~TEXT
      ERROR: GM Beginner Suitability: adjacent-lower falsification is required for scores above 1; GM Beginner Suitability: adjacent-higher falsification is required for scores below 5
        - GM Beginner Suitability: adjacent-lower falsification is required for scores above 1
        - GM Beginner Suitability: adjacent-higher falsification is required for scores below 5
    TEXT

    dimension = base_dimension.merge("adjacent_lower_reason" => nil, "adjacent_higher_reason" => nil)
    assert_equal EXPECTED, classify(dimension: dimension, stderr: stderr)
  end

  def test_invalid_path_sensitive_is_expected_terminal_model_failure
    stderr = "ERROR: GM Beginner Suitability: path_sensitive must be boolean\n  - GM Beginner Suitability: path_sensitive must be boolean\n"
    dimension = base_dimension.merge("path_sensitive" => "false")
    assert_equal EXPECTED, classify(dimension: dimension, stderr: stderr)
  end

  def test_finish_reason_length_remains_operational_or_unknown
    stderr = "ERROR: GM Beginner Suitability: adjacent-higher falsification is required for scores below 5\n"
    assert_equal UNKNOWN, classify(finish_reason: "length", stderr: stderr)
  end

  def test_empty_rationale_remains_operational_or_unknown
    stderr = "ERROR: GM Beginner Suitability: adjacent-higher falsification is required for scores below 5\n"
    dimension = base_dimension.merge("rationale" => "", "adjacent_higher_reason" => nil)
    assert_equal UNKNOWN, classify(dimension: dimension, stderr: stderr)
  end

  def test_implausibly_truncated_prompt_usage_fails_closed
    stderr = "ERROR: GM Beginner Suitability: adjacent-higher falsification is required for scores below 5\n"
    dimension = base_dimension.merge("adjacent_higher_reason" => nil)
    assert_equal UNKNOWN, classify(dimension: dimension, stderr: stderr, prompt_tokens: 1_589, prompt_chars: 150_000)
  end

  def test_unknown_validation_error_fails_closed
    stderr = "ERROR: provider connection reset\n"
    assert_equal UNKNOWN, classify(stderr: stderr)
  end
end
