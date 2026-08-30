# frozen_string_literal: true

require_relative "test_helper"
require "yaml"
require_relative "../lib/production_backlog_selector"

class EeProductionContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  QUALIFIED = File.join(ROOT, "production_backlog", "qualified_exploration_emphasis.yml")
  RUNTIME = File.join(ROOT, "production_backlog", "ee-v0.5-runtime.yml")

  def setup
    @contract = YAML.safe_load_file(QUALIFIED)
    @runtime = YAML.safe_load_file(RUNTIME)
  end

  def test_freezes_final_ee_gpt_oss_runtime
    assert_equal "ee_local_qualified_v1", @contract.fetch("contract_type")
    assert_equal "Exploration Emphasis", @contract.fetch("dimension")
    assert_equal "ee-clean-reset-v0.5", @contract.fetch("profile")
    assert_equal "gptoss", @contract.fetch("model_alias")
    assert_equal "gpt-oss:20b", @contract.fetch("ollama_model")
    assert_equal "ollama", @contract.fetch("provider")
    assert_equal "low", @contract.fetch("reasoning_effort")
    assert_equal 4_096, @contract.fetch("max_tokens")
    assert_equal 0, @contract.fetch("temperature")
    assert_equal 1, @contract.fetch("replicates")
    assert_equal true, @contract.fetch("no_favorable_rerun")
    assert_equal 0.0, @contract.fetch("external_api_cost_usd")

    assert_equal(
      {
        "provider" => "ollama",
        "model" => "gpt-oss:20b",
        "reasoning_effort" => "low",
        "max_tokens" => 4_096
      },
      @runtime.fetch("llm")
    )
  end

  def test_first_wave_is_exactly_40_with_10_5_22_3_page_mix_and_35_percent_source_cap
    first_wave = @contract.fetch("first_wave")
    assert_equal 40, first_wave.fetch("calls")
    assert_equal 60, first_wave.fetch("max_page_count")
    assert_equal "stratified_page_count_source_diverse", first_wave.fetch("selection_strategy")
    assert_equal 0.35, first_wave.fetch("max_source_share")

    strata = ProductionBacklogSelector.build_strata(
      first_wave.fetch("page_strata"),
      max_pages: first_wave.fetch("max_page_count")
    )
    quotas = ProductionBacklogSelector.allocate_quotas(strata, first_wave.fetch("calls"))

    assert_equal(
      {
        "1-2-pages" => 10,
        "3-10-pages" => 5,
        "11-30-pages" => 22,
        "31-60-pages" => 3
      },
      quotas
    )
    assert_equal 14, (first_wave.fetch("calls") * first_wave.fetch("max_source_share")).ceil
  end

  def test_backfill_exhausts_same_ordinary_size_domain
    backfill = @contract.fetch("backfill")
    assert_equal 60, backfill.fetch("max_page_count")
    assert_equal "exhaustive_source_ready_backfill", backfill.fetch("selection_strategy")
  end

  def test_reliability_gate_is_frozen
    gate = @contract.fetch("reliability_gate")
    assert_equal 39, gate.fetch("green_min_valid")
    assert_equal 38, gate.fetch("yellow_min_valid")
    assert_equal 37, gate.fetch("red_max_valid")
    assert_equal true, gate.fetch("repeated_operational_failure_is_red")
  end
end
