#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
INDEX="experiments/phase6/phase6_lethality_v0_3_manifest_index_v0.1.csv"
DRY_RUN=false
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=true ;;
  *) echo "Usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

echo "============================================================"
echo "Phase-6 Lethality v0.3 failure-state topology pilot"
echo "Maximum local inference calls: 3"
echo 'External/API inference cost: $0'
echo "Score-triggered early stop: disabled"
echo "============================================================"
echo

echo "[1/3] Static manifest/profile preflight (zero inference)..."
ruby -Ilib - "$INDEX" <<'RUBY'
require "csv"
require "local_model_evaluation/experiment"
rows = CSV.read(ARGV.fetch(0), headers: true)
abort "Expected exactly 3 pilot manifests; found #{rows.length}" unless rows.length == 3
abort "Sequences must be 1,2,3" unless rows.map { |r| r["sequence"] } == %w[1 2 3]
seen = {}
rows.each do |row|
  path = row.fetch("manifest")
  abort "Missing manifest #{path}" unless File.file?(path)
  exp = LocalModelEvaluation::Experiment.new(path)
  abort "#{path}: wrong model" unless exp.models == ["qwen"]
  abort "#{path}: wrong dimension" unless exp.dimension == "Lethality / Failure Severity"
  abort "#{path}: expected one adventure" unless exp.adventures.length == 1
  abort "#{path}: expected one replicate" unless exp.replicates == 1
  abort "#{path}: expected local mac worker" unless exp.worker_names == ["mac"]
  expected = { "AF_LETHALITY_GUARDRAIL_PROFILE" => "phase6-v0.3" }
  abort "#{path}: wrong scorer profile #{exp.phase6_scorer_env.inspect}" unless exp.phase6_scorer_env == expected
  c = exp.phase6_contract
  abort "#{path}: oracle visibility is not post-run only" unless c.dig("oracle", "visibility") == "post-run-adjudication-only"
  abort "#{path}: favorable rerun not prohibited" unless c["no_favorable_rerun"] == true
  abort "#{path}: nonzero external API authorization" unless c["external_api_cost_usd"].to_f == 0.0
  abort "#{path}: diagnostic completion not frozen" unless c.dig("diagnostic_completion", "complete_all_authorized_cases") == true && c.dig("diagnostic_completion", "score_triggered_stop") == false && c.dig("diagnostic_completion", "systemic_integrity_failure_only") == true
  key = [exp.dimension, exp.adventures.first]
  abort "Duplicate pilot case #{key.join(' / ')}" if seen[key]
  seen[key] = true
end
puts "Static manifest/profile preflight: PASS"
puts "Cases: 3/3"
puts "Profile: AF_LETHALITY_GUARDRAIL_PROFILE=phase6-v0.3"
puts "Provider inference calls: 0"
RUBY
echo
FIRST_MANIFEST="$(ruby -rcsv -e 'puts CSV.read(ARGV[0], headers: true).first.fetch("manifest")' "$INDEX")"
echo "[2/3] Worker/model check (zero inference)..."
bin/lme worker-check "$FIRST_MANIFEST"
echo "Provider inference calls: 0"
echo

if [[ "$DRY_RUN" == true ]]; then
  echo "Pilot dry run: PASS"
  echo "Provider inference calls: 0"
  exit 0
fi

echo "[3/3] Running all three authorized diagnostic calls sequentially..."
echo "Unfavorable scores do not stop later cases; no favorable reruns."
echo

i=0
while IFS= read -r manifest; do
  i=$((i + 1))
  echo "------------------------------------------------------------"
  printf 'RUN %02d/03  %s\n' "$i" "$manifest"
  echo "------------------------------------------------------------"
  caffeinate -dimsu nice -n 10 bin/lme run "$manifest"
done < <(ruby -rcsv -e 'CSV.read(ARGV[0], headers: true).each { |r| puts r.fetch("manifest") }' "$INDEX")

echo
echo "Phase-6 Lethality v0.3 pilot execution complete."
echo "Attempted authorized manifests: 3"
echo "Adjudicate against phase6_lethality_topology_pilot_v0.1.md."
