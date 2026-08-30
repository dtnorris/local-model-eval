#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${LME_REPO:-$SCRIPT_DIR}"
QUEUE_ARG="${1:-}"

QUALIFIED="$REPO/production_backlog/qualified_exploration_emphasis.yml"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ -n "$QUEUE_ARG" ]] || {
  echo "Usage: ./verify_production_backlog_ee.sh production_backlog/QUEUE"
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

[[ -f "$QUALIFIED" ]] || die "missing $QUALIFIED"
[[ -f "$SNAPSHOT" ]] || die "missing $SNAPSHOT"
[[ -f "$INDEX" ]] || die "missing $INDEX"
[[ -f "$ORDER" ]] || die "missing $ORDER"

echo "AdventureFinder Exploration Emphasis production verifier"
echo "Queue: $QUEUE_DIR"
echo

#
# Resolve frozen runtime config.
#
RUNTIME_CONFIG="$(
  ruby - "$QUALIFIED" "$REPO" <<'RUBY'
require "yaml"
q = YAML.safe_load_file(ARGV.fetch(0))
print File.expand_path(q.fetch("runtime_config_path"), ARGV.fetch(1))
RUBY
)"

[[ -f "$RUNTIME_CONFIG" ]] || die "missing runtime config $RUNTIME_CONFIG"

#
# Resolve scorer checkout. AF_SCORER_REPO may override the path, but it must
# resolve to the exact scorer path frozen into the queue snapshot.
#
SCORER_REPO="${AF_SCORER_REPO:-}"

if [[ -z "$SCORER_REPO" ]]; then
  SNAPSHOT_SCORER="$(
    ruby - "$SNAPSHOT" <<'RUBY'
require "yaml"
snapshot = YAML.safe_load_file(ARGV.fetch(0), aliases: true)
print snapshot.fetch("scorer_repo_path")
RUBY
  )"

  if [[ "$SNAPSHOT_SCORER" = /* ]]; then
    SCORER_REPO="$SNAPSHOT_SCORER"
  else
    SCORER_REPO="$REPO/$SNAPSHOT_SCORER"
  fi
fi

SCORER_REPO="$(cd "$SCORER_REPO" 2>/dev/null && pwd)" ||
  die "scorer checkout not found: $SCORER_REPO"

[[ -d "$SCORER_REPO/.git" ]] ||
  die "scorer checkout lacks .git: $SCORER_REPO"

cd "$REPO"

[[ -x bin/lme ]] || die "bin/lme missing or not executable"

#
# Prevent environment variables from silently overriding the frozen runtime
# YAML. AF_OLLAMA_BASE_URL is intentionally allowed because the worker may
# supply its endpoint.
#
check_env_override() {
  local name="$1"
  local expected="$2"
  local actual="${!name:-}"

  [[ -z "$actual" ]] && return 0

  if [[ "$actual" != "$expected" ]]; then
    die "$name=$actual overrides frozen EE value $expected"
  fi
}

check_env_override AF_LLM_PROVIDER "gpt_oss_qualification"
check_env_override AF_OPENAI_MODEL "gpt-oss:20b"
check_env_override AF_OPENAI_REASONING_EFFORT "low"
check_env_override AF_LLM_MAX_TOKENS "16384"

echo "Environment override gate: PASS"

#
# Static frozen-queue semantics.
#
ruby - \
  "$QUALIFIED" \
  "$RUNTIME_CONFIG" \
  "$SNAPSHOT" \
  "$INDEX" \
  "$ORDER" \
  "$SCORER_REPO" \
  "$REPO" <<'RUBY'

require "csv"
require "digest"
require "yaml"

qualified_path,
runtime_config_path,
snapshot_path,
index_path,
order_path,
scorer_repo,
repo_root = ARGV

qualified = YAML.safe_load_file(qualified_path)
runtime = YAML.safe_load_file(runtime_config_path) || {}
snapshot = YAML.safe_load_file(snapshot_path, aliases: true)
rows = CSV.read(index_path, headers: true, encoding: "UTF-8")
order = File.readlines(order_path, chomp: true).reject(&:empty?)

abort "wrong EE contract type" unless
  qualified.fetch("contract_type") == "ee_local_qualified_v1"

abort "wrong EE dimension" unless
  qualified.fetch("dimension") == "Exploration Emphasis"

abort "wrong EE model alias" unless
  qualified.fetch("model_alias") == "gptoss"

abort "wrong EE Ollama model" unless
  qualified.fetch("ollama_model") == "gpt-oss:20b"

abort "wrong EE provider" unless
  qualified.fetch("provider") == "gpt_oss_qualification"

abort "wrong reasoning profile" unless
  qualified.fetch("reasoning_effort") == "low"

abort "wrong max-token profile" unless
  Integer(qualified.fetch("max_tokens")) == 16_384

abort "wrong temperature" unless
  Float(qualified.fetch("temperature")) == 1.0

abort "wrong top_p" unless
  Float(qualified.fetch("top_p")) == 1.0

abort "wrong seed" unless
  Integer(qualified.fetch("seed")) == 42

abort "production replicate contract changed" unless
  Integer(qualified.fetch("replicates")) == 1

abort "favorable reruns unexpectedly allowed" unless
  qualified.fetch("no_favorable_rerun") == true

abort "external API cost is not zero" unless
  qualified.fetch("external_api_cost_usd").to_f == 0.0

#
# First-wave contract.
#
first_wave = qualified.fetch("first_wave")

abort "first wave must contain exactly 40 calls" unless
  Integer(first_wave.fetch("calls")) == 40

abort "first-wave max page count must remain 60" unless
  Integer(first_wave.fetch("max_page_count")) == 60

#
# Qualification/runtime files must be exactly what the queue froze.
#
abort "snapshot contract type changed" unless
  snapshot.fetch("contract_type") == qualified.fetch("contract_type")

abort "qualification contract changed after queue freeze" unless
  Digest::SHA256.file(qualified_path).hexdigest ==
    snapshot.fetch("qualification_contract_sha256")

abort "snapshot qualification payload changed" unless
  snapshot.fetch("qualification_contract") == qualified

abort "runtime config changed after queue freeze" unless
  Digest::SHA256.file(runtime_config_path).hexdigest ==
    snapshot.fetch("runtime_config_sha256")

#
# Runtime YAML.
#
llm = runtime.fetch("llm")

abort "runtime provider changed" unless
  llm.fetch("provider") == "gpt_oss_qualification"

abort "runtime model changed" unless
  llm.fetch("model") == "gpt-oss:20b"

abort "runtime reasoning changed" unless
  llm.fetch("reasoning_effort") == "low"

abort "runtime max_tokens changed" unless
  Integer(llm.fetch("max_tokens")) == 16_384

#
# Snapshot identity.
#
abort "snapshot dimension changed" unless
  snapshot.fetch("dimension") == "Exploration Emphasis"

abort "snapshot profile changed" unless
  snapshot.fetch("profile") == qualified.fetch("profile")

abort "snapshot model alias changed" unless
  snapshot.fetch("model_alias") == "gptoss"

abort "snapshot model changed" unless
  snapshot.fetch("ollama_model") == "gpt-oss:20b"

abort "snapshot reasoning changed" unless
  snapshot.fetch("reasoning_effort") == "low"

abort "snapshot max tokens changed" unless
  Integer(snapshot.fetch("max_tokens")) == 16_384

#
# Freeze scorer location.
#
frozen_scorer =
  File.expand_path(snapshot.fetch("scorer_repo_path"), repo_root)

abort(
  "queue scorer path changed: " \
  "snapshot=#{frozen_scorer} active=#{scorer_repo}"
) unless frozen_scorer == File.expand_path(scorer_repo)

#
# Exactly 40 unique first-pass cases.
#
selected = snapshot.fetch("selected_adventures")
expected = Integer(snapshot.fetch("expected_calls"))

abort "snapshot expected_calls must equal 40, got #{expected}" unless expected == 40
abort "selected count #{selected.length}; expected 40" unless selected.length == 40
abort "case count #{rows.length}; expected 40" unless rows.length == 40
abort "run-order count #{order.length}; expected 40" unless order.length == 40

abort "run order has duplicates" unless
  order.uniq.length == order.length

abort "duplicate selected Adventure IDs" unless
  selected.map { |a| a.fetch("id") }.uniq.length == selected.length

abort "run order/index mismatch" unless
  rows.map { |r| r["manifest_path"] } == order

abort "case-index adventure order changed" unless
  rows.map { |r| r["adventure_id"] } ==
    selected.map { |a| a.fetch("id") }

#
# Every selected adventure must remain inside the first-wave page envelope,
# and must contain frozen zero-inference provenance.
#
selected.each do |adv|
  pages = Integer(adv.fetch("page_count"))

  abort "#{adv.fetch('id')} has invalid page count #{pages}" unless pages.positive?

  abort "#{adv.fetch('id')} exceeds first-wave 60-page envelope" unless
    pages <= 60

  %w[
    prompt_sha256
    schema_sha256
    source_file
    source_scope
    afao_version
    provider
    model
    reasoning_effort
  ].each do |key|
    value = adv[key]
    abort "missing frozen #{key} for #{adv.fetch('id')}" if
      value.nil? || value.to_s.empty?
  end

  abort "#{adv.fetch('id')} frozen AFAO version changed" unless
    adv["afao_version"] == qualified.fetch("afao_version")

  abort "#{adv.fetch('id')} frozen provider changed" unless
    adv["provider"] == "gpt_oss_qualification"

  abort "#{adv.fetch('id')} frozen model changed" unless
    adv["model"] == "gpt-oss:20b"

  abort "#{adv.fetch('id')} frozen reasoning changed" unless
    adv["reasoning_effort"] == "low"
end

#
# Every generated manifest must encode exactly the same contract.
#
runtime_abs = File.expand_path(runtime_config_path)

rows.each do |row|
  path = row.fetch("manifest_path")

  abort "missing manifest #{path}" unless File.file?(path)

  data = YAML.safe_load_file(path)

  abort "index dimension changed in #{path}" unless
    row["dimension"] == "Exploration Emphasis"

  abort "index profile changed in #{path}" unless
    row["profile"] == qualified.fetch("profile")

  abort "wrong model alias in #{path}" unless
    data["models"] == ["gptoss"]

  abort "wrong dimension in #{path}" unless
    data["dimension"] == "Exploration Emphasis"

  abort "wrong adventure in #{path}" unless
    data["adventures"] == [row["adventure_id"]]

  abort "replicates != 1 in #{path}" unless
    data["replicates"] == 1

  abort "wrong worker in #{path}" unless
    data["workers"] == ["mac"]

  abort "wrong required worker labels in #{path}" unless
    data["required_worker_labels"] == ["local"]

  manifest_scorer =
    File.expand_path(
      data.dig("scorer", "repo").to_s,
      File.dirname(path)
    )

  abort "wrong scorer repo in #{path}: #{manifest_scorer}" unless
    manifest_scorer == File.expand_path(scorer_repo)

  abort "wrong scorer mode in #{path}" unless
    data.dig("scorer", "mode") == "positional"

  extra = data.dig("scorer", "extra_args")

  abort "wrong scorer args in #{path}" unless
    extra.is_a?(Array) &&
    extra.length == 2 &&
    extra[0] == "--config"

  expected_runtime_arg =
    "${LME_REPO}/#{qualified.fetch('runtime_config_path')}"

  abort "non-portable runtime config arg in #{path}: #{extra[1].inspect}" unless
    extra[1] == expected_runtime_arg

  manifest_runtime =
    File.expand_path(extra[1].sub("${LME_REPO}", repo_root))

  abort "wrong runtime config in #{path}: #{manifest_runtime}" unless
    manifest_runtime == runtime_abs

  contract = data.fetch("production_contract")

  abort "wrong production contract in #{path}" unless
    contract["contract_type"] == "ee_local_qualified_v1"

  abort "wrong production queue in #{path}" unless
    contract["queue"] == snapshot.fetch("queue")

  abort "wrong qualified profile in #{path}" unless
    contract["qualified_profile"] == qualified.fetch("profile")

  abort "wrong scorer baseline in #{path}" unless
    contract["qualified_scorer_baseline"] ==
      qualified.fetch("qualified_scorer_baseline")

  abort "wrong reasoning in #{path}" unless
    contract["reasoning_effort"] == "low"

  abort "wrong max_tokens in #{path}" unless
    Integer(contract["max_tokens"]) == 16_384

  abort "wrong temperature in #{path}" unless
    Float(contract["temperature"]) == 1.0

  abort "wrong top_p in #{path}" unless
    Float(contract["top_p"]) == 1.0

  abort "wrong seed in #{path}" unless
    Integer(contract["seed"]) == 42

  abort "favorable reruns allowed in #{path}" unless
    contract["no_favorable_rerun"] == true

  abort "external API cost is not zero in #{path}" unless
    contract["external_api_cost_usd"].to_f == 0.0

  abort "wrong cost cap in #{path}" unless
    data["cost_cap_usd"].to_f == 0.01
end

puts "Frozen EE B001 queue semantics: PASS"
puts "  Adventures/calls: 40"
puts "  Dimension: Exploration Emphasis"
puts "  Profile: #{qualified.fetch('profile')}"
puts "  Model: gptoss => gpt-oss:20b"
puts "  Provider: gpt_oss_qualification"
puts "  Runtime: reasoning=low max_tokens=16384 temperature=1 top_p=1 seed=42"
RUBY

echo

#
# Confirm local-model-eval's model alias still points at the qualified model.
#
EXPECTED_MODEL="$(
  ruby - <<'RUBY'
require "yaml"
models = YAML.safe_load_file("config/models.yml")
print models.dig("models", "gptoss", "ollama_model").to_s
RUBY
)"

[[ "$EXPECTED_MODEL" == "gpt-oss:20b" ]] ||
  die "gptoss alias is $EXPECTED_MODEL; expected gpt-oss:20b"

echo "Model alias: gptoss => gpt-oss:20b (expected)"

#
# Scorer lineage: the active checkout must still be the exact scorer commit
# frozen when this production queue was prepared, and that commit must descend
# from the qualified EE baseline.
#
QUALIFIED_BASE="$(
  ruby - "$QUALIFIED" <<'RUBY'
require "yaml"
print YAML.safe_load_file(ARGV.fetch(0)).fetch("qualified_scorer_baseline")
RUBY
)"

FROZEN_SCORER="$(
  ruby - "$SNAPSHOT" <<'RUBY'
require "yaml"
print YAML.safe_load_file(ARGV.fetch(0), aliases: true).fetch("scorer_commit")
RUBY
)"

ACTIVE_SCORER="$(git -C "$SCORER_REPO" rev-parse HEAD)"

echo
echo "Checking qualified EE scorer lineage..."

git -C "$SCORER_REPO" cat-file -e "${QUALIFIED_BASE}^{commit}" 2>/dev/null ||
  die "scorer checkout lacks qualified baseline $QUALIFIED_BASE"

git -C "$SCORER_REPO" merge-base --is-ancestor \
  "$QUALIFIED_BASE" "$FROZEN_SCORER" ||
  die "frozen scorer is not a descendant of qualified EE baseline"

[[ "$ACTIVE_SCORER" == "$FROZEN_SCORER" ]] ||
  die "active scorer HEAD is $ACTIVE_SCORER; queue froze $FROZEN_SCORER"

echo "EE scorer lineage: PASS"
echo "  qualified baseline: $QUALIFIED_BASE"
echo "  frozen runtime:     $FROZEN_SCORER"

#
# Dedicated EE prompt regression suite.
#
echo
echo "Running EE blind-reset regression tests..."

(
  cd "$SCORER_REPO"
  bundle exec ruby -Itest test/ee_blind_prompt_reset_test.rb
)

echo "EE blind-reset tests: PASS"

#
# Confirm the scorer's hard-coded GPT-OSS qualification provider still has the
# exact generation contract used for qualification.
#
echo
echo "Checking GPT-OSS qualification provider contract..."

ruby - "$SCORER_REPO" <<'RUBY'
scorer_repo = ARGV.fetch(0)

require File.join(scorer_repo, "lib", "af_scoring")

profile = AFScoring::GptOssQualificationProfile

abort "GPT-OSS model changed" unless
  profile::MODEL == "gpt-oss:20b"

abort "GPT-OSS reasoning changed" unless
  profile::REASONING_EFFORT == "low"

abort "GPT-OSS max tokens changed" unless
  profile::MAX_TOKENS == 16_384

abort "GPT-OSS temperature changed" unless
  profile::TEMPERATURE == 1.0

abort "GPT-OSS top_p changed" unless
  profile::TOP_P == 1.0

abort "GPT-OSS seed changed" unless
  profile::SEED == 42

Prompt = Struct.new(:instructions, :input)

provider =
  AFScoring::GptOssQualificationOllamaProvider.new(
    base_url: "http://127.0.0.1:11434"
  )

artifact = provider.request_artifact(
  group_name: "play_mix",
  prompt: Prompt.new("verification only", "verification only"),
  schema: {
    "type" => "object",
    "properties" => {},
    "additionalProperties" => false
  }
)

payload = artifact.fetch("payload")

abort "request model changed" unless
  payload.fetch("model") == "gpt-oss:20b"

abort "request reasoning changed" unless
  payload.fetch("reasoning_effort") == "low"

abort "request max_tokens changed" unless
  Integer(payload.fetch("max_tokens")) == 16_384

abort "request temperature changed" unless
  Float(payload.fetch("temperature")) == 1.0

abort "request top_p changed" unless
  Float(payload.fetch("top_p")) == 1.0

abort "request seed changed" unless
  Integer(payload.fetch("seed")) == 42

abort "request unexpectedly streams" unless
  payload.fetch("stream") == false

format = payload.fetch("response_format")

abort "structured output is no longer json_schema" unless
  format.fetch("type") == "json_schema"

abort "structured output is no longer strict" unless
  format.fetch("json_schema").fetch("strict") == true

puts "GPT-OSS qualification provider: PASS"
puts "  model=gpt-oss:20b"
puts "  reasoning=low"
puts "  max_tokens=16384"
puts "  temperature=1"
puts "  top_p=1"
puts "  seed=42"
puts "  strict JSON schema=true"
RUBY

#
# Verify current configured AMC is exactly the AMC frozen into the queue.
#
CURRENT_CATALOG="$(
  ruby - "$SCORER_REPO" "$RUNTIME_CONFIG" <<'RUBY'
repo, runtime = ARGV

require File.join(repo, "lib", "af_scoring", "errors")
require File.join(repo, "lib", "af_scoring", "config")

print AFScoring::Config.new(
  project_root: repo,
  config_path: runtime
).catalog_path
RUBY
)"

EXPECTED_CATALOG_FILE="$(
  ruby - "$SNAPSHOT" <<'RUBY'
require "yaml"
print YAML.safe_load_file(ARGV.fetch(0), aliases: true).fetch("catalog_filename")
RUBY
)"

EXPECTED_CATALOG_SHA="$(
  ruby - "$SNAPSHOT" <<'RUBY'
require "yaml"
print YAML.safe_load_file(ARGV.fetch(0), aliases: true).fetch("catalog_sha256")
RUBY
)"

[[ -f "$CURRENT_CATALOG" ]] ||
  die "configured AMC missing: $CURRENT_CATALOG"

[[ "$(basename "$CURRENT_CATALOG")" == "$EXPECTED_CATALOG_FILE" ]] ||
  die "configured AMC is $(basename "$CURRENT_CATALOG"); expected $EXPECTED_CATALOG_FILE"

ACTUAL_CATALOG_SHA="$(shasum -a 256 "$CURRENT_CATALOG" | awk '{print $1}')"

[[ "$ACTUAL_CATALOG_SHA" == "$EXPECTED_CATALOG_SHA" ]] ||
  die "AMC SHA is $ACTUAL_CATALOG_SHA; expected $EXPECTED_CATALOG_SHA"

echo
echo "Frozen AMC: PASS"
echo "  $(basename "$CURRENT_CATALOG")"
echo "  $ACTUAL_CATALOG_SHA"

#
# Recheck the selected AMC cells. Every selected EE cell must still be blank,
# IDs/pages must still agree with the frozen snapshot, and Page Count must
# remain <=60.
#
echo
echo "Rechecking selected EE AMC cells..."

ruby - \
  "$SNAPSHOT" \
  "$SCORER_REPO" \
  "$CURRENT_CATALOG" <<'RUBY'

require "yaml"

snapshot_path, scorer_repo, catalog_path = ARGV

snapshot = YAML.safe_load_file(snapshot_path, aliases: true)
selected = snapshot.fetch("selected_adventures")
selected_by_id = selected.to_h { |adv| [adv.fetch("id"), adv] }

require File.join(scorer_repo, "lib", "af_scoring", "errors")
require File.join(scorer_repo, "lib", "af_scoring", "xlsx_reader")

rows =
  AFScoring::XlsxReader.new(catalog_path)
                       .rows(sheet_name: "Adventure Catalog")

abort "AMC Adventure Catalog is empty" if rows.empty?

headers = rows.shift.map do |value|
  header = value.to_s.strip
  header == "ADV - ID" ? "Adventure ID" : header
end

required = [
  "Adventure ID",
  "Page Count",
  "Start Page",
  "End Page",
  "Exploration Emphasis"
]

missing = required - headers
abort "AMC missing columns: #{missing.join(', ')}" unless missing.empty?

def blank?(value)
  value.nil? || value.to_s.strip.empty?
end

def integer_or_nil(value)
  return nil if blank?(value)
  Integer(Float(value))
rescue ArgumentError, TypeError
  nil
end

seen = {}

rows.each do |row|
  values = headers.zip(row).to_h
  id = values["Adventure ID"].to_s.strip

  next unless selected_by_id.key?(id)

  abort "duplicate selected AMC row #{id}" if seen[id]
  seen[id] = true

  frozen = selected_by_id.fetch(id)

  page_count = integer_or_nil(values["Page Count"])
  start_page = integer_or_nil(values["Start Page"])
  end_page = integer_or_nil(values["End Page"])

  page_count ||=
    (end_page - start_page + 1) if
      start_page && end_page && end_page >= start_page

  abort "#{id} page count missing" unless page_count

  abort "#{id} AMC page count #{page_count} != frozen #{frozen.fetch('page_count')}" unless
    page_count == Integer(frozen.fetch("page_count"))

  abort "#{id} now exceeds first-wave 60-page boundary" unless
    page_count <= 60

  abort "#{id} Exploration Emphasis is no longer blank" unless
    blank?(values["Exploration Emphasis"])
end

missing_ids = selected_by_id.keys - seen.keys

abort "selected IDs disappeared from AMC: #{missing_ids.join(', ')}" unless
  missing_ids.empty?

puts "Selected EE AMC cells: PASS"
puts "  40/40 still blank"
puts "  40/40 Page Count <= 60"
RUBY

#
# Re-render all 40 scorer preflights and compare prompt/schema/source identity
# against the fingerprints frozen when the queue was prepared.
#
echo
echo "Re-rendering 40 zero-inference EE preflights..."

ruby - \
  "$QUALIFIED" \
  "$RUNTIME_CONFIG" \
  "$SNAPSHOT" \
  "$SCORER_REPO" <<'RUBY'

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

qualified_path, runtime_config_path, snapshot_path, scorer_repo = ARGV

qualified = YAML.safe_load_file(qualified_path)
snapshot = YAML.safe_load_file(snapshot_path, aliases: true)

selected = snapshot.fetch("selected_adventures")

selected.each_with_index do |adv, index|
  id = adv.fetch("id")

  Dir.mktmpdir("af-ee-verify") do |dir|
    rendered = File.join(dir, "preflight.json")

    command = [
      File.join(scorer_repo, "bin", "af-score"),
      "--config", runtime_config_path,
      "--dimension", "Exploration Emphasis",
      "--preflight",
      "--render-preflight", rendered,
      id
    ]

    env = ENV.to_h.dup

    # Avoid accidental model/runtime overrides while preserving the worker's
    # Ollama endpoint if one is configured.
    env.delete("AF_LLM_PROVIDER")
    env.delete("AF_OPENAI_MODEL")
    env.delete("AF_OPENAI_REASONING_EFFORT")
    env.delete("AF_LLM_MAX_TOKENS")

    stdout, stderr, status =
      Open3.capture3(env, *command, chdir: scorer_repo)

    unless status.success?
      abort(
        "#{id} zero-inference preflight failed:\n" \
        "#{stdout}\n#{stderr}"
      )
    end

    data = JSON.parse(File.read(rendered))
    target = data.fetch("targets").fetch(0)
    metadata = data.fetch("run_metadata")

    abort "#{id} preflight target count changed" unless
      data.fetch("targets").length == 1

    abort "#{id} preflight dimension changed" unless
      target.fetch("dimensions") == ["Exploration Emphasis"]

    checks = {
      "prompt_sha256" => target.fetch("prompt_sha256"),
      "schema_sha256" => target.fetch("schema_sha256"),
      "source_file" => data.fetch("source_file"),
      "source_scope" => data.fetch("source_scope"),
      "afao_version" => metadata.fetch("afao_version"),
      "provider" => metadata.fetch("provider"),
      "model" => metadata.fetch("model"),
      "reasoning_effort" => metadata.fetch("reasoning_effort")
    }

    checks.each do |key, current|
      frozen = adv.fetch(key)

      abort(
        "#{id} #{key} drifted:\n" \
        "  frozen:  #{frozen.inspect}\n" \
        "  current: #{current.inspect}"
      ) unless current == frozen
    end

    puts format(
      "PREFLIGHT %2d/40  %-9s  PASS",
      index + 1,
      id
    )
  end
end

puts "Zero-inference prompt/source/schema fingerprints: PASS"
RUBY

#
# All manifests must still be plannable by LME.
#
echo
echo "Checking all 40 LME manifests..."

COUNT=0

while IFS= read -r manifest; do
  [[ -n "$manifest" ]] || continue

  COUNT=$((COUNT + 1))

  bin/lme plan "$manifest" >/dev/null ||
    die "bin/lme plan failed for $manifest"

  printf "PLAN      %2d/40  PASS  %s\n" "$COUNT" "$manifest"
done < "$ORDER"

[[ "$COUNT" -eq 40 ]] ||
  die "planned $COUNT manifests; expected 40"

echo "All LME manifests: PASS"

#
# One worker-check is sufficient because static verification above proves all
# manifests use the same gptoss model and mac/local worker contract.
#
FIRST_MANIFEST="$(head -n 1 "$ORDER")"

[[ -n "$FIRST_MANIFEST" ]] ||
  die "run_order.txt is empty"

echo
echo "Checking local worker + GPT-OSS availability..."

bin/lme worker-check "$FIRST_MANIFEST"

echo
echo "============================================================"
echo "EE B001 PREFLIGHT PASS — NO INFERENCE WAS RUN"
echo "============================================================"
echo "Cases:       40"
echo "Dimension:   Exploration Emphasis"
echo "Model:       gpt-oss:20b"
echo "Provider:    gpt_oss_qualification"
echo "Reasoning:   low"
echo "Max tokens:  16384"
echo "Temperature: 1"
echo "Top-p:       1"
echo "Seed:        42"
echo "Page domain: <=60"
echo "Replicates:  1"
echo "API cost:    \$0"
echo
echo "Next:"
echo "  run the frozen production-ee-b001 first-pass queue"
