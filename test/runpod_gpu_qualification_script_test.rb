# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"

class RunpodGpuQualificationScriptTest < Minitest::Test
  REPO_ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(REPO_ROOT, "bin", "lme-qualify-gpu")

  def test_runpod_gpu_selection_remains_environment_configurable
    code = <<~'RUBY'
      require "local_model_evaluation/runpod_fleet"
      puts LocalModelEvaluation::RunpodFleet::GPU_ID
      puts LocalModelEvaluation::RunpodFleet::GPU_MEMORY_GB
    RUBY

    stdout, stderr, status = Open3.capture3(
      {
        "RUNPOD_GPU_ID" => "NVIDIA GeForce RTX 3090",
        "RUNPOD_GPU_MEMORY_GB" => "24"
      },
      RbConfig.ruby,
      "-I", File.join(REPO_ROOT, "lib"),
      "-e", code
    )

    assert status.success?, stderr
    assert_equal ["NVIDIA GeForce RTX 3090", "24"], stdout.lines.map(&:strip)
  end

  def test_qualification_script_has_valid_bash_syntax
    _stdout, stderr, status = Open3.capture3("bash", "-n", SCRIPT)
    assert status.success?, stderr
  end

  def test_qualification_script_requires_gpu_and_vram_and_freezes_workload
    text = File.read(SCRIPT)

    assert_includes text, 'GPU_ID=""'
    assert_includes text, 'GPU_MEMORY_GB=""'
    assert_includes text, 'MODEL="gpt-oss:20b"'
    assert_includes text, 'CONTEXT=32768'
    assert_includes text, 'QUERY_ID="Q3"'
    assert_includes text, 'REPEAT=1'
    assert_includes text, '--gpu'
    assert_includes text, '--vram'
    assert_includes text, 'runpod-create'
    assert_includes text, '--workers 1'
    assert_includes text, 'runpod-bootstrap'
    assert_includes text, 'bin/af-matcher run-case'
    assert_includes text, 'size == size_vram'
    assert_includes text, 'runpod-destroy --workers 1 --yes'
    assert_includes text, 'WATCHDOG_MINUTES="${LME_GPU_QUAL_WATCHDOG_MINUTES:-15}"'
  end
end
