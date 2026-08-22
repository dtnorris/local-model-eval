# Phase-5 local-model qualification harness

This layer performs the **numeric and operational** portion of Terra-relative local-model qualification without changing `af-cli-scoring-utility` semantics.

It implements the frozen `AdventureFinder_Phase4_Local_Model_Acceptance_Contract_v0.1` rules for the seventeen interpretive 1–5 dimensions:

- reuse a frozen Terra Comparator Record from archived accepted Terra evidence;
- do not rerun Terra merely to construct the comparator;
- compare local hard-error count against Terra on the same case basis;
- stop a candidate once its hard-error count exceeds Terra's allowance;
- permit adjacent disagreements;
- flag an exact-rate deficit greater than 10 percentage points on the completed qualification set;
- detect repeated identical adjacent boundary shifts as `BOUNDARY_BIAS` requiring later product-impact review;
- never use qualification reruns to seek a favorable stochastic sample.

`# of Sessions` and `Levels` are deliberately **not** supported by this numeric harness. Their frozen contract requires field-level / practical-range qualification rather than mechanically applying 1–5 adjacency rules. Add those only after their Terra field-level comparator criteria are frozen explicitly.

## Cost guardrail

The runner refuses any referenced worker whose configured `hourly_rate_usd` is greater than zero and requires every referenced worker to carry the `local` label. There is no paid-compute override in this Phase-5 harness.

## Files

A Terra comparator records the accepted Terra evidence and the complete comparable qualification cases. Start from:

```text
qualification/templates/terra-comparator.yml
```

A qualification plan maps a local model to a frozen comparator and one normal single-case `lme` experiment manifest per comparator case. Start from:

```text
qualification/templates/phase5-plan.yml
```

Each qualification experiment manifest MUST:

- contain exactly one model;
- contain exactly one adventure;
- use the comparator dimension;
- use `replicates: 1`;
- reference only local zero-dollar workers.

Using one case per manifest is intentional: it lets the outer qualification runner stop the model × dimension candidate immediately when further inference becomes low-value.

## Dry run

```bash
bin/lme-qualify qualification/phase5.yml --dry-run
```

The dry run validates the comparator, case coverage, manifests, worker labels/rates, and prints the maximum number of new inference calls. It makes no worker HTTP calls and runs no inference.

## Overnight run

```bash
./run_phase5_local_qualification.sh qualification/phase5.yml
```

The wrapper runs under `caffeinate -dimsu`. The qualification runner preflights each candidate, delegates inference to normal `bin/lme run`, and relies on `lme`'s existing completed-job resume behavior.

An operational failure (for example, worker outage) aborts the overall overnight queue instead of manufacturing a long series of invalid results. A **qualification** failure stops only that candidate and proceeds to the next candidate.

## Resume and force

Re-run the same command to resume. Completed qualification cases recorded in the Phase-5 bundle are skipped, and completed `lme` jobs are already resume-safe.

```bash
bin/lme-qualify qualification/phase5.yml --force
```

`--force` rebuilds Phase-5 bookkeeping and summary files. It does **not** pass `--force` to `bin/lme`, so already-completed model inference is not repeated.

## Output

```text
output/qualification/<plan-name>/
├── plan.yml
├── environment.json
├── comparators/
│   └── <frozen-comparator>.yml
├── results.csv
└── summary.md
```

The underlying native scorer artifacts remain in the existing `output/<experiment>/...` directories and remain authoritative.

## Interpretation boundary

A numeric pass is reported as either:

- `QUALIFICATION_NUMERIC_PASS_INTEGRITY_REVIEW_REQUIRED`, or
- `QUALIFICATION_NUMERIC_PASS_BIAS_REVIEW_REQUIRED`.

The harness intentionally does **not** emit `LOCAL_QUALIFIED` or `LOCAL_QUALIFIED_WITH_BIAS`. Final acceptance still requires human review of canonical-source identity, grounding, conceptual integrity, and any required matcher/product-impact review.
