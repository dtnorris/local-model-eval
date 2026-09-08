# frozen_string_literal: true

require "digest"
require "fileutils"
require "yaml"

module ProductionBacklogRuntimeContract
  VERSION = 1
  RUNTIME_KEY = "qwen35_core"
  SOURCE_RELATIVE_PATH = "production_backlog/qwen35-core-v1-runtime.yml"

  QWEN35_CORE_DIMENSIONS = [
    "Combat Emphasis",
    "Social Interaction Emphasis",
    "Investigation Emphasis",
    "Structural Openness",
    "Darkness / Horror Intensity",
    "Player Beginner Suitability"
  ].freeze

  EXPECTED_LLM = {
    "provider" => "ollama",
    "model" => "qwen3.6:35b-a3b",
    "reasoning_effort" => "high",
    "max_tokens" => 8192
  }.freeze

  EXPECTED_CONFIG = { "llm" => EXPECTED_LLM }.freeze

  module_function

  def runtime_key_for(dimension_name)
    QWEN35_CORE_DIMENSIONS.include?(dimension_name.to_s) ? RUNTIME_KEY : nil
  end

  def expected_dimension_runtime_keys
    QWEN35_CORE_DIMENSIONS.to_h { |name| [name, RUNTIME_KEY] }
  end

  def validate_source!(root)
    path = File.join(root, SOURCE_RELATIVE_PATH)
    raise ArgumentError, "missing qwen35 core runtime source #{path}" unless File.file?(path)

    validate_runtime_file!(path)
    path
  end

  def freeze!(root:, queue:)
    source = validate_source!(root)
    relative = File.join("production_backlog", queue, "runtime-qwen35-core-v1.yml")
    target = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(target))
    FileUtils.cp(source, target)

    {
      "version" => VERSION,
      "dimension_runtime_keys" => expected_dimension_runtime_keys,
      "runtime_files" => {
        RUNTIME_KEY => {
          "path" => relative,
          "sha256" => sha256(target),
          "source_path" => SOURCE_RELATIVE_PATH,
          "source_sha256" => sha256(source)
        }
      }
    }
  end

  def validate_snapshot!(root:, contract:)
    version = Integer(contract.fetch("version"))
    raise ArgumentError, "unsupported production runtime contract version #{version}" unless version == VERSION

    actual_map = contract.fetch("dimension_runtime_keys")
    unless actual_map == expected_dimension_runtime_keys
      raise ArgumentError, "production runtime dimension mapping changed"
    end

    info = contract.fetch("runtime_files").fetch(RUNTIME_KEY)
    source = File.join(root, info.fetch("source_path"))
    target = File.join(root, info.fetch("path"))

    raise ArgumentError, "missing qwen35 core runtime source #{source}" unless File.file?(source)
    raise ArgumentError, "missing frozen qwen35 core runtime #{target}" unless File.file?(target)
    raise ArgumentError, "qwen35 core runtime source changed" unless sha256(source) == info.fetch("source_sha256")
    raise ArgumentError, "frozen qwen35 core runtime changed" unless sha256(target) == info.fetch("sha256")

    validate_runtime_file!(source)
    validate_runtime_file!(target)
    true
  rescue KeyError, TypeError => e
    raise ArgumentError, e.message
  end

  def extra_args_for(dimension_name:, contract:)
    runtime_key = contract.fetch("dimension_runtime_keys")[dimension_name.to_s]
    return [] unless runtime_key

    info = contract.fetch("runtime_files").fetch(runtime_key)
    ["--config", "${LME_REPO}/#{info.fetch('path')}"]
  end

  def validate_runtime_file!(path)
    data = YAML.safe_load_file(path, aliases: true) || {}
    return true if data == EXPECTED_CONFIG

    raise ArgumentError,
          "qwen35 core runtime must be exactly ollama/qwen3.6:35b-a3b/high/max_tokens=8192: #{path}"
  rescue Psych::SyntaxError => e
    raise ArgumentError, "invalid qwen35 core runtime YAML #{path}: #{e.message}"
  end

  def sha256(path)
    Digest::SHA256.file(path).hexdigest
  end
end
