# frozen_string_literal: true
require_relative "test_helper"

class RunStatusTest < Minitest::Test
  def test_reports_job_counts_and_cost
    Dir.mktmpdir do |dir|
      jobs = [
        LocalModelEvaluation::Job.build(model_alias: "granite", ollama_model: "granite:test", adventure: "ADV-0001", replicate: 1),
        LocalModelEvaluation::Job.build(model_alias: "granite", ollama_model: "granite:test", adventure: "ADV-0002", replicate: 1)
      ]

      complete_dir = File.join(dir, "runs", jobs.first.id)
      FileUtils.mkdir_p(complete_dir)
      File.write(File.join(complete_dir, "metadata.json"), JSON.generate(status: "complete", estimated_cost_usd: 0.125))

      status = LocalModelEvaluation::RunStatus.new(output_dir: dir, jobs:)

      assert_equal 1, status.counts["complete"]
      assert_equal 1, status.counts["pending"]
      assert_in_delta 0.125, status.estimated_cost_usd, 0.000001
      assert_nil status.manager_pid
      refute status.manager_running?
    end
  end
end
