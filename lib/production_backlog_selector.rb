# frozen_string_literal: true

module ProductionBacklogSelector
  class SelectionError < StandardError; end

  module_function

  def select(eligible:, required:, policy:, max_pages:, preflight:)
    strategy = policy.fetch("selection_strategy")
    unless strategy == "stratified_page_count_source_diverse"
      raise SelectionError, "unsupported production backlog selection strategy #{strategy.inspect}"
    end

    strata = build_strata(policy.fetch("page_strata"), max_pages: max_pages)
    quotas = allocate_quotas(strata, required)
    max_source_share = Float(policy.fetch("max_source_share"))
    unless max_source_share.positive? && max_source_share <= 1.0
      raise SelectionError, "max_source_share must be > 0 and <= 1"
    end
    max_per_source = [(required * max_source_share).ceil, 1].max

    candidates_by_stratum = strata.to_h { |stratum| [stratum.fetch("name"), []] }
    audit = []

    eligible.each do |record|
      stratum = strata.find do |candidate|
        pages = Integer(record.fetch("page_count"))
        pages >= candidate.fetch("min_pages") && pages <= candidate.fetch("max_pages")
      end
      unless stratum
        audit << record.merge(
          "page_stratum" => nil,
          "decision" => "REJECT",
          "reason" => "outside_page_strata"
        )
        next
      end

      candidates_by_stratum.fetch(stratum.fetch("name")) <<
        record.merge("page_stratum" => stratum.fetch("name"))
    end

    plans = strata.each_with_index.map do |stratum, index|
      candidates = candidates_by_stratum.fetch(stratum.fetch("name"))
      {
        "name" => stratum.fetch("name"),
        "min_pages" => stratum.fetch("min_pages"),
        "max_pages" => stratum.fetch("max_pages"),
        "weight" => stratum.fetch("weight"),
        "quota" => quotas.fetch(stratum.fetch("name")),
        "index" => index,
        "candidate_count" => candidates.length,
        "distinct_source_count" => candidates.map { |record| source_key(record) }.uniq.length
      }
    end

    selected_by_stratum = strata.to_h { |stratum| [stratum.fetch("name"), []] }
    source_counts = Hash.new(0)

    # Satisfy the most source-constrained strata first. The final queue order is
    # independently interleaved by page stratum, so this only affects feasibility.
    selection_plans = plans.sort_by do |plan|
      [
        plan.fetch("distinct_source_count"),
        plan.fetch("candidate_count"),
        plan.fetch("index")
      ]
    end

    selection_plans.each do |plan|
      name = plan.fetch("name")
      quota = plan.fetch("quota")
      candidates = diversity_order(candidates_by_stratum.fetch(name))

      candidates.each do |record|
        break if selected_by_stratum.fetch(name).length >= quota

        source = source_key(record)
        next if source_counts[source] >= max_per_source

        ok, detail = preflight.call(record)
        if ok
          selected_by_stratum.fetch(name) << record
          source_counts[source] += 1
          audit << record.merge(
            "decision" => "SELECT",
            "reason" => "source_preflight_pass"
          )
        else
          compact = detail.to_s.lines.last(4).join(" ").gsub(/\s+/, " ").strip
          audit << record.merge(
            "decision" => "REJECT",
            "reason" => "source_preflight_failed:#{compact}"
          )
        end
      end

      actual = selected_by_stratum.fetch(name).length
      next if actual == quota

      raise SelectionError,
            "page stratum #{name.inspect} produced only #{actual}/#{quota} selections " \
            "after source diversity and source preflight constraints"
    end

    selected_ids = selected_by_stratum.values.flatten.map { |record| record.fetch("id") }.to_h { |id| [id, true] }
    audited_ids = audit.map { |record| record.fetch("id") }.to_h { |id| [id, true] }

    eligible.each do |record|
      next if selected_ids.key?(record.fetch("id")) || audited_ids.key?(record.fetch("id"))

      stratum = strata.find do |candidate|
        pages = Integer(record.fetch("page_count"))
        pages >= candidate.fetch("min_pages") && pages <= candidate.fetch("max_pages")
      end
      next unless stratum

      source = source_key(record)
      reason =
        if source_counts[source] >= max_per_source
          "source_book_cap_reached"
        else
          "stratum_quota_reached"
        end

      audit << record.merge(
        "page_stratum" => stratum.fetch("name"),
        "decision" => "ELIGIBLE_NOT_SELECTED",
        "reason" => reason
      )
    end

    selected = interleave(strata.map { |stratum| selected_by_stratum.fetch(stratum.fetch("name")) })

    {
      selected: selected,
      audit: audit,
      strata: plans.map { |plan| plan.reject { |key, _value| %w[index candidate_count distinct_source_count].include?(key) } },
      max_source_share: max_source_share,
      max_per_source: max_per_source,
      source_counts: source_counts.sort.to_h
    }
  end

  def build_strata(raw_strata, max_pages:)
    raise SelectionError, "page_strata must not be empty" unless raw_strata.is_a?(Array) && !raw_strata.empty?

    strata = raw_strata.map do |raw|
      {
        "name" => raw.fetch("name").to_s,
        "min_pages" => Integer(raw.fetch("min_pages")),
        "max_pages" => Integer(raw.fetch("max_pages")),
        "weight" => Integer(raw.fetch("weight"))
      }
    end

    names = strata.map { |stratum| stratum.fetch("name") }
    raise SelectionError, "page_strata names must be unique" unless names.uniq.length == names.length

    strata.each do |stratum|
      raise SelectionError, "page stratum name must not be empty" if stratum.fetch("name").empty?
      raise SelectionError, "page stratum minimum must be >= 1" if stratum.fetch("min_pages") < 1
      raise SelectionError, "page stratum maximum must be >= minimum" if stratum.fetch("max_pages") < stratum.fetch("min_pages")
      raise SelectionError, "page stratum weight must be >= 0" if stratum.fetch("weight") < 0
    end

    coverage = Hash.new(0)
    strata.each do |stratum|
      (stratum.fetch("min_pages")..stratum.fetch("max_pages")).each do |pages|
        coverage[pages] += 1 if pages <= max_pages
      end
    end

    missing = (1..max_pages).select { |pages| coverage[pages].zero? }
    overlapping = (1..max_pages).select { |pages| coverage[pages] > 1 }
    raise SelectionError, "page_strata do not cover pages #{missing.first(10).join(',')}" unless missing.empty?
    raise SelectionError, "page_strata overlap on pages #{overlapping.first(10).join(',')}" unless overlapping.empty?

    highest = strata.map { |stratum| stratum.fetch("max_pages") }.max
    if highest > max_pages
      raise SelectionError,
            "max-pages #{max_pages} is incompatible with configured page strata ending at #{highest}; " \
            "change the strata or use --max-pages #{highest}"
    end

    strata
  end

  def allocate_quotas(strata, required)
    total_weight = strata.sum { |stratum| stratum.fetch("weight") }
    raise SelectionError, "page_strata total weight must be >= 1" if total_weight < 1

    allocations = {}
    remainders = []

    strata.each_with_index do |stratum, index|
      numerator = required * stratum.fetch("weight")
      allocations[stratum.fetch("name")] = numerator / total_weight
      remainders << [numerator % total_weight, index, stratum.fetch("name")]
    end

    remaining = required - allocations.values.sum
    remainders.sort_by { |remainder, index, _name| [-remainder, index] }
              .first(remaining)
              .each { |_remainder, _index, name| allocations[name] += 1 }

    allocations
  end

  def diversity_order(records)
    groups = records.group_by { |record| source_key(record) }
    groups.each_value do |group|
      group.sort_by! { |record| [Integer(record.fetch("page_count")), record.fetch("id")] }
    end

    ordered = []
    loop do
      active = groups.keys.select { |key| !groups.fetch(key).empty? }
      break if active.empty?

      active.sort_by! do |key|
        first = groups.fetch(key).first
        [Integer(first.fetch("page_count")), key.downcase, first.fetch("id")]
      end
      active.each { |key| ordered << groups.fetch(key).shift }
    end
    ordered
  end

  def interleave(groups)
    copies = groups.map(&:dup)
    result = []
    loop do
      emitted = false
      copies.each do |group|
        next if group.empty?
        result << group.shift
        emitted = true
      end
      break unless emitted
    end
    result
  end

  def source_key(record)
    value = record.fetch("source_book", "").to_s.strip
    value.empty? ? "(unknown source)" : value
  end
end
