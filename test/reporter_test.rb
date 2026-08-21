# frozen_string_literal: true
require_relative "test_helper"

class ReporterTest < Minitest::Test
  def test_extracts_common_result_fields_without_altering_native_output
    Dir.mktmpdir do |dir|
      run_dir = File.join(dir, "runs", "job1")
      native = File.join(run_dir, "native")
      FileUtils.mkdir_p(native)
      File.write(File.join(run_dir, "metadata.json"), JSON.pretty_generate(
        worker: "mac", model_alias: "granite", adventure: "ADV-0001", replicate: 1,
        status: "complete", elapsed_seconds: 10, estimated_cost_usd: 0
      ))
      File.write(File.join(native, "result.json"), JSON.generate("assessment" => { "score" => 4, "confidence" => 91 }))
      File.write(File.join(dir, "experiment.yml"), "name: test\n")

      LocalModelEvaluation::Reporter.new(dir).write
      results = CSV.read(File.join(dir, "results.csv"), headers: true)
      assert_equal "4", results[0]["score"]
      assert_equal "91", results[0]["confidence"]
      assert File.file?(File.join(native, "result.json"))
      assert File.file?(File.join(dir, "summary.md"))
    end
  end
end
