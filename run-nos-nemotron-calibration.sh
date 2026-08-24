(
  for manifest in \
    experiments/nos-two-stage-nemotron-calibration-v0.1/01-adv0200-lake-monster.yml \
    experiments/nos-two-stage-nemotron-calibration-v0.1/02-adv0287-house-of-lament.yml \
    experiments/nos-two-stage-nemotron-calibration-v0.1/03-adv0040-barrier-peaks.yml \
    experiments/nos-two-stage-nemotron-calibration-v0.1/04-adv0262-lost-mine-of-phandelver.yml \
    experiments/nos-two-stage-nemotron-calibration-v0.1/05-adv0277-wild-beyond-the-witchlight.yml
  do
    echo "=== Running $manifest ==="
    env AF_NOS_TWO_STAGE_PROFILE=nemotron-v0.1 \
      bin/lme run "$manifest" || exit 1
  done
)
