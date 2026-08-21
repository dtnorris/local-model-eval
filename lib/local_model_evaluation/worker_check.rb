# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module LocalModelEvaluation
  class WorkerCheck
    Result = Struct.new(:worker, :ok, :version, :models, :error, keyword_init: true)

    def initialize(open_timeout: 3, read_timeout: 10)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def check(worker)
      version_data = get_json(worker.base_url, "/api/version")
      tags_data = get_json(worker.base_url, "/api/tags")
      models = Array(tags_data["models"]).map { |m| m["name"] || m["model"] }.compact
      Result.new(worker:, ok: true, version: version_data["version"], models:)
    rescue StandardError => e
      Result.new(worker:, ok: false, error: "#{e.class}: #{e.message}", models: [])
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
