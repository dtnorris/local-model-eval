# frozen_string_literal: true
require_relative "test_helper"
require_relative "../lib/local_model_evaluation/manifest_batch"

class ManifestBatchTest < Minitest::Test
  def write_manifest(dir, filename, model:, adventure:, dimension:, worker: "mac")
    path = File.join(dir, filename)
    File.write(path, <<~YAML)
      name: #{File.basename(filename, ".yml")}
      dispatch: pool
      models: [#{model}]
      dimension: #{dimension}
      adventures: [#{adventure}]
      replicates: 1
      workers: [#{worker}]
      scorer:
        repo: scorer
    YAML
    path
  end

  def test_orders_atomic_manifests_by_worker_model_adventure_then_dimension
    Dir.mktmpdir do |dir|
      paths = [
        write_manifest(dir, "qwen-adv2-darkness.yml", model: "qwen", adventure: "ADV-0002", dimension: "Darkness / Horror Intensity"),
        write_manifest(dir, "qwen-adv1-social.yml", model: "qwen", adventure: "ADV-0001", dimension: "Social Interaction Emphasis"),
        write_manifest(dir, "nemotron-adv1-tactical.yml", model: "nemotron", adventure: "ADV-0001", dimension: "Tactical Complexity"),
        write_manifest(dir, "qwen-adv1-darkness.yml", model: "qwen", adventure: "ADV-0001", dimension: "Darkness / Horror Intensity")
      ]

      list = File.join(dir, "batch.txt")
      File.write(list, paths.map { |path| File.basename(path) }.join("\n") + "\n")

      ordered = LocalModelEvaluation::ManifestBatch.new(list).ordered_entries

      assert_equal(
        [
          ["mac", "nemotron", "ADV-0001", "Tactical Complexity"],
          ["mac", "qwen", "ADV-0001", "Darkness / Horror Intensity"],
          ["mac", "qwen", "ADV-0001", "Social Interaction Emphasis"],
          ["mac", "qwen", "ADV-0002", "Darkness / Horror Intensity"]
        ],
        ordered.map { |entry| [entry.worker, entry.model, entry.adventure, entry.dimension] }
      )
    end
  end

  def test_ignores_comments_and_resolves_paths_relative_to_list
    Dir.mktmpdir do |dir|
      manifest = write_manifest(
        dir,
        "case.yml",
        model: "qwen",
        adventure: "ADV-0001",
        dimension: "Combat Emphasis"
      )
      list = File.join(dir, "batch.txt")
      File.write(list, "# comment\n\n#{File.basename(manifest)}\n")

      batch = LocalModelEvaluation::ManifestBatch.new(list)

      assert_equal [File.expand_path(manifest)], batch.entries.map(&:manifest_path)
    end
  end

  def test_rejects_multi_adventure_manifest
    Dir.mktmpdir do |dir|
      manifest = File.join(dir, "multi.yml")
      File.write(manifest, <<~YAML)
        name: multi
        dispatch: pool
        models: [qwen]
        dimension: Combat Emphasis
        adventures: [ADV-0001, ADV-0002]
        replicates: 1
        workers: [mac]
        scorer:
          repo: scorer
      YAML
      list = File.join(dir, "batch.txt")
      File.write(list, "#{File.basename(manifest)}\n")

      error = assert_raises(ArgumentError) { LocalModelEvaluation::ManifestBatch.new(list) }
      assert_includes error.message, "exactly one adventure"
    end
  end

  def test_rejects_multi_worker_manifest_because_cache_locality_would_not_be_guaranteed
    Dir.mktmpdir do |dir|
      manifest = File.join(dir, "multi-worker.yml")
      File.write(manifest, <<~YAML)
        name: multi-worker
        dispatch: pool
        models: [qwen]
        dimension: Combat Emphasis
        adventures: [ADV-0001]
        replicates: 1
        workers: [mac, remote]
        scorer:
          repo: scorer
      YAML
      list = File.join(dir, "batch.txt")
      File.write(list, "#{File.basename(manifest)}\n")

      error = assert_raises(ArgumentError) { LocalModelEvaluation::ManifestBatch.new(list) }
      assert_includes error.message, "exactly one worker"
    end
  end
end
