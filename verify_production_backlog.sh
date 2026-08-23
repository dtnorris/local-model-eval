#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${LME_REPO:-$SCRIPT_DIR}"
QUEUE_ARG="${1:-}"
QUALIFIED="$REPO/production_backlog/qualified_dimensions.yml"
SCORER_REPO="${AF_SCORER_REPO:-}"

[[ -n "$QUEUE_ARG" ]] || {
  echo "Usage: ./verify_production_backlog.sh production_backlog/QUEUE"
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

if [[ -z "$SCORER_REPO" && -f "$SNAPSHOT" ]]; then
  SNAPSHOT_SCORER=$(ruby - "$SNAPSHOT" <<'RUBY'
require "yaml"
snapshot = YAML.safe_load_file(ARGV.fetch(0))
print snapshot["scorer_repo_path"].to_s
RUBY
)
  if [[ -n "$SNAPSHOT_SCORER" ]]; then
    if [[ "$SNAPSHOT_SCORER" = /* ]]; then
      SCORER_REPO="$SNAPSHOT_SCORER"
    else
      SCORER_REPO="$REPO/$SNAPSHOT_SCORER"
    fi
  fi
fi
if [[ -z "$SCORER_REPO" ]]; then
  SCORER_REPO="$(cd "$REPO/.." && pwd)/af-cli-scoring-utility"
fi
SCORER_REPO="$(cd "$SCORER_REPO" 2>/dev/null && pwd)" || {
  echo "ERROR: scorer checkout not found: $SCORER_REPO"
  exit 1
}

cd "$REPO" || exit 1
[[ -x bin/lme ]] || { echo "ERROR: bin/lme missing/executable"; exit 1; }
[[ -f "$QUALIFIED" ]] || { echo "ERROR: missing $QUALIFIED"; exit 1; }
[[ -f "$SNAPSHOT" ]] || { echo "ERROR: missing $SNAPSHOT"; exit 1; }
[[ -f "$INDEX" ]] || { echo "ERROR: missing $INDEX"; exit 1; }
[[ -f "$ORDER" ]] || { echo "ERROR: missing $ORDER"; exit 1; }
[[ -d "$SCORER_REPO/.git" ]] || { echo "ERROR: adjacent scorer checkout missing: $SCORER_REPO"; exit 1; }

ruby - "$QUALIFIED" "$SNAPSHOT" "$INDEX" "$ORDER" "$SCORER_REPO" "$REPO" <<'RUBY' || exit 1
require "csv"
require "yaml"

qualified_path, snapshot_path, index_path, order_path, scorer_repo, repo_root = ARGV
qualified = YAML.safe_load_file(qualified_path)
snapshot = YAML.safe_load_file(snapshot_path)
rows = CSV.read(index_path, headers: true, encoding: "UTF-8")
order = File.readlines(order_path, chomp: true).reject(&:empty?)

dims = qualified.fetch("dimensions")
dim_names = dims.map { |d| d.fetch("name") }
profiles = dims.to_h { |d| [d.fetch("name"), d.fetch("profile")] }
selected = snapshot.fetch("selected_adventures")
frozen_scorer = snapshot["scorer_repo_path"].to_s
unless frozen_scorer.empty?
  frozen_abs = File.expand_path(frozen_scorer, repo_root)
  abort "queue scorer path changed: snapshot=#{frozen_abs} active=#{scorer_repo}" unless frozen_abs == File.expand_path(scorer_repo)
end
packs = Integer(snapshot.fetch("packs"))
per_pack = Integer(snapshot.fetch("adventures_per_pack"))
expected_adventures = packs * per_pack
expected_calls = expected_adventures * dims.length

abort "snapshot selected adventure count changed" unless selected.length == expected_adventures
abort "case count #{rows.length}; expected #{expected_calls}" unless rows.length == expected_calls
abort "run order count #{order.length}; expected #{expected_calls}" unless order.length == expected_calls
abort "run order has duplicates" unless order.uniq.length == order.length
abort "run order/index mismatch" unless rows.map { |r| r["manifest_path"] } == order

selected_ids = selected.map { |a| a.fetch("id") }
actual_ids = rows.map { |r| r["adventure_id"] }.uniq
abort "case index adventure set/order changed" unless actual_ids == selected_ids

selected.each do |adv|
  abort "#{adv.fetch('id')} exceeds frozen page cap" if Integer(adv.fetch("page_count")) > Integer(snapshot.fetch("max_page_count"))
end

if snapshot["selection_strategy"] == "stratified_page_count_source_diverse"
  strata = snapshot.fetch("page_strata")
  stratum_counts = selected.group_by { |adv| adv.fetch("page_stratum") }.transform_values(&:length)

  strata.each do |stratum|
    name = stratum.fetch("name")
    expected = Integer(stratum.fetch("quota"))
    actual = stratum_counts.fetch(name, 0)
    abort "page stratum #{name} count #{actual}; expected #{expected}" unless actual == expected

    selected.select { |adv| adv.fetch("page_stratum") == name }.each do |adv|
      pages = Integer(adv.fetch("page_count"))
      min_pages = Integer(stratum.fetch("min_pages"))
      max_pages = Integer(stratum.fetch("max_pages"))
      unless pages >= min_pages && pages <= max_pages
        abort "#{adv.fetch('id')} is #{pages} pages but frozen stratum #{name} is #{min_pages}-#{max_pages}"
      end
    end
  end

  source_counts = selected.group_by do |adv|
    value = adv.fetch("source_book", "").to_s.strip
    value.empty? ? "(unknown source)" : value
  end.transform_values(&:length)
  max_per_source = Integer(snapshot.fetch("max_adventures_per_source_book"))
  offenders = source_counts.select { |_source, count| count > max_per_source }
  abort "source-book diversity cap exceeded: #{offenders.inspect}" unless offenders.empty?

  puts "Frozen selection semantics: PASS"
  strata.each { |stratum| puts "  #{stratum.fetch('name')}: #{stratum.fetch('quota')} adventure(s)" }
  puts "  max per source book: #{max_per_source}"
end

counts = Hash.new(0)
rows.each do |row|
  path = row["manifest_path"]
  abort "missing manifest #{path}" unless File.file?(path)
  data = YAML.safe_load_file(path)
  dim = row["dimension"]
  abort "unknown dimension #{dim}" unless dim_names.include?(dim)
  abort "wrong profile in index for #{path}" unless row["profile"] == profiles.fetch(dim)
  abort "wrong model in #{path}" unless data["models"] == ["qwen"]
  abort "wrong dimension in #{path}" unless data["dimension"] == dim
  abort "wrong adventure in #{path}" unless data["adventures"] == [row["adventure_id"]]
  abort "replicates != 1 in #{path}" unless data["replicates"] == 1
  abort "wrong worker in #{path}" unless data["workers"] == ["mac"]
  abort "wrong worker label in #{path}" unless data["required_worker_labels"] == ["local"]
  manifest_scorer = File.expand_path(data.dig("scorer", "repo").to_s, File.dirname(path))
  abort "wrong scorer repo in #{path}: #{manifest_scorer}" unless manifest_scorer == File.expand_path(scorer_repo)
  abort "wrong scorer mode in #{path}" unless data.dig("scorer", "mode") == "positional"
  abort "unexpected scorer args in #{path}" unless data.dig("scorer", "extra_args") == []
  abort "wrong production queue in #{path}" unless data.dig("production_contract", "queue") == snapshot.fetch("queue")
  abort "favorable reruns allowed in #{path}" unless data.dig("production_contract", "no_favorable_rerun") == true
  abort "external API cost is not zero in #{path}" unless data.dig("production_contract", "external_api_cost_usd").to_f == 0.0
  abort "wrong cost cap in #{path}" unless data["cost_cap_usd"].to_f == 0.01

  q = dims.find { |d| d.fetch("name") == dim }
  if q["env_name"]
    contract = data.dig("phase6_contract", "prompt_profile")
    expected = {
      "version" => q.fetch("profile"),
      "env_name" => q.fetch("env_name"),
      "env_value" => q.fetch("env_value")
    }
    abort "qualified prompt contract mismatch in #{path}" unless contract == expected
  end

  counts[dim] += 1
end

dim_names.each do |dim|
  abort "#{dim} count #{counts[dim]}; expected #{expected_adventures}" unless counts[dim] == expected_adventures
end

puts "Frozen queue semantics: PASS"
puts "  Adventures: #{expected_adventures}"
puts "  Dimensions: #{dims.length}"
puts "  Calls: #{expected_calls}"
puts "  Packs: #{packs} × #{per_pack} adventures"
dim_names.each { |dim| puts "  #{dim}: #{counts[dim]} RUN" }
RUBY

EXPECTED_MODEL=$(ruby - "$QUALIFIED" <<'RUBY'
require "yaml"
print YAML.safe_load_file(ARGV.fetch(0)).fetch("ollama_model")
RUBY
)

QUALIFIED_BASE=$(ruby - "$QUALIFIED" <<'RUBY'
require "yaml"
print YAML.safe_load_file(ARGV.fetch(0)).fetch("social_investigation_qualified_scorer_baseline")
RUBY
)

ACTUAL_MODEL=$(ruby - <<'RUBY'
require "yaml"
models = YAML.safe_load_file("config/models.yml")
print models.dig("models", "qwen", "ollama_model")
RUBY
)
[[ "$ACTUAL_MODEL" == "$EXPECTED_MODEL" ]] || {
  echo "ERROR: qwen alias is $ACTUAL_MODEL; expected $EXPECTED_MODEL"
  exit 1
}
echo "Qwen alias: $ACTUAL_MODEL (expected)"

echo
echo "Checking qualified Social/Investigation scorer lineage..."
git -C "$SCORER_REPO" cat-file -e "${QUALIFIED_BASE}^{commit}" 2>/dev/null || {
  echo "ERROR: scorer checkout lacks qualified baseline $QUALIFIED_BASE"
  exit 1
}
git -C "$SCORER_REPO" merge-base --is-ancestor "$QUALIFIED_BASE" HEAD || {
  echo "ERROR: scorer HEAD is not a descendant of qualified baseline $QUALIFIED_BASE"
  exit 1
}

PROTECTED_SCORER_FILES=(
  lib/af_scoring.rb
  lib/af_scoring/prompt_builder.rb
  lib/af_scoring/phase6_social_interaction_guardrail.rb
  lib/af_scoring/phase6_social_interaction_runner_metadata.rb
  lib/af_scoring/phase6_investigation_emphasis_guardrail.rb
  lib/af_scoring/phase6_investigation_emphasis_runner_metadata.rb
)

for protected in "${PROTECTED_SCORER_FILES[@]}"; do
  git -C "$SCORER_REPO" cat-file -e "$QUALIFIED_BASE:$protected" 2>/dev/null || {
    echo "ERROR: qualified baseline is missing protected scorer file $protected"
    exit 1
  }
  [[ -f "$SCORER_REPO/$protected" ]] || {
    echo "ERROR: scorer HEAD is missing protected scorer file $protected"
    exit 1
  }
done

git -C "$SCORER_REPO" diff --quiet "$QUALIFIED_BASE"..HEAD -- "${PROTECTED_SCORER_FILES[@]}" || {
  echo "ERROR: qualified Social/Investigation implementation changed after $QUALIFIED_BASE"
  git -C "$SCORER_REPO" diff --name-only "$QUALIFIED_BASE"..HEAD -- "${PROTECTED_SCORER_FILES[@]}"
  exit 1
}
git -C "$SCORER_REPO" diff --quiet -- "${PROTECTED_SCORER_FILES[@]}" || {
  echo "ERROR: unstaged changes touch qualified Social/Investigation implementation"
  exit 1
}
git -C "$SCORER_REPO" diff --cached --quiet -- "${PROTECTED_SCORER_FILES[@]}" || {
  echo "ERROR: staged changes touch qualified Social/Investigation implementation"
  exit 1
}
echo "Scorer profile lineage: PASS"
echo "  scorer checkout: $SCORER_REPO"
echo "  qualified baseline: $QUALIFIED_BASE"
echo "  scorer HEAD: $(git -C "$SCORER_REPO" rev-parse HEAD)"

echo
echo "Checking exact inference-request provenance support..."
[[ -f "$SCORER_REPO/test/request_provenance_test.rb" ]] || {
  echo "ERROR: scorer request-provenance test is missing."
  echo "Apply af-cli-scoring-utility-inference-request-provenance-v1.patch before running this backlog."
  exit 1
}
(
  cd "$SCORER_REPO" &&
  ruby -Itest test/request_provenance_test.rb >/dev/null
) || {
  echo "ERROR: scorer inference-request provenance tests failed."
  exit 1
}
echo "Inference request provenance: PASS"
echo "  exact provider request is archived before inference"
echo "  raw provider response remains separately preserved"

FIRST_ADV=$(ruby - "$SNAPSHOT" <<'RUBY'
require "yaml"
snapshot = YAML.safe_load_file(ARGV.fetch(0))
print snapshot.fetch("selected_adventures").first.fetch("id")
RUBY
)

echo
echo "Rendering qualified Social/Investigation profiles (zero inference)..."
TMP_PROFILE_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_PROFILE_DIR"' EXIT INT TERM

env \
  AF_SOCIAL_INTERACTION_GUARDRAIL_PROFILE=phase6-v0.3 \
  AF_INVESTIGATION_GUARDRAIL_PROFILE=phase6-v0.4 \
  "$SCORER_REPO/bin/af-score" \
  --model "$EXPECTED_MODEL" \
  --dimension "Social Interaction Emphasis" \
  --preflight \
  --render-preflight "$TMP_PROFILE_DIR/social.json" \
  "$FIRST_ADV" >/dev/null || {
    echo "ERROR: Social qualified-profile preflight failed"
    exit 1
  }

env \
  AF_SOCIAL_INTERACTION_GUARDRAIL_PROFILE=phase6-v0.3 \
  AF_INVESTIGATION_GUARDRAIL_PROFILE=phase6-v0.4 \
  "$SCORER_REPO/bin/af-score" \
  --model "$EXPECTED_MODEL" \
  --dimension "Investigation Emphasis" \
  --preflight \
  --render-preflight "$TMP_PROFILE_DIR/investigation.json" \
  "$FIRST_ADV" >/dev/null || {
    echo "ERROR: Investigation qualified-profile preflight failed"
    exit 1
  }

ruby - "$TMP_PROFILE_DIR/social.json" "$TMP_PROFILE_DIR/investigation.json" <<'RUBY' || exit 1
require "json"
social = JSON.parse(File.read(ARGV.fetch(0)))
investigation = JSON.parse(File.read(ARGV.fetch(1)))

abort "Social profile metadata missing/wrong" unless social.fetch("run_metadata")["social_interaction_guardrail_profile"] == "phase6-v0.3"
abort "Investigation profile metadata missing/wrong" unless investigation.fetch("run_metadata")["investigation_guardrail_profile"] == "phase6-v0.4"

sp = social.fetch("targets").fetch(0).dig("prompt", "input").to_s
ip = investigation.fetch("targets").fetch(0).dig("prompt", "input").to_s
abort "Social v0.3 guardrail absent from rendered prompt" unless sp.include?("Social Interaction Emphasis Cross-Mode Independence Guardrail v0.3")
abort "Investigation v0.4 guardrail absent from rendered prompt" unless ip.include?("Investigation Emphasis Endpoint Boundary Guardrail v0.4")

puts "Qualified prompt activation: PASS"
puts "  Social Interaction Emphasis => phase6-v0.3"
puts "  Investigation Emphasis => phase6-v0.4"
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
[[ "$failed" -eq 0 ]] || {
  echo "ERROR: $failed manifest(s) failed bin/lme plan"
  exit 1
}
TOTAL=$(grep -c '^experiments/' "$ORDER" || true)
echo "All $TOTAL manifests passed bin/lme plan."

echo
echo "Checking local worker and authorized Qwen model..."
FIRST_MANIFEST=$(head -n 1 "$ORDER")
bin/lme worker-check "$FIRST_MANIFEST" || exit 1

echo
echo "PREFLIGHT PASSED — frozen background production queue is ready."
echo "NO INFERENCE WAS RUN."
