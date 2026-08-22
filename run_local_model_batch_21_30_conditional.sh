#!/bin/zsh

cd "${0:A:h}" || exit 1

caffeinate -dimsu &
CAFFEINATE_PID=$!
trap 'kill "$CAFFEINATE_PID" 2>/dev/null || true' EXIT

echo "Working directory: $(pwd)"
echo "caffeinate active (PID $CAFFEINATE_PID)"
echo

metric_value() {
  local experiment_dir="$1"
  local metric="$2"

  ruby -rcsv -e '
    root, metric = ARGV
    files = Dir[File.join(root, "runs", "*", "native", "assessments", "*.csv")]
    exit 2 if files.empty?
    file = files.max_by { |f| File.mtime(f) }
    row = CSV.foreach(file, headers: true).find { |r| r["metric"] == metric }
    exit 3 unless row && row["value"] && !row["value"].empty?
    print row["value"]
  ' "$experiment_dir" "$metric"
}

gate_range() {
  local experiment_dir="$1"
  local metric="$2"
  local low="$3"
  local high="$4"
  local value

  value=$(metric_value "$experiment_dir" "$metric") || return 1

  echo "  prerequisite: $metric = $value"

  [[ "$value" =~ '^[0-9]+$' ]] || return 1
  (( value >= low && value <= high ))
}

gate_levels_10() {
  local experiment_dir="output/10-qwen-levels-adv0262-control-v1"
  local start end ds de

  start=$(metric_value "$experiment_dir" "Level Start") || return 1
  end=$(metric_value "$experiment_dir" "Level End") || return 1

  echo "  prerequisite: Level Start = $start, Level End = $end"

  [[ "$start" =~ '^[0-9]+$' ]] || return 1
  [[ "$end" =~ '^[0-9]+$' ]] || return 1

  ds=$(( start - 1 ))
  de=$(( end - 5 ))
  (( ds < 0 )) && ds=$(( -ds ))
  (( de < 0 )) && de=$(( -de ))

  # Experiment 10 survives if exact, or exactly one endpoint is adjacent.
  (( (ds == 0 && de == 0) ||
     (ds == 1 && de == 0) ||
     (ds == 0 && de == 1) ))
}

run_one() {
  local manifest="$1"

  echo
  echo "================================================================"
  echo "RUNNING: $manifest"
  echo "================================================================"

  if ! bin/lme run "$manifest"; then
    echo
    echo "OPERATIONAL ERROR: $manifest"
    return 1
  fi
}

skip_one() {
  local manifest="$1"
  local prerequisite="$2"

  echo
  echo "================================================================"
  echo "SKIPPING: $manifest"
  echo "GATE CLOSED: prerequisite experiment $prerequisite did not survive"
  echo "================================================================"
}

echo "Preflight: checking workers/models..."

if ! bin/lme worker-check experiments/21-nemotron-exploration-adv0053-mid-control-v1.yml; then
  echo "ERROR: Nemotron/mac worker preflight failed."
  exit 1
fi

if ! bin/lme worker-check experiments/25-qwen-weirdness-adv0062-lower-endpoint-v1.yml; then
  echo "ERROR: Qwen/mac worker preflight failed."
  exit 1
fi

# 21 <- experiment 01: Exploration target 2; 1-3 survives.
if gate_range \
  output/01-nemotron-exploration-adv0062-discriminator-v1 \
  "Exploration Emphasis" 1 3
then
  run_one experiments/21-nemotron-exploration-adv0053-mid-control-v1.yml || exit 1
else
  skip_one experiments/21-nemotron-exploration-adv0053-mid-control-v1.yml 01
fi

# 22 <- experiment 02: Tactical target 4; 3-5 survives.
if gate_range \
  output/02-nemotron-tactical-complexity-adv0189-discriminator-v1 \
  "Tactical Complexity" 3 5
then
  run_one experiments/22-nemotron-tactical-adv0278-lower-endpoint-v1.yml || exit 1
else
  skip_one experiments/22-nemotron-tactical-adv0278-lower-endpoint-v1.yml 02
fi

# 23 <- experiment 03: CPA target 4; 3-5 survives.
if gate_range \
  output/03-nemotron-cpa-adv0040-discriminator-v1 \
  "Consequential Player Agency" 3 5
then
  run_one experiments/23-nemotron-cpa-adv0034-lower-control-v1.yml || exit 1
else
  skip_one experiments/23-nemotron-cpa-adv0034-lower-control-v1.yml 03
fi

# 24 <- experiment 04: GM Prep target 4; 3-5 survives.
if gate_range \
  output/04-nemotron-gm-prep-adv0287-discriminator-v1 \
  "GM Preparation Burden" 3 5
then
  run_one experiments/24-nemotron-gm-prep-adv0262-mid-control-v1.yml || exit 1
else
  skip_one experiments/24-nemotron-gm-prep-adv0262-mid-control-v1.yml 04
fi

# 25 and 26 <- experiment 08: Weirdness target 4; 3-5 survives.
if gate_range \
  output/08-qwen-weirdness-adv0278-upper-control-v1 \
  "Fantastic Weirdness" 3 5
then
  run_one experiments/25-qwen-weirdness-adv0062-lower-endpoint-v1.yml || exit 1
  run_one experiments/26-qwen-weirdness-adv0040-upper-endpoint-v1.yml || exit 1
else
  skip_one experiments/25-qwen-weirdness-adv0062-lower-endpoint-v1.yml 08
  skip_one experiments/26-qwen-weirdness-adv0040-upper-endpoint-v1.yml 08
fi

# 27 <- experiment 19: Player Beginner target 5; 4-5 survives.
if gate_range \
  output/19-qwen-player-beginner-adv0262-upper-endpoint-v1 \
  "Player Beginner Suitability" 4 5
then
  run_one experiments/27-qwen-player-beginner-adv0034-lower-endpoint-v1.yml || exit 1
else
  skip_one experiments/27-qwen-player-beginner-adv0034-lower-endpoint-v1.yml 19
fi

# 28 <- experiment 07: GM Beginner target 3; 2-4 survives.
if gate_range \
  output/07-qwen-gm-beginner-adv0034-mid-control-v1 \
  "GM Beginner Suitability" 2 4
then
  run_one experiments/28-qwen-gm-beginner-adv0287-upper-endpoint-v1.yml || exit 1
else
  skip_one experiments/28-qwen-gm-beginner-adv0287-upper-endpoint-v1.yml 07
fi

# 29 <- experiment 09: Sessions target 2; 1-3 survives.
if gate_range \
  output/09-qwen-sessions-adv0062-two-session-control-v1 \
  "# of Sessions" 1 3
then
  run_one experiments/29-qwen-sessions-adv0262-scaling-control-v1.yml || exit 1
else
  skip_one experiments/29-qwen-sessions-adv0262-scaling-control-v1.yml 09
fi

# 30 <- experiment 10: Levels 1->5 exact or one adjacent endpoint survives.
if gate_levels_10
then
  run_one experiments/30-qwen-levels-adv0062-high-narrow-control-v1.yml || exit 1
else
  skip_one experiments/30-qwen-levels-adv0062-high-narrow-control-v1.yml 10
fi

echo
echo "================================================================"
echo "CONDITIONAL BATCH 21-30 FINISHED"
echo "================================================================"
