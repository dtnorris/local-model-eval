# frozen_string_literal: true
require_relative "test_helper"

class ExperimentTest < Minitest::Test
  def test_loads_manifest
    Dir.mktmpdir do |dir|
      path = File.join(dir, "exp.yml")
      File.write(path, <<~YAML)
        name: test
        dispatch: pool
        models: [granite]
        dimension: Tactical Complexity
        adventures: [ADV-0001]
        replicates: 2
        workers: [mac]
        scorer:
          repo: scorer
          mode: regression
      YAML
      exp = LocalModelEvaluation::Experiment.new(path)
      assert_equal "test", exp.name
      assert_equal 2, exp.replicates
      assert_equal File.join(dir, "scorer"), exp.scorer_repo
    end
  end
end
