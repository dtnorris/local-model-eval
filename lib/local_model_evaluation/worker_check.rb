# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module LocalModelEvaluation
  class WorkerCheck
    Result = Struct.new(
      :worker,
      :ok,
      :version,
      :models,
      :error,
      :missing_models,
      :missing_labels,
      keyword_init: true
    )

    def initialize(open_timeout: 3, read_timeout: 10)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def check(worker, required_models: [], required_labels: [])
      missing_labels = Array(required_labels).map(&:to_s) - worker.labels
      version_data = get_json(worker.base_url, "/api/version")
      tags_data = get_json(worker.base_url, "/api/tags")
      models = Array(tags_data["models"]).map { |m| m["name"] || m["model"] }.compact
      missing_models = Array(required_models).map(&:to_s).reject do |model|
        models.include?(model) || models.any? { |available| available.start_with?("#{model}:") }
      end
      Result.new(
        worker:,
        ok: missing_models.empty? && missing_labels.empty?,
        version: version_data["version"],
        models:,
        missing_models:,
        missing_labels:
      )
    rescue StandardError => e
      Result.new(
        worker:,
        ok: false,
        error: "#{e.class}: #{e.message}",
        models: [],
        missing_models: [],
        missing_labels: missing_labels || []
      )
    end

    private

    def get_json(base_url, path)
      uri = URI.join("#{base_url}/", path.sub(%r{^/}, ""))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout
      response = http.get(uri.request_uri)
      raise "HTTP #{response.code} from #{uri}" unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    end
  end
end
