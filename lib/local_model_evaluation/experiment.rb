# frozen_string_literal: true

require "pathname"
require_relative "config"
require_relative "worker"

module LocalModelEvaluation
  class Experiment

    PHASE6_PROFILES = {
      "Social Interaction Emphasis" => {
        "env_name" => "AF_SOCIAL_INTERACTION_GUARDRAIL_PROFILE",
        "env_value" => "phase6-v0.3"
      },
      "Investigation Emphasis" => {
        "env_name" => "AF_INVESTIGATION_GUARDRAIL_PROFILE",
        "env_value" => "phase6-v0.4"
      },
      "Lethality / Failure Severity" => {
        "env_name" => "AF_LETHALITY_GUARDRAIL_PROFILE",
        "env_value" => "phase6-v0.2"
      },
      "Puzzle / Problem-Solving Emphasis" => {
        "env_name" => "AF_PUZZLE_GUARDRAIL_PROFILE",
        "env_value" => "phase6-v0.2"
      },
      "Seriousness" => {
        "env_name" => "AF_SERIOUSNESS_GUARDRAIL_PROFILE",
        "env_value" => "phase6-v0.3"
      }
    }.freeze
    attr_reader :path, :name, :purpose, :dispatch, :models, :dimension, :adventures,
                :replicates, :worker_names, :scorer, :success_criteria, :stop_conditions,
                :cost_cap_usd, :required_worker_labels, :phase6_contract

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
      @phase6_contract = data["phase6_contract"]

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

    def phase6_scorer_env
      return {} if phase6_contract.nil?

      expected = PHASE6_PROFILES[dimension]
      raise ArgumentError, "unsupported Phase-6 remediation dimension #{dimension.inspect}" unless expected

      profile = phase6_contract["prompt_profile"]
      raise ArgumentError, "phase6_contract.prompt_profile is required" unless profile.is_a?(Hash)

      version = profile["version"].to_s
      env_name = profile["env_name"].to_s
      env_value = profile["env_value"].to_s
      unless version == expected.fetch("env_value") &&
             env_name == expected.fetch("env_name") &&
             env_value == expected.fetch("env_value")
        raise ArgumentError,
              "Phase-6 prompt profile for #{dimension} must be " \
              "#{expected.fetch('env_name')}=#{expected.fetch('env_value')}"
      end

      { env_name => env_value }
    end

    def effective_scorer_env(base_env)
      merged = (base_env || {}).transform_keys(&:to_s).transform_values(&:to_s)
      phase6_scorer_env.each do |key, value|
        if merged.key?(key) && merged[key] != value
          raise ArgumentError,
                "worker scorer environment #{key}=#{merged[key].inspect} conflicts with " \
                "manifest-declared Phase-6 profile #{value.inspect}"
        end
        merged[key] = value
      end
      merged
    end
  end
end
