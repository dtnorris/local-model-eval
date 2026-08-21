# frozen_string_literal: true
require_relative "test_helper"

class SchedulerTest < Minitest::Test
  def build_experiment(dir, dispatch)
    path = File.join(dir, "exp.yml")
    File.write(path, <<~YAML)
      name: test
      dispatch: #{dispatch}
      models: [granite]
      dimension: Tactical Complexity
      adventures: [ADV-0001, ADV-0002]
      replicates: 2
      workers: [mac, cloud]
      scorer:
        repo: scorer
    YAML
    LocalModelEvaluation::Experiment.new(path)
  end

  def workers
    {
      "mac" => LocalModelEvaluation::Worker.new("mac", "base_url" => "http://mac"),
      "cloud" => LocalModelEvaluation::Worker.new("cloud", "base_url" => "http://cloud")
    }
  end

  def models
    { "granite" => { "ollama_model" => "granite4:test" } }
  end

  def test_pool_creates_each_logical_job_once
    Dir.mktmpdir do |dir|
      jobs = LocalModelEvaluation::Scheduler.new(experiment: build_experiment(dir, "pool"), workers:, models:).jobs
      assert_equal 4, jobs.length
      assert jobs.all? { |j| j.planned_worker.nil? }
    end
  end

  def test_matrix_multiplies_jobs_by_workers
    Dir.mktmpdir do |dir|
      jobs = LocalModelEvaluation::Scheduler.new(experiment: build_experiment(dir, "matrix"), workers:, models:).jobs
      assert_equal 8, jobs.length
      assert_equal %w[cloud mac], jobs.map(&:planned_worker).uniq.sort
    end
  end
end
