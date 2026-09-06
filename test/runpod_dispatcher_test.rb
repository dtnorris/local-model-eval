# frozen_string_literal: true

require_relative "test_helper"

class RunpodDispatcherTest < Minitest::Test
  Health = Struct.new(:healthy, :detail, keyword_init: true)

  class FakeFleetState
    attr_reader :fleet

    def initialize(worker_count)
      @fleet = {
        "fleet_id" => "20260905T120000Z-podabc",
        "status" => "active",
        "worker_count" => worker_count,
        "workers" => (1..worker_count).map do |index|
          {
            "index" => index,
            "pod_id" => "pod_#{index}",
            "status" => "active",
            "local_ollama_url" => "http://127.0.0.1:#{11_440 + index}"
          }
        end
      }
    end

    def current
      Marshal.load(Marshal.dump(@fleet))
    end
  end

  class HealthyEndpoints
    def check(_endpoint)
      Health.new(healthy: true)
    end
  end

  class TrackingRunner
    attr_reader :calls, :max_active_by_worker, :environments

    def initialize(fail_ids: [], after: nil)
      @fail_ids = fail_ids
      @after = after
      @calls = []
      @environments = {}
      @active_by_worker = Hash.new(0)
      @max_active_by_worker = Hash.new(0)
      @mutex = Mutex.new
    end

    def run(argv:, env:, stdout_path:, stderr_path:, chdir:)
      job_id = env.fetch("LME_JOB_ID")
      worker = Integer(env.fetch("LME_WORKER_INDEX"))
      @mutex.synchronize do
        @calls << job_id
        @environments[job_id] = env.dup
        @active_by_worker[worker] += 1
        @max_active_by_worker[worker] = [@max_active_by_worker[worker], @active_by_worker[worker]].max
      end
      sleep 0.003
      File.write(stdout_path, "#{job_id} via #{env.fetch('LME_OLLAMA_URL')} in #{chdir}\n")
      File.write(stderr_path, @fail_ids.include?(job_id) ? "simulated failure\n" : "")
      @fail_ids.include?(job_id) ? 7 : 0
    ensure
      @mutex.synchronize { @active_by_worker[worker] -= 1 } if worker
      @after&.call(job_id)
    end
  end

  def setup
    @tmp = Dir.mktmpdir("lme-runpod-dispatcher-")
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp && File.exist?(@tmp)
  end

  def test_twelve_jobs_execute_exactly_once_without_overlapping_a_worker
    [4, 6, 8, 12].each do |worker_count|
      fleet_state = FakeFleetState.new(worker_count)
      runner = TrackingRunner.new
      dispatcher = build_dispatcher(fleet_state, runner, "twelve-on-#{worker_count}")

      summary = dispatcher.run(jobs: jobs(12), worker_indices: (1..worker_count).to_a)

      assert_equal "completed", summary.fetch("status")
      assert_equal 12, summary.fetch("completed_count")
      assert_equal 0, summary.fetch("not_started_count")
      assert_equal jobs(12).map { |job| job.fetch("job_id") }.sort, runner.calls.sort
      assert runner.max_active_by_worker.values.all? { |maximum| maximum == 1 },
             "a worker ran overlapping jobs with #{worker_count} workers"
    end
  end

  def test_fewer_jobs_than_workers_execute_once
    fleet_state = FakeFleetState.new(6)
    runner = TrackingRunner.new
    dispatcher = build_dispatcher(fleet_state, runner, "three-on-six")

    summary = dispatcher.run(jobs: jobs(3), worker_indices: (1..6).to_a)

    assert_equal "completed", summary.fetch("status")
    assert_equal 3, summary.fetch("completed_count")
    assert_equal %w[job-01 job-02 job-03], runner.calls.sort
    assert runner.max_active_by_worker.values.all? { |maximum| maximum == 1 }
  end

  def test_workload_failure_preserves_all_job_evidence_and_continues
    fleet_state = FakeFleetState.new(2)
    runner = TrackingRunner.new(fail_ids: ["job-02"])
    dispatcher = build_dispatcher(fleet_state, runner, "workload-failure")

    summary = dispatcher.run(jobs: jobs(5), worker_indices: [1, 2])

    assert_equal "workload_failed", summary.fetch("status")
    assert_equal 4, summary.fetch("completed_count")
    assert_equal 1, summary.fetch("failed_count")
    assert_equal 0, summary.fetch("not_started_count")
    assert_equal 5, runner.calls.uniq.length
    failed = JSON.parse(File.read(File.join(dispatcher.output_dir, "jobs", "job-02", "metadata.json")))
    assert_equal "failed", failed.fetch("status")
    assert_equal 7, failed.fetch("exit_status")
    assert_equal "simulated failure\n", File.read(File.join(dispatcher.output_dir, failed.fetch("stderr_path")))
    assert File.file?(File.join(dispatcher.output_dir, "jobs", "job-01", "stdout.log"))
  end

  def test_infrastructure_failure_stops_new_assignments_and_preserves_completion
    fleet_state = FakeFleetState.new(1)
    runner = TrackingRunner.new(after: lambda do |job_id|
      fleet_state.fleet.fetch("workers").first["status"] = "destroyed" if job_id == "job-01"
    end)
    dispatcher = build_dispatcher(fleet_state, runner, "infrastructure-failure")

    summary = dispatcher.run(jobs: jobs(3), worker_indices: [1])

    assert_equal "infrastructure_failed", summary.fetch("status")
    assert_equal 1, summary.fetch("completed_count")
    assert_equal 2, summary.fetch("not_started_count")
    assert_equal ["job-01"], runner.calls
    assert_includes summary.fetch("infrastructure_failures").first.fetch("error"), "is not active"
    assert File.file?(File.join(dispatcher.output_dir, "jobs", "job-01", "metadata.json"))
  end

  def test_generic_identity_and_endpoint_are_injected_without_shell_interpolation
    fleet_state = FakeFleetState.new(16)
    runner = TrackingRunner.new
    dispatcher = build_dispatcher(fleet_state, runner, "worker-sixteen")
    job = {
      "job_id" => "portable-job",
      "argv" => ["fake-workload", "argument with spaces", "; not shell"],
      "env" => { "WORKLOAD_SETTING" => "kept" }
    }

    summary = dispatcher.run(jobs: [job], worker_indices: [16])

    assert_equal "completed", summary.fetch("status")
    env = runner.environments.fetch("portable-job")
    assert_equal "portable-job", env.fetch("LME_JOB_ID")
    assert_equal "16", env.fetch("LME_WORKER_INDEX")
    assert_equal "http://127.0.0.1:11456", env.fetch("LME_OLLAMA_URL")
    assert_equal "kept", env.fetch("WORKLOAD_SETTING")
    metadata = summary.fetch("jobs").first
    assert_equal 16, metadata.fetch("worker_index")
    assert_equal "http://127.0.0.1:11456", metadata.fetch("worker_url")
  end

  private

  def jobs(count)
    (1..count).map do |index|
      { "job_id" => format("job-%02d", index), "argv" => ["fake-workload", index.to_s], "env" => {} }
    end
  end

  def build_dispatcher(fleet_state, runner, name)
    LocalModelEvaluation::RunpodDispatcher.new(
      fleet_state:,
      output_dir: File.join(@tmp, name),
      repo_root: @tmp,
      out: StringIO.new,
      endpoint_checker: HealthyEndpoints.new,
      command_runner: runner
    )
  end
end
