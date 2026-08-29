#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${LME_REPO:-$SCRIPT_DIR}"
QUEUE_ARG="${1:-}"
QUALIFIED="$REPO/production_backlog/qualified_gm_preparation_burden.yml"
SCORER_REPO="${AF_SCORER_REPO:-}"

[[ -n "$QUEUE_ARG" ]] || { echo "Usage: ./verify_production_backlog_gmpb.sh production_backlog/QUEUE"; exit 2; }
if [[ "$QUEUE_ARG" = /* ]]; then QUEUE_DIR="$QUEUE_ARG"; else QUEUE_DIR="$REPO/$QUEUE_ARG"; fi
SNAPSHOT="$QUEUE_DIR/snapshot.yml"
INDEX="$QUEUE_DIR/case_index.csv"
ORDER="$QUEUE_DIR/run_order.txt"

[[ -f "$QUALIFIED" ]] || { echo "ERROR: missing $QUALIFIED"; exit 1; }
[[ -f "$SNAPSHOT" ]] || { echo "ERROR: missing $SNAPSHOT"; exit 1; }
[[ -f "$INDEX" ]] || { echo "ERROR: missing $INDEX"; exit 1; }
[[ -f "$ORDER" ]] || { echo "ERROR: missing $ORDER"; exit 1; }

RUNTIME_CONFIG=$(ruby - "$QUALIFIED" "$REPO" <<'RUBY'
require "yaml"
q = YAML.safe_load_file(ARGV.fetch(0))
print File.expand_path(q.fetch("runtime_config_path"), ARGV.fetch(1))
RUBY
)
[[ -f "$RUNTIME_CONFIG" ]] || { echo "ERROR: missing runtime config $RUNTIME_CONFIG"; exit 1; }

if [[ -z "$SCORER_REPO" ]]; then
  SNAPSHOT_SCORER=$(ruby - "$SNAPSHOT" <<'RUBY'
require "yaml"
snapshot = YAML.safe_load_file(ARGV.fetch(0), aliases: true)
print snapshot.fetch("scorer_repo_path")
RUBY
)
  if [[ "$SNAPSHOT_SCORER" = /* ]]; then SCORER_REPO="$SNAPSHOT_SCORER"; else SCORER_REPO="$REPO/$SNAPSHOT_SCORER"; fi
fi

SCORER_REPO="$(cd "$SCORER_REPO" 2>/dev/null && pwd)" || { echo "ERROR: scorer checkout not found: $SCORER_REPO"; exit 1; }
[[ -d "$SCORER_REPO/.git" ]] || { echo "ERROR: scorer checkout lacks .git: $SCORER_REPO"; exit 1; }
cd "$REPO" || exit 1
[[ -x bin/lme ]] || { echo "ERROR: bin/lme missing/executable"; exit 1; }

ruby - "$QUALIFIED" "$RUNTIME_CONFIG" "$SNAPSHOT" "$INDEX" "$ORDER" "$SCORER_REPO" "$REPO" <<'RUBY' || exit 1
require "csv"
require "digest"
require "yaml"

qualified_path, runtime_config_path, snapshot_path, index_path, order_path, scorer_repo, repo_root = ARGV
qualified = YAML.safe_load_file(qualified_path)
runtime = YAML.safe_load_file(runtime_config_path) || {}
snapshot = YAML.safe_load_file(snapshot_path, aliases: true)
rows = CSV.read(index_path, headers: true, encoding: "UTF-8")
order = File.readlines(order_path, chomp: true).reject(&:empty?)

abort "wrong B011 contract type" unless qualified.fetch("contract_type") == "gmpb_local_qualified_v1"
abort "snapshot contract type changed" unless snapshot.fetch("contract_type") == qualified.fetch("contract_type")
abort "qualification contract changed after queue freeze" unless Digest::SHA256.file(qualified_path).hexdigest == snapshot.fetch("qualification_contract_sha256")
abort "snapshot qualification payload changed" unless snapshot.fetch("qualification_contract") == qualified
abort "runtime config changed after queue freeze" unless Digest::SHA256.file(runtime_config_path).hexdigest == snapshot.fetch("runtime_config_sha256")
abort "wrong dimension" unless snapshot.fetch("dimension") == qualified.fetch("dimension") && qualified.fetch("dimension") == "GM Preparation Burden"
abort "wrong profile" unless snapshot.fetch("profile") == qualified.fetch("profile") && qualified.fetch("profile") == "gmpb-v0.6-dependency-fan-out"
abort "wrong model alias" unless snapshot.fetch("model_alias") == qualified.fetch("model_alias")
abort "wrong Ollama model" unless snapshot.fetch("ollama_model") == qualified.fetch("ollama_model")
abort "wrong qualification boundary" unless Integer(snapshot.fetch("max_page_count_exclusive")) == 100 && Integer(qualified.fetch("max_page_count_exclusive")) == 100
abort "wrong reasoning profile" unless snapshot.fetch("reasoning_effort") == "medium" && qualified.fetch("reasoning_effort") == "medium"
abort "wrong max token profile" unless Integer(snapshot.fetch("max_tokens")) == 16_384 && Integer(qualified.fetch("max_tokens")) == 16_384
abort "wrong temperature profile" unless Float(snapshot.fetch("temperature")) == 0.0 && Float(qualified.fetch("temperature")) == 0.0

llm = runtime.fetch("llm")
abort "runtime provider changed" unless llm.fetch("provider") == "ollama"
abort "runtime model changed" unless llm.fetch("model") == qualified.fetch("ollama_model")
abort "runtime reasoning changed" unless llm.fetch("reasoning_effort") == qualified.fetch("reasoning_effort")
abort "runtime max_tokens changed" unless Integer(llm.fetch("max_tokens")) == Integer(qualified.fetch("max_tokens"))

frozen_scorer = File.expand_path(snapshot.fetch("scorer_repo_path"), repo_root)
abort "queue scorer path changed: snapshot=#{frozen_scorer} active=#{scorer_repo}" unless frozen_scorer == File.expand_path(scorer_repo)

selected = snapshot.fetch("selected_adventures")
expected = Integer(snapshot.fetch("expected_calls"))
abort "selected count #{selected.length}; expected #{expected}" unless selected.length == expected
abort "case count #{rows.length}; expected #{expected}" unless rows.length == expected
abort "run order count #{order.length}; expected #{expected}" unless order.length == expected
abort "run order has duplicates" unless order.uniq.length == order.length
abort "run order/index mismatch" unless rows.map { |r| r["manifest_path"] } == order
abort "duplicate adventure IDs in B011" unless selected.map { |a| a.fetch("id") }.uniq.length == selected.length
abort "case index adventure order changed" unless rows.map { |r| r["adventure_id"] } == selected.map { |a| a.fetch("id") }

selected.each do |adv|
  pages = Integer(adv.fetch("page_count"))
  abort "#{adv.fetch('id')} outside qualified Page Count <100 domain" unless pages.positive? && pages < 100
  %w[prompt_sha256 schema_sha256 source_file source_scope afao_version provider model reasoning_effort].each do |key|
    abort "missing frozen #{key} for #{adv.fetch('id')}" if adv[key].nil? || adv[key].to_s.empty?
  end
  abort "#{adv.fetch('id')} frozen AFAO version changed" unless adv["afao_version"] == qualified.fetch("afao_version")
  abort "#{adv.fetch('id')} frozen provider changed" unless adv["provider"] == "ollama"
  abort "#{adv.fetch('id')} frozen model changed" unless adv["model"] == qualified.fetch("ollama_model")
  abort "#{adv.fetch('id')} frozen reasoning changed" unless adv["reasoning_effort"] == qualified.fetch("reasoning_effort")
end

runtime_abs = File.expand_path(runtime_config_path)
rows.each do |row|
  path = row.fetch("manifest_path")
  abort "missing manifest #{path}" unless File.file?(path)
  data = YAML.safe_load_file(path)
  abort "index dimension changed in #{path}" unless row["dimension"] == qualified.fetch("dimension")
  abort "index profile changed in #{path}" unless row["profile"] == qualified.fetch("profile")
  abort "wrong model in #{path}" unless data["models"] == [qualified.fetch("model_alias")]
  abort "wrong dimension in #{path}" unless data["dimension"] == qualified.fetch("dimension")
  abort "wrong adventure in #{path}" unless data["adventures"] == [row["adventure_id"]]
  abort "replicates != 1 in #{path}" unless data["replicates"] == 1
  abort "wrong worker in #{path}" unless data["workers"] == ["mac"]
  abort "wrong worker label in #{path}" unless data["required_worker_labels"] == ["local"]
  manifest_scorer = File.expand_path(data.dig("scorer", "repo").to_s, File.dirname(path))
  abort "wrong scorer repo in #{path}: #{manifest_scorer}" unless manifest_scorer == File.expand_path(scorer_repo)
  abort "wrong scorer mode in #{path}" unless data.dig("scorer", "mode") == "positional"
  extra = data.dig("scorer", "extra_args")
  abort "wrong scorer args in #{path}" unless extra.is_a?(Array) && extra.length == 2 && extra[0] == "--config"
  manifest_runtime = File.expand_path(extra[1].to_s, scorer_repo)
  abort "wrong runtime config in #{path}: #{manifest_runtime}" unless manifest_runtime == runtime_abs
  contract = data.fetch("production_contract")
  abort "wrong production contract in #{path}" unless contract["contract_type"] == qualified.fetch("contract_type")
  abort "wrong production queue in #{path}" unless contract["queue"] == snapshot.fetch("queue")
  abort "wrong qualified profile in #{path}" unless contract["qualified_profile"] == qualified.fetch("profile")
  abort "wrong scorer baseline in #{path}" unless contract["qualified_scorer_baseline"] == qualified.fetch("qualified_scorer_baseline")
  abort "wrong reasoning in #{path}" unless contract["reasoning_effort"] == qualified.fetch("reasoning_effort")
  abort "wrong max_tokens in #{path}" unless Integer(contract["max_tokens"]) == Integer(qualified.fetch("max_tokens"))
  abort "wrong temperature in #{path}" unless Float(contract["temperature"]) == Float(qualified.fetch("temperature"))
  abort "favorable reruns allowed in #{path}" unless contract["no_favorable_rerun"] == true
  abort "external API cost is not zero in #{path}" unless contract["external_api_cost_usd"].to_f == 0.0
  abort "wrong cost cap in #{path}" unless data["cost_cap_usd"].to_f == 0.01
end

puts "Frozen B011 queue semantics: PASS"
puts "  Adventures/calls: #{expected}"
puts "  Dimension: #{qualified.fetch('dimension')}"
puts "  Profile: #{qualified.fetch('profile')}"
puts "  Model: #{qualified.fetch('model_alias')} => #{qualified.fetch('ollama_model')}"
puts "  Runtime: reasoning=#{qualified.fetch('reasoning_effort')} temperature=#{qualified.fetch('temperature')} max_tokens=#{qualified.fetch('max_tokens')}"
RUBY

EXPECTED_ALIAS=$(ruby - "$QUALIFIED" <<'RUBY'
require "yaml"; print YAML.safe_load_file(ARGV.fetch(0)).fetch("model_alias")
RUBY
)
EXPECTED_MODEL=$(ruby - "$QUALIFIED" <<'RUBY'
require "yaml"; print YAML.safe_load_file(ARGV.fetch(0)).fetch("ollama_model")
RUBY
)
ACTUAL_MODEL=$(ruby - "$EXPECTED_ALIAS" <<'RUBY'
require "yaml"; alias_name = ARGV.fetch(0); models = YAML.safe_load_file("config/models.yml"); print models.dig("models", alias_name, "ollama_model").to_s
RUBY
)
[[ "$ACTUAL_MODEL" == "$EXPECTED_MODEL" ]] || { echo "ERROR: $EXPECTED_ALIAS alias is $ACTUAL_MODEL; expected $EXPECTED_MODEL"; exit 1; }
echo "Model alias: $EXPECTED_ALIAS => $ACTUAL_MODEL (expected)"

QUALIFIED_BASE=$(ruby - "$QUALIFIED" <<'RUBY'
require "yaml"; print YAML.safe_load_file(ARGV.fetch(0)).fetch("qualified_scorer_baseline")
RUBY
)
FROZEN_SCORER=$(ruby - "$SNAPSHOT" <<'RUBY'
require "yaml"; print YAML.safe_load_file(ARGV.fetch(0), aliases: true).fetch("scorer_commit")
RUBY
)
ACTIVE_SCORER=$(git -C "$SCORER_REPO" rev-parse HEAD)

echo
echo "Checking qualified GMPB scorer lineage..."
git -C "$SCORER_REPO" cat-file -e "${QUALIFIED_BASE}^{commit}" 2>/dev/null || { echo "ERROR: scorer checkout lacks qualified baseline $QUALIFIED_BASE"; exit 1; }
git -C "$SCORER_REPO" merge-base --is-ancestor "$QUALIFIED_BASE" "$FROZEN_SCORER" || { echo "ERROR: frozen scorer is not a descendant of qualified baseline"; exit 1; }
[[ "$ACTIVE_SCORER" == "$FROZEN_SCORER" ]] || { echo "ERROR: active scorer HEAD is $ACTIVE_SCORER; B011 froze $FROZEN_SCORER"; exit 1; }
echo "GMPB scorer lineage: PASS"
echo "  qualified baseline: $QUALIFIED_BASE"
echo "  frozen runtime:     $FROZEN_SCORER"

CURRENT_CATALOG=$(ruby - "$SCORER_REPO" "$RUNTIME_CONFIG" <<'RUBY'
repo, runtime = ARGV
require File.join(repo, "lib", "af_scoring", "errors")
require File.join(repo, "lib", "af_scoring", "config")
print AFScoring::Config.new(project_root: repo, config_path: runtime).catalog_path
RUBY
)
EXPECTED_CATALOG_FILE=$(ruby - "$SNAPSHOT" <<'RUBY'
require "yaml"; print YAML.safe_load_file(ARGV.fetch(0), aliases: true).fetch("catalog_filename")
RUBY
)
EXPECTED_CATALOG_SHA=$(ruby - "$SNAPSHOT" <<'RUBY'
require "yaml"; print YAML.safe_load_file(ARGV.fetch(0), aliases: true).fetch("catalog_sha256")
RUBY
)
[[ -f "$CURRENT_CATALOG" ]] || { echo "ERROR: configured AMC missing: $CURRENT_CATALOG"; exit 1; }
[[ "$(basename "$CURRENT_CATALOG")" == "$EXPECTED_CATALOG_FILE" ]] || { echo "ERROR: configured AMC is $(basename "$CURRENT_CATALOG"); expected $EXPECTED_CATALOG_FILE"; exit 1; }
ACTUAL_CATALOG_SHA=$(shasum -a 256 "$CURRENT_CATALOG" | awk '{print $1}')
[[ "$ACTUAL_CATALOG_SHA" == "$EXPECTED_CATALOG_SHA" ]] || { echo "ERROR: AMC SHA is $ACTUAL_CATALOG_SHA; expected $EXPECTED_CATALOG_SHA"; exit 1; }

echo
echo "Recomputing exhaustive blank-GMPB AMC population..."
ruby - "$QUALIFIED" "$SNAPSHOT" "$INDEX" "$SCORER_REPO" "$CURRENT_CATALOG" "$REPO" <<'RUBY' || exit 1
require "csv"
require "yaml"

qualified_path, snapshot_path, index_path, scorer_repo, catalog_path, repo_root = ARGV
q = YAML.safe_load_file(qualified_path)
snapshot = YAML.safe_load_file(snapshot_path, aliases: true)

require File.join(scorer_repo, "lib", "af_scoring", "errors")
require File.join(scorer_repo, "lib", "af_scoring", "xlsx_reader")
rows = AFScoring::XlsxReader.new(catalog_path).rows(sheet_name: "Adventure Catalog")
headers = rows.shift.map { |v| v.to_s.strip == "ADV - ID" ? "Adventure ID" : v.to_s.strip }
blank = ->(v) { v.nil? || v.to_s.strip.empty? }
int = ->(v) { begin Integer(Float(v)) rescue nil end }

reserved = {}
queue = snapshot.fetch("queue")
Dir.glob(File.join(repo_root, "production_backlog", "**", "*case_index.csv")).sort.each do |path|
  rel = path.delete_prefix("#{repo_root}/")
  next if rel.start_with?("production_backlog/#{queue}/")
  begin
    rs = CSV.read(path, headers: true, encoding: "UTF-8")
    next unless rs.headers&.include?("adventure_id") && rs.headers&.include?("dimension")
    rs.each do |r|
      next unless r["dimension"].to_s.strip == q.fetch("dimension")
      id = r["adventure_id"].to_s.strip
      reserved[id] = true unless id.empty?
    end
  rescue CSV::MalformedCSVError
  end
end

catalog_ids = []
under = []
prepop = []
eligible = []
rows.each do |row|
  values = headers.zip(row).to_h
  id = values["Adventure ID"].to_s.strip
  next if id.empty?
  catalog_ids << id

  pages = int.call(values["Page Count"])
  start_page = int.call(values["Start Page"])
  end_page = int.call(values["End Page"])
  pages ||= (end_page - start_page + 1) if start_page && end_page && end_page >= start_page
  next unless pages && pages > 0 && pages < Integer(q.fetch("max_page_count_exclusive"))

  under << id
  if blank.call(values[q.fetch("catalog_column")])
    eligible << id unless reserved.key?(id)
  else
    prepop << id
  end
end

duplicates = catalog_ids.tally.select { |_id, count| count > 1 }
abort "AMC duplicate Adventure IDs: #{duplicates.keys.join(', ')}" unless duplicates.empty?
abort "AMC adventure count changed" unless catalog_ids.length == Integer(snapshot.fetch("catalog_total_adventures"))
abort "under-100 population changed" unless under.length == Integer(snapshot.fetch("catalog_under_page_limit"))
abort "prepopulated GMPB count changed" unless prepop.length == Integer(snapshot.fetch("catalog_prepopulated_gmpb"))
abort "same-dimension reservation count changed" unless reserved.length == Integer(snapshot.fetch("catalog_reserved_gmpb"))
abort "eligible blank GMPB count changed" unless eligible.length == Integer(snapshot.fetch("catalog_eligible_blank_gmpb"))

selected = snapshot.fetch("selected_adventures").map { |a| a.fetch("id") }
abort "B011 is not exhaustive or AMC order changed" unless selected == eligible
index_ids = CSV.read(index_path, headers: true, encoding: "UTF-8").map { |r| r["adventure_id"] }
abort "case index no longer matches exhaustive GMPB population" unless index_ids == eligible

puts "AMC population: PASS"
puts "  total adventures: #{catalog_ids.length}"
puts "  Page Count <100: #{under.length}"
puts "  accepted GMPB already present: #{prepop.length}"
puts "  prior GMPB production reservations: #{reserved.length}"
puts "  B011 blank eligible: #{eligible.length}"
RUBY

echo
echo "Checking exact inference-request provenance support..."
[[ -f "$SCORER_REPO/test/request_provenance_test.rb" ]] || { echo "ERROR: scorer request-provenance test missing"; exit 1; }
( cd "$SCORER_REPO" && ruby -Itest test/request_provenance_test.rb >/dev/null ) || { echo "ERROR: scorer inference-request provenance tests failed"; exit 1; }
echo "Inference request provenance: PASS"

echo
echo "Checking frozen Gemma/Ollama request contract..."
ruby -I"$SCORER_REPO/lib" - "$RUNTIME_CONFIG" "$EXPECTED_MODEL" <<'RUBY' || exit 1
require "yaml"
require "af_scoring"

runtime_path, expected_model = ARGV
runtime = YAML.safe_load_file(runtime_path).fetch("llm")
prompt = Struct.new(:instructions, :input).new("system", "user")
schema = {
  "type" => "object",
  "properties" => { "score" => { "type" => "integer" } },
  "required" => ["score"],
  "additionalProperties" => false
}
provider = AFScoring::Providers::OllamaProvider.new(
  model: expected_model,
  reasoning_effort: runtime.fetch("reasoning_effort"),
  max_tokens: runtime.fetch("max_tokens"),
  base_url: "http://127.0.0.1:11434"
)
request = provider.request_artifact(group_name: "gmpb_contract", prompt: prompt, schema: schema)
payload = request.fetch("payload")

abort "provider request model changed" unless payload.fetch("model") == expected_model
abort "reasoning_effort is not medium" unless payload.fetch("reasoning_effort") == "medium"
abort "max_tokens is not 16384" unless Integer(payload.fetch("max_tokens")) == 16_384
abort "temperature is not 0" unless Float(payload.fetch("temperature")) == 0.0
abort "streaming unexpectedly enabled" unless payload.fetch("stream") == false
abort "strict structured output disabled" unless payload.dig("response_format", "json_schema", "strict") == true

puts "Gemma/Ollama request contract: PASS"
RUBY

FIRST_ADV=$(ruby - "$SNAPSHOT" <<'RUBY'
require "yaml"; print YAML.safe_load_file(ARGV.fetch(0), aliases: true).fetch("selected_adventures").first.fetch("id")
RUBY
)
TMP_PROFILE_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_PROFILE_DIR"' EXIT INT TERM
"$SCORER_REPO/bin/af-score" --config "$RUNTIME_CONFIG" --model "$EXPECTED_MODEL" --dimension "GM Preparation Burden" --preflight --render-preflight "$TMP_PROFILE_DIR/gmpb.json" "$FIRST_ADV" >/dev/null || { echo "ERROR: GMPB zero-inference preflight failed"; exit 1; }

ruby - "$TMP_PROFILE_DIR/gmpb.json" "$EXPECTED_MODEL" <<'RUBY' || exit 1
require "json"
data = JSON.parse(File.read(ARGV.fetch(0)))
expected_model = ARGV.fetch(1)
target = data.fetch("targets").fetch(0)
metadata = data.fetch("run_metadata")
input = target.dig("prompt", "input").to_s

abort "wrong AFAO version" unless metadata.fetch("afao_version") == "1.6.1"
abort "preflight provider is not ollama" unless metadata.fetch("provider") == "ollama"
abort "preflight model changed" unless metadata.fetch("model") == expected_model
abort "preflight reasoning is not medium" unless metadata.fetch("reasoning_effort") == "medium"
abort "generic production rules absent from GMPB prompt" unless input.include?("# AdventureFinder Production Assessment Rules")
abort "GMPB v0.6 dependency-fan-out procedure absent" unless input.include?("# GM Preparation Burden 4 ↔ 5 Dependency-Fan-Out Procedure v0.6")
abort "dependency fan-out step absent" unless input.include?("# Step 2 — Evaluate dependency fan-out")
abort "legacy GMPB v0.5 upper-boundary procedure still active" if input.include?("# GM Preparation Burden 4 ↔ 5 Decision Procedure v0.5")
abort "calibration benchmarks contaminated GMPB prompt" if input.include?("#### Calibration Benchmarks")
abort "score-5 benchmark expansion contaminated GMPB prompt" if input.include?("AFAO 1.6 Score-5 Benchmark Expansion and Blind Replication")

puts "Qualified GMPB v0.6 prompt activation: PASS"
RUBY

echo
echo "Checking mac worker scorer environment..."
ruby -I"$REPO/lib" - "$REPO/config/workers.yml" <<'RUBY' || exit 1
require "local_model_evaluation"

workers_path = ARGV.fetch(0)
data = LocalModelEvaluation::Config.load_yaml(workers_path)
mac = data.fetch("workers").fetch("mac")
env = (mac["scorer_env"] || {}).transform_keys(&:to_s).transform_values(&:to_s)

if env.key?("AF_LLM_PROVIDER") && env["AF_LLM_PROVIDER"] != "ollama"
  abort "mac worker overrides AF_LLM_PROVIDER=#{env['AF_LLM_PROVIDER'].inspect}; expected ollama"
end
if env.key?("AF_OPENAI_REASONING_EFFORT") && env["AF_OPENAI_REASONING_EFFORT"] != "medium"
  abort "mac worker overrides AF_OPENAI_REASONING_EFFORT=#{env['AF_OPENAI_REASONING_EFFORT'].inspect}; expected medium"
end
if env.key?("AF_LLM_MAX_TOKENS") && Integer(env["AF_LLM_MAX_TOKENS"]) != 16_384
  abort "mac worker overrides AF_LLM_MAX_TOKENS=#{env['AF_LLM_MAX_TOKENS'].inspect}; expected 16384"
end

puts "Mac worker scorer environment: PASS"
RUBY

echo
echo "Planning all manifests..."
failed=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if ! bin/lme plan "$f" >/dev/null; then
    echo "PLAN FAILED: $f"
    failed=$((failed + 1))
  fi
done < "$ORDER"
[[ "$failed" -eq 0 ]] || { echo "ERROR: $failed manifest(s) failed bin/lme plan"; exit 1; }
TOTAL=$(grep -c '^experiments/' "$ORDER" || true)
echo "All $TOTAL manifests passed bin/lme plan."

echo
echo "Checking local worker and authorized Gemma model..."
FIRST_MANIFEST=$(head -n 1 "$ORDER")
bin/lme worker-check "$FIRST_MANIFEST" || exit 1

echo
echo "PREFLIGHT PASSED — exhaustive qualified GMPB production queue is ready."
echo "NO INFERENCE WAS RUN."
