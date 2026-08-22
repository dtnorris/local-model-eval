# Phase-6 boundary remediation workspace

Purpose: isolate follow-up local-model prompt-remediation experiments from the frozen Phase-5 raw/qualification evidence.

## Scope

Phase 6 is for small, falsifiable remediation pilots on model × dimension combinations that survived broad local testing but showed a specific, reproducible boundary or directional bias.

This workspace does **not** alter or reinterpret Phase-5 evidence. A successful Phase-6 remediation pilot only establishes that a new scorer prompt/profile is worth fresh qualification; it does not retroactively qualify the Phase-5 scorer configuration.

## Isolation rules

1. Treat all Phase-5 manifests, run-order files, case indexes, outputs, comparator records, and qualification evidence as read-only baseline inputs.
2. Put every Phase-6 experiment manifest under `experiments/phase6/`.
3. Use experiment IDs beginning with `phase6-remediation-` so generated output remains visibly separate from Phase 4/5 evidence.
4. Version any scorer prompt/guardrail change explicitly in the scoring utility; do not overwrite the Phase-5 production profile in place.
5. One manifest remains one model × one adventure × one dimension × one replicate unless a later Phase-6 plan explicitly says otherwise.
6. Preserve blind scoring: accepted/oracle values may be used by analysis/validation tooling but must never enter target scorer input.
7. Do not favorable-rerun a completed case. If a run is operationally invalid, record that failure and follow the predeclared experiment rule.
8. Execute remediation dimension-by-dimension with the most diagnostic kill test first; stop a failed hypothesis rather than spending the rest of its call budget.
9. Keep external inference cost at `$0` for this phase unless a separately approved escalation decision says otherwise.

## Frozen call-budget envelope

The initial remediation budget is frozen in [`phase6_call_budget_v0.1.md`](phase6_call_budget_v0.1.md). The authorized ceiling is **25 core local calls / 26 maximum**:

| Dimension | Core calls | Optional | Purpose |
| --- | ---: | ---: | --- |
| Social Interaction Emphasis | 5 | 1 | Test remediation of the established downward bias / House of Lament hard miss |
| Investigation Emphasis | 5 | 0 | Test Minimal↔Low and 4↔5 boundary remediation |
| Lethality / Failure Severity | 5 | 0 | Test remediation of interior downward compression |
| Puzzle / Problem-Solving Emphasis | 5 | 0 | Test the diagnosed 2→1 compression once its rationale-level failure is frozen |
| Seriousness | 5 | 0 | Test the diagnosed upward bias once its rationale-level failure is frozen |
| **Total** | **25** | **1** | **26 maximum** |

This table is a budget ceiling, not an instruction to execute every call. Per-dimension stop rules control actual spend. The frozen budget file governs call accounting, non-transferability, the Social-only optional call, and amendments.

## Planned execution order

1. Social Interaction Emphasis
2. Investigation Emphasis
3. Lethality / Failure Severity
4. Puzzle / Problem-Solving Emphasis
5. Seriousness

Do not create final qualification manifests in this workspace until a remediation pilot succeeds. Remediation evidence and subsequent blind qualification evidence must remain distinguishable.

## Namespace

Phase-6 experiment manifests live in:

```text
experiments/phase6/
```

The namespace-specific conventions and current status live in `experiments/phase6/README.md`.
