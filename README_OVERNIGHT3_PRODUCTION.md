# Overnight3 Production Scoring — 2026-08-22/23

This bundle is repo-root-relative for `dtnorris/local-model-eval`.

## Frozen production matrix

- Cohort: 33 canonical Adventure IDs supplied for Overnight3.
- Authorized local model: `qwen` => `qwen3.6:35b-a3b`.
- Authorized dimensions in this batch:
  - Combat Emphasis
  - Structural Openness
  - Darkness / Horror Intensity
  - Player Beginner Suitability
- Full 33 × 4 matrix: 132 cells.
- AMC 2.4.5 cells already populated and protected: 9.
- New production inference cells: **123**.
- Ordering: adventure-major, preserving the supplied Adventure-ID order; within each adventure the dimension order is Combat, Structural Openness, Darkness/Horror, Player Beginner.
- One model × one adventure × one dimension × one replicate per manifest.
- Local worker only (`mac`, required label `local`).
- No paid compute; manifest cost cap remains `$0.01` as a defensive soft ceiling.

## Protected AMC 2.4.5 cells (do not rerun)

- ADV-0278 / Combat Emphasis = 1
- ADV-0278 / Structural Openness = 5
- ADV-0200 / Combat Emphasis = 1
- ADV-0200 / Structural Openness = 1
- ADV-0230 / Combat Emphasis = 4
- ADV-0288 / Structural Openness = 1
- ADV-0323 / Structural Openness = 5
- ADV-0033 / Combat Emphasis = 5
- ADV-0020 / Combat Emphasis = 3

The exact 132-cell matrix, including RUN/SKIP disposition and source metadata, is in `production_overnight3_case_index.csv`.

## Install into the repo

From the local-model-eval repo root, unzip/copy this bundle so that:

- manifests land in `experiments/production-overnight3-2026-08-22/`
- the run-order, verifier, runner, and case-index files land at repo root.

Then ensure the two shell files are executable if your unzip tool did not preserve mode:

```sh
chmod +x verify_production_overnight3_123.sh run_production_overnight3_123.sh
```

## Mandatory dry run — no inference

```sh
./verify_production_overnight3_123.sh
```

The verifier hard-checks:

1. exactly 123 RUN manifests and 9 AMC-protected skips;
2. no duplicate production cells;
3. exact per-dimension counts (28 Combat, 29 Structural, 33 Darkness/Horror, 33 Player Beginner);
4. the exact nine AMC skip cells and their existing values;
5. every manifest's model, adventure, dimension, replicate, worker, labels, scorer mode/path, and cost cap;
6. `qwen` still maps to `qwen3.6:35b-a3b`;
7. every manifest passes `bin/lme plan`;
8. the local worker can see the required Qwen model.

It ends with `NO INFERENCE WAS RUN.`

## Launch production

Only after the verifier passes:

```sh
./run_production_overnight3_123.sh
```

The runner executes the verifier again as a hard gate, activates `caffeinate -dimsu`, runs the 123 cells sequentially, continues after isolated operational failures, and relies on `bin/lme`'s completed-job skipping so the batch is resumable.

Failures, if any, are collected in `production_overnight3_failed.txt`.

## Production-data status

These outputs should be treated as **proposed production assessments pending QC/ingestion**, not as silent overwrites of accepted AMC values. The runner deliberately creates no manifests for the nine already-populated target cells.
