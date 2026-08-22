# frozen_string_literal: true

require_relative "config"
require_relative "terra_comparator"

module LocalModelEvaluation
  class QualificationPlan
    CONTRACT = TerraComparator::CONTRACT

    PlanCase = Struct.new(:comparator_case_id, :manifest_path, keyword_init: true)
    Candidate = Struct.new(:id, :model, :comparator_path, :comparator, :cases, keyword_init: true)

    attr_reader :path, :name, :max_exact_deficit_percentage_points,
                :require_zero_cost_workers, :require_local_workers, :candidates

    def initialize(path)
      @path = File.expand_path(path)
      data = Config.load_yaml(@path)

      version = Integer(data.fetch("version"))
      raise ArgumentError, "unsupported qualification plan version #{version}" unless version == 1

      contract = data.fetch("acceptance_contract").to_s
      raise ArgumentError, "qualification plan must use frozen contract #{CONTRACT}" unless contract == CONTRACT

      @name = nonempty(data.fetch("name"), "name")
      @max_exact_deficit_percentage_points = Float(data.fetch("max_exact_deficit_percentage_points", 10.0))
      unless @max_exact_deficit_percentage_points == 10.0
        raise ArgumentError, "frozen contract requires max_exact_deficit_percentage_points: 10"
      end

      @require_zero_cost_workers = data.fetch("require_zero_cost_workers", true) != false
      @require_local_workers = data.fetch("require_local_workers", true) != false
      raise ArgumentError, "Phase 5 harness requires zero-cost workers" unless @require_zero_cost_workers
      raise ArgumentError, "Phase 5 harness requires local workers" unless @require_local_workers

      @candidates = Array(data.fetch("candidates")).map { |row| build_candidate(row) }
      raise ArgumentError, "candidates cannot be empty" if @candidates.empty?
      ids = @candidates.map(&:id)
      raise ArgumentError, "duplicate candidate ids" unless ids.uniq.length == ids.length
    end

    private

    def build_candidate(row)
      id = nonempty(row.fetch("id"), "candidates.id")
      model = nonempty(row.fetch("model"), "candidates.model")
      comparator_path = resolve(row.fetch("comparator"))
      comparator = TerraComparator.new(comparator_path)
      cases = Array(row.fetch("cases")).map do |entry|
        PlanCase.new(
          comparator_case_id: nonempty(entry.fetch("comparator_case"), "cases.comparator_case"),
          manifest_path: resolve(entry.fetch("manifest"))
        )
      end

      expected = comparator.cases.map(&:id)
      actual = cases.map(&:comparator_case_id)
      raise ArgumentError, "candidate #{id} must cover every comparator case exactly once" unless actual.sort == expected.sort && actual.uniq.length == actual.length

      Candidate.new(id:, model:, comparator_path:, comparator:, cases:)
    end

    def resolve(value)
      File.expand_path(value.to_s, File.dirname(path))
    end

    def nonempty(value, label)
      text = value.to_s.strip
      raise ArgumentError, "#{label} cannot be empty" if text.empty?
      text
    end
  end
end
