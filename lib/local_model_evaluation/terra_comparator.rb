# frozen_string_literal: true

require_relative "config"

module LocalModelEvaluation
  class TerraComparator
    CONTRACT = "AdventureFinder_Phase4_Local_Model_Acceptance_Contract_v0.1"
    KINDS = ["ordinal_1_5"].freeze
    CATALOG_DIMENSIONS = ["# of Sessions", "Levels"].freeze

    Case = Struct.new(:id, :adventure, :oracle, :terra, :notes, keyword_init: true) do
      def delta
        terra - oracle
      end

      def classification
        distance = delta.abs
        return "exact" if distance.zero?
        return "adjacent" if distance == 1

        "hard"
      end
    end

    attr_reader :path, :id, :dimension, :metric, :kind, :accepted_artifact_set,
                :artifact_paths, :known_bias, :editorial_caveats,
                :malformed_unusable_outputs, :cases

    def initialize(path)
      @path = File.expand_path(path)
      data = Config.load_yaml(@path)

      version = Integer(data.fetch("version"))
      raise ArgumentError, "unsupported Terra comparator version #{version}" unless version == 1

      contract = data.fetch("acceptance_contract").to_s
      raise ArgumentError, "Terra comparator must use frozen contract #{CONTRACT}" unless contract == CONTRACT

      @id = nonempty(data.fetch("id"), "id")
      @dimension = nonempty(data.fetch("dimension"), "dimension")
      @metric = nonempty(data.fetch("metric"), "metric")
      if CATALOG_DIMENSIONS.include?(@dimension)
        raise ArgumentError, "#{@dimension} uses special catalog qualification criteria and is not supported by the ordinal Phase-5 harness"
      end
      @kind = data.fetch("kind").to_s
      raise ArgumentError, "kind must be one of: #{KINDS.join(', ')}" unless KINDS.include?(@kind)

      source = data.fetch("source")
      @accepted_artifact_set = nonempty(source.fetch("accepted_artifact_set"), "source.accepted_artifact_set")
      @artifact_paths = Array(source.fetch("artifact_paths")).map(&:to_s).reject(&:empty?)
      raise ArgumentError, "source.artifact_paths cannot be empty" if @artifact_paths.empty?
      if placeholder?(@accepted_artifact_set) || @artifact_paths.any? { |item| placeholder?(item) }
        raise ArgumentError, "Terra comparator still contains REPLACE_ placeholder source data"
      end

      @known_bias = data["known_bias"].to_s.strip
      @editorial_caveats = Array(data["editorial_caveats"]).map(&:to_s)
      @malformed_unusable_outputs = Integer(data.fetch("malformed_unusable_outputs", 0))
      raise ArgumentError, "malformed_unusable_outputs must be >= 0" if @malformed_unusable_outputs.negative?

      @cases = Array(data.fetch("cases")).map { |row| build_case(row) }
      raise ArgumentError, "cases cannot be empty" if @cases.empty?
      ids = @cases.map(&:id)
      raise ArgumentError, "duplicate comparator case ids" unless ids.uniq.length == ids.length

      validate_declared_summary!(data.fetch("summary"))
    end

    def case_by_id(id)
      cases.find { |item| item.id == id.to_s }
    end

    def completed_count
      cases.length
    end

    def exact_count
      cases.count { |item| item.classification == "exact" }
    end

    def adjacent_count
      cases.count { |item| item.classification == "adjacent" }
    end

    def hard_error_count
      cases.count { |item| item.classification == "hard" }
    end

    def exact_rate
      exact_count.to_f / completed_count
    end

    private

    def build_case(row)
      id = nonempty(row.fetch("id"), "cases.id")
      adventure = nonempty(row.fetch("adventure"), "cases.adventure")
      raise ArgumentError, "cases.adventure still contains placeholder ADV-0000" if adventure == "ADV-0000"
      oracle = score(row.fetch("oracle"), "cases.oracle")
      terra = score(row.fetch("terra"), "cases.terra")
      Case.new(id:, adventure:, oracle:, terra:, notes: row["notes"].to_s.strip)
    end

    def score(value, label)
      n = Integer(value)
      raise ArgumentError, "#{label} must be between 1 and 5" unless (1..5).cover?(n)
      n
    end

    def nonempty(value, label)
      text = value.to_s.strip
      raise ArgumentError, "#{label} cannot be empty" if text.empty?
      text
    end

    def placeholder?(value)
      value.to_s.start_with?("REPLACE_")
    end

    def validate_declared_summary!(summary)
      declared = {
        "completed_assessments" => completed_count,
        "exact" => exact_count,
        "adjacent" => adjacent_count,
        "hard_errors" => hard_error_count,
        "malformed_unusable_outputs" => malformed_unusable_outputs
      }

      declared.each do |key, actual|
        value = Integer(summary.fetch(key))
        raise ArgumentError, "summary.#{key}=#{value} does not match comparator cases (#{actual})" unless value == actual
      end
    end
  end
end
