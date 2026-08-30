#!/usr/bin/env bash
set -euo pipefail

# Controlled AdventureFinder speed benchmark for one Ollama endpoint.
# All Ollama CLI operations AND af-cli-scoring-utility inference are forced to
# the same endpoint, avoiding accidental local-warmup/remote-score mixtures.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCORER_REPO="${AF_SCORE_REPO:-$(cd "$ROOT/../af-cli-scoring-utility" 2>/dev/null && pwd || true)}"
ENDPOINT="${AF_OLLAMA_BASE_URL:-${OLLAMA_HOST:-http://127.0.0.1:11434}}"
ADVENTURE="ADV-0200"
DIMENSION="Social Interaction Emphasis"
OUTPUT_ROOT=""
MODELS=("qwen3.6:27b" "qwen3.6:35b-a3b")
declare -A EXPECTED_DIGESTS=()
CUSTOM_MODELS=0

usage() {
  cat <<'USAGE'
Usage:
  benchmark_qwen_speed.sh [options]

Options:
  --endpoint URL                Ollama endpoint. Overrides AF_OLLAMA_BASE_URL/OLLAMA_HOST.
  --scorer-repo PATH            af-cli-scoring-utility checkout.
  --model MODEL                 Model to benchmark. Repeatable; replaces default pair.
  --expect-digest MODEL=DIGEST  Fail before inference if endpoint digest differs. Repeatable.
  --adventure ADV-ID            Adventure ID (default: ADV-0200)
  --dimension NAME              Dimension (default: Social Interaction Emphasis)
  --output-root PATH            Output parent (default: <scorer>/output/speed)
  -h, --help                    Show this help.

Default models:
  qwen3.6:27b
  qwen3.6:35b-a3b

Example remote run:
  scripts/benchmark_qwen_speed.sh \
    --endpoint http://127.0.0.1:11441 \
    --expect-digest qwen3.6:27b=9d5803d493a991af27b9441c098aa56f2ed7bbd260877f075ec09b575c049bc3
USAGE
}

ts() { date '+%H:%M:%S'; }
info() { printf '[%s] %s\n' "$(ts)" "$*"; }
die() { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    --endpoint) ENDPOINT="${2:-}"; shift 2 ;;
    --scorer-repo) SCORER_REPO="${2:-}"; shift 2 ;;
    --model)
      if [[ $CUSTOM_MODELS -eq 0 ]]; then MODELS=(); CUSTOM_MODELS=1; fi
      MODELS+=("${2:-}"); shift 2 ;;
    --expect-digest)
      [[ "${2:-}" == *=* ]] || die "--expect-digest must be MODEL=DIGEST"
      EXPECTED_DIGESTS["${2%%=*}"]="${2#*=}"
      shift 2 ;;
    --adventure) ADVENTURE="${2:-}"; shift 2 ;;
    --dimension) DIMENSION="${2:-}"; shift 2 ;;
    --output-root) OUTPUT_ROOT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$SCORER_REPO" ]] || die "could not infer scorer repo; pass --scorer-repo PATH"
[[ -x "$SCORER_REPO/bin/af-score" ]] || die "$SCORER_REPO/bin/af-score not found or not executable"
command -v ollama >/dev/null 2>&1 || die "ollama CLI is required on the Mac"
command -v curl >/dev/null 2>&1 || die "curl is required"
command -v ruby >/dev/null 2>&1 || die "ruby is required"

case "$ENDPOINT" in
  http://*|https://*) ;;
  *) ENDPOINT="http://$ENDPOINT" ;;
esac
ENDPOINT="${ENDPOINT%/}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$SCORER_REPO/output/speed}"
STAMP="$(date '+%Y%m%d-%H%M%S')"
OUT_ROOT="$OUTPUT_ROOT/$STAMP"
mkdir -p "$OUT_ROOT"
SUMMARY="$OUT_ROOT/summary.tsv"
printf 'model\tdigest\tadventure\tdimension\texit_code\tstructured_output\twall_seconds\tcontext\tfull_gpu\n' > "$SUMMARY"

model_digest_from_file() {
  local file="$1" model="$2"
  ruby -rjson -e '
    data = JSON.parse(File.read(ARGV[0]))
    model = ARGV[1]
    found = Array(data["models"]).find { |m| m["name"] == model || m["model"] == model }
    puts(found && found["digest"] || "")
  ' "$file" "$model"
}

model_ps_field() {
  local file="$1" model="$2" field="$3"
  ruby -rjson -e '
    data = JSON.parse(File.read(ARGV[0]))
    model, field = ARGV[1], ARGV[2]
    found = Array(data["models"]).find { |m| m["name"] == model || m["model"] == model }
    value = found && found[field]
    puts(value.nil? ? "" : value)
  ' "$file" "$model" "$field"
}

capture_state() {
  local dir="$1" label="$2"
  OLLAMA_HOST="$ENDPOINT" ollama ps > "$dir/${label}-ollama-ps.txt" 2>&1 || true
  curl -fsS "$ENDPOINT/api/ps" > "$dir/${label}-api-ps.json" 2> "$dir/${label}-api-ps.stderr" || true
  curl -fsS "$ENDPOINT/api/tags" > "$dir/${label}-api-tags.json" 2> "$dir/${label}-api-tags.stderr" || true
  if command -v jq >/dev/null 2>&1; then
    [[ -s "$dir/${label}-api-ps.json" ]] && jq . "$dir/${label}-api-ps.json" > "$dir/${label}-api-ps.pretty.json" 2>/dev/null || true
    [[ -s "$dir/${label}-api-tags.json" ]] && jq . "$dir/${label}-api-tags.json" > "$dir/${label}-api-tags.pretty.json" 2>/dev/null || true
  fi
}

info "[1/4] Checking benchmark endpoint $ENDPOINT ..."
curl -fsS "$ENDPOINT/api/version" | tee "$OUT_ROOT/api-version.json"
printf '\n'
curl -fsS "$ENDPOINT/api/tags" > "$OUT_ROOT/api-tags-initial.json"
info "Endpoint PASS. Output: $OUT_ROOT"

info "[2/4] Verifying requested models are already installed (benchmark will not auto-pull) ..."
for model in "${MODELS[@]}"; do
  digest="$(model_digest_from_file "$OUT_ROOT/api-tags-initial.json" "$model")"
  [[ -n "$digest" ]] || die "$model is not installed at $ENDPOINT; install it before benchmarking"
  info "$model digest=$digest"
  expected="${EXPECTED_DIGESTS[$model]:-}"
  if [[ -n "$expected" && "$digest" != "$expected" ]]; then
    die "$model digest mismatch: expected $expected, got $digest"
  fi
done

info "[3/4] Running ${#MODELS[@]} benchmark model(s) sequentially ..."
overall_rc=0
for model in "${MODELS[@]}"; do
  safe="${model//[^A-Za-z0-9._-]/_}"
  dir="$OUT_ROOT/$safe"
  native_out="$dir/native"
  mkdir -p "$dir" "$native_out"

  printf '\n[%s] ================================================================\n' "$(ts)"
  info "Benchmarking $model :: $ADVENTURE :: $DIMENSION"
  printf '[%s] ================================================================\n' "$(ts)"

  curl -fsS "$ENDPOINT/api/tags" > "$dir/api-tags-before.json"
  digest="$(model_digest_from_file "$dir/api-tags-before.json" "$model")"
  expected="${EXPECTED_DIGESTS[$model]:-}"
  if [[ -n "$expected" && "$digest" != "$expected" ]]; then
    die "$model digest changed before run: expected $expected, got $digest"
  fi

  {
    echo "timestamp=$(date -Iseconds)"
    echo "model=$model"
    echo "digest=$digest"
    echo "adventure=$ADVENTURE"
    echo "dimension=$DIMENSION"
    echo "ollama_endpoint=$ENDPOINT"
    echo "scorer_repo=$SCORER_REPO"
  } > "$dir/metadata.txt"

  info "Unloading benchmark models at the selected endpoint ..."
  for m in "${MODELS[@]}"; do
    OLLAMA_HOST="$ENDPOINT" ollama stop "$m" >/dev/null 2>&1 || true
  done
  sleep 1
  capture_state "$dir" before-load

  info "Warming/loading $model at $ENDPOINT (warmup is not timed) ..."
  set +e
  OLLAMA_HOST="$ENDPOINT" ollama run "$model" "Reply with OK only." \
    > >(tee "$dir/warmup.stdout.log") \
    2> >(tee "$dir/warmup.stderr.log" >&2)
  warmup_rc=$?
  set -e
  echo "warmup_exit_code=$warmup_rc" >> "$dir/metadata.txt"
  if [[ $warmup_rc -ne 0 ]]; then
    info "Warmup FAIL for $model; continuing to preserve evidence."
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$model" "$digest" "$ADVENTURE" "$DIMENSION" "$warmup_rc" "FAIL-WARMUP" "" "" "" >> "$SUMMARY"
    overall_rc=1
    continue
  fi
  capture_state "$dir" after-load

  info "Starting timed af-score inference now ..."
  start="$(ruby -e 'puts Process.clock_gettime(Process::CLOCK_MONOTONIC)')"
  set +e
  (
    cd "$SCORER_REPO"
    AF_LLM_PROVIDER=ollama \
    AF_OLLAMA_BASE_URL="$ENDPOINT" \
      bin/af-score \
        --model "$model" \
        --dimension "$DIMENSION" \
        --output "$native_out" \
        "$ADVENTURE"
  ) > >(tee "$dir/score.stdout.log") 2> >(tee "$dir/score.stderr.log" >&2)
  score_rc=$?
  set -e
  finish="$(ruby -e 'puts Process.clock_gettime(Process::CLOCK_MONOTONIC)')"
  wall_seconds="$(ruby -e 'printf "%.3f", ARGV[1].to_f - ARGV[0].to_f' "$start" "$finish")"

  capture_state "$dir" after-score
  structured=FAIL
  [[ $score_rc -eq 0 ]] && structured=PASS

  context="$(model_ps_field "$dir/after-score-api-ps.json" "$model" context_length)"
  size="$(model_ps_field "$dir/after-score-api-ps.json" "$model" size)"
  size_vram="$(model_ps_field "$dir/after-score-api-ps.json" "$model" size_vram)"
  full_gpu=""
  if [[ -n "$size" && -n "$size_vram" ]]; then
    [[ "$size" == "$size_vram" ]] && full_gpu=yes || full_gpu=no
  fi

  {
    echo "score_exit_code=$score_rc"
    echo "structured_output=$structured"
    echo "wall_seconds=$wall_seconds"
    echo "context=$context"
    echo "full_gpu=$full_gpu"
  } >> "$dir/metadata.txt"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$model" "$digest" "$ADVENTURE" "$DIMENSION" "$score_rc" "$structured" \
    "$wall_seconds" "$context" "$full_gpu" >> "$SUMMARY"

  info "$model result: structured=$structured wall=${wall_seconds}s context=${context:-unknown} full_gpu=${full_gpu:-unknown}"
  OLLAMA_HOST="$ENDPOINT" ollama stop "$model" >/dev/null 2>&1 || true
  [[ $score_rc -eq 0 ]] || overall_rc=1
done

info "[4/4] Benchmark complete."
printf '\nResults: %s\n\n' "$OUT_ROOT"
if command -v column >/dev/null 2>&1; then
  column -ts $'\t' "$SUMMARY"
else
  cat "$SUMMARY"
fi
printf '\nOverall benchmark exit status: %d\n' "$overall_rc"
exit "$overall_rc"
