# Phase-5 raw overnight scoring batch (132 cases)

Purpose: collect local-model scoring evidence tonight without waiting for Terra comparator provenance or early-stop logic.

## Frozen scope

- 14 ordinal Phase-5 candidate dimensions.
- AFAO calibration benchmarks only; up to 10 unique adventures per dimension, and all available when there are 8 or 9.
- 132 total atomic manifests.
- One model × one adventure × one dimension × one replicate.
- Qwen route for 11 candidate dimensions; Nemotron route for Tactical Complexity, Consequential Player Agency, and GM Preparation Burden.
- Local worker only; no paid API/hosted inference.
- No Terra comparator and no early stopping in this raw batch.
- Completed cases are not force-rerun; the batch is resumable.
- An operational failure is logged and the batch continues instead of wasting the rest of the overnight window.

## Case selection

When a dimension has more than 10 AFAO benchmark adventures, the set is balanced across the 1–5 scale. Within a score level, AFHRO v0.4 cohort cases are preferred before AFAO-only cases. The 14 included benchmark tables are identical between the attached AFAO 1.4.1 and current accepted AFAO 1.5.

| Dimension | Candidate | Model | Cases | Scores represented |
| --- | --- | --- | ---: | --- |
| Combat Emphasis | `qwen-combat` | `qwen` | 10 | 1,2,3,4,5 |
| Social Interaction Emphasis | `qwen-social` | `qwen` | 10 | 1,2,3,4,5 |
| Investigation Emphasis | `qwen-investigation` | `qwen` | 9 | 1,2,3,4,5 |
| Puzzle / Problem-Solving Emphasis | `qwen-puzzle` | `qwen` | 9 | 1,2,3,4,5 |
| Tactical Complexity | `nemotron-tactical` | `nemotron` | 10 | 1,2,3,4,5 |
| Lethality / Failure Severity | `qwen-lethality` | `qwen` | 9 | 1,2,3,4,5 |
| Structural Openness | `qwen-structural-openness` | `qwen` | 10 | 1,2,3,4,5 |
| Consequential Player Agency | `nemotron-cpa` | `nemotron` | 9 | 1,2,3,4,5 |
| Seriousness | `qwen-seriousness` | `qwen` | 10 | 1,2,3,4,5 |
| Darkness / Horror Intensity | `qwen-darkness` | `qwen` | 8 | 1,2,3,4,5 |
| Fantastic Weirdness | `qwen-fantastic-weirdness` | `qwen` | 10 | 1,2,3,4,5 |
| GM Preparation Burden | `nemotron-gm-prep` | `nemotron` | 10 | 1,2,3,4,5 |
| Player Beginner Suitability | `qwen-player-beginner` | `qwen` | 8 | 1,2,3,4,5 |
| GM Beginner Suitability | `qwen-gm-beginner` | `qwen` | 10 | 1,2,3,4,5 |

## Install into the repo

Copy/unzip the contents of this package into the root of `~/code/local-model-eval`, preserving the `experiments/` directory.

Then run the no-inference preflight:

```bash
cd ~/code/local-model-eval
./verify_phase5_raw_overnight_132.sh
```

If it passes, launch the overnight batch:

```bash
./run_phase5_raw_overnight_132.sh
```

The run order front-loads one low-end and one high-end case for every candidate before filling in the remaining cases, while grouping by model enough to avoid excessive Qwen/Nemotron swapping.
