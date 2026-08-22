#!/usr/bin/env bash
set -u
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

INDEX="experiments/phase6/phase6_core_manifest_index_v0.1.csv"
EXPECTED_COUNT=25

if [[ ! -f "$INDEX" ]]; then
  echo "ERROR: Phase-6 manifest index not found: $INDEX" >&2
  exit 1
fi

mapfile_compat() {
  ruby -rcsv -e '
    CSV.foreach(ARGV.fetch(0), headers: true) do |row|
      manifest = row["manifest"]
      abort "ERROR: manifest column missing or blank" if manifest.nil? || manifest.empty?
      puts manifest
    end
  ' "$INDEX"
}

manifests=()
while IFS= read -r manifest; do
  manifests+=("$manifest")
done < <(mapfile_compat)

if [[ "${#manifests[@]}" -ne "$EXPECTED_COUNT" ]]; then
  echo "ERROR: Expected $EXPECTED_COUNT frozen Phase-6 manifests, found ${#manifests[@]}." >&2
  exit 1
fi

for manifest in "${manifests[@]}"; do
  if [[ ! -f "$manifest" ]]; then
    echo "ERROR: Manifest listed in index does not exist: $manifest" >&2
    exit 1
  fi
done

echo "Phase-6 core diagnostic batch"
echo "Index: $INDEX"
echo "Authorized manifests: ${#manifests[@]}"
echo "Execution: sequential, one manifest at a time"
echo "Numeric score outcomes do not stop the batch."
echo

sequence=0
for manifest in "${manifests[@]}"; do
  sequence=$((sequence + 1))

  echo "============================================================"
  printf 'RUN %02d/%02d: %s\n' "$sequence" "$EXPECTED_COUNT" "$manifest"
  echo "============================================================"

  # `bin/lme run` records case-level scorer/model failures in run metadata.
  # The Phase-6 diagnostic-completion policy says unfavorable score outcomes
  # do not terminate the remaining authorized core cases.
  #
  # caffeinate prevents macOS sleep while this individual inference is active.
  # nice reduces CPU scheduling priority to protect interactive responsiveness.
  caffeinate -dimsu nice -n 10 bin/lme run "$manifest"
  exit_status=$?

  if [[ "$exit_status" -ne 0 ]]; then
    echo
    echo "ERROR: bin/lme itself exited with status $exit_status for:"
    echo "  $manifest"
    echo "Stopping because this may indicate a systemic harness/configuration failure."
    exit "$exit_status"
  fi

  echo
done

echo "============================================================"
echo "PHASE-6 CORE BATCH COMPLETE"
echo "Attempted all $EXPECTED_COUNT frozen core manifests."
echo "============================================================"
