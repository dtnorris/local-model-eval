# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "open3"
require "stringio"
require "tmpdir"
require_relative "../lib/local_model_evaluation/runpod_fleet"

class MatcherBurstScriptTest < Minitest::Test
  REPO_ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(REPO_ROOT, "bin", "lme-matcher-burst")

  class EightWorkerCatalogClient
    attr_reader :catalog_calls

    def initialize
      @catalog_calls = []
    end

    def list_pods = []

    def list_gpu_types(cloud:, count:)
      @catalog_calls << [cloud, count]
      [{
        "id" => "NVIDIA A40",
        "memory" => 48,
        "community" => true,
        "secure" => true,
        "availability" => "HIGH",
        "price" => { "community" => 0.35, "secure" => 0.44 }
      }]
    end
  end

  def test_runpod_preflight_checks_capacity_and_cost_for_all_eight_workers
    Dir.mktmpdir("lme-matcher-burst-") do |dir|
      client = EightWorkerCatalogClient.new
      fleet = LocalModelEvaluation::RunpodFleet.new(
        client: client,
        env_path: File.join(dir, ".env"),
        state_root: File.join(dir, "state"),
        out: StringIO.new
      )

      result = fleet.preflight(worker_count: 8)

      assert_equal 8, LocalModelEvaluation::RunpodFleet::MAX_WORKERS
      assert_equal 8, result.worker_count
      assert_in_delta 2.80, result.fleet_hourly_rate, 0.0001
      assert_equal [["COMMUNITY", 8]], client.catalog_calls

      error = assert_raises(LocalModelEvaluation::RunpodFleet::Error) do
        fleet.preflight(worker_count: 9, max_fleet_hourly_usd: 10.0)
      end
      assert_includes error.message, "between 1 and 8"
    end
  end

  def test_script_has_valid_bash_syntax
    _stdout, stderr, status = Open3.capture3("bash", "-n", SCRIPT)
    assert status.success?, stderr
  end

  def test_script_locks_the_eight_case_gptoss_pilot_and_teardown
    text = File.read(SCRIPT)

    assert_includes text, 'WORKERS=8'
    assert_includes text, 'MODEL="gpt-oss:20b"'
    assert_includes text, 'CONTEXT=32768'
    assert_includes text, '"Q1:1"'
    assert_includes text, '"Q4:2"'
    assert_includes text, 'AF_MATCHER_TEMPERATURE=""'
    assert_includes text, 'AF_MATCHER_SEED=""'
    assert_includes text, 'bin/af-matcher run-case'
    assert_includes text, 'runpod-bootstrap'
    assert_includes text, 'runpod-tunnels start --workers 1-8'
    assert_includes text, 'runpod-destroy --workers 1-8 --yes'
    assert_includes text, 'WATCHDOG_MINUTES="${LME_MATCHER_BURST_WATCHDOG_MINUTES:-25}"'
  end
end
