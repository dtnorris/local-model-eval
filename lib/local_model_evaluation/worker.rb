# frozen_string_literal: true

module LocalModelEvaluation
  class Worker
    attr_reader :name, :type, :base_url, :labels, :scorer_env, :hourly_rate_usd

    def initialize(name, attrs)
      @name = name.to_s
      @type = (attrs["type"] || "ollama").to_s
      @base_url = attrs.fetch("base_url").to_s.sub(%r{/+$}, "")
      @labels = Array(attrs["labels"]).map(&:to_s).freeze
      @scorer_env = (attrs["scorer_env"] || {}).transform_keys(&:to_s).transform_values(&:to_s).freeze
      @hourly_rate_usd = Float(attrs["hourly_rate_usd"] || 0.0)
    end

    def compatible?(required_labels)
      (Array(required_labels).map(&:to_s) - labels).empty?
    end
  end
end
