# frozen_string_literal: true
require_relative "test_helper"

class WorkerCheckTest < Minitest::Test
  class StubWorkerCheck < LocalModelEvaluation::WorkerCheck
    def initialize(version: "0.33.2", models: ["qwen3.6:27b"])
      @version = version
      @models = models
    end

    private

    def get_json(_base_url, path)
      return { "version" => @version } if path == "/api/version"
      return { "models" => @models.map { |name| { "name" => name } } } if path == "/api/tags"
      raise "unexpected path #{path}"
    end
  end

  def test_required_worker_labels_make_an_otherwise_healthy_worker_ineligible
    worker = LocalModelEvaluation::Worker.new(
      "burst_1",
      "base_url" => "http://127.0.0.1:11441",
      "labels" => %w[remote burst a40]
    )

    result = StubWorkerCheck.new.check(
      worker,
      required_models: ["qwen3.6:27b"],
      required_labels: %w[remote burst nvidia a40 48gb]
    )

    refute result.ok
    assert_equal %w[nvidia 48gb], result.missing_labels
    assert_empty result.missing_models
    assert_nil result.error
  end

  def test_required_model_and_labels_pass_when_worker_satisfies_both
    worker = LocalModelEvaluation::Worker.new(
      "burst_1",
      "base_url" => "http://127.0.0.1:11441",
      "labels" => %w[remote burst nvidia a40 48gb]
    )

    result = StubWorkerCheck.new.check(
      worker,
      required_models: ["qwen3.6:27b"],
      required_labels: %w[remote burst nvidia a40 48gb]
    )

    assert result.ok
    assert_empty result.missing_labels
    assert_empty result.missing_models
    assert_equal "0.33.2", result.version
  end
end
