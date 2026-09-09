#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${LME_REPO:-$SCRIPT_DIR}"
QUEUE_ARG="${1:-}"
SCORER_REPO="${AF_SCORER_REPO:-}"

[[ -n "$QUEUE_ARG" ]] || {
  echo "Usage: ./verify_production_backlog_018.sh production_backlog/production-backlog-018"
  exit 2
}

if [[ "$QUEUE_ARG" = /* ]]; then
  QUEUE_DIR="$QUEUE_ARG"
else
  QUEUE_DIR="$REPO/$QUEUE_ARG"
fi
SNAPSHOT="$QUEUE_DIR/snapshot.yml"
INDEX="$QUEUE_DIR/case_index.csv"
ORDER="$QUEUE_DIR/run_order.txt"

[[ -f "$SNAPSHOT" ]] || { echo "ERROR: missing $SNAPSHOT"; exit 1; }
[[ -f "$INDEX" ]] || { echo "ERROR: missing $INDEX"; exit 1; }
[[ -f "$ORDER" ]] || { echo "ERROR: missing $ORDER"; exit 1; }

if [[ -z "$SCORER_REPO" ]]; then
  SNAPSHOT_SCORER=$(ruby - "$SNAPSHOT" <<'RUBY'
require "yaml"
print YAML.safe_load_file(ARGV.fetch(0), aliases: true).fetch("scorer_repo_path")
RUBY
)
  if [[ "$SNAPSHOT_SCORER" = /* ]]; then
    SCORER_REPO="$SNAPSHOT_SCORER"
  else
    SCORER_REPO="$REPO/$SNAPSHOT_SCORER"
  fi
fi
SCORER_REPO="$(cd "$SCORER_REPO" 2>/dev/null && pwd)" || { echo "ERROR: scorer checkout not found: $SCORER_REPO"; exit 1; }
[[ -d "$SCORER_REPO/.git" ]] || { echo "ERROR: scorer checkout lacks .git: $SCORER_REPO"; exit 1; }

cd "$REPO" || exit 1
[[ -x bin/lme ]] || { echo "ERROR: bin/lme missing/executable"; exit 1; }

ruby - "$SNAPSHOT" "$INDEX" "$ORDER" "$SCORER_REPO" "$REPO" <<'RUBY' || exit 1
require "csv"
require "digest"
require "yaml"

snapshot_path, index_path, order_path, scorer_repo, repo_root = ARGV
snapshot = YAML.safe_load_file(snapshot_path, aliases: true)
rows = CSV.read(index_path, headers: true, encoding: "UTF-8")
order = File.readlines(order_path, chomp: true).reject(&:empty?)

CATALOG_FILENAME = "5e_Adventure_Master_Catalog_4.6.xlsx"
CATALOG_SHA256 = "7451c6680eb59e76e686ac01951beb3d8ff0816dad385833cc9fcce3b3cf93cb"
EXPECTED_IDS = ((404..412).to_a + (414..427).to_a).map { |n| format("ADV-%04d", n) }.freeze
EXPECTED_LEVEL_IDS = %w[
  ADV-0409
  ADV-0414 ADV-0415 ADV-0416 ADV-0417 ADV-0418 ADV-0419 ADV-0420
  ADV-0421 ADV-0422 ADV-0423 ADV-0424 ADV-0425 ADV-0426 ADV-0427
].freeze
SOURCE_BOUNDARY_CLAMP_IDS = [].freeze
EXPECTED_DIMENSIONS = [
  ["# of Sessions", "nos-clean-blind-v1", "qwen27", "qwen3.6:27b", "base", "Number of Sessions"],
  ["Exploration Emphasis", "ee-clean-reset-v0.5", "gptoss", "gpt-oss:20b", "ee", "Exploration Emphasis"],
  ["GM Preparation Burden", "gmpb-v0.6-dependency-fan-out", "gemma", "gemma4:26b", "gmpb", "GM Preparation Burden"],
  ["Combat Emphasis", "production-base", "qwen", "qwen3.6:35b-a3b", "base", "Combat Emphasis"],
  ["Social Interaction Emphasis", "phase6-v0.3", "qwen", "qwen3.6:35b-a3b", "base", "Social Interaction Emphasis"],
  ["Investigation Emphasis", "phase6-v0.4", "qwen", "qwen3.6:35b-a3b", "base", "Investigation Emphasis"],
  ["Structural Openness", "production-base", "qwen", "qwen3.6:35b-a3b", "base", "Structural Openness"],
  ["Darkness / Horror Intensity", "production-base", "qwen", "qwen3.6:35b-a3b", "base", "Darkness / Horror Intensity"],
  ["Player Beginner Suitability", "production-base", "qwen", "qwen3.6:35b-a3b", "base", "Player Beginner Suitability"],
  ["GM Beginner Suitability", "gmbs-clean-blind-v0.3", "qwen", "qwen3.6:35b-a3b", "base", "GM Beginner Suitability"],
  ["Seriousness", "seriousness-reset-only", "qwen", "qwen3.6:35b-a3b", "seriousness", "Seriousness"]
].freeze
EXPECTED_LEVELS = [
  "Levels", "levels-v2.1", "qwen", "qwen3.6:35b-a3b", "base", ["Level Start", "Level End"]
].freeze
DEFERRED_COLUMNS = [
  "Rules / System-Master Demand",
  "Tactical Complexity",
  "Lethality / Failure Severity",
  "Puzzle / Problem-Solving Emphasis",
  "Consequential Player Agency",
  "Fantastic Weirdness",
  "GM Improvisation Demand"
].freeze
EXPECTED_CALLS = (EXPECTED_IDS.length * EXPECTED_DIMENSIONS.length) + EXPECTED_LEVEL_IDS.length

def sha256(path)
  Digest::SHA256.file(path).hexdigest
end

def blank?(value)
  value.nil? || value.to_s.strip.empty?
end

def canonical_header(value)
  h = value.to_s.strip
  h == "ADV - ID" ? "Adventure ID" : h
end

def integer_or_nil(value)
  return nil if blank?(value)
  Integer(Float(value))
rescue ArgumentError, TypeError
  nil
end

abort "wrong Batch 18 contract type" unless snapshot.fetch("contract_type") == "adventure_ingest_v1"
abort "wrong Batch 18 queue name" unless snapshot.fetch("queue") == "production-backlog-018"
abort "wrong catalog filename" unless snapshot.fetch("catalog_filename") == CATALOG_FILENAME
abort "wrong catalog SHA" unless snapshot.fetch("catalog_sha256") == CATALOG_SHA256
abort "wrong expected adventure count" unless Integer(snapshot.fetch("expected_adventure_count")) == 23
abort "wrong expected call count" unless Integer(snapshot.fetch("expected_calls")) == EXPECTED_CALLS
abort "adventure order changed" unless snapshot.fetch("adventure_order") == EXPECTED_IDS
abort "source-boundary clamp approvals changed" unless
  snapshot.fetch("source_boundary_clamp_adventure_ids") == SOURCE_BOUNDARY_CLAMP_IDS
abort "dimension order changed" unless snapshot.fetch("dimension_order") == EXPECTED_DIMENSIONS.map(&:first)
abort "conditional dimension order changed" unless snapshot.fetch("conditional_dimension_order") == ["Levels"]
abort "conditional Levels adventure IDs changed" unless snapshot.fetch("levels_inference_adventure_ids") == EXPECTED_LEVEL_IDS
abort "deferred columns changed" unless snapshot.fetch("deferred_columns") == DEFERRED_COLUMNS

qualification_files = snapshot.fetch("qualification_files")
qualification_files.each do |relative, expected_sha|
  path = File.join(repo_root, relative)
  abort "missing qualification file #{relative}" unless File.file?(path)
  abort "qualification file changed after queue freeze: #{relative}" unless sha256(path) == expected_sha
end

runtime_files = snapshot.fetch("runtime_files")
runtime_files.each do |key, info|
  path = File.join(repo_root, info.fetch("path"))
  abort "missing runtime config #{key}: #{path}" unless File.file?(path)
  abort "runtime config changed after queue freeze: #{key}" unless sha256(path) == info.fetch("sha256")
  data = YAML.safe_load_file(path, aliases: true) || {}
  abort "runtime #{key} no longer points to AMC 4.6" unless data.dig("files", "catalog") == CATALOG_FILENAME
  abort "runtime #{key} source-boundary clamp approvals changed" unless
    data.dig("source", "allow_inward_boundary_clamp_adventure_ids") == SOURCE_BOUNDARY_CLAMP_IDS

  if info["source_path"]
    source = File.join(repo_root, info.fetch("source_path"))
    abort "missing qualified runtime source #{info.fetch('source_path')}" unless File.file?(source)
    abort "qualified runtime source changed after queue freeze: #{info.fetch('source_path')}" unless sha256(source) == info.fetch("source_sha256")
  end
end

expected_runtime = {
  "base" => {},
  "ee" => { "provider" => "ollama", "model" => "gpt-oss:20b", "reasoning_effort" => "low", "max_tokens" => 4096 },
  "gmpb" => { "provider" => "ollama", "model" => "gemma4:26b", "reasoning_effort" => "medium", "max_tokens" => 16_384 },
  "seriousness" => { "provider" => "ollama", "model" => "qwen3.6:35b-a3b", "reasoning_effort" => "low", "max_tokens" => 16_384 }
}
expected_runtime.each do |key, expected_llm|
  next if expected_llm.empty?
  data = YAML.safe_load_file(File.join(repo_root, runtime_files.fetch(key).fetch("path")), aliases: true)
  llm = data.fetch("llm")
  expected_llm.each do |field, expected|
    actual = llm.fetch(field)
    actual = Integer(actual) if field == "max_tokens"
    abort "runtime #{key} #{field} changed: #{actual.inspect}" unless actual == expected
  end
end

models = YAML.safe_load_file(File.join(repo_root, "config", "models.yml"), aliases: true).fetch("models")
EXPECTED_DIMENSIONS.each do |_name, _profile, alias_name, ollama_model, _runtime_key, _catalog_column|
  abort "model alias #{alias_name} changed" unless models.dig(alias_name, "ollama_model") == ollama_model
end
abort "Levels model alias changed" unless models.dig(EXPECTED_LEVELS.fetch(2), "ollama_model") == EXPECTED_LEVELS.fetch(3)

dimension_contracts = snapshot.fetch("dimension_contracts")
abort "snapshot dimension-contract count changed" unless dimension_contracts.length == EXPECTED_DIMENSIONS.length
EXPECTED_DIMENSIONS.each_with_index do |expected, index|
  name, profile, alias_name, ollama_model, runtime_key, catalog_column = expected
  actual = dimension_contracts.fetch(index)
  abort "dimension contract #{index + 1} name changed" unless actual.fetch("name") == name
  abort "dimension contract #{name} profile changed" unless actual.fetch("profile") == profile
  abort "dimension contract #{name} model alias changed" unless actual.fetch("model_alias") == alias_name
  abort "dimension contract #{name} Ollama model changed" unless actual.fetch("ollama_model") == ollama_model
  abort "dimension contract #{name} runtime key changed" unless actual.fetch("runtime_key") == runtime_key
  abort "dimension contract #{name} catalog column changed" unless actual.fetch("catalog_column") == catalog_column
  qpath = actual.fetch("qualification_path")
  abort "dimension contract #{name} qualification SHA no longer matches frozen file" unless qualification_files.fetch(qpath) == actual.fetch("qualification_sha256")
end

levels_contract = snapshot.fetch("levels_contract")
levels_name, levels_profile, levels_alias, levels_model, levels_runtime, levels_columns = EXPECTED_LEVELS
abort "Levels contract name changed" unless levels_contract.fetch("name") == levels_name
abort "Levels contract profile changed" unless levels_contract.fetch("profile") == levels_profile
abort "Levels contract model alias changed" unless levels_contract.fetch("model_alias") == levels_alias
abort "Levels contract Ollama model changed" unless levels_contract.fetch("ollama_model") == levels_model
abort "Levels contract runtime key changed" unless levels_contract.fetch("runtime_key") == levels_runtime
abort "Levels contract catalog columns changed" unless levels_contract.fetch("catalog_columns") == levels_columns
levels_qpath = levels_contract.fetch("qualification_path")
abort "Levels qualification SHA no longer matches frozen file" unless qualification_files.fetch(levels_qpath) == levels_contract.fetch("qualification_sha256")

contracts_by_name = dimension_contracts.to_h { |contract| [contract.fetch("name"), contract] }
contracts_by_name[levels_name] = levels_contract

frozen_scorer = File.expand_path(snapshot.fetch("scorer_repo_path"), repo_root)
abort "queue scorer path changed: snapshot=#{frozen_scorer} active=#{scorer_repo}" unless frozen_scorer == File.expand_path(scorer_repo)

catalog_path = snapshot.fetch("catalog_path")
abort "catalog path missing: #{catalog_path}" unless File.file?(catalog_path)
abort "catalog basename changed" unless File.basename(catalog_path) == CATALOG_FILENAME
abort "catalog bytes changed" unless sha256(catalog_path) == CATALOG_SHA256

require File.join(scorer_repo, "lib", "af_scoring", "errors")
require File.join(scorer_repo, "lib", "af_scoring", "xlsx_reader")
workbook_rows = AFScoring::XlsxReader.new(catalog_path).rows(sheet_name: "Adventure Catalog")
abort "AMC Adventure Catalog sheet is empty" if workbook_rows.empty?
headers = workbook_rows.shift.map { |v| canonical_header(v) }
score_columns = EXPECTED_DIMENSIONS.map { |d| d.fetch(5) }
required_headers = ["Adventure ID", "Level Start", "Level End", *score_columns, *DEFERRED_COLUMNS].uniq
missing = required_headers - headers
abort "AMC missing required Batch 18 columns: #{missing.join(', ')}" unless missing.empty?

selected_rows = []
workbook_rows.each do |row|
  values = headers.zip(row).to_h
  id = values["Adventure ID"].to_s.strip
  next unless EXPECTED_IDS.include?(id)

  level_start_blank = blank?(values["Level Start"])
  level_end_blank = blank?(values["Level End"])
  abort "#{id} has asymmetric Levels state" if level_start_blank != level_end_blank
  needs_levels = level_start_blank && level_end_blank
  expected_needs_levels = EXPECTED_LEVEL_IDS.include?(id)
  abort "#{id} Levels state changed" unless needs_levels == expected_needs_levels

  populated = score_columns.reject { |column| blank?(values[column]) }
  abort "#{id} Batch 18 score field is no longer blank: #{populated.join(', ')}" unless populated.empty?
  populated_deferred = DEFERRED_COLUMNS.reject { |column| blank?(values[column]) }
  abort "#{id} deferred field unexpectedly populated: #{populated_deferred.join(', ')}" unless populated_deferred.empty?
  selected_rows << [id, needs_levels]
end
abort "AMC Batch 18 target IDs/order changed" unless selected_rows.map(&:first) == EXPECTED_IDS
actual_level_ids = selected_rows.select { |_id, needs_levels| needs_levels }.map(&:first)
abort "AMC Batch 18 conditional Levels IDs changed" unless actual_level_ids == EXPECTED_LEVEL_IDS
preserved_level_ids = selected_rows.reject { |_id, needs_levels| needs_levels }.map(&:first)
abort "AMC Batch 18 preserved Levels count changed" unless preserved_level_ids.length == 8

abort "case count #{rows.length}; expected #{EXPECTED_CALLS}" unless rows.length == EXPECTED_CALLS
abort "run-order count #{order.length}; expected #{EXPECTED_CALLS}" unless order.length == EXPECTED_CALLS
abort "run order has duplicates" unless order.uniq.length == order.length
abort "run order/index mismatch" unless rows.map { |r| r["manifest_path"] } == order

dimension_counts = rows.group_by { |row| row["dimension"] }.transform_values(&:length)
EXPECTED_DIMENSIONS.each do |dimension|
  name = dimension.fetch(0)
  abort "#{name} case count changed" unless dimension_counts[name] == EXPECTED_IDS.length
end
abort "Levels case count changed" unless dimension_counts["Levels"] == EXPECTED_LEVEL_IDS.length
expected_dimension_names = EXPECTED_DIMENSIONS.map(&:first) + ["Levels"]
unexpected_dimensions = dimension_counts.keys - expected_dimension_names
abort "unexpected Batch 18 dimensions: #{unexpected_dimensions.join(', ')}" unless unexpected_dimensions.empty?

expected_rows = []
EXPECTED_IDS.each_with_index do |id, adv_index|
  EXPECTED_DIMENSIONS.each do |dimension|
    expected_rows << [adv_index + 1, id, *dimension]
  end
  expected_rows << [adv_index + 1, id, *EXPECTED_LEVELS] if EXPECTED_LEVEL_IDS.include?(id)
end

rows.each_with_index do |row, index|
  adv_index, id, name, profile, alias_name, _ollama_model, runtime_key, _catalog_column = expected_rows.fetch(index)
  abort "case #{index + 1} adventure index changed" unless Integer(row["adventure_index"]) == adv_index
  abort "case #{index + 1} adventure changed" unless row["adventure_id"] == id
  abort "case #{index + 1} dimension changed" unless row["dimension"] == name
  abort "case #{index + 1} profile changed" unless row["profile"] == profile
  abort "case #{index + 1} model alias changed" unless row["model_alias"] == alias_name
  abort "case #{index + 1} runtime key changed" unless row["runtime_key"] == runtime_key

  relative_manifest = row.fetch("manifest_path")
  manifest_path = File.join(repo_root, relative_manifest)
  abort "missing manifest #{relative_manifest}" unless File.file?(manifest_path)
  data = YAML.safe_load_file(manifest_path, aliases: true)
  abort "wrong manifest model in #{relative_manifest}" unless data["models"] == [alias_name]
  abort "wrong manifest dimension in #{relative_manifest}" unless data["dimension"] == name
  abort "wrong manifest adventure in #{relative_manifest}" unless data["adventures"] == [id]
  abort "replicates != 1 in #{relative_manifest}" unless data["replicates"] == 1
  abort "wrong worker in #{relative_manifest}" unless data["workers"] == ["mac"]
  abort "wrong worker label in #{relative_manifest}" unless data["required_worker_labels"] == ["local"]
  abort "wrong scorer mode in #{relative_manifest}" unless data.dig("scorer", "mode") == "positional"

  extra = data.dig("scorer", "extra_args")
  expected_runtime_path = runtime_files.fetch(runtime_key).fetch("path")
  expected_arg = "${LME_REPO}/#{expected_runtime_path}"
  abort "wrong runtime args in #{relative_manifest}" unless extra == ["--config", expected_arg]

  contract = data.fetch("production_contract")
  abort "wrong contract type in #{relative_manifest}" unless contract["contract_type"] == "adventure_ingest_v1"
  abort "wrong queue in #{relative_manifest}" unless contract["queue"] == "production-backlog-018"
  abort "wrong qualified profile in #{relative_manifest}" unless contract["qualified_profile"] == profile
  expected_contract = contracts_by_name.fetch(name)
  abort "wrong qualification path in #{relative_manifest}" unless contract["source_qualification_path"] == expected_contract.fetch("qualification_path")
  abort "qualification hash drift in #{relative_manifest}" unless contract["source_qualification_sha256"] == expected_contract.fetch("qualification_sha256")
  abort "favorable reruns allowed in #{relative_manifest}" unless contract["no_favorable_rerun"] == true
  abort "external API cost is not zero in #{relative_manifest}" unless contract["external_api_cost_usd"].to_f == 0.0
  abort "wrong cost cap in #{relative_manifest}" unless data["cost_cap_usd"].to_f == 0.01

  case name
  when "Social Interaction Emphasis"
    p = data.dig("phase6_contract", "prompt_profile")
    abort "Social guardrail profile drift" unless p == { "version" => "phase6-v0.3", "env_name" => "AF_SOCIAL_INTERACTION_GUARDRAIL_PROFILE", "env_value" => "phase6-v0.3" }
  when "Investigation Emphasis"
    p = data.dig("phase6_contract", "prompt_profile")
    abort "Investigation guardrail profile drift" unless p == { "version" => "phase6-v0.4", "env_name" => "AF_INVESTIGATION_GUARDRAIL_PROFILE", "env_value" => "phase6-v0.4" }
  else
    abort "unexpected phase6 profile in #{relative_manifest}" if data.key?("phase6_contract")
  end
end

puts "Frozen Batch 18 queue semantics: PASS"
puts "  Adventures: 23"
puts "  Calls: #{EXPECTED_CALLS} (253 ordinary + 15 conditional Levels)"
puts "  Order: adventure-major / 11 ordinary dimensions plus conditional Levels"
puts "  Catalog: #{CATALOG_FILENAME} @ #{CATALOG_SHA256}"
puts "  Levels: 8 preserved pairs / 15 qualified paired-output calls"
puts "  Deferred AFAO columns: preserved blank / not scored"
RUBY

FROZEN_SCORER=$(ruby - "$SNAPSHOT" <<'RUBY'
require "yaml"
print YAML.safe_load_file(ARGV.fetch(0), aliases: true).fetch("scorer_commit")
RUBY
)
ACTIVE_SCORER=$(git -C "$SCORER_REPO" rev-parse HEAD)
[[ "$ACTIVE_SCORER" == "$FROZEN_SCORER" ]] || {
  echo "ERROR: active scorer HEAD is $ACTIVE_SCORER; Batch 18 froze $FROZEN_SCORER"
  exit 1
}

git -C "$SCORER_REPO" diff --quiet -- lib/af_scoring config/default.yml config/source_mappings.yml || {
  echo "ERROR: unstaged scorer/runtime changes touch Batch 18 protected paths"
  exit 1
}
git -C "$SCORER_REPO" diff --cached --quiet -- lib/af_scoring config/default.yml config/source_mappings.yml || {
  echo "ERROR: staged scorer/runtime changes touch Batch 18 protected paths"
  exit 1
}
echo "Scorer checkout: PASS ($ACTIVE_SCORER)"

REPRESENTATIVE_LIST="$(mktemp "${TMPDIR:-/tmp}/af-b018-representative.XXXXXX")" || exit 1
MODEL_LIST="$(mktemp "${TMPDIR:-/tmp}/af-b018-models.XXXXXX")" || {
  rm -f "$REPRESENTATIVE_LIST"
  exit 1
}
trap 'rm -f "$REPRESENTATIVE_LIST" "$MODEL_LIST"' EXIT

ruby - "$INDEX" >"$REPRESENTATIVE_LIST" <<'RUBY'
require "csv"
rows = CSV.read(ARGV.fetch(0), headers: true, encoding: "UTF-8")
seen = {}
rows.each do |row|
  dimension = row["dimension"]
  next if seen[dimension]
  seen[dimension] = true
  puts row["manifest_path"]
end
RUBY

REPRESENTATIVE_COUNT="$(wc -l < "$REPRESENTATIVE_LIST" | tr -d '[:space:]')"
[[ "$REPRESENTATIVE_COUNT" -eq 12 ]] || {
  echo "ERROR: expected 12 representative manifests; found $REPRESENTATIVE_COUNT"
  exit 1
}

echo
echo "Planning one frozen manifest per dimension..."
while IFS= read -r manifest; do
  [[ -n "$manifest" ]] || continue
  bin/lme plan "$manifest" >/dev/null || {
    echo "ERROR: LME plan failed: $manifest"
    exit 1
  }
done < "$REPRESENTATIVE_LIST"
echo "LME manifest planning: PASS (12/12)"

ruby - "$INDEX" >"$MODEL_LIST" <<'RUBY'
require "csv"
rows = CSV.read(ARGV.fetch(0), headers: true, encoding: "UTF-8")
seen = {}
rows.each do |row|
  model = row["model_alias"]
  next if seen[model]
  seen[model] = true
  puts row["manifest_path"]
end
RUBY

MODEL_COUNT="$(wc -l < "$MODEL_LIST" | tr -d '[:space:]')"
[[ "$MODEL_COUNT" -eq 4 ]] || {
  echo "ERROR: expected 4 distinct local model aliases; found $MODEL_COUNT"
  exit 1
}

echo
echo "Checking all four required local Ollama models on worker mac..."
while IFS= read -r manifest; do
  [[ -n "$manifest" ]] || continue
  bin/lme worker-check "$manifest" || {
    echo "ERROR: local worker/model preflight failed: $manifest"
    exit 1
  }
done < "$MODEL_LIST"

echo
echo "BATCH 18 PREFLIGHT: PASS"
echo "  23 adventures"
echo "  11 ordinary scored fields per adventure"
echo "  15 conditional Levels calls (paired Level Start + Level End)"
echo "  268 frozen local inference calls"
echo '  External/API inference cost: $0'
echo "Runtime source resolution is rechecked by run_production_backlog.sh before inference starts."
