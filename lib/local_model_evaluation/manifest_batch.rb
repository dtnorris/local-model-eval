# frozen_string_literal: true

require_relative "experiment"

module LocalModelEvaluation
  class ManifestBatch
    Entry = Struct.new(
      :manifest_path,
      :experiment,
      :worker,
      :model,
      :adventure,
      :dimension,
      keyword_init: true
    )

    attr_reader :list_path, :entries

    def initialize(list_path)
      @list_path = File.expand_path(list_path)
      raise ArgumentError, "manifest batch list not found: #{@list_path}" unless File.file?(@list_path)

      @entries = load_entries
      raise ArgumentError, "manifest batch list is empty: #{@list_path}" if @entries.empty?
    end

    def ordered_entries
      entries.sort_by do |entry|
        [
          entry.worker,
          entry.model,
          entry.adventure,
          entry.dimension.downcase,
          entry.experiment.name,
          entry.manifest_path
        ]
      end
    end

    private

    def load_entries
      base = File.dirname(list_path)
      seen = {}

      File.readlines(list_path, chomp: true).filter_map.with_index(1) do |line, line_number|
        value = line.strip
        next if value.empty? || value.start_with?("#")

        manifest_path = File.expand_path(value, base)
        unless File.file?(manifest_path)
          raise ArgumentError, "#{list_path}:#{line_number}: manifest not found: #{value}"
        end
        if seen[manifest_path]
          raise ArgumentError, "#{list_path}:#{line_number}: duplicate manifest: #{value}"
        end

        seen[manifest_path] = true
        build_entry(manifest_path)
      end
    end

    def build_entry(manifest_path)
      experiment = Experiment.new(manifest_path)

      unless experiment.models.length == 1
        raise ArgumentError,
              "#{manifest_path}: adventure-major batches require exactly one model per manifest"
      end
      unless experiment.adventures.length == 1
        raise ArgumentError,
              "#{manifest_path}: adventure-major batches require exactly one adventure per manifest"
      end
      unless experiment.worker_names.length == 1
        raise ArgumentError,
              "#{manifest_path}: adventure-major batches require exactly one worker per manifest"
      end
      unless experiment.replicates == 1
        raise ArgumentError,
              "#{manifest_path}: adventure-major batches require replicates: 1"
      end

      Entry.new(
        manifest_path: manifest_path,
        experiment: experiment,
        worker: experiment.worker_names.first,
        model: experiment.models.first,
        adventure: experiment.adventures.first,
        dimension: experiment.dimension
      )
    end
  end
end
