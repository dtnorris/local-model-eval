#!/bin/zsh
set -u

ROOT="${0:A:h}"
BENCH_DIR="$ROOT/experiments/adventure-major-benchmark"
ARM_A="$BENCH_DIR/arm-a-dimension-major.txt"
ARM_B="$BENCH_DIR/arm-b-adventure-major.txt"
ORDER="${BENCHMARK_ORDER:-AB}"
RESULT_DIR="$ROOT/output/adventure-major-ordering-benchmark"
STAMP="$(date +%Y%m%d-%H%M%S)"
RESULT="$RESULT_DIR/result-$STAMP.txt"

cd "$ROOT" || exit 1
[[ -x bin/lme ]] || { echo "ERROR: bin/lme missing or not executable"; exit 1; }
[[ -x bin/lme-batch ]] || { echo "ERROR: bin/lme-batch missing or not executable (PR #3 change required)"; exit 1; }
[[ -f "$ARM_A" && -f "$ARM_B" ]] || { echo "ERROR: benchmark lists missing"; exit 1; }
[[ "$ORDER" == "AB" || "$ORDER" == "BA" ]] || { echo "ERROR: BENCHMARK_ORDER must be AB or BA"; exit 1; }
command -v ollama >/dev/null 2>&1 || { echo "ERROR: ollama CLI not found"; exit 1; }

MODEL="$(ruby -ryaml -e 'puts YAML.load_file("config/models.yml").fetch("models").fetch("qwen").fetch("ollama_model")')"
[[ -n "$MODEL" ]] || { echo "ERROR: could not resolve qwen model"; exit 1; }
mkdir -p "$RESULT_DIR"

manifest_paths() {
  local list="$1" base="${list:h}"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    echo "$base/$line"
  done < "$list"
}

clear_outputs() {
  local list="$1"
  while IFS= read -r manifest; do
    local name="$(ruby -ryaml -e 'puts YAML.load_file(ARGV[0]).fetch("name")' "$manifest")" || return 1
    rm -rf "$ROOT/output/$name"
  done < <(manifest_paths "$list")
}

preflight() {
  echo "Preflighting all 12 atomic manifests..."
  for list in "$ARM_A" "$ARM_B"; do
    while IFS= read -r manifest; do
      bin/lme plan "$manifest" >/dev/null || { echo "ERROR: manifest preflight failed: $manifest"; return 1; }
    done < <(manifest_paths "$list")
  done
  echo "Adventure-major order that Arm B will execute:"
  bin/lme-batch plan "$ARM_B" || return 1
  local sample="$(manifest_paths "$ARM_A" | head -n 1)"
  echo "Checking local Qwen worker..."
  bin/lme worker-check "$sample" || return 1
}

reset_and_warm_model() {
  echo "Resetting Qwen model state..."
  ollama stop "$MODEL" >/dev/null 2>&1 || true
  sleep 2
  ollama run "$MODEL" "Reply with exactly: OK" >/dev/null 2>&1 || { echo "ERROR: failed to warm $MODEL"; return 1; }
  sleep 1
}

monotonic() { ruby -e 'printf "%.6f\\n", Process.clock_gettime(Process::CLOCK_MONOTONIC)'; }
elapsed_between() { ruby -e 'printf "%.3f\\n", ARGV[1].to_f - ARGV[0].to_f' "$1" "$2"; }

sum_scoring_seconds() {
  local list="$1"
  ruby -ryaml -rjson -e '
    root=ARGV.shift; list=File.expand_path(ARGV.shift); base=File.dirname(list); total=0.0; count=0
    File.readlines(list, chomp:true).each do |line|
      line=line.strip; next if line.empty? || line.start_with?("#")
      manifest=File.expand_path(line, base); name=YAML.load_file(manifest).fetch("name")
      files=Dir.glob(File.join(root,"output",name,"runs","*","metadata.json"))
      abort "expected exactly one metadata file for #{name}; found #{files.length}" unless files.length==1
      row=JSON.parse(File.read(files.first)); abort "non-complete run for #{name}: #{row["status"]}" unless row["status"]=="complete"
      total += Float(row.fetch("elapsed_seconds")); count += 1
    end
    abort "expected 6 completed runs; found #{count}" unless count==6
    printf "%.3f\\n", total
  ' "$ROOT" "$list"
}

run_arm_a() {
  echo; echo "================================================================"; echo "ARM A — DIMENSION-MAJOR CONTROL"; echo "================================================================"
  clear_outputs "$ARM_A" || return 1
  reset_and_warm_model || return 1
  local start="$(monotonic)" finish n=0
  while IFS= read -r manifest; do
    n=$((n+1)); echo; echo "[A $n/6] $manifest"
    bin/lme run "$manifest" || { echo "ERROR: Arm A failed; stopping benchmark."; return 1; }
  done < <(manifest_paths "$ARM_A")
  finish="$(monotonic)"
  ARM_A_WALL="$(elapsed_between "$start" "$finish")"
  ARM_A_SCORING="$(sum_scoring_seconds "$ARM_A")" || return 1
  echo "Arm A wall-clock: ${ARM_A_WALL}s"; echo "Arm A scoring-runtime sum: ${ARM_A_SCORING}s"
}

run_arm_b() {
  echo; echo "================================================================"; echo "ARM B — ADVENTURE-MAJOR EXPERIMENT"; echo "================================================================"
  clear_outputs "$ARM_B" || return 1
  reset_and_warm_model || return 1
  local start="$(monotonic)" finish
  bin/lme-batch run "$ARM_B" || { echo "ERROR: Arm B failed; stopping benchmark."; return 1; }
  finish="$(monotonic)"
  ARM_B_WALL="$(elapsed_between "$start" "$finish")"
  ARM_B_SCORING="$(sum_scoring_seconds "$ARM_B")" || return 1
  echo "Arm B wall-clock: ${ARM_B_WALL}s"; echo "Arm B scoring-runtime sum: ${ARM_B_SCORING}s"
}

summarize() {
  local wall_speed="$(ruby -e 'a=ARGV[0].to_f;b=ARGV[1].to_f;printf "%.1f", ((a-b)/a)*100.0' "$ARM_A_WALL" "$ARM_B_WALL")"
  local scoring_speed="$(ruby -e 'a=ARGV[0].to_f;b=ARGV[1].to_f;printf "%.1f", ((a-b)/a)*100.0' "$ARM_A_SCORING" "$ARM_B_SCORING")"
  local decision="$(ruby -e 's=ARGV[0].to_f; puts(s>=40 ? "STRONG PASS" : s>=25 ? "PASS" : s<15 ? "FAIL" : "INCONCLUSIVE")' "$wall_speed")"
  {
    echo "Adventure-major ordering benchmark"; echo "Timestamp: $STAMP"; echo "Execution order: $ORDER"
    echo "LME commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "Scorer commit: $(git -C ../af-cli-scoring-utility rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "Ollama model: $MODEL"; echo
    echo "Arm A — dimension-major"; echo "  wall-clock_seconds: $ARM_A_WALL"; echo "  scoring-runtime_seconds: $ARM_A_SCORING"; echo
    echo "Arm B — adventure-major"; echo "  wall-clock_seconds: $ARM_B_WALL"; echo "  scoring-runtime_seconds: $ARM_B_SCORING"; echo
    echo "Adventure-major wall-clock reduction: ${wall_speed}%"; echo "Adventure-major scoring-runtime reduction: ${scoring_speed}%"; echo "Decision: $decision"; echo
    echo "Predeclared gate:"; echo "  STRONG PASS: >=40% wall-clock reduction"; echo "  PASS:        >=25% wall-clock reduction"
    echo "  FAIL:        <15% wall-clock reduction"; echo "  INCONCLUSIVE: 15% to <25%; rerun once in reverse arm order"
  } | tee "$RESULT"
  echo
  if [[ "$decision" == "INCONCLUSIVE" ]]; then
    if [[ "$ORDER" == "AB" ]]; then
      echo "Ambiguous band. One reverse-order tie-breaker is justified:"
      echo "  BENCHMARK_ORDER=BA ./run_adventure_major_ordering_benchmark.sh"
    else
      echo "Reverse-order tie-breaker also landed in the ambiguous band; stop and inspect before more inference."
    fi
  fi
  echo "Result saved: $RESULT"
}

CAFFEINATE_PID=""
if command -v caffeinate >/dev/null 2>&1; then caffeinate -dimsu & CAFFEINATE_PID=$!; fi
trap '[[ -n "$CAFFEINATE_PID" ]] && kill "$CAFFEINATE_PID" 2>/dev/null || true' EXIT INT TERM

ARM_A_WALL=""; ARM_A_SCORING=""; ARM_B_WALL=""; ARM_B_SCORING=""
preflight || exit 1
if [[ "$ORDER" == "AB" ]]; then run_arm_a || exit 1; run_arm_b || exit 1; else run_arm_b || exit 1; run_arm_a || exit 1; fi
summarize
