# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

class ProductionBacklogQualificationContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  QUALIFIED = File.join(ROOT, "production_backlog", "qualified_dimensions.yml")

  def setup
    @contract = YAML.safe_load_file(QUALIFIED)
    @dimensions = @contract.fetch("dimensions")
  end

  def test_authorizes_exactly_the_seven_lsdl_qualified_qwen_operations
    assert_equal(
      [
        "Levels",
        "Combat Emphasis",
        "Structural Openness",
        "Darkness / Horror Intensity",
        "Player Beginner Suitability",
        "Social Interaction Emphasis",
        "Investigation Emphasis"
      ],
      @dimensions.map { |dimension| dimension.fetch("name") }
    )
  end

  def test_levels_is_one_operation_with_two_catalog_outputs
    levels = @dimensions.find { |dimension| dimension.fetch("name") == "Levels" }

    assert_equal "levels-v2.1", levels.fetch("profile")
    assert_equal ["Level Start", "Level End"], levels.fetch("catalog_columns")
    assert_equal false, levels.fetch("selection_gate")
    assert_equal 6, @dimensions.count { |dimension| dimension.fetch("selection_gate", true) }
  end
end
