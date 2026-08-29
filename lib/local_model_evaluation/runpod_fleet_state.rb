# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module LocalModelEvaluation
  class RunpodFleetState
    SCHEMA_VERSION = 1
    STATE_FILE = "fleet.json"
    CURRENT_FILE = "current"
    ARTIFACT_DIRS = %w[bootstrap tunnels].freeze

    class Error < StandardError; end

    def initialize(root:, clock: nil)
      @root = File.expand_path(root)
      @clock = clock || -> { Time.now.utc }
    end

    attr_reader :root

    def current_id
      return nil unless File.file?(current_path)

      value = File.read(current_path).strip
      return nil if value.empty?

      validate_fleet_id!(value)
      value
    end

    def current
      id = current_id
      id ? load(id) : nil
    end

    def assert_no_active!
      record = current
      return unless record

      if record["status"] == "active"
        raise Error,
              "active RunPod fleet state already exists: #{record.fetch('fleet_id')}; " \
              "destroy or reconcile it before creating another fleet"
      end

      clear_current(record.fetch("fleet_id"))
    end

    def activate(workers:, cloud:, gpu_id:, image:)
      assert_no_active!

      workers = Array(workers).sort_by(&:index)
      raise Error, "cannot activate an empty RunPod fleet" if workers.empty?

      timestamp = utc_now
      fleet_id = build_fleet_id(timestamp, workers.first.pod_id)
      dir = fleet_dir(fleet_id)
      raise Error, "fleet state directory already exists: #{dir}" if File.exist?(dir)

      worker_records = workers.map do |worker|
        {
          "index" => worker.index,
          "name" => worker.name,
          "pod_id" => worker.pod_id,
          "host" => worker.host,
          "ssh_port" => worker.ssh_port,
          "hourly_rate_usd" => worker.hourly_rate,
          "local_ollama_url" => "http://127.0.0.1:#{11_440 + worker.index}",
          "status" => "active"
        }
      end

      record = {
        "schema_version" => SCHEMA_VERSION,
        "fleet_id" => fleet_id,
        "status" => "active",
        "created_at_utc" => timestamp.iso8601,
        "destroyed_at_utc" => nil,
        "cloud" => cloud,
        "gpu" => {
          "id" => gpu_id,
          "count_per_worker" => 1
        },
        "image" => image,
        "worker_count" => worker_records.length,
        "fleet_hourly_rate_usd" => workers.sum(&:hourly_rate),
        "workers" => worker_records,
        "artifact_dirs" => {
          "bootstrap" => "bootstrap",
          "tunnels" => "tunnels"
        }
      }

      begin
        ARTIFACT_DIRS.each { |name| FileUtils.mkdir_p(File.join(dir, name)) }
        write_record(record)
        atomic_write(current_path, "#{fleet_id}\n")
      rescue StandardError
        FileUtils.rm_rf(dir)
        raise
      end

      record
    end

    def mark_destroyed(indices)
      record = current
      return nil unless record

      requested = Array(indices).map { |value| Integer(value) }.uniq
      timestamp = utc_now.iso8601
      known = record.fetch("workers").to_h { |worker| [worker.fetch("index"), worker] }
      unknown = requested.reject { |index| known.key?(index) }
      raise Error, "fleet state does not contain worker index(es): #{unknown.join(', ')}" unless unknown.empty?

      requested.each do |index|
        worker = known.fetch(index)
        worker["status"] = "destroyed"
        worker["destroyed_at_utc"] ||= timestamp
      end

      if record.fetch("workers").all? { |worker| worker["status"] == "destroyed" }
        record["status"] = "destroyed"
        record["destroyed_at_utc"] ||= timestamp
      end

      write_record(record)
      clear_current(record.fetch("fleet_id")) if record["status"] == "destroyed"
      record
    rescue ArgumentError, TypeError
      raise Error, "worker indices must be integers"
    end

    def discard(fleet_id)
      return unless fleet_id

      validate_fleet_id!(fleet_id)
      clear_current(fleet_id)
      FileUtils.rm_rf(fleet_dir(fleet_id))
    end

    def load(fleet_id)
      path = state_path(fleet_id)
      raise Error, "fleet state file is missing: #{path}" unless File.file?(path)

      record = JSON.parse(File.read(path))
      unless record["fleet_id"] == fleet_id
        raise Error, "fleet state id mismatch in #{path}"
      end

      record
    rescue JSON::ParserError => e
      raise Error, "fleet state file is invalid JSON: #{path}: #{e.message}"
    end

    def fleet_dir(fleet_id)
      validate_fleet_id!(fleet_id)
      File.join(@root, fleet_id)
    end

    def state_path(fleet_id)
      File.join(fleet_dir(fleet_id), STATE_FILE)
    end

    def artifact_dir(fleet_id, name)
      key = name.to_s
      raise Error, "unknown fleet artifact directory: #{key}" unless ARTIFACT_DIRS.include?(key)

      File.join(fleet_dir(fleet_id), key)
    end

    private

    def current_path
      File.join(@root, CURRENT_FILE)
    end

    def write_record(record)
      atomic_write(
        state_path(record.fetch("fleet_id")),
        JSON.pretty_generate(record) + "\n"
      )
    end

    def atomic_write(path, content)
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.tmp.#{$$}.#{Thread.current.object_id}"
      File.write(tmp, content)
      File.rename(tmp, path)
    ensure
      File.delete(tmp) if defined?(tmp) && tmp && File.exist?(tmp)
    end

    def clear_current(fleet_id)
      return unless File.file?(current_path)
      return unless File.read(current_path).strip == fleet_id

      File.delete(current_path)
    end

    def build_fleet_id(timestamp, pod_id)
      suffix = pod_id.to_s.gsub(/[^A-Za-z0-9_-]/, "")[0, 12].to_s
      raise Error, "cannot build fleet id from empty pod id" if suffix.empty?

      "#{timestamp.strftime('%Y%m%dT%H%M%SZ')}-#{suffix}"
    end

    def utc_now
      value = @clock.call
      value = Time.parse(value.to_s) unless value.is_a?(Time)
      value.utc
    end

    def validate_fleet_id!(fleet_id)
      return if fleet_id.to_s.match?(/\A\d{8}T\d{6}Z-[A-Za-z0-9_-]{1,32}\z/)

      raise Error, "invalid fleet id: #{fleet_id.inspect}"
    end
  end
end
