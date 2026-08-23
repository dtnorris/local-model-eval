#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${LME_REPO:-$SCRIPT_DIR}"
QUEUE_ARG="${1:-}"
CONTROL_DIR="$REPO/output/production-backlog-control"
CURRENT_FILE="$CONTROL_DIR/current"
PAUSE_FILE="$CONTROL_DIR/pause"

[[ -n "$QUEUE_ARG" ]] || {
  echo "Usage: ./status_production_backlog.sh production_backlog/QUEUE"
  exit 2
}

if [[ "$QUEUE_ARG" = /* ]]; then
  QUEUE_DIR="$QUEUE_ARG"
else
  QUEUE_DIR="$REPO/$QUEUE_ARG"
fi
ORDER="$QUEUE_DIR/run_order.txt"

[[ -f "$ORDER" ]] || { echo "ERROR: missing $ORDER"; exit 1; }

ruby - "$ORDER" "$REPO/output" <<'RUBY'
require "json"
require "yaml"

order_path, output_root = ARGV
paths = File.readlines(order_path, chomp: true).reject(&:empty?)
counts = Hash.new(0)

paths.each do |manifest|
  data = YAML.safe_load_file(manifest)
  name = data.fetch("name")
  metadata = Dir.glob(File.join(output_root, name, "runs", "*", "metadata.json")).sort
  status =
    if metadata.empty?
      "pending"
    else
      begin
        states = metadata.map { |path| JSON.parse(File.read(path))["status"].to_s }
        if states.all? { |s| s == "complete" }
          "complete"
        elsif states.any? { |s| s == "failed" }
          "failed"
        elsif states.any? { |s| s == "running" }
          "running"
        else
          "unknown"
        end
      rescue JSON::ParserError
        "unknown"
      end
    end
  counts[status] += 1
end

puts "Queue calls: #{paths.length}"
%w[complete failed running pending unknown].each do |status|
  puts format("  %-8s %d", status, counts[status])
end
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
