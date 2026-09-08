# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/production_backlog_runtime_contract"

class ProductionBacklogRuntimeContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_qwen35_core_runtime_is_exactly_the_six_proven_dimensions
    assert_equal(
      [
        "Combat Emphasis",
        "Social Interaction Emphasis",
        "Investigation Emphasis",
        "Structural Openness",
        "Darkness / Horror Intensity",
        "Player Beginner Suitability"
      ],
      ProductionBacklogRuntimeContract::QWEN35_CORE_DIMENSIONS
    )

    assert_nil ProductionBacklogRuntimeContract.runtime_key_for("Levels")
    assert_nil ProductionBacklogRuntimeContract.runtime_key_for("GM Beginner Suitability")
    assert_nil ProductionBacklogRuntimeContract.runtime_key_for("Seriousness")
  end

  def test_canonical_runtime_is_qwen35_high_with_8192_token_ceiling
    path = ProductionBacklogRuntimeContract.validate_source!(ROOT)
    data = YAML.safe_load_file(path, aliases: true)

    assert_equal(
      {
        "llm" => {
          "provider" => "ollama",
          "model" => "qwen3.6:35b-a3b",
          "reasoning_effort" => "high",
          "max_tokens" => 8192
        }
      },
      data
    )
  end

  def test_freeze_copies_and_hashes_runtime_into_future_queue
    Dir.mktmpdir("qwen35-runtime-contract") do |root|
      source = File.join(root, "production_backlog", "qwen35-core-v1-runtime.yml")
      FileUtils.mkdir_p(File.dirname(source))
      FileUtils.cp(
        File.join(ROOT, "production_backlog", "qwen35-core-v1-runtime.yml"),
        source
      )

      contract = ProductionBacklogRuntimeContract.freeze!(
        root: root,
        queue: "production-backlog-019"
      )

      assert_equal 1, contract.fetch("version")
      assert_equal(
        ProductionBacklogRuntimeContract.expected_dimension_runtime_keys,
        contract.fetch("dimension_runtime_keys")
      )

      info = contract.fetch("runtime_files").fetch("qwen35_core")
      assert_equal(
        "production_backlog/production-backlog-019/runtime-qwen35-core-v1.yml",
        info.fetch("path")
      )
      assert File.file?(File.join(root, info.fetch("path")))
      assert ProductionBacklogRuntimeContract.validate_snapshot!(root: root, contract: contract)
    end
  end

  def test_manifest_args_are_declarative_for_core_dimensions_only
    contract = {
      "version" => 1,
      "dimension_runtime_keys" => ProductionBacklogRuntimeContract.expected_dimension_runtime_keys,
      "runtime_files" => {
        "qwen35_core" => {
          "path" => "production_backlog/production-backlog-019/runtime-qwen35-core-v1.yml"
        }
      }
    }

    assert_equal(
      [
        "--config",
        "${LME_REPO}/production_backlog/production-backlog-019/runtime-qwen35-core-v1.yml"
      ],
      ProductionBacklogRuntimeContract.extra_args_for(
        dimension_name: "Structural Openness",
        contract: contract
      )
    )

    assert_equal(
      [],
      ProductionBacklogRuntimeContract.extra_args_for(
        dimension_name: "Levels",
        contract: contract
      )
    )
  end
end
