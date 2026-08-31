#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${LME_REPO:-$SCRIPT_DIR}"
QUEUE="discovery-horizontal-095-v0.1"
QUEUE_DIR="$REPO/production_backlog/$QUEUE"
INDEX="$QUEUE_DIR/case_index.csv"
SNAPSHOT="$QUEUE_DIR/snapshot.yml"
CURRENT_FILE="$REPO/output/production-backlog-control/current"
PAUSE_FILE="$REPO/output/production-backlog-control/pause"

[[ -f "$INDEX" && -f "$SNAPSHOT" ]] || {
  echo "Discovery-95 queue not prepared. Run: bin/prepare-discovery-horizontal"
  exit 1
}

cd "$REPO" || exit 1
ruby - "$INDEX" "$SNAPSHOT" "$REPO/output" <<'RUBY'
require "csv"
require "json"
require "yaml"

index_path, snapshot_path, output_root = ARGV
rows = CSV.read(index_path, headers: true, encoding: "UTF-8")
snapshot = YAML.safe_load_file(snapshot_path)
status_for = lambda do |manifest|
  data = YAML.safe_load_file(manifest)
  name = data.fetch("name")
  metadata = Dir.glob(File.join(output_root, name, "runs", "*", "metadata.json")).sort
  if metadata.empty?
    "pending"
  else
    states = metadata.map do |path|
      JSON.parse(File.read(path))["status"].to_s
    rescue JSON::ParserError
      "unknown"
    end
    if states.all? { |s| s == "complete" }
      "complete"
    elsif states.any? { |s| s == "failed" }
      "failed"
    elsif states.any? { |s| s == "running" }
      "running"
    else
      "unknown"
    end
  end
end

counts = Hash.new(0)
by_adv = Hash.new { |h, k| h[k] = [] }
rows.each do |row|
  status = status_for.call(row["manifest_path"])
  counts[status] += 1
  by_adv[row["adventure_id"]] << status
end

cohort_ids = snapshot.fetch("cohort_ids")
complete_adventures = cohort_ids.count do |id|
  states = by_adv[id]
  states.empty? || states.all? { |s| s == "complete" }
end
blocked_adventures = cohort_ids.count { |id| by_adv[id].any? { |s| s == "failed" } }
pending_adventures = cohort_ids.length - complete_adventures - blocked_adventures

puts "Discovery-95 horizontal status"
puts "  cohort adventures: #{cohort_ids.length}"
puts "  runnable blank pairs at prepare: #{rows.length}"
%w[complete failed running pending unknown].each { |s| puts format("  %-8s %d", s, counts[s]) }
puts "  adventures fully covered by catalog + completed scheduled samples: #{complete_adventures}/#{cohort_ids.length}"
puts "  adventures blocked by failed sample: #{blocked_adventures}"
puts "  adventures still pending: #{pending_adventures}"
puts "  synthesized manifests: #{snapshot.fetch('synthesized_from_frozen_templates')}"
puts "  reused frozen manifests: #{snapshot.fetch('reused_frozen_manifests')}"
puts "  holds: #{snapshot.fetch('holds')}"
RUBY

if [[ -f "$PAUSE_FILE" ]]; then
  echo "Pause: REQUESTED"
else
  echo "Pause: not requested"
fi
if [[ -f "$CURRENT_FILE" ]]; then
  echo
  echo "Current call:"
  cat "$CURRENT_FILE"
fi
