# frozen_string_literal: true

require "pathname"
require_relative "config"
require_relative "worker"

module LocalModelEvaluation
  class Experiment
    attr_reader :path, :name, :purpose, :dispatch, :models, :dimension, :adventures,
                :replicates, :worker_names, :scorer, :success_criteria, :stop_conditions,
                :cost_cap_usd, :required_worker_labels

    def initialize(path)
      @path = File.expand_path(path)
      data = Config.load_yaml(@path)
      @name = data.fetch("name").to_s
      @purpose = data["purpose"].to_s.strip
      @dispatch = (data["dispatch"] || "pool").to_s
      raise ArgumentError, "dispatch must be matrix or pool" unless %w[matrix pool].include?(@dispatch)

      @models = Array(data["models"] || data["model"]).map(&:to_s)
      @dimension = data.fetch("dimension").to_s
      @adventures = Array(data.fetch("adventures")).map(&:to_s)
      @replicates = Integer(data.fetch("replicates", 1))
      @worker_names = Array(data.fetch("workers")).map(&:to_s)
      @scorer = data.fetch("scorer")
      @success_criteria = Array(data["success_criteria"])
      @stop_conditions = Array(data["stop_conditions"])
      @cost_cap_usd = data["cost_cap_usd"] && Float(data["cost_cap_usd"])
      @required_worker_labels = Array(data["required_worker_labels"])

      raise ArgumentError, "models cannot be empty" if @models.empty?
      raise ArgumentError, "adventures cannot be empty" if @adventures.empty?
      raise ArgumentError, "workers cannot be empty" if @worker_names.empty?
      raise ArgumentError, "replicates must be >= 1" if @replicates < 1
    end

    def scorer_repo
      value = scorer.fetch("repo")
      base = File.dirname(path)
      File.expand_path(value, base)
    end

    def scorer_mode
      (scorer["mode"] || "regression").to_s
    end

    def extra_args
      Array(scorer["extra_args"]).map(&:to_s)
    end
  end
end
