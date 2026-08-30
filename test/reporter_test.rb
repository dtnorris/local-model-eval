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

class ReporterRawResponseTest < Minitest::Test
  def test_ignores_request_schema_and_extracts_json_message_content
    Dir.mktmpdir do |dir|
      run_dir = File.join(dir, "runs", "job1")
      native = File.join(run_dir, "native", "raw", "ADV-0200", "run1")
      FileUtils.mkdir_p(native)
      File.write(File.join(run_dir, "metadata.json"), JSON.pretty_generate(
        worker: "burst_1", model_alias: "qwen27", adventure: "ADV-0200", replicate: 1,
        status: "complete", elapsed_seconds: 145, estimated_cost_usd: 0.02
      ))
      File.write(File.join(native, "dimension_social_interaction_emphasis_request.json"), JSON.generate(
        "request" => {
          "response_format" => {
            "json_schema" => {
              "schema" => {
                "properties" => {
                  "score" => { "type" => ["integer", "null"], "minimum" => 1, "maximum" => 5 },
                  "confidence" => { "type" => ["integer", "null"], "minimum" => 0, "maximum" => 100 }
                }
              }
            }
          }
        }
      ))
      response_path = File.join(native, "dimension_social_interaction_emphasis.json")
      File.write(response_path, JSON.generate(
        "choices" => [{
          "message" => {
            "content" => JSON.generate(
              "group" => "play_mix",
              "dimensions" => [{ "dimension" => "Social Interaction Emphasis", "score" => 1, "confidence" => 85 }]
            )
          }
        }]
      ))
      File.write(File.join(dir, "experiment.yml"), "name: test\n")

      LocalModelEvaluation::Reporter.new(dir).write
      results = CSV.read(File.join(dir, "results.csv"), headers: true)
      assert_equal "1", results[0]["score"]
      assert_equal "85", results[0]["confidence"]
      assert_equal "runs/job1/native/raw/ADV-0200/run1/dimension_social_interaction_emphasis.json", results[0]["result_json"]
    end
  end
end
