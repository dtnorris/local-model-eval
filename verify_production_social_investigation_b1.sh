#!/bin/zsh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${LME_REPO:-$SCRIPT_DIR}"
ORDER="$SCRIPT_DIR/production_social_investigation_b1_run_order.txt"
INDEX="$SCRIPT_DIR/production_social_investigation_b1_case_index.csv"
SCORER_REPO="$(cd "$REPO/.." && pwd)/af-cli-scoring-utility"

EXPECTED_RUNS=63
EXPECTED_MATRIX=66
EXPECTED_SKIPS=3
EXPECTED_MODEL="qwen3.6:35b-a3b"
QUALIFIED_SCORER_BASE="e49a198b36774d47ef136699573b6db6632032bc"

SOCIAL_ENV="AF_SOCIAL_INTERACTION_GUARDRAIL_PROFILE"
SOCIAL_PROFILE="phase6-v0.3"
INVESTIGATION_ENV="AF_INVESTIGATION_GUARDRAIL_PROFILE"
INVESTIGATION_PROFILE="phase6-v0.4"

cd "$REPO" || { echo "ERROR: Could not find $REPO"; exit 1; }
[[ -x bin/lme ]] || { echo "ERROR: bin/lme not found/executable in $REPO"; exit 1; }
[[ -f "$ORDER" ]] || { echo "ERROR: missing $ORDER"; exit 1; }
[[ -f "$INDEX" ]] || { echo "ERROR: missing $INDEX"; exit 1; }
[[ -d "$SCORER_REPO/.git" ]] || { echo "ERROR: adjacent scorer checkout not found: $SCORER_REPO"; exit 1; }
[[ -x "$SCORER_REPO/bin/af-score" ]] || { echo "ERROR: scorer executable missing: $SCORER_REPO/bin/af-score"; exit 1; }

actual=$(grep -c '^experiments/' "$ORDER" || true)
echo "Run manifest count: $actual (expected $EXPECTED_RUNS)"
[[ "$actual" -eq "$EXPECTED_RUNS" ]] || { echo "ERROR: wrong run manifest count"; exit 1; }

dups=$(sort "$ORDER" | uniq -d)
[[ -z "$dups" ]] || { echo "ERROR: duplicate manifest paths:"; echo "$dups"; exit 1; }

ruby - "$INDEX" "$ORDER" <<'RUBY' || exit 1
require "csv"
require "yaml"
Encoding.default_external = Encoding::UTF_8

index_path, order_path = ARGV
rows = CSV.read(index_path, headers: true, encoding: "UTF-8")
abort "case index must contain 66 matrix cells" unless rows.length == 66

run_rows = rows.select { |r| r["action"] == "RUN" }
skip_rows = rows.select { |r| r["action"] == "SKIP_ACCEPTED_AFAO" }
abort "case index must contain 63 RUN cells" unless run_rows.length == 63
abort "case index must contain 3 protected skips" unless skip_rows.length == 3

expected_adventures = %w[
  ADV-0278 ADV-0200 ADV-0230 ADV-0031 ADV-0257 ADV-0288 ADV-0092 ADV-0232
  ADV-0223 ADV-0189 ADV-0248 ADV-0227 ADV-0335 ADV-0032 ADV-0337 ADV-0345
  ADV-0234 ADV-0229 ADV-0323 ADV-0168 ADV-0132 ADV-0150 ADV-0135 ADV-0162
  ADV-0169 ADV-0170 ADV-0198 ADV-0013 ADV-0185 ADV-0195 ADV-0046 ADV-0033
  ADV-0020
]
expected_dimensions = ["Social Interaction Emphasis", "Investigation Emphasis"]

matrix_pairs = rows.map { |r| [r["adventure_id"], r["dimension"]] }
expected_pairs = expected_adventures.flat_map { |adv| expected_dimensions.map { |dim| [adv, dim] } }
abort "66-cell matrix order/content changed" unless matrix_pairs == expected_pairs

expected_paths = run_rows.map { |r| r["manifest_path"] }
order_paths = File.readlines(order_path, chomp: true).reject(&:empty?)
abort "run order does not exactly match RUN rows in case index" unless order_paths == expected_paths

expected_profile = {
  "Social Interaction Emphasis" => {
    "version" => "phase6-v0.3",
    "env_name" => "AF_SOCIAL_INTERACTION_GUARDRAIL_PROFILE",
    "env_value" => "phase6-v0.3"
  },
  "Investigation Emphasis" => {
    "version" => "phase6-v0.4",
    "env_name" => "AF_INVESTIGATION_GUARDRAIL_PROFILE",
    "env_value" => "phase6-v0.4"
  }
}

actual_counts = Hash.new(0)
seen = {}

run_rows.each do |row|
  path = row["manifest_path"]
  abort "missing manifest: #{path}" unless File.file?(path)
  data = YAML.safe_load_file(path)
  adv = row["adventure_id"]
  dim = row["dimension"]
  key = [adv, dim]
  abort "duplicate production cell #{key.join(' / ')}" if seen[key]
  seen[key] = true

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
  abort "wrong production disposition in #{path}" unless data.dig("production_contract", "disposition") == "local-qualified"
  abort "favorable reruns must be forbidden in #{path}" unless data.dig("production_contract", "no_favorable_rerun") == true
  abort "external API cost must be zero in #{path}" unless data.dig("production_contract", "external_api_cost_usd").to_f == 0.0

  profile = data.dig("phase6_contract", "prompt_profile")
  abort "missing profile contract in #{path}" unless profile == expected_profile.fetch(dim)
  abort "index/profile mismatch in #{path}" unless row["profile"] == profile.fetch("version")
  actual_counts[dim] += 1
end

expected_counts = {
  "Social Interaction Emphasis" => 31,
  "Investigation Emphasis" => 32
}
abort "dimension counts mismatch: #{actual_counts.inspect}" unless actual_counts == expected_counts

skips = skip_rows.map { |r| [r["adventure_id"], r["dimension"], r["existing_score"]] }
expected_skips = [
  ["ADV-0257", "Social Interaction Emphasis", "4"],
  ["ADV-0234", "Investigation Emphasis", "5"],
  ["ADV-0229", "Social Interaction Emphasis", "5"]
]
abort "protected accepted cells mismatch: #{skips.inspect}" unless skips == expected_skips

puts "Matrix semantics: PASS"
puts "  Social Interaction Emphasis: #{actual_counts["Social Interaction Emphasis"]} RUN"
puts "  Investigation Emphasis: #{actual_counts["Investigation Emphasis"]} RUN"
puts "  Protected accepted skips: #{skip_rows.length}"
RUBY

ruby - <<'RUBY' || exit 1
require "yaml"
models = YAML.safe_load_file("config/models.yml")
actual = models.dig("models", "qwen", "ollama_model")
expected = "qwen3.6:35b-a3b"
abort "ERROR: qwen alias is #{actual.inspect}; expected #{expected.inspect}" unless actual == expected
puts "Qwen alias: #{actual} (expected)"
RUBY

echo
echo "Checking qualified scorer lineage/profile integrity..."
git -C "$SCORER_REPO" cat-file -e "${QUALIFIED_SCORER_BASE}^{commit}" 2>/dev/null || {
  echo "ERROR: scorer checkout does not contain qualified baseline commit $QUALIFIED_SCORER_BASE"
  exit 1
}
git -C "$SCORER_REPO" merge-base --is-ancestor "$QUALIFIED_SCORER_BASE" HEAD || {
  echo "ERROR: scorer HEAD is not a descendant of qualified baseline $QUALIFIED_SCORER_BASE"
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

git -C "$SCORER_REPO" diff --quiet "$QUALIFIED_SCORER_BASE"..HEAD -- "${PROTECTED_SCORER_FILES[@]}" || {
  echo "ERROR: qualified Social/Investigation scorer implementation changed after $QUALIFIED_SCORER_BASE"
  git -C "$SCORER_REPO" diff --name-only "$QUALIFIED_SCORER_BASE"..HEAD -- "${PROTECTED_SCORER_FILES[@]}"
  exit 1
}
git -C "$SCORER_REPO" diff --quiet -- "${PROTECTED_SCORER_FILES[@]}" || {
  echo "ERROR: unstaged changes touch qualified Social/Investigation scorer implementation"
  exit 1
}
git -C "$SCORER_REPO" diff --cached --quiet -- "${PROTECTED_SCORER_FILES[@]}" || {
  echo "ERROR: staged changes touch qualified Social/Investigation scorer implementation"
  exit 1
}
echo "Scorer profile lineage: PASS"
echo "  qualified baseline: $QUALIFIED_SCORER_BASE"
echo "  scorer HEAD: $(git -C "$SCORER_REPO" rev-parse HEAD)"

echo
echo "Rendering qualified scorer profiles (zero inference)..."
TMP_PROFILE_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_PROFILE_DIR"' EXIT INT TERM

env \
  "$SOCIAL_ENV=$SOCIAL_PROFILE" \
  "$INVESTIGATION_ENV=$INVESTIGATION_PROFILE" \
  "$SCORER_REPO/bin/af-score" \
  --model "$EXPECTED_MODEL" \
  --dimension "Social Interaction Emphasis" \
  --preflight \
  --render-preflight "$TMP_PROFILE_DIR/social.json" \
  ADV-0200 >/dev/null || {
    echo "ERROR: Social qualified-profile scorer preflight failed"
    exit 1
  }

env \
  "$SOCIAL_ENV=$SOCIAL_PROFILE" \
  "$INVESTIGATION_ENV=$INVESTIGATION_PROFILE" \
  "$SCORER_REPO/bin/af-score" \
  --model "$EXPECTED_MODEL" \
  --dimension "Investigation Emphasis" \
  --preflight \
  --render-preflight "$TMP_PROFILE_DIR/investigation.json" \
  ADV-0200 >/dev/null || {
    echo "ERROR: Investigation qualified-profile scorer preflight failed"
    exit 1
  }

ruby - "$TMP_PROFILE_DIR/social.json" "$TMP_PROFILE_DIR/investigation.json" <<'RUBY' || exit 1
require "json"
social_path, investigation_path = ARGV
social = JSON.parse(File.read(social_path))
investigation = JSON.parse(File.read(investigation_path))

s_meta = social.fetch("run_metadata")
i_meta = investigation.fetch("run_metadata")
abort "Social profile metadata missing/wrong" unless s_meta["social_interaction_guardrail_profile"] == "phase6-v0.3"
abort "Investigation profile metadata missing/wrong" unless i_meta["investigation_guardrail_profile"] == "phase6-v0.4"

s_prompt = social.fetch("targets").fetch(0).dig("prompt", "input").to_s
i_prompt = investigation.fetch("targets").fetch(0).dig("prompt", "input").to_s
abort "Social v0.3 guardrail not present in rendered prompt" unless s_prompt.include?("Social Interaction Emphasis Cross-Mode Independence Guardrail v0.3")
abort "Investigation v0.4 guardrail not present in rendered prompt" unless i_prompt.include?("Investigation Emphasis Endpoint Boundary Guardrail v0.4")

puts "Qualified prompt activation: PASS"
puts "  Social Interaction Emphasis => phase6-v0.3"
puts "  Investigation Emphasis => phase6-v0.4"
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

sample=$(head -n 1 "$ORDER")
echo
echo "Checking local worker and authorized Qwen model..."
bin/lme worker-check "$sample" || exit 1

echo
echo "PREFLIGHT PASSED — 63 RUN cells + 3 protected accepted skips = 66-cell Social/Investigation matrix."
echo "Qualified scorer profiles were rendered and verified."
echo "NO INFERENCE WAS RUN."
