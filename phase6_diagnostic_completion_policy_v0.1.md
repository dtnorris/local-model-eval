# Phase-6 Diagnostic Completion Policy

## Version 0.1 — FROZEN PRE-INFERENCE AMENDMENT

**Status:** Controls Phase-6 execution unless superseded by a later version

**Scope:** Initial Phase-6 Qwen3.6 35B boundary-remediation wave

**External/API inference cost target:** `$0`

## Purpose

This policy separates two decisions that were previously coupled too tightly:

1. **remediation / qualification success** — whether a scorer profile meets the strict predeclared accuracy and integrity standard; and
2. **experiment continuation** — whether the remaining already-authorized local diagnostic cases still have information value.

The strict per-dimension success criteria remain unchanged. This policy changes only the execution stop rule.

## Governing rule

**Complete all 25 authorized core Phase-6 local calls by default.**

An unfavorable numeric result — including an adjacent miss, hard miss, repeated known miss, failure of a per-dimension remediation gate, or a result that makes strict remediation success mathematically impossible — does **not** by itself terminate the remaining core diagnostic cases.

The remaining cases may still distinguish:

- no effect from partial correction;
- boundary-specific correction from global score movement;
- target improvement from control regression;
- local improvement from indiscriminate directional bias; and
- one failed remediation family from another independent family.

The core batch is therefore a diagnostic map as well as a remediation screen.

## Strict success criteria are preserved

This policy does **not** relax any frozen per-dimension `REMEDIATION_SUCCESS`, `INCONCLUSIVE`, qualification, or graduation criterion.

After a family's core cases are complete, adjudicate it using its existing frozen success criteria. A family may therefore be classified `REMEDIATION_FAILED` even though all five calls were intentionally completed.

Completing additional diagnostic cases after strict success has become impossible must not be described as rescuing, retrying, or improving the pass percentage.

## Permitted early stops

Stop or pause execution early only when continuing would no longer produce valid comparable evidence because of a **systemic experiment-integrity failure**, such as:

- wrong model or model alias;
- wrong scorer / guardrail profile;
- target or oracle leakage into blind scorer input;
- wrong canonical Adventure ID or source boundary;
- corrupted or materially incomplete source extraction;
- harness/configuration defect expected to affect subsequent cases;
- output-routing defect that would overwrite or commingle evidence; or
- another systemic operational defect that invalidates the intended experiment.

A case-specific unfavorable score, rationale disagreement, malformed model response, or validator failure is not automatically systemic. Record it under the existing call-accounting rule and continue when later cases can still execute under the intended experiment contract.

If a systemic integrity problem is corrected before inference begins for affected later cases, resume from the next valid authorized slot. Do not favorable-rerun a completed inference merely because its result was unfavorable.

## Family independence

Failure of one dimension's strict remediation criterion does not terminate another dimension's authorized core cases. Social Interaction, Investigation, Lethality / Failure Severity, Puzzle / Problem-Solving, and Seriousness are separate remediation hypotheses.

## Secondary diagnostic interpretation

In addition to the unchanged strict pass/fail classification, summarize each completed family descriptively using the full evidence:

- which known misses became exact;
- which known misses moved closer to the accepted target without becoming exact;
- which known misses were unchanged;
- which cases regressed;
- whether protected controls were preserved; and
- whether movement was boundary-specific or consistent with a blanket directional shift.

These observations are diagnostic only. They do not substitute for the frozen success criterion and do not authorize qualification or further tuning by themselves.

## Cost discipline

The existing budget remains unchanged: **25 core local calls, plus at most one separately authorized Social-only discriminator, 26 maximum, `$0` external inference spend**.

This amendment does not authorize extra calls, paid inference, hosted compute, favorable reruns, or budget transfer between dimensions. It changes only whether already-authorized core calls should be skipped after an unfavorable result.

## Precedence

For the initial Phase-6 wave, this file supersedes conflicting score-triggered early-stop language in earlier Phase-6 pilot documents and workspace READMEs.

Per-dimension documents still control case identity and order, target-scrubbing / blindness requirements, scorer profile, strict success / failure classification, and family-specific interpretation.

This file controls **whether an unfavorable score terminates remaining authorized core inference**.
