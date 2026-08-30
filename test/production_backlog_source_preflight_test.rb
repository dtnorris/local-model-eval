# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "pathname"
require "stringio"
require "yaml"

class ProductionBacklogSourcePreflightTest < Minitest::Test
  FakeStatus = Struct.new(:ok) do
    def success?
      ok
    end
  end

  def setup
    @root = Dir.mktmpdir("lme-source-preflight")
    FileUtils.mkdir_p(File.join(@root, "config"))
    FileUtils.mkdir_p(File.join(@root, "experiments", "queue"))
    FileUtils.mkdir_p(File.join(@root, "production_backlog", "queue"))
    FileUtils.mkdir_p(File.join(@root, "scorer", "bin"))
    File.write(File.join(@root, "scorer", "bin", "af-score"), "#!/bin/sh\n")
    File.write(
      File.join(@root, "config", "models.yml"),
      YAML.dump("models" => { "qwen" => { "ollama_model" => "qwen3.6:35b-a3b" } })
    )
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_preflights_each_unique_runtime_source_context_once
    first = write_manifest("levels", "Levels", "ADV-0059")
    second = write_manifest("combat", "Combat Emphasis", "ADV-0059")
    write_order(first, second)

    calls = []
    runner = lambda do |env, command, chdir|
      calls << [env, command, chdir]
      ["ok", "", FakeStatus.new(true)]
    end
    out = StringIO.new
    err = StringIO.new

    ok = LocalModelEvaluation::ProductionBacklogSourcePreflight.new(
      root: @root,
      io: out,
      err: err,
      command_runner: runner
    ).run("production_backlog/queue")

    assert ok
    assert_equal 1, calls.length
    _env, command, chdir = calls.fetch(0)
    assert_equal File.join(@root, "scorer"), chdir
    assert_equal File.join(@root, "scorer", "bin", "af-score"), command.fetch(0)
    assert_includes command, "qwen3.6:35b-a3b"
    assert_includes command, "--preflight"
    assert_includes command, "ADV-0059"
    assert_match(/Runtime source preflight: PASS/, out.string)
    assert_empty err.string
  end

  def test_fails_closed_when_active_scorer_cannot_resolve_a_source
    first = write_manifest("levels", "Levels", "ADV-0059")
    write_order(first)

    runner = lambda do |_env, _command, _chdir|
      ["", 'ERROR: No Markdown source resolved for "Rise of the Ice Dragons Trilogy"', FakeStatus.new(false)]
    end
    out = StringIO.new
    err = StringIO.new

    ok = LocalModelEvaluation::ProductionBacklogSourcePreflight.new(
      root: @root,
      io: out,
      err: err,
      command_runner: runner
    ).run("production_backlog/queue")

    refute ok
    assert_match(/SOURCE FAIL/, err.string)
    assert_match(/No Markdown source resolved/, err.string)
    assert_match(/No inference is authorized/, err.string)
  end

  def test_applies_manifest_prompt_profile_environment_and_runtime_config
    manifest = write_manifest(
      "social",
      "Social Interaction Emphasis",
      "ADV-0122",
      extra_args: ["--config", "${LME_REPO}/runtime.yml"],
      phase6: {
        "prompt_profile" => {
          "version" => "phase6-v0.3",
          "env_name" => "AF_SOCIAL_INTERACTION_GUARDRAIL_PROFILE",
          "env_value" => "phase6-v0.3"
        }
      }
    )
    write_order(manifest)
    File.write(File.join(@root, "runtime.yml"), "--- {}\n")

    calls = []
    runner = lambda do |env, command, chdir|
      calls << [env, command, chdir]
      ["ok", "", FakeStatus.new(true)]
    end

    old_lme_repo = ENV.delete("LME_REPO")
    begin
      ok = LocalModelEvaluation::ProductionBacklogSourcePreflight.new(
        root: @root,
        io: StringIO.new,
        err: StringIO.new,
        command_runner: runner
      ).run("production_backlog/queue")
      assert ok
    ensure
      ENV["LME_REPO"] = old_lme_repo if old_lme_repo
    end

    env, command, = calls.fetch(0)
    assert_equal "phase6-v0.3", env.fetch("AF_SOCIAL_INTERACTION_GUARDRAIL_PROFILE")
    assert_equal ["--config", File.join(@root, "runtime.yml")], command.last(2)
  end

  private

  def write_manifest(slug, dimension, adventure, extra_args: [], phase6: nil)
    path = File.join(@root, "experiments", "queue", "#{slug}.yml")
    data = {
      "name" => "queue-#{slug}",
      "dispatch" => "pool",
      "models" => ["qwen"],
      "dimension" => dimension,
      "adventures" => [adventure],
      "replicates" => 1,
      "workers" => ["mac"],
      "scorer" => {
        "repo" => "../../scorer",
        "mode" => "positional",
        "extra_args" => extra_args
      }
    }
    data["phase6_contract"] = phase6 if phase6
    File.write(path, YAML.dump(data))
    Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s
  end

  def write_order(*entries)
    File.write(
      File.join(@root, "production_backlog", "queue", "run_order.txt"),
      entries.join("\n") + "\n"
    )
  end
end

class ProductionBacklogRuntimeSourceGateIntegrationTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_runner_stops_before_lme_when_runtime_source_preflight_fails
    Dir.mktmpdir("lme-runtime-source-gate") do |repo|
      FileUtils.mkdir_p(File.join(repo, "bin"))
      FileUtils.mkdir_p(File.join(repo, "production_backlog", "queue"))
      FileUtils.mkdir_p(File.join(repo, "experiments"))
      FileUtils.cp(File.join(ROOT, "run_production_backlog.sh"), File.join(repo, "run_production_backlog.sh"))
      FileUtils.chmod(0o755, File.join(repo, "run_production_backlog.sh"))

      File.write(File.join(repo, "production_backlog", "queue", "snapshot.yml"), "--- {}\n")
      File.write(File.join(repo, "production_backlog", "queue", "run_order.txt"), "experiments/test.yml\n")

      write_executable(File.join(repo, "verify_production_backlog.sh"), "#!/bin/sh\nexit 0\n")
      write_executable(
        File.join(repo, "bin", "preflight-production-backlog-sources"),
        "#!/bin/sh\ntouch \"$LME_REPO/source-preflight-called\"\nexit 1\n"
      )
      write_executable(
        File.join(repo, "bin", "lme"),
        "#!/bin/sh\ntouch \"$LME_REPO/inference-called\"\nexit 0\n"
      )

      stdout, stderr, status = Open3.capture3(
        { "LME_REPO" => repo },
        File.join(repo, "run_production_backlog.sh"),
        "production_backlog/queue"
      )

      refute status.success?
      assert File.exist?(File.join(repo, "source-preflight-called"))
      refute File.exist?(File.join(repo, "inference-called"))
      assert_match(/runtime source preflight failed\. No inference launched\./, stdout + stderr)
    end
  end

  private

  def write_executable(path, content)
    File.write(path, content)
    FileUtils.chmod(0o755, path)
  end
end
