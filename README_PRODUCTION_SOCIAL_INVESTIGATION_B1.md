# Production Batch B1 — Social Interaction + Investigation

This bundle expands the same 33-adventure AdventureFinder cohort used by the
first production batch, now on the two newly local-qualified dimensions:

- **Social Interaction Emphasis** — Qwen3.6 35B, `phase6-v0.3`
- **Investigation Emphasis** — Qwen3.6 35B, `phase6-v0.4`

## Frozen matrix

- Cohort: **33 canonical adventures**
- Dimensions: **2**
- Full matrix: **66 cells**
- Existing accepted AFAO calibration cells protected/skipped: **3**
- Fresh local production inference cells: **63**
  - Social Interaction Emphasis: **31**
  - Investigation Emphasis: **32**
- One model × one adventure × one dimension × one replicate per RUN manifest.
- Adventure-major ordering; Social first, then Investigation, except protected skips.
- Local worker only (`mac`, label `local`).
- External/API inference cost: **$0**.

Protected accepted cells:

- ADV-0257 / Social Interaction Emphasis = **4**
- ADV-0229 / Social Interaction Emphasis = **5**
- ADV-0234 / Investigation Emphasis = **5**

The exact 66-cell matrix is frozen in
`production_social_investigation_b1_case_index.csv`.

## Qualified scorer dependency

These production dimensions were qualified with `af-cli-scoring-utility`
commit:

`b90684c3f65b1d6ac95381f8bb5dd2c11ef38822`

The adjacent scorer checkout may be at that commit or a descendant, but the
Social/Investigation profile implementation stack must remain unchanged from
that qualified baseline. The verifier fails closed if:

- the qualified commit is not an ancestor of the scorer checkout;
- the Social or Investigation guardrail/metadata files changed afterward;
- those protected scorer files have uncommitted changes; or
- a rendered zero-inference scorer preflight does not actually contain the
  required v0.3/v0.4 guardrail and profile metadata.

This means the scorer may remain on the existing
`phase6-boundary-remediation` branch for this run, or PR #71 may later be merged
into scorer `main`; no `local-model-eval` Phase-6 branch is required.

## Mandatory preflight — no inference

From the `local-model-eval` checkout containing this bundle:

```sh
./verify_production_social_investigation_b1.sh
```

The verifier checks:

1. exactly 66 matrix cells, 63 RUN cells, and the 3 exact protected accepted cells;
2. exactly 31 Social and 32 Investigation RUN manifests;
3. exact adventure-major run order and no duplicate production cells;
4. Qwen model, local worker, one replicate, scorer path/mode, cost cap, and
   manifest-declared qualified profile for every RUN cell;
5. `qwen` still maps to `qwen3.6:35b-a3b`;
6. scorer ancestry/profile integrity against the qualified scorer baseline;
7. a **zero-inference rendered preflight** for each dimension proves the actual
   qualified guardrail is active;
8. all 63 manifests pass `bin/lme plan`; and
9. the local worker can see the Qwen model.

It ends with `NO INFERENCE WAS RUN.`

## Launch

After preflight passes:

```sh
./run_production_social_investigation_b1.sh
```

The runner invokes the verifier again, activates both qualified profile
environment variables, starts `caffeinate -dimsu`, and runs the 63 cells
sequentially. Isolated operational failures are logged and do not waste the
remaining compute window. Completed jobs are skipped by `bin/lme`, so the batch
is resumable.

Failures, if any, are collected in:

`production_social_investigation_b1_failed.txt`

## Runtime / cost expectation

The immediately preceding local batch completed 128 calls in about 5h52m.
Purely linear scaling would put 63 calls near **2h54m**. Treat that only as a
planning estimate; source length and dimension behavior can move the actual
runtime.

External/API inference cost is **$0**. No paid compute or new hardware is
authorized by this batch.

## Production-data status

Outputs are **proposed production assessments pending QC/ingestion**. The three
accepted calibration cells are deliberately not rerun or overwritten.
