# frozen_string_literal: true

require "json"

module LocalModelEvaluation
  class RunStatus
    attr_reader :output_dir, :jobs

    def initialize(output_dir:, jobs:)
      @output_dir = File.expand_path(output_dir)
      @jobs = jobs
    end

    def counts
      result = Hash.new(0)
      jobs.each do |job|
        metadata = metadata_for(job)
        status = metadata ? metadata.fetch("status", "unknown").to_s : "pending"
        result[status] += 1
      end
      result
    end

    def estimated_cost_usd
      jobs.sum do |job|
        metadata = metadata_for(job)
        metadata ? metadata["estimated_cost_usd"].to_f : 0.0
      end
    end

    def manager_pid
      path = File.join(output_dir, "manager.pid")
      return nil unless File.file?(path)

      Integer(File.read(path).strip)
    rescue ArgumentError
      nil
    end

    def manager_running?
      pid = manager_pid
      return false unless pid

      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    private

    def metadata_for(job)
      path = File.join(output_dir, "runs", job.id, "metadata.json")
      return nil unless File.file?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      { "status" => "unknown" }
    end
  end
end
