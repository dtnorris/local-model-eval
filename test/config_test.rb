# frozen_string_literal: true
require_relative "test_helper"

class ConfigTest < Minitest::Test
  def test_expands_environment_variables_and_defaults
    Dir.mktmpdir do |dir|
      path = File.join(dir, "x.yml")
      File.write(path, "a: ${LME_TEST_VALUE}\nb: ${LME_MISSING_VALUE:-fallback}\n")
      ENV["LME_TEST_VALUE"] = "hello"
      data = LocalModelEvaluation::Config.load_yaml(path)
      assert_equal "hello", data["a"]
      assert_equal "fallback", data["b"]
    ensure
      ENV.delete("LME_TEST_VALUE")
    end
  end

  def test_missing_required_environment_variable_raises
    Dir.mktmpdir do |dir|
      path = File.join(dir, "x.yml")
      File.write(path, "a: ${LME_DEFINITELY_MISSING}\n")
      ENV.delete("LME_DEFINITELY_MISSING")
      assert_raises(KeyError) { LocalModelEvaluation::Config.load_yaml(path) }
    end
  end
end
