# frozen_string_literal: true
require_relative "test_helper"

class RunnerTest < Minitest::Test
  def test_runner_preserves_native_output_and_resume
    Dir.mktmpdir do |dir|
      scorer = File.join(dir, "scorer")
      FileUtils.mkdir_p(File.join(scorer, "bin"))
      File.write(File.join(scorer, "bin", "af-score"), <<~'RUBY')
        #!/usr/bin/env ruby
        require "json"
        args = ARGV
        output = args[args.index("--output") + 1]
        Dir.mkdir(output) unless Dir.exist?(output)
        File.write(File.join(output, "result.json"), JSON.generate(score: 4, confidence: 90))
        puts "ok"
      RUBY
      FileUtils.chmod("+x", File.join(scorer, "bin", "af-score"))

      exp_path = File.join(dir, "exp.yml")
      File.write(exp_path, <<~YAML)
        name: run-test
        dispatch: pool
        models: [granite]
        dimension: Tactical Complexity
        adventures: [ADV-0001]
        replicates: 1
        workers: [mac]
        scorer:
          repo: #{scorer}
          mode: regression
      YAML
      exp = LocalModelEvaluation::Experiment.new(exp_path)
      worker = LocalModelEvaluation::Worker.new("mac", "base_url" => "http://localhost", "scorer_env" => {})
      workers = { "mac" => worker }
      models = { "granite" => { "ollama_model" => "granite4:test" } }
      jobs = LocalModelEvaluation::Scheduler.new(experiment: exp, workers:, models:).jobs
      out = StringIO.new
      runner = LocalModelEvaluation::Runner.new(experiment: exp, workers:, models:, output_root: File.join(dir, "out"), io: out)
      runner.run(jobs)
      metadata = JSON.parse(File.read(File.join(runner.output_dir, "runs", jobs.first.id, "metadata.json")))
      assert_equal "complete", metadata["status"]
      assert File.file?(File.join(runner.output_dir, "runs", jobs.first.id, "native", "result.json"))

      second_out = StringIO.new
      second = LocalModelEvaluation::Runner.new(experiment: exp, workers:, models:, output_root: File.join(dir, "out"), io: second_out)
      second.run(jobs)
      assert_match(/1 completed\/skipped; 0 pending/, second_out.string)
    end
  end
end
