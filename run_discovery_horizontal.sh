#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${LME_REPO:-$SCRIPT_DIR}"
QUEUE="discovery-horizontal-095-v0.1"
QUEUE_DIR="$REPO/production_backlog/$QUEUE"
ORDER="$QUEUE_DIR/run_order.txt"
SNAPSHOT="$QUEUE_DIR/snapshot.yml"
INDEX="$QUEUE_DIR/case_index.csv"
CONTROL_DIR="$REPO/output/production-backlog-control"
PAUSE_FILE="$CONTROL_DIR/pause"
CURRENT_FILE="$CONTROL_DIR/current"
FAIL_LOG="$CONTROL_DIR/discovery-horizontal-failures.log"
SOURCE_PREFLIGHT="$REPO/bin/preflight-production-backlog-sources"

cd "$REPO" || exit 1
mkdir -p "$CONTROL_DIR"

[[ -f "$ORDER" && -f "$SNAPSHOT" && -f "$INDEX" ]] || {
  echo "ERROR: horizontal queue is not prepared. Run:"
  echo "  bin/prepare-discovery-horizontal"
  exit 1
}
[[ -x "$SOURCE_PREFLIGHT" ]] || { echo "ERROR: missing $SOURCE_PREFLIGHT"; exit 1; }
[[ -x bin/lme ]] || { echo "ERROR: missing bin/lme"; exit 1; }

if [[ -f "$CURRENT_FILE" ]]; then
  echo "ERROR: another production call appears active:"
  cat "$CURRENT_FILE"
  echo
  echo "Pause the existing queue and wait for its current call to finish before starting Discovery-95."
  exit 1
fi

if [[ -f "$PAUSE_FILE" ]]; then
  echo "ERROR: production pause sentinel is still present: $PAUSE_FILE"
  echo "After the previous queue has stopped, remove the stale sentinel with:"
  echo "  rm -f '$PAUSE_FILE'"
  exit 1
fi

ruby - "$SNAPSHOT" "$INDEX" "$ORDER" "$REPO" <<'RUBY' || exit 1
require "csv"
require "digest"
require "yaml"

snapshot_path, index_path, order_path, root = ARGV
snapshot = YAML.safe_load_file(snapshot_path)
rows = CSV.read(index_path, headers: true, encoding: "UTF-8")
order = File.readlines(order_path, chomp: true).reject(&:empty?)
abort "wrong horizontal contract" unless snapshot.fetch("contract_type") == "discovery_horizontal_priority_v1"
abort "cohort count changed" unless Integer(snapshot.fetch("cohort_count")) == 95
abort "case/order count mismatch" unless rows.length == order.length
abort "case/order path mismatch" unless rows.map { |r| r["manifest_path"] } == order
abort "run order has duplicates" unless order.uniq.length == order.length
abort "external API cost changed" unless snapshot.fetch("external_api_cost_usd").to_f == 0.0
abort "favorable rerun contract changed" unless snapshot.fetch("no_favorable_rerun") == true

catalog = snapshot.fetch("catalog_path")
abort "frozen AMC missing: #{catalog}" unless File.file?(catalog)
actual_sha = Digest::SHA256.file(catalog).hexdigest
abort "AMC changed since prepare: #{actual_sha} != #{snapshot.fetch('catalog_sha256')}" unless actual_sha == snapshot.fetch("catalog_sha256")

rows.each do |row|
  path = File.expand_path(row["manifest_path"], root)
  abort "missing manifest #{row['manifest_path']}" unless File.file?(path)
  data = YAML.safe_load_file(path)
  abort "wrong adventure in #{path}" unless data["adventures"] == [row["adventure_id"]]
  abort "wrong dimension in #{path}" unless data["dimension"].to_s == row["dimension"]
  abort "replicates != 1 in #{path}" unless Integer(data["replicates"]) == 1
  abort "non-local worker in #{path}" unless data["required_worker_labels"] == ["local"]
  abort "favorable rerun allowed in #{path}" unless data.dig("production_contract", "no_favorable_rerun") == true
  abort "external API cost not zero in #{path}" unless data.dig("production_contract", "external_api_cost_usd").to_f == 0.0
end

puts "Horizontal frozen-plan verification: PASS"
puts "  cohort: #{snapshot.fetch('cohort_count')} adventures"
puts "  runnable blank pairs: #{rows.length}"
puts "  AMC SHA-256: #{actual_sha}"
RUBY

echo
echo "Checking runtime source resolution for every scheduled manifest (zero inference)..."
"$SOURCE_PREFLIGHT" "production_backlog/$QUEUE" || {
  echo "ERROR: runtime source preflight failed. No inference launched."
  exit 1
}

manifest_status() {
  local manifest="$1"
  ruby - "$manifest" "$REPO/output" <<'RUBY'
require "json"
require "yaml"
manifest, output_root = ARGV
data = YAML.safe_load_file(manifest)
name = data.fetch("name")
metadata = Dir.glob(File.join(output_root, name, "runs", "*", "metadata.json")).sort
if metadata.empty?
  print "pending"
  exit
end
states = metadata.map do |path|
  JSON.parse(File.read(path))["status"].to_s
rescue JSON::ParserError
  "unknown"
end
if states.all? { |s| s == "complete" }
  print "complete"
elsif states.any? { |s| s == "failed" }
  print "failed"
elsif states.any? { |s| s == "running" }
  print "running"
else
  print "unknown"
end
RUBY
}

if command -v caffeinate >/dev/null 2>&1; then
  caffeinate -dimsu &
  CAFFEINATE_PID=$!
else
  CAFFEINATE_PID=""
  echo "WARNING: caffeinate not found; sleep prevention is not active."
fi

cleanup() {
  rm -f "$CURRENT_FILE"
  if [[ -n "${CAFFEINATE_PID:-}" ]]; then
    kill "$CAFFEINATE_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

total=$(grep -c '^experiments/' "$ORDER" || true)
new_failures=0
consecutive_failures=0
n=0

echo
echo "DISCOVERY-95 HORIZONTAL PRIORITY SCORING"
echo "Adventure-major order; existing completed/failed samples are never rerun."
echo "Scheduled manifest pairs: $total"
echo 'External/API inference cost: $0'
echo "Pause safely from another terminal with: ./pause_production_backlog.sh"
echo

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  n=$((n + 1))

  if [[ -f "$PAUSE_FILE" ]]; then
    echo "PAUSE OBSERVED before dispatch."
    exit 0
  fi

  status=$(manifest_status "$f")
  case "$status" in
    complete)
      echo "[$n/$total] SKIP complete: $f"
      continue
      ;;
    failed)
      echo "[$n/$total] SKIP previously failed (no favorable rerun): $f"
      continue
      ;;
    running)
      echo "[$n/$total] ERROR unexpected running status: $f"
      exit 1
      ;;
  esac

  {
    echo "queue=production_backlog/$QUEUE"
    echo "index=$n"
    echo "total=$total"
    echo "manifest=$f"
    echo "started_at=$(date '+%Y-%m-%dT%H:%M:%S%z')"
  } > "$CURRENT_FILE"

  echo
echo "================================================================"
  echo "[$n/$total] DISCOVERY HORIZONTAL: $f"
  echo "================================================================"

  command_ok=true
  bin/lme run "$f" || command_ok=false
  status=$(manifest_status "$f")

  if [[ "$command_ok" == true && "$status" == "complete" ]]; then
    consecutive_failures=0
    echo "[$n/$total] COMPLETE"
  else
    new_failures=$((new_failures + 1))
    consecutive_failures=$((consecutive_failures + 1))
    echo "$(date '+%Y-%m-%dT%H:%M:%S%z') $status $f" >> "$FAIL_LOG"
    echo "[$n/$total] FAILURE status=$status"
    echo "New failures this invocation: $new_failures; consecutive: $consecutive_failures"
    if [[ "$consecutive_failures" -ge 2 || "$new_failures" -ge 3 ]]; then
      echo "CIRCUIT BREAKER: stopping after >=2 consecutive or >=3 total new failures."
      exit 1
    fi
  fi

  rm -f "$CURRENT_FILE"
done < "$ORDER"

echo
echo "DISCOVERY-95 HORIZONTAL QUEUE FINISHED"
echo "New failures this invocation: $new_failures"
./status_discovery_horizontal.sh || true
