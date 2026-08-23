#!/bin/zsh
set -u

REPO="${LME_REPO:-$HOME/code/local-model-eval}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORDER="$SCRIPT_DIR/production_overnight3_run_order.txt"
INDEX="$SCRIPT_DIR/production_overnight3_case_index.csv"
EXPECTED_RUNS=123
EXPECTED_SKIPS=9
EXPECTED_MATRIX=132
EXPECTED_MODEL="qwen3.6:35b-a3b"

cd "$REPO" || { echo "ERROR: Could not find $REPO"; exit 1; }
[[ -x bin/lme ]] || { echo "ERROR: bin/lme not found/executable in $REPO"; exit 1; }
[[ -f "$ORDER" ]] || { echo "ERROR: missing $ORDER"; exit 1; }
[[ -f "$INDEX" ]] || { echo "ERROR: missing $INDEX"; exit 1; }

actual=$(grep -c '^experiments/' "$ORDER" || true)
echo "Run manifest count: $actual (expected $EXPECTED_RUNS)"
[[ "$actual" -eq "$EXPECTED_RUNS" ]] || { echo "ERROR: wrong run manifest count"; exit 1; }

dups=$(sort "$ORDER" | uniq -d)
[[ -z "$dups" ]] || { echo "ERROR: duplicate manifest paths:"; echo "$dups"; exit 1; }

# Verify the frozen production matrix and every manifest's semantics without inference.
ruby - "$INDEX" "$ORDER" <<'RUBY' || exit 1
require "csv"
require "yaml"
Encoding.default_external = Encoding::UTF_8

index_path, order_path = ARGV
rows = CSV.read(index_path, headers: true, encoding: "UTF-8")
abort "case index must contain 132 matrix cells" unless rows.length == 132
run_rows = rows.select { |r| r["action"] == "RUN" }
skip_rows = rows.select { |r| r["action"] == "SKIP_AMC_EXISTING" }
abort "case index must contain 123 RUN cells" unless run_rows.length == 123
abort "case index must contain 9 SKIP cells" unless skip_rows.length == 9

expected_paths = run_rows.map { |r| r["manifest_path"] }
order_paths = File.readlines(order_path, chomp: true).reject(&:empty?)
abort "run order does not exactly match RUN rows in case index" unless order_paths == expected_paths

expected_counts = {
  "Combat Emphasis" => 28,
  "Structural Openness" => 29,
  "Darkness / Horror Intensity" => 33,
  "Player Beginner Suitability" => 33,
}
actual_counts = Hash.new(0)
seen_cases = {}

run_rows.each do |row|
  path = row["manifest_path"]
  abort "missing manifest: #{path}" unless File.file?(path)
  data = YAML.safe_load_file(path)
  adv = row["adventure_id"]
  dim = row["dimension"]
  key = [adv, dim]
  abort "duplicate production cell #{key.join(' / ')}" if seen_cases[key]
  seen_cases[key] = true

  abort "wrong model in #{path}" unless data["models"] == ["qwen"]
  abort "wrong dimension in #{path}" unless data["dimension"] == dim
  abort "wrong adventure in #{path}" unless data["adventures"] == [adv]
  abort "wrong replicate count in #{path}" unless data["replicates"] == 1
  abort "wrong worker in #{path}" unless data["workers"] == ["mac"]
  abort "wrong worker labels in #{path}" unless data["required_worker_labels"] == ["local"]
  abort "wrong scorer repo in #{path}" unless data.dig("scorer", "repo") == "../../../af-cli-scoring-utility"
  abort "wrong scorer mode in #{path}" unless data.dig("scorer", "mode") == "positional"
  abort "unexpected scorer extra args in #{path}" unless data.dig("scorer", "extra_args") == []
  abort "wrong cost cap in #{path}" unless data["cost_cap_usd"].to_f == 0.01
  actual_counts[dim] += 1
end

abort "dimension counts mismatch: #{actual_counts.inspect}" unless actual_counts == expected_counts

# Freeze the 9 AMC-existing cells that must not have production manifests.
skips = skip_rows.map { |r| [r["adventure_id"], r["dimension"], r["existing_score"]] }
expected_skips = [
  ["ADV-0278", "Combat Emphasis", "1"],
  ["ADV-0278", "Structural Openness", "5"],
  ["ADV-0200", "Combat Emphasis", "1"],
  ["ADV-0200", "Structural Openness", "1"],
  ["ADV-0230", "Combat Emphasis", "4"],
  ["ADV-0288", "Structural Openness", "1"],
  ["ADV-0323", "Structural Openness", "5"],
  ["ADV-0033", "Combat Emphasis", "5"],
  ["ADV-0020", "Combat Emphasis", "3"],
]
abort "AMC skip cells mismatch" unless skips == expected_skips

puts "Matrix semantics: PASS"
actual_counts.each { |dim, n| puts "  #{dim}: #{n} RUN" }
puts "  AMC-existing skips: #{skip_rows.length}"
RUBY

# Assert the authorized model alias has not silently changed.
ruby - <<'RUBY' || exit 1
require "yaml"
models = YAML.safe_load_file("config/models.yml")
actual = models.dig("models", "qwen", "ollama_model")
expected = "qwen3.6:35b-a3b"
abort "ERROR: qwen alias is #{actual.inspect}; expected #{expected.inspect}" unless actual == expected
puts "Qwen alias: #{actual} (expected)"
RUBY

failed=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if [[ ! -f "$f" ]]; then
    echo "MISSING: $f"
    failed=$((failed + 1))
    continue
  fi
  if ! bin/lme plan "$f" >/dev/null; then
    echo "PLAN FAILED: $f"
    failed=$((failed + 1))
  fi
done < "$ORDER"

if [[ "$failed" -ne 0 ]]; then
  echo "ERROR: $failed manifest(s) failed bin/lme plan. No inference was run."
  exit 1
fi

echo "All $EXPECTED_RUNS production manifests passed bin/lme plan."

qwen_sample=$(head -n 1 "$ORDER")
echo
echo "Checking local worker and authorized Qwen model..."
bin/lme worker-check "$qwen_sample" || exit 1

echo
echo "PREFLIGHT PASSED — 123 RUN cells + 9 protected AMC skips = 132-cell matrix."
echo "NO INFERENCE WAS RUN."
