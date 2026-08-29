# frozen_string_literal: true

require "csv"
require "json"
require "pathname"

module LocalModelEvaluation
  class Reporter
    def initialize(output_dir)
      @output_dir = File.expand_path(output_dir)
    end

    def write
      rows = metadata_rows
      write_results(rows)
      write_summary(rows)
    end

    private

    def metadata_rows
      Dir.glob(File.join(@output_dir, "runs", "*", "metadata.json")).sort.filter_map do |path|
        JSON.parse(File.read(path)).merge("_run_dir" => File.dirname(path))
      rescue JSON::ParserError
        nil
      end
    end

    def write_results(rows)
      CSV.open(File.join(@output_dir, "results.csv"), "w") do |csv|
        csv << %w[worker model adventure replicate status elapsed_seconds score confidence estimated_cost_usd result_json]
        rows.each do |r|
          extracted = extract_result(r["_run_dir"])
          csv << [r["worker"], r["model_alias"], r["adventure"], r["replicate"], r["status"], r["elapsed_seconds"], extracted[:score], extracted[:confidence], r["estimated_cost_usd"], extracted[:path]]
        end
      end
    end

    def write_summary(rows)
      completed = rows.count { |r| r["status"] == "complete" }
      failed = rows.count { |r| r["status"] == "failed" }
      total_cost = rows.sum { |r| r["estimated_cost_usd"].to_f }
      grouped = rows.group_by { |r| r["worker"] }
      manifest = File.join(@output_dir, "experiment.yml")
      experiment_text = File.file?(manifest) ? File.read(manifest) : ""

      lines = []
      lines << "# Evaluation Summary"
      lines << ""
      lines << "- Jobs observed: #{rows.length}"
      lines << "- Completed: #{completed}"
      lines << "- Failed: #{failed}"
      lines << format("- Estimated scoring-runtime cost: $%.4f", total_cost)
      lines << ""
      lines << "## Workers"
      lines << ""
      grouped.sort.each do |worker, worker_rows|
        done = worker_rows.select { |r| r["status"] == "complete" }
        mean = done.empty? ? nil : done.sum { |r| r["elapsed_seconds"].to_f } / done.length
        cost = worker_rows.sum { |r| r["estimated_cost_usd"].to_f }
        lines << "- **#{worker}** — #{done.length}/#{worker_rows.length} complete; mean #{mean ? format('%.1fs', mean) : 'n/a'}; estimated runtime cost #{format('$%.4f', cost)}"
      end
      lines << ""
      lines << "## Interpretation boundary"
      lines << ""
      lines << "This report summarizes execution evidence only. Native `af-cli-scoring-utility` output remains authoritative; benchmark adjudication and AFAO interpretation are intentionally outside this repository."
      lines << ""
      lines << "## Frozen experiment manifest"
      lines << ""
      lines << "```yaml"
      lines << experiment_text.rstrip
      lines << "```"
      File.write(File.join(@output_dir, "summary.md"), lines.join("\n") + "\n")
    end

    def extract_result(run_dir)
      candidates = Dir.glob(File.join(run_dir, "native", "**", "*.json")).sort.reject do |path|
        File.basename(path).end_with?("_request.json")
      end
      candidates.each do |path|
        data = JSON.parse(File.read(path)) rescue next
        found = recursive_fields(data)
        return found.merge(path: Pathname(path).relative_path_from(Pathname(@output_dir)).to_s) if found[:score] || found[:confidence]
      end
      { score: nil, confidence: nil, path: nil }
    end

    def recursive_fields(obj)
      case obj
      when Hash
        score = obj["score"] || obj["Score"]
        confidence = obj["confidence"] || obj["Confidence"]
        return { score:, confidence: } if score || confidence
        obj.each_value do |value|
          found = recursive_fields(value)
          return found if found[:score] || found[:confidence]
        end
      when Array
        obj.each do |value|
          found = recursive_fields(value)
          return found if found[:score] || found[:confidence]
        end
      when String
        stripped = obj.lstrip
        if stripped.start_with?("{", "[")
          parsed = JSON.parse(obj) rescue nil
          return recursive_fields(parsed) if parsed
        end
      end
      { score: nil, confidence: nil }
    end
  end
end
