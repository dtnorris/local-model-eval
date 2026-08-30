# frozen_string_literal: true

require "json"
require_relative "runpod_fleet_state"

module LocalModelEvaluation
  class RunpodProvenance
    REQUIRED_CONTEXT = 131_072
    BURST_WORKER = /\Aburst_(\d+)\z/
    DIGEST = /\A[0-9a-f]{64}\z/i

    class Error < StandardError; end

    def initialize(fleet_state:)
      @fleet_state = fleet_state
    end

    def verify_experiment!(experiment:, models:, required_context: REQUIRED_CONTEXT)
      worker_indices = burst_worker_indices(experiment.worker_names)
      return nil if worker_indices.empty?

      fleet = @fleet_state.current
      raise Error, "experiment uses RunPod burst workers but no current fleet exists" unless fleet
      unless fleet["status"] == "active"
        raise Error, "current fleet #{fleet.fetch('fleet_id')} is not active"
      end

      expected_gpu = fleet.dig("gpu", "id").to_s
      raise Error, "current fleet does not record an exact GPU id" if expected_gpu.empty?

      required_context = Integer(required_context)
      required_models = experiment.models.map do |model_alias|
        config = models.fetch(model_alias) do
          raise Error, "experiment model alias #{model_alias.inspect} is not present in config/models.yml"
        end
        config.fetch("ollama_model").to_s
      end

      bootstrap = current_bootstrap!(fleet)
      unless bootstrap["status"] == "passed"
        raise Error, "latest bootstrap #{bootstrap.fetch('bootstrap_run_id')} is #{bootstrap['status'].inspect}, not passed"
      end
      if bootstrap["fleet_id"] != fleet.fetch("fleet_id")
        raise Error, "latest bootstrap belongs to fleet #{bootstrap['fleet_id'].inspect}, not current fleet #{fleet.fetch('fleet_id')}"
      end
      if bootstrap["expected_gpu"] != expected_gpu
        raise Error, "bootstrap GPU contract mismatch: fleet requires #{expected_gpu.inspect}, bootstrap expected #{bootstrap['expected_gpu'].inspect}"
      end
      if Integer(bootstrap["context"]) != required_context
        raise Error, "bootstrap context mismatch: scoring requires #{required_context}, bootstrap used #{bootstrap['context'].inspect}"
      end

      expected_digests = bootstrap.fetch("expected_digests", {})
      required_models.each do |model|
        digest = expected_digests[model].to_s
        bootstrapped_models = Array(bootstrap["models"])
        unless bootstrapped_models.include?(model)
          raise Error,
                "model mismatch: experiment requires #{model}, latest bootstrap contains #{bootstrapped_models.join(', ')}"
        end
        unless digest.match?(DIGEST)
          raise Error, "latest bootstrap does not contain an exact pinned digest for #{model}"
        end
      end

      fleet_workers = fleet.fetch("workers").to_h { |worker| [Integer(worker.fetch("index")), worker] }
      bootstrap_workers = Array(bootstrap.fetch("workers")).to_h do |worker|
        [Integer(worker.fetch("index")), worker]
      end

      worker_indices.each do |index|
        fleet_worker = fleet_workers[index]
        raise Error, "current fleet does not contain burst_#{index}" unless fleet_worker
        unless fleet_worker["status"] == "active"
          raise Error, "burst_#{index} is #{fleet_worker['status'].inspect} in current fleet state"
        end

        bootstrap_worker = bootstrap_workers[index]
        raise Error, "latest bootstrap does not contain burst_#{index}" unless bootstrap_worker
        unless bootstrap_worker["status"] == "passed"
          raise Error, "burst_#{index} bootstrap state is #{bootstrap_worker['status'].inspect}, not passed"
        end

        verify_worker!(
          index:,
          worker: bootstrap_worker,
          required_models:,
          expected_digests:,
          required_context:,
          expected_gpu:
        )
      end

      {
        "fleet_id" => fleet.fetch("fleet_id"),
        "bootstrap_run_id" => bootstrap.fetch("bootstrap_run_id"),
        "workers" => worker_indices,
        "models" => required_models,
        "digests" => required_models.to_h { |model| [model, expected_digests.fetch(model)] },
        "context" => required_context,
        "gpu" => expected_gpu
      }
    rescue RunpodFleetState::Error => e
      raise Error, e.message
    rescue ArgumentError, TypeError => e
      raise Error, "invalid provenance state: #{e.message}"
    end

    private

    def burst_worker_indices(names)
      Array(names).filter_map do |name|
        match = BURST_WORKER.match(name.to_s)
        Integer(match[1]) if match
      end.uniq.sort
    end

    def current_bootstrap!(fleet)
      root = @fleet_state.artifact_dir(fleet.fetch("fleet_id"), "bootstrap")
      pointer = File.join(root, "current")
      raise Error, "current fleet has no bootstrap/current pointer" unless File.file?(pointer)

      run_id = File.read(pointer).strip
      unless run_id.match?(/\A[A-Za-z0-9_.-]+\z/) && !run_id.include?("..")
        raise Error, "bootstrap/current contains an unsafe run id"
      end

      path = File.join(root, run_id, "bootstrap.json")
      raise Error, "latest bootstrap state is missing: #{path}" unless File.file?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError => e
      raise Error, "latest bootstrap state is invalid JSON: #{e.message}"
    end

    def verify_worker!(index:, worker:, required_models:, expected_digests:, required_context:, expected_gpu:)
      provenance = worker["provenance"]
      raise Error, "burst_#{index} has no exact provenance evidence" unless provenance.is_a?(Hash)

      observed_gpu = provenance.dig("gpu", "name")
      unless observed_gpu == expected_gpu
        raise Error, "burst_#{index} GPU mismatch: expected #{expected_gpu.inspect}, observed #{observed_gpu.inspect}"
      end

      observed_models = provenance.fetch("models", {})
      required_models.each do |model|
        observed = observed_models[model]
        unless observed
          raise Error,
                "burst_#{index} model mismatch: required #{model}; verified #{observed_models.keys.join(', ')}"
        end

        expected_digest = expected_digests.fetch(model).downcase
        actual_digest = observed["digest"].to_s.downcase
        unless actual_digest == expected_digest && actual_digest.match?(DIGEST)
          raise Error,
                "burst_#{index} #{model} digest mismatch: expected #{expected_digest}, observed #{actual_digest.inspect}"
        end

        unless Integer(observed["context_length"]) == required_context
          raise Error,
                "burst_#{index} #{model} context mismatch: expected #{required_context}, observed #{observed['context_length'].inspect}"
        end

        size = Integer(observed["size_bytes"])
        size_vram = Integer(observed["size_vram_bytes"])
        unless observed["fully_gpu_resident"] == true && size.positive? && size == size_vram
          raise Error,
                "burst_#{index} #{model} is not proven fully GPU-resident: size=#{size}, size_vram=#{size_vram}"
        end
      end
    end
  end
end
