# frozen_string_literal: true

require "thread"
require_relative "job"

module LocalModelEvaluation
  class Scheduler
    def initialize(experiment:, workers:, models:)
      @experiment = experiment
      @workers = workers
      @models = models
    end

    def jobs
      base = []
      @experiment.models.each do |model_alias|
        model = @models.fetch(model_alias) { raise KeyError, "unknown model alias #{model_alias}" }
        ollama_model = model.fetch("ollama_model")
        @experiment.adventures.each do |adventure|
          1.upto(@experiment.replicates) do |replicate|
            if @experiment.dispatch == "matrix"
              eligible_workers.each do |worker|
                base << Job.build(model_alias:, ollama_model:, adventure:, replicate:, planned_worker: worker.name)
              end
            else
              base << Job.build(model_alias:, ollama_model:, adventure:, replicate:)
            end
          end
        end
      end
      base
    end

    def eligible_workers
      @experiment.worker_names.map do |name|
        @workers.fetch(name) { raise KeyError, "unknown worker #{name}" }
      end.select { |w| w.compatible?(@experiment.required_worker_labels) }
    end
  end
end
