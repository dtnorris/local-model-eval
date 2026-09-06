# frozen_string_literal: true

require "minitest/autorun"
require "open3"

class ServerlessBurstProbeScriptTest < Minitest::Test
  REPO_ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(REPO_ROOT, "bin", "lme-runpod-serverless-burst-probe")
  LIBRARY = File.join(REPO_ROOT, "lib", "serverless_burst_probe.py")

  def test_python_sources_compile
    _stdout, stderr, status = Open3.capture3("python3", "-m", "py_compile", SCRIPT, LIBRARY)
    assert status.success?, stderr
  end

  def test_probe_contract_is_fixed_and_self_cleaning
    text = File.read(LIBRARY)

    assert_includes text, 'DEFAULT_WORKER_COUNT = 8'
    assert_includes text, 'MAX_WORKER_COUNT = 8'
    assert_includes text, 'MODEL_NAME = "openai/gpt-oss-20b"'
    assert_includes text, 'GPU_TYPE = "NVIDIA GeForce RTX 4090"'
    assert_includes text, '"workersMin": 0'
    assert_includes text, '"workersMax": self.worker_count'
    assert_includes text, '"scalerType": "REQUEST_COUNT"'
    assert_includes text, '"event": "workers_ready"'
    assert_includes text, '"event": "all_first_tokens"'
    assert_includes text, 'self._delete_and_confirm'

    script = File.read(SCRIPT)
    assert_includes script, '"--workers"'
    refute_includes script, "--keep"

    _stdout, stderr, status = Open3.capture3(
      { "RUNPOD_API_KEY" => nil },
      SCRIPT,
      "--workers",
      "0",
      "--dry-run"
    )
    refute status.success?
    assert_equal 2, status.exitstatus
    assert_includes stderr, "ERROR: --workers must be between 1 and 8"
    refute_includes stderr, "RUNPOD_API_KEY"
  end
end
