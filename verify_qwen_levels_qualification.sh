#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"

PACKAGE="qualification/levels-qwen-v0.1"
MANIFEST="$PACKAGE/manifest.yml"
RUN_ORDER="$PACKAGE/run_order.txt"

for required_file in "$MANIFEST" "$PACKAGE/criteria.md" "$RUN_ORDER" config/models.yml bin/lme; do
  if [[ ! -f "$required_file" ]]; then
    echo "ERROR: missing required file: $required_file" >&2
    exit 1
  fi
done

ruby <<'RUBY'
require "yaml"

root = Dir.pwd
package_path = File.join(root, "qualification/levels-qwen-v0.1/manifest.yml")
run_order_path = File.join(root, "qualification/levels-qwen-v0.1/run_order.txt")
package = YAML.safe_load(File.read(package_path), aliases: true)

expected = [
  ["ADV-0040", "experiments/qualification/qualification-qwen-levels-adv0040-v1.yml", "completion-award-ownership"],
  ["ADV-0278", "experiments/qualification/qualification-qwen-levels-adv0278-v1.yml", "canonical-child-transition"],
  ["ADV-0034", "experiments/qualification/qualification-qwen-levels-adv0034-v1.yml", "qualitative-guidance-uncertainty"]
]

abort "ERROR: package dimension is not Levels" unless package["dimension"] == "Levels"
abort "ERROR: candidate model must be qwen" unless package["candidate_model"] == "qwen"
abort "ERROR: package must cap fresh calls at 3" unless package.dig("execution", "max_fresh_inference_calls") == 3
abort "ERROR: package must use one replicate per case" unless package.dig("execution", "replicates_per_case") == 1
abort "ERROR: qualification must remain local-only" unless package.dig("execution", "local_worker_only") == true
abort "ERROR: external API cost must be zero" unless package.dig("execution", "external_api_cost_usd").to_f.zero?
abort "ERROR: favorable reruns must be disabled" unless package.dig("execution", "favorable_reruns") == false
abort "ERROR: Levels comparator must be exact" unless package.dig("reference_oracle", "comparator") == "exact_field_semantics"
abort "ERROR: ordinal tolerance must be disabled" unless package.dig("reference_oracle", "ordinal_tolerance_applies") == false
abort "ERROR: fresh Terra must not be required" unless package.dig("reference_oracle", "fresh_terra_required") == false

cases = package.fetch("fresh_cases")
abort "ERROR: expected exactly 3 fresh cases" unless cases.length == 3

run_order = File.readlines(run_order_path, chomp: true).reject(&:empty?)
expected_paths = expected.map { |(_, path, _)| path }
abort "ERROR: run_order.txt is not the frozen three-case order" unless run_order == expected_paths

models = YAML.safe_load(File.read(File.join(root, "config/models.yml")), aliases: true)
ollama_model = models.dig("models", "qwen", "ollama_model")
abort "ERROR: qwen model mapping changed: #{ollama_model.inspect}" unless ollama_model == "qwen3.6:35b-a3b"

cases.each_with_index do |entry, index|
  adv, path, role = expected.fetch(index)
  abort "ERROR: package adventure order mismatch at case #{index + 1}" unless entry["adventure_id"] == adv
  abort "ERROR: package manifest path mismatch for #{adv}" unless entry["manifest"] == path

  full_path = File.join(root, path)
  abort "ERROR: missing case manifest: #{path}" unless File.file?(full_path)
  data = YAML.safe_load(File.read(full_path), aliases: true)

  checks = {
    "one qwen model" => data["models"] == ["qwen"],
    "Levels dimension" => data["dimension"] == "Levels",
    "one canonical adventure" => data["adventures"] == [adv],
    "one replicate" => data["replicates"] == 1,
    "mac worker" => data["workers"] == ["mac"],
    "local worker label" => data["required_worker_labels"] == ["local"],
    "empty scorer extra_args" => data.dig("scorer", "extra_args") == [],
    "qualification wave" => data.dig("qualification_contract", "wave") == "qwen-levels-v0.1",
    "case role" => data.dig("qualification_contract", "case_role") == role,
    "blind expected value" => data.dig("qualification_contract", "blind_expected_value") == true,
    "no favorable rerun" => data.dig("qualification_contract", "no_favorable_rerun") == true,
    "zero external cost" => data.dig("qualification_contract", "external_api_cost_usd").to_f.zero?,
    "small local cost cap" => data["cost_cap_usd"].to_f <= 0.01
  }

  failures = checks.reject { |_, ok| ok }.keys
  abort "ERROR: #{path}: failed checks: #{failures.join(', ')}" unless failures.empty?
end

puts "Static contract: OK"
puts "Qwen mapping: qwen3.6:35b-a3b"
puts "Fresh inference ceiling: 3 local calls"
puts "External/API inference budget: $0.00"
puts "Comparator: exact Level Start / Level End semantics; no +/-1 tolerance"
RUBY

if [[ ! -f config/workers.yml ]]; then
  echo "ERROR: config/workers.yml is missing; copy/configure config/workers.example.yml before running qualification." >&2
  exit 1
fi

while IFS= read -r case_manifest; do
  [[ -z "$case_manifest" ]] && continue
  echo
  echo "Planning: $case_manifest"
  bin/lme plan "$case_manifest"
done < "$RUN_ORDER"

echo
echo "Checking local worker/model availability (no inference)..."
bin/lme worker-check "$(head -n 1 "$RUN_ORDER")"

echo
echo "Qwen Levels qualification preflight: VERIFIED"
