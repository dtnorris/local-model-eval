# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/local_model_evaluation/worker"
require_relative "../lib/local_model_evaluation/runpod_ready"

class RunpodReadyTest < Minitest::Test
  Experiment = Struct.new(:name, :worker_names, :models, :required_worker_labels, keyword_init: true)
  CheckResult = Struct.new(:ok, :version, :models, :error, :missing_models, :missing_labels, keyword_init: true)

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

  class FakeClient
    attr_reader :calls

    def initialize(pods)
      @pods = pods
      @calls = 0
    end

    def list_pods
      @calls += 1
      @pods
    end
  end

  class FakeTunnels
    attr_reader :calls

    def initialize(rows)
      @rows = rows
      @calls = []
    end

    def status(worker_indices: nil)
      @calls << worker_indices
      @rows
    end
  end

  class FakeProvenance
    def initialize(result: nil, error: nil)
      @result = result
      @error = error
    end

    def verify_experiment!(experiment:, models:)
      raise @error if @error
      @result
    end
  end

  class FakeWorkerCheck
    attr_reader :calls

    def initialize(results)
      @results = results
      @calls = []
    end

    def check(worker, required_models:, required_labels:)
      @calls << [worker.name, required_models, required_labels]
      @results.fetch(worker.name)
    end
  end

  def setup
    @tmp = Dir.mktmpdir("lme-ready-")
    @now = Time.utc(2026, 8, 30, 1, 0, 0)
    @fleet = {
      "fleet_id" => "20260830T003000Z-pod_a",
      "status" => "active",
      "created_at_utc" => "2026-08-30T00:30:00Z",
      "destroyed_at_utc" => nil,
      "cloud" => "SECURE",
      "gpu" => { "id" => "NVIDIA A40", "count_per_worker" => 1 },
      "fleet_hourly_rate_usd" => 0.88,
      "workers" => [fleet_worker(1, "pod_a"), fleet_worker(2, "pod_b")]
    }
    @state = FakeFleetState.new(root: @tmp, fleet: @fleet)
    @experiment = Experiment.new(
      name: "ee-gemma-five",
      worker_names: %w[burst_1 burst_2],
      models: ["gemma"],
      required_worker_labels: %w[remote nvidia]
    )
    @models = { "gemma" => { "ollama_model" => "gemma4:26b" } }
    @workers = {
      "burst_1" => LocalModelEvaluation::Worker.new("burst_1", { "base_url" => "http://127.0.0.1:11441", "labels" => %w[remote nvidia] }),
      "burst_2" => LocalModelEvaluation::Worker.new("burst_2", { "base_url" => "http://127.0.0.1:11442", "labels" => %w[remote nvidia] })
    }
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp && File.exist?(@tmp)
  end

  def test_all_gates_pass_and_billing_is_visible
    gate, client, tunnels, worker_check = build_gate

    snapshot = gate.check(experiment: @experiment, workers: @workers, models: @models)

    assert snapshot.fetch("ready")
    assert_equal 1, client.calls
    assert_equal [[1, 2]], tunnels.calls
    assert_equal 2, worker_check.calls.length
    assert_in_delta 0.88, snapshot.dig("billing", "current_tracked_hourly_rate_usd"), 0.0001
    assert_in_delta 0.44, snapshot.dig("billing", "estimated_accrued_cost_usd"), 0.0001

    output = gate.render(snapshot)
    assert_includes output, "provider        PASS"
    assert_includes output, "provenance      PASS"
    assert_includes output, "tunnels         PASS"
    assert_includes output, "worker-health   PASS"
    assert_includes output, "READY TO RUN"
  end

  def test_provider_state_failure_blocks_readiness_but_other_checks_still_run
    pods = provider_pods
    pods[1]["status"] = "STOPPED"
    gate, = build_gate(pods: pods)

    snapshot = gate.check(experiment: @experiment, workers: @workers, models: @models)

    refute snapshot.fetch("ready")
    row = check(snapshot, "provider")
    assert_equal "FAIL", row.fetch("status")
    assert_includes row.fetch("detail"), "burst_2 provider status"
    assert_equal "PASS", check(snapshot, "tunnels").fetch("status")
    assert_equal "PASS", check(snapshot, "worker-health").fetch("status")
  end

  def test_unhealthy_tunnel_blocks_readiness_and_skips_slow_worker_checks
    rows = tunnel_rows
    rows[1]["health_status"] = "unhealthy"
    rows[1]["detail"] = "connection refused"
    worker_check = FakeWorkerCheck.new(worker_results)
    gate, = build_gate(tunnel_rows: rows, worker_check: worker_check)

    snapshot = gate.check(experiment: @experiment, workers: @workers, models: @models)

    refute snapshot.fetch("ready")
    assert_equal "FAIL", check(snapshot, "tunnels").fetch("status")
    assert_equal "SKIP", check(snapshot, "worker-health").fetch("status")
    assert_empty worker_check.calls
  end

  def test_worker_missing_required_model_blocks_readiness
    results = worker_results
    results["burst_2"] = CheckResult.new(
      ok: false,
      version: "0.33.2",
      models: [],
      error: nil,
      missing_models: ["gemma4:26b"],
      missing_labels: []
    )
    gate, = build_gate(worker_check: FakeWorkerCheck.new(results))

    snapshot = gate.check(experiment: @experiment, workers: @workers, models: @models)

    refute snapshot.fetch("ready")
    row = check(snapshot, "worker-health")
    assert_equal "FAIL", row.fetch("status")
    assert_includes row.fetch("detail"), "burst_2: missing models gemma4:26b"
  end

  def test_provenance_failure_blocks_readiness
    error = LocalModelEvaluation::RunpodProvenance::Error.new("digest mismatch")
    gate, = build_gate(provenance: FakeProvenance.new(error: error))

    snapshot = gate.check(experiment: @experiment, workers: @workers, models: @models)

    refute snapshot.fetch("ready")
    assert_equal "FAIL", check(snapshot, "provenance").fetch("status")
    assert_includes check(snapshot, "provenance").fetch("detail"), "digest mismatch"
  end

  def test_experiment_without_burst_workers_is_not_applicable_and_makes_no_remote_calls
    experiment = Experiment.new(
      name: "local-only",
      worker_names: ["mac"],
      models: ["gemma"],
      required_worker_labels: []
    )
    client = FakeClient.new(provider_pods)
    tunnels = FakeTunnels.new(tunnel_rows)
    worker_check = FakeWorkerCheck.new(worker_results)
    gate = LocalModelEvaluation::RunpodReady.new(
      fleet_state: @state,
      client: client,
      tunnels: tunnels,
      worker_check: worker_check,
      provenance: provenance,
      wall_clock: -> { @now }
    )

    snapshot = gate.check(experiment: experiment, workers: {}, models: @models)

    assert snapshot.fetch("ready")
    refute snapshot.fetch("applicable")
    assert_equal 0, client.calls
    assert_empty tunnels.calls
    assert_empty worker_check.calls
    assert_includes gate.render(snapshot), "NOT APPLICABLE"
  end

  private

  def build_gate(pods: provider_pods, tunnel_rows: self.tunnel_rows, worker_check: FakeWorkerCheck.new(worker_results), provenance: self.provenance)
    client = FakeClient.new(pods)
    tunnels = FakeTunnels.new(tunnel_rows)
    gate = LocalModelEvaluation::RunpodReady.new(
      fleet_state: @state,
      client: client,
      tunnels: tunnels,
      worker_check: worker_check,
      provenance: provenance,
      wall_clock: -> { @now }
    )
    [gate, client, tunnels, worker_check]
  end

  def provenance
    FakeProvenance.new(result: {
      "fleet_id" => @fleet.fetch("fleet_id"),
      "bootstrap_run_id" => "20260830T003500Z-1111-abcd",
      "workers" => [1, 2],
      "models" => ["gemma4:26b"],
      "digests" => { "gemma4:26b" => "a" * 64 },
      "context" => 262_144,
      "gpu" => "NVIDIA A40"
    })
  end

  def provider_pods
    [
      { "id" => "pod_a", "name" => "af-lme-burst-1", "status" => "RUNNING" },
      { "id" => "pod_b", "name" => "af-lme-burst-2", "status" => "RUNNING" }
    ]
  end

  def tunnel_rows
    [
      { "index" => 1, "pid" => 101, "process_status" => "running", "health_status" => "healthy", "endpoint" => "http://127.0.0.1:11441", "ollama_version" => "0.33.2", "detail" => nil },
      { "index" => 2, "pid" => 102, "process_status" => "running", "health_status" => "healthy", "endpoint" => "http://127.0.0.1:11442", "ollama_version" => "0.33.2", "detail" => nil }
    ]
  end

  def worker_results
    {
      "burst_1" => healthy_worker_result,
      "burst_2" => healthy_worker_result
    }
  end

  def healthy_worker_result
    CheckResult.new(
      ok: true,
      version: "0.33.2",
      models: ["gemma4:26b"],
      error: nil,
      missing_models: [],
      missing_labels: []
    )
  end

  def fleet_worker(index, pod_id)
    {
      "index" => index,
      "name" => "af-lme-burst-#{index}",
      "pod_id" => pod_id,
      "host" => "198.51.100.#{index}",
      "ssh_port" => 22_000 + index,
      "hourly_rate_usd" => 0.44,
      "local_ollama_url" => "http://127.0.0.1:#{11_440 + index}",
      "status" => "active"
    }
  end

  def check(snapshot, name)
    snapshot.fetch("checks").find { |row| row.fetch("name") == name } || raise("missing #{name}")
  end
end
