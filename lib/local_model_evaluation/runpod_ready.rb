# frozen_string_literal: true

require "time"
require_relative "runpod_provenance"
require_relative "runpod_status"

module LocalModelEvaluation
  class RunpodReady
    BURST_WORKER = /\Aburst_(\d+)\z/

    class Error < StandardError; end

    def self.applicable?(experiment)
      Array(experiment.worker_names).any? { |name| BURST_WORKER.match?(name.to_s) }
    end

    def initialize(fleet_state:, client:, tunnels:, worker_check:, provenance: nil, wall_clock: nil)
      @fleet_state = fleet_state
      @client = client
      @tunnels = tunnels
      @worker_check = worker_check
      @provenance = provenance || RunpodProvenance.new(fleet_state:)
      @wall_clock = wall_clock || -> { Time.now.utc }
    end

    def check(experiment:, workers:, models:)
      burst_names = Array(experiment.worker_names).select { |name| BURST_WORKER.match?(name.to_s) }
      unless self.class.applicable?(experiment)
        return {
          "applicable" => false,
          "ready" => true,
          "experiment" => experiment.name,
          "checks" => [],
          "workers" => [],
          "models" => []
        }
      end

      checks = []
      indices = burst_names.map { |name| Integer(BURST_WORKER.match(name.to_s)[1]) }.uniq.sort
      required_models = resolve_models(experiment, models)
      configured_workers = burst_names.to_h do |name|
        [name.to_s, workers.fetch(name.to_s)]
      end

      snapshot = {
        "applicable" => true,
        "ready" => false,
        "experiment" => experiment.name,
        "fleet_id" => nil,
        "workers" => indices,
        "models" => required_models,
        "checks" => checks,
        "billing" => nil,
        "provenance" => nil,
        "tunnels" => [],
        "worker_health" => []
      }

      fleet = load_fleet(checks)
      unless fleet
        checks << check_row("provider", "SKIP", "fleet state is not ready")
        checks << check_row("provenance", "SKIP", "fleet state is not ready")
        checks << check_row("tunnels", "SKIP", "fleet state is not ready")
        checks << check_row("worker-health", "SKIP", "fleet state is not ready")
        return finalize(snapshot)
      end

      snapshot["fleet_id"] = fleet.fetch("fleet_id")
      fleet_workers = selected_fleet_workers(fleet, indices, checks)
      unless fleet_workers
        checks << check_row("provider", "SKIP", "selected fleet workers are not valid")
        checks << check_row("provenance", "SKIP", "selected fleet workers are not valid")
        checks << check_row("tunnels", "SKIP", "selected fleet workers are not valid")
        checks << check_row("worker-health", "SKIP", "selected fleet workers are not valid")
        snapshot["billing"] = billing_snapshot
        return finalize(snapshot)
      end

      check_provider(fleet, fleet_workers, checks)
      check_provenance(experiment, models, snapshot, checks)
      tunnel_ok = check_tunnels(indices, configured_workers, snapshot, checks)
      if tunnel_ok
        check_workers(experiment, configured_workers, required_models, snapshot, checks)
      else
        checks << check_row("worker-health", "SKIP", "tunnel readiness failed; live Ollama checks were not attempted")
      end

      snapshot["billing"] = billing_snapshot
      finalize(snapshot)
    rescue KeyError, ArgumentError, TypeError => e
      raise Error, "invalid readiness inputs: #{e.message}"
    end

    def render(snapshot)
      unless snapshot.fetch("applicable")
        return "RunPod readiness: NOT APPLICABLE -- experiment has no managed burst_N workers.\n"
      end

      lines = []
      lines << "RunPod pre-inference readiness"
      lines << "  Experiment: #{snapshot.fetch('experiment')}"
      lines << "  Fleet: #{snapshot['fleet_id'] || '-'}"
      lines << "  Workers: #{snapshot.fetch('workers').map { |index| "burst_#{index}" }.join(', ')}"
      lines << "  Models: #{snapshot.fetch('models').join(', ')}"
      lines << ""
      lines << format("%-15s %-7s %s", "CHECK", "STATUS", "DETAIL")
      snapshot.fetch("checks").each do |check|
        lines << format("%-15s %-7s %s", check.fetch("name"), check.fetch("status"), check.fetch("detail"))
      end

      billing = snapshot["billing"]
      if billing
        lines << ""
        lines << format("Current fleet burn: $%.4f/hr", billing.fetch("current_tracked_hourly_rate_usd"))
        lines << format("Estimated accrued fleet cost: $%.4f", billing.fetch("estimated_accrued_cost_usd"))
        lines << "Tracked fleet elapsed: #{format_duration(billing.fetch('tracked_elapsed_seconds'))}"
      end

      lines << ""
      if snapshot.fetch("ready")
        lines << "READY TO RUN -- all managed RunPod pre-inference gates passed."
      else
        lines << "NOT READY -- scoring must not start until every failed readiness check passes."
      end
      lines.join("\n") + "\n"
    end

    private

    def resolve_models(experiment, models)
      experiment.models.map do |model_alias|
        config = models.fetch(model_alias) do
          raise Error, "experiment model alias #{model_alias.inspect} is not present in config/models.yml"
        end
        value = config.fetch("ollama_model").to_s
        raise Error, "experiment model alias #{model_alias.inspect} has an empty ollama_model" if value.empty?
        value
      end.uniq
    end

    def load_fleet(checks)
      fleet = @fleet_state.current
      unless fleet
        checks << check_row("fleet", "FAIL", "no current RunPod fleet exists")
        return nil
      end
      unless fleet["status"] == "active"
        checks << check_row("fleet", "FAIL", "current fleet #{fleet.fetch('fleet_id')} is #{fleet['status'].inspect}, not active")
        return nil
      end

      checks << check_row("fleet", "PASS", "#{fleet.fetch('fleet_id')} is active")
      fleet
    rescue StandardError => e
      checks << check_row("fleet", "FAIL", e.message)
      nil
    end

    def selected_fleet_workers(fleet, indices, checks)
      by_index = Array(fleet.fetch("workers")).to_h do |worker|
        [Integer(worker.fetch("index")), worker]
      end
      missing = indices.reject { |index| by_index.key?(index) }
      inactive = indices.filter_map do |index|
        worker = by_index[index]
        "burst_#{index}=#{worker['status']}" if worker && worker["status"] != "active"
      end

      unless missing.empty? && inactive.empty?
        details = []
        details << "missing #{missing.map { |index| "burst_#{index}" }.join(', ')}" unless missing.empty?
        details << "inactive #{inactive.join(', ')}" unless inactive.empty?
        checks[checks.index { |row| row["name"] == "fleet" }] = check_row("fleet", "FAIL", details.join("; "))
        return nil
      end

      indices.map { |index| by_index.fetch(index) }
    end

    def check_provider(fleet, selected, checks)
      unless @client
        checks << check_row("provider", "FAIL", "RUNPOD_API_KEY is unavailable; live pod state cannot be verified")
        return
      end

      pods = Array(@client.list_pods)
      by_id = pods.to_h { |pod| [pod["id"].to_s, pod] }
      failures = selected.filter_map do |worker|
        index = Integer(worker.fetch("index"))
        pod = by_id[worker.fetch("pod_id").to_s]
        next "burst_#{index} pod #{worker.fetch('pod_id')} is missing from RunPod" unless pod
        next "burst_#{index} name mismatch: #{pod['name'].inspect}" unless pod["name"] == worker.fetch("name")
        next "burst_#{index} provider status is #{pod['status'].inspect}" unless pod["status"].to_s.upcase == "RUNNING"
        nil
      end

      if failures.empty?
        checks << check_row("provider", "PASS", "#{selected.length}/#{selected.length} selected pod(s) are RUNNING with expected identities")
      else
        checks << check_row("provider", "FAIL", failures.join("; "))
      end
    rescue StandardError => e
      checks << check_row("provider", "FAIL", "RunPod API check failed: #{e.message}")
    end

    def check_provenance(experiment, models, snapshot, checks)
      result = @provenance.verify_experiment!(experiment:, models:)
      snapshot["provenance"] = result
      checks << check_row(
        "provenance",
        "PASS",
        "bootstrap=#{result.fetch('bootstrap_run_id')} gpu=#{result.fetch('gpu')} context=#{result.fetch('context')} exact digests pinned"
      )
    rescue StandardError => e
      checks << check_row("provenance", "FAIL", e.message)
    end

    def check_tunnels(indices, configured_workers, snapshot, checks)
      rows = @tunnels.status(worker_indices: indices)
      snapshot["tunnels"] = rows
      failures = rows.filter_map do |row|
        index = Integer(row.fetch("index"))
        expected = configured_workers.fetch("burst_#{index}").base_url
        next "burst_#{index} process=#{row['process_status']} health=#{row['health_status']}#{detail_suffix(row['detail'])}" unless row["process_status"] == "running" && row["health_status"] == "healthy"
        next "burst_#{index} endpoint mismatch: tunnel=#{row['endpoint'].inspect} worker=#{expected.inspect}" unless row["endpoint"] == expected
        nil
      end

      if failures.empty? && rows.length == indices.length
        checks << check_row("tunnels", "PASS", "#{rows.length}/#{indices.length} managed tunnel(s) are running and healthy")
        true
      else
        failures << "expected #{indices.length} tunnel row(s), received #{rows.length}" if rows.length != indices.length
        checks << check_row("tunnels", "FAIL", failures.join("; "))
        false
      end
    rescue StandardError => e
      checks << check_row("tunnels", "FAIL", e.message)
      false
    end

    def check_workers(experiment, configured_workers, required_models, snapshot, checks)
      failures = []
      rows = configured_workers.values.map do |worker|
        result = @worker_check.check(
          worker,
          required_models:,
          required_labels: experiment.required_worker_labels
        )
        row = {
          "name" => worker.name,
          "version" => result.version,
          "models" => Array(result.models),
          "ok" => result.ok == true,
          "error" => result.error,
          "missing_models" => Array(result.missing_models),
          "missing_labels" => Array(result.missing_labels)
        }
        if result.error
          failures << "#{worker.name}: #{result.error}"
        elsif row["missing_labels"].any?
          failures << "#{worker.name}: missing labels #{row['missing_labels'].join(', ')}"
        elsif row["missing_models"].any?
          failures << "#{worker.name}: missing models #{row['missing_models'].join(', ')}"
        elsif !row["ok"]
          failures << "#{worker.name}: worker health check did not pass"
        end
        row
      end
      snapshot["worker_health"] = rows

      if failures.empty?
        checks << check_row("worker-health", "PASS", "#{rows.length}/#{rows.length} Ollama endpoint(s) reachable with required models and labels")
      else
        checks << check_row("worker-health", "FAIL", failures.join("; "))
      end
    rescue StandardError => e
      checks << check_row("worker-health", "FAIL", e.message)
    end

    def billing_snapshot
      RunpodStatus.new(
        fleet_state: @fleet_state,
        client: nil,
        wall_clock: @wall_clock
      ).snapshot&.slice(
        "tracked_elapsed_seconds",
        "current_tracked_hourly_rate_usd",
        "estimated_accrued_cost_usd"
      )
    rescue StandardError
      nil
    end

    def finalize(snapshot)
      snapshot["ready"] = snapshot.fetch("checks").none? { |row| row["status"] == "FAIL" }
      snapshot
    end

    def check_row(name, status, detail)
      { "name" => name, "status" => status, "detail" => detail.to_s }
    end

    def detail_suffix(detail)
      value = detail.to_s
      value.empty? ? "" : " (#{value})"
    end

    def format_duration(seconds)
      total = Float(seconds).to_i
      hours = total / 3600
      minutes = (total % 3600) / 60
      secs = total % 60
      format("%02d:%02d:%02d", hours, minutes, secs)
    end
  end
end
