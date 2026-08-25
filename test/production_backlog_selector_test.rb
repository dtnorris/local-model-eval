# frozen_string_literal: true

require_relative "test_helper"
require "production_backlog_selector"

class ProductionBacklogSelectorTest < Minitest::Test
  POLICY = {
    "selection_strategy" => "stratified_page_count_source_diverse",
    "max_source_share" => 0.30,
    "page_strata" => [
      { "name" => "1-2-pages", "min_pages" => 1, "max_pages" => 2, "weight" => 2 },
      { "name" => "3-10-pages", "min_pages" => 3, "max_pages" => 10, "weight" => 3 },
      { "name" => "11-30-pages", "min_pages" => 11, "max_pages" => 30, "weight" => 3 },
      { "name" => "31-60-pages", "min_pages" => 31, "max_pages" => 60, "weight" => 2 }
    ]
  }.freeze

  def test_selects_exact_stratified_and_source_diverse_pilot
    eligible = []
    add_candidates(eligible, "1-2-pages", [1, 2], 4, 100)
    add_candidates(eligible, "3-10-pages", [3, 5, 8], 5, 200)
    add_candidates(eligible, "11-30-pages", [11, 18, 27], 5, 300)
    add_candidates(eligible, "31-60-pages", [31, 45, 59], 4, 400)

    result = ProductionBacklogSelector.select(
      eligible: eligible,
      required: 10,
      policy: POLICY,
      max_pages: 60,
      preflight: ->(_record) { [true, ""] }
    )

    selected = result.fetch(:selected)
    assert_equal 10, selected.length
    assert_equal(
      {
        "1-2-pages" => 2,
        "3-10-pages" => 3,
        "11-30-pages" => 3,
        "31-60-pages" => 2
      },
      selected.group_by { |record| record.fetch("page_stratum") }.transform_values(&:length)
    )
    assert_operator result.fetch(:source_counts).values.max, :<=, 3
    assert_equal 3, result.fetch(:max_per_source)

    # Final order is interleaved so early interrupted work spans source lengths.
    assert_equal(
      ["1-2-pages", "3-10-pages", "11-30-pages", "31-60-pages"],
      selected.first(4).map { |record| record.fetch("page_stratum") }
    )
  end

  def test_preflight_failure_uses_replacement_without_inference_semantics
    eligible = []
    add_candidates(eligible, "1-2-pages", [1, 2], 4, 500)
    add_candidates(eligible, "3-10-pages", [3, 4, 5], 5, 600)
    add_candidates(eligible, "11-30-pages", [11, 12, 13], 5, 700)
    add_candidates(eligible, "31-60-pages", [31, 32, 33], 4, 800)
    failed_id = eligible.find { |record| record.fetch("page_count") == 3 }.fetch("id")

    result = ProductionBacklogSelector.select(
      eligible: eligible,
      required: 10,
      policy: POLICY,
      max_pages: 60,
      preflight: ->(record) { record.fetch("id") == failed_id ? [false, "missing source"] : [true, ""] }
    )

    refute_includes result.fetch(:selected).map { |record| record.fetch("id") }, failed_id
    failure = result.fetch(:audit).find { |record| record.fetch("id") == failed_id }
    assert_equal "REJECT", failure.fetch("decision")
    assert_match(/source_preflight_failed:missing source/, failure.fetch("reason"))
    assert_equal 10, result.fetch(:selected).length
  end

  def test_allocates_same_proportions_when_queue_scales
    strata = ProductionBacklogSelector.build_strata(POLICY.fetch("page_strata"), max_pages: 60)
    assert_equal(
      {
        "1-2-pages" => 6,
        "3-10-pages" => 9,
        "11-30-pages" => 9,
        "31-60-pages" => 6
      },
      ProductionBacklogSelector.allocate_quotas(strata, 30)
    )
  end

  def test_zero_weight_stratum_preserves_coverage_without_selection
    policy = {
      "selection_strategy" => "stratified_page_count_source_diverse",
      "max_source_share" => 0.35,
      "page_strata" => [
        { "name" => "1-2-pages", "min_pages" => 1, "max_pages" => 2, "weight" => 0 },
        { "name" => "3-10-pages", "min_pages" => 3, "max_pages" => 10, "weight" => 16 },
        { "name" => "11-30-pages", "min_pages" => 11, "max_pages" => 30, "weight" => 11 },
        { "name" => "31-60-pages", "min_pages" => 31, "max_pages" => 60, "weight" => 4 },
        { "name" => "61-160-pages", "min_pages" => 61, "max_pages" => 160, "weight" => 3 }
      ]
    }

    eligible = []
    add_candidates(eligible, "1-2-pages", [1, 2], 4, 900)
    add_candidates(eligible, "3-10-pages", [3, 6, 10], 18, 1000)
    add_candidates(eligible, "11-30-pages", [11, 20, 30], 13, 1100)
    add_candidates(eligible, "31-60-pages", [31, 45, 60], 6, 1200)
    add_candidates(eligible, "61-160-pages", [61, 124, 160], 5, 1300)

    preflighted_short = 0

    result = ProductionBacklogSelector.select(
      eligible: eligible,
      required: 34,
      policy: policy,
      max_pages: 160,
      preflight: lambda do |record|
        preflighted_short += 1 if Integer(record.fetch("page_count")) <= 2
        [true, ""]
      end
    )

    assert_equal(
      {
        "1-2-pages" => 0,
        "3-10-pages" => 16,
        "11-30-pages" => 11,
        "31-60-pages" => 4,
        "61-160-pages" => 3
      },
      result.fetch(:strata).to_h { |stratum| [stratum.fetch("name"), stratum.fetch("quota")] }
    )

    selected_counts =
      result.fetch(:selected)
            .group_by { |record| record.fetch("page_stratum") }
            .transform_values(&:length)

    assert_equal 0, selected_counts.fetch("1-2-pages", 0)
    assert_equal 16, selected_counts.fetch("3-10-pages")
    assert_equal 11, selected_counts.fetch("11-30-pages")
    assert_equal 4, selected_counts.fetch("31-60-pages")
    assert_equal 3, selected_counts.fetch("61-160-pages")
    assert_equal 0, preflighted_short
    assert_equal 34, result.fetch(:selected).length
  end

  private

  def add_candidates(records, _stratum, pages, count, seed)
    count.times do |offset|
      records << {
        "id" => format("ADV-%04d", seed + offset),
        "title" => "Adventure #{seed + offset}",
        "source_book" => "Source #{offset % 4}",
        "publisher" => "Publisher",
        "page_count" => pages[offset % pages.length],
        "start_page" => 1,
        "end_page" => pages[offset % pages.length],
        "populated_qualified_dimensions" => []
      }
    end
  end
end
