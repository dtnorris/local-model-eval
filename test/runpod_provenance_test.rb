# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../lib/local_model_evaluation/runpod_provenance"

class RunpodProvenanceTest < Minitest::Test
  DIGEST = "a" * 64
  OTHER_DIGEST = "b" * 64
  Experiment = Struct.new(:worker_names, :models, keyword_init: true)

  class FakeFleetState
    def initialize(root:, fleet:)
      @root = root
      @fleet = fleet
    end

    def current
      @fleet
    end

    def artifact_dir(fleet_id, name)
      File.join(@root, fleet_id, name)
    end
  end

  def setup
    @tmp = Dir.mktmpdir("lme-provenance-")
    @fleet = {
      "fleet_id" => "20260829T200000Z-podabc",
      "status" => "active",
      "gpu" => { "id" => "NVIDIA A40", "count_per_worker" => 1 },
      "workers" => [
        { "index" => 1, "status" => "active" },
        { "index" => 2, "status" => "active" }
      ]
    }
    @state = FakeFleetState.new(root: @tmp, fleet: @fleet)
    @models = {
      "gemma" => { "ollama_model" => "gemma4:26b" },
      "qwen27" => { "ollama_model" => "qwen3.6:27b" }
    }
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp && File.exist?(@tmp)
  end

  def test_passes_exact_model_digest_context_gpu_and_residency
    write_bootstrap
    result = verifier.verify_experiment!(
      experiment: Experiment.new(worker_names: %w[burst_1 burst_2], models: ["gemma"]),
      models: @models
    )

    assert_equal [1, 2], result.fetch("workers")
    assert_equal ["gemma4:26b"], result.fetch("models")
    assert_equal DIGEST, result.dig("digests", "gemma4:26b")
    assert_equal 262_144, result.fetch("context")
    assert_equal "NVIDIA A40", result.fetch("gpu")
  end

  def test_fails_closed_when_experiment_requires_a_different_model
    write_bootstrap

    error = assert_raises(LocalModelEvaluation::RunpodProvenance::Error) do
      verifier.verify_experiment!(
        experiment: Experiment.new(worker_names: ["burst_1"], models: ["qwen27"]),
        models: @models
      )
    end

    assert_includes error.message, "model mismatch"
    assert_includes error.message, "qwen3.6:27b"
  end

  def test_fails_closed_on_digest_context_gpu_or_residency_mismatch
    [
      ->(record) { record["workers"][0]["provenance"]["models"]["gemma4:26b"]["digest"] = OTHER_DIGEST },
      ->(record) { record["workers"][0]["provenance"]["models"]["gemma4:26b"]["context_length"] = 131_072 },
      ->(record) { record["workers"][0]["provenance"]["gpu"]["name"] = "NVIDIA A100" },
      lambda do |record|
        model = record["workers"][0]["provenance"]["models"]["gemma4:26b"]
        model["size_vram_bytes"] = model["size_bytes"] - 1
        model["fully_gpu_resident"] = false
      end
    ].each do |mutation|
      record = bootstrap_record
      mutation.call(record)
      write_bootstrap(record)

      assert_raises(LocalModelEvaluation::RunpodProvenance::Error) do
        verifier.verify_experiment!(
          experiment: Experiment.new(worker_names: ["burst_1"], models: ["gemma"]),
          models: @models
        )
      end
    end
  end

  def test_fails_closed_when_latest_bootstrap_is_not_passed_or_worker_missing
    record = bootstrap_record
    record["status"] = "failed"
    write_bootstrap(record)

    error = assert_raises(LocalModelEvaluation::RunpodProvenance::Error) do
      verifier.verify_experiment!(
        experiment: Experiment.new(worker_names: ["burst_1"], models: ["gemma"]),
        models: @models
      )
    end
    assert_includes error.message, "not passed"

    record = bootstrap_record
    record["workers"].reject! { |worker| worker["index"] == 2 }
    write_bootstrap(record)
    error = assert_raises(LocalModelEvaluation::RunpodProvenance::Error) do
      verifier.verify_experiment!(
        experiment: Experiment.new(worker_names: ["burst_2"], models: ["gemma"]),
        models: @models
      )
    end
    assert_includes error.message, "does not contain burst_2"
  end

  def test_local_only_experiment_does_not_require_runpod_state
    state = FakeFleetState.new(root: @tmp, fleet: nil)
    result = LocalModelEvaluation::RunpodProvenance.new(fleet_state: state).verify_experiment!(
      experiment: Experiment.new(worker_names: ["mac"], models: ["gemma"]),
      models: @models
    )

    assert_nil result
  end

  private

  def verifier
    LocalModelEvaluation::RunpodProvenance.new(fleet_state: @state)
  end

  def write_bootstrap(record = bootstrap_record)
    root = @state.artifact_dir(@fleet.fetch("fleet_id"), "bootstrap")
    run_id = record.fetch("bootstrap_run_id")
    run_dir = File.join(root, run_id)
    FileUtils.mkdir_p(run_dir)
    File.write(File.join(root, "current"), "#{run_id}\n")
    File.write(File.join(run_dir, "bootstrap.json"), JSON.pretty_generate(record))
  end

  def bootstrap_record
    {
      "schema_version" => 2,
      "bootstrap_run_id" => "20260829T201000Z-1234-abcd",
      "fleet_id" => @fleet.fetch("fleet_id"),
      "status" => "passed",
      "models" => ["gemma4:26b"],
      "expected_digests" => { "gemma4:26b" => DIGEST },
      "expected_gpu" => "NVIDIA A40",
      "context" => 262_144,
      "workers" => [verified_worker(1), verified_worker(2)]
    }
  end

  def verified_worker(index)
    {
      "index" => index,
      "status" => "passed",
      "provenance" => {
        "gpu" => {
          "name" => "NVIDIA A40",
          "vram_mib" => 46_068
        },
        "models" => {
          "gemma4:26b" => {
            "digest" => DIGEST,
            "context_length" => 262_144,
            "size_bytes" => 2_566_893_074,
            "size_vram_bytes" => 2_566_893_074,
            "fully_gpu_resident" => true
          }
        }
      }
    }
  end
end
