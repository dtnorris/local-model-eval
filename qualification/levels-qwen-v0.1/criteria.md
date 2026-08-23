# Qwen `Levels` Qualification Criteria v0.1

**Status:** Frozen before the three fresh qualification inferences.

**Candidate:** Qwen3.6 35B (`qwen` => `qwen3.6:35b-a3b`)
**Dimension:** `Levels` / Level Start + Level End (Levels v2.1)
**Execution cost:** local Mac only; **$0 external/API inference**
**Fresh inference budget:** at most **3** one-replicate cases; no favorable reruns.

## Purpose

Determine whether Qwen can be accepted for local production assessment of the frozen Levels v2.1 field. Levels is not a 1--5 interpretive score: it is a pair of discrete character-level endpoints, with explicit uncertainty when the source cannot responsibly establish an endpoint.

Because AdventureFinder can use these fields as hard matching constraints, **adjacent integers are not automatically acceptable**. A one-level error can change whether an adventure is a valid party-entry or progression match. This qualification therefore uses exact field semantics rather than the ordinary ordinal `±1` tolerance used elsewhere.

No new Terra inference is required for this qualification. The comparator is the already frozen AFAO v1.5 / human-adjudicated Levels v2.1 reference logic. Spending another frontier-model call would not resolve an unmet evidentiary need.

## Fresh benchmark cases and frozen targets

The values below are for **post-inference adjudication only**. They MUST remain absent from the three executable experiment manifests and MUST NOT be passed to the scorer.

| Order | Adventure | Frozen Level Start | Frozen Level End | Qualification role |
| ---: | --- | ---: | ---: | --- |
| 1 | **ADV-0040 — Expedition to the Barrier Peaks** | **11** | **13** | Completion-award ownership: the level explicitly awarded for completing the canonical adventure counts in Level End. |
| 2 | **ADV-0278 — Witchlight Carnival** | **1** | **1** | Canonical child-unit boundary: advancement belonging only to later Hither material must not be assigned backward. |
| 3 | **ADV-0034 — Tomb of Horrors** | **Uncertain / Requires Source Verification** | **Uncertain / Requires Source Verification** | Qualitative “high-level” guidance must not be converted into invented integers. |

The order is intentional. It asks the highest-information completion-ownership question first, then the canonical-transition boundary, then the uncertainty/refusal behavior.

### Supplemental existing evidence

Existing clean local evidence may be retained as supporting context rather than rerun merely to enlarge the sample, including the previously exact Qwen controls for **ADV-0262 — Lost Mine of Phandelver (1 -> 5)** and **ADV-0278 — Witchlight Carnival (1 -> 1)**. The fresh ADV-0278 call in this qualification is a deliberate reproducibility check of a product-critical canonical-boundary rule, not a substitute for the archived control.

## Exact comparator

A fresh case **passes** only when all applicable requirements below are satisfied:

1. **Integer endpoint case:** Level Start and Level End both exactly match the frozen integers above.
2. **Uncertainty case:** both endpoints preserve the frozen uncertainty state; manufacturing any discrete integer for Tomb of Horrors fails the case.
3. Structured scorer output is valid and the assessment is grounded to the correct canonical Adventure ID.
4. The rationale applies Levels v2.1 ownership semantics rather than inheriting a parent campaign, adjacent adventure, anthology placement, or generic encounter difficulty.
5. The result was produced once under the frozen manifest. A completed unfavorable inference is not rerun to seek a better sample.

There is **no `±1` tolerance** and no “practical agreement” substitution for the canonical endpoint pair.

## Qualification decision

Call Qwen **`LOCAL_QUALIFIED` for `Levels`** only when:

- all three fresh cases pass the exact comparator above;
- there is no target leakage into scorer inputs;
- there is no wrong-canonical-unit, source-grounding, structured-output, or operational pathology that makes a case non-comparable; and
- the combined fresh + archived evidence does not reveal a contradictory Levels failure pattern.

A genuine semantic miss on any fresh case is sufficient to **withhold qualification**. Do not spend the remaining qualification calls merely because they were budgeted; they may be run later only if the goal is explicitly changed from qualification to diagnostic evidence collection.

If a case fails before inference because of infrastructure, missing source, or configuration, classify the wave as **INCOMPLETE**, not as a model miss. Repairing a true pre-inference operational failure is allowed. Rerunning a completed inference because its answer was unfavorable is not.

## Execution policy and stop conditions

The default runner is deliberately sequential:

1. run ADV-0040;
2. adjudicate its persisted output against this document;
3. continue only if it passes;
4. repeat for ADV-0278, then ADV-0034.

This is the cheapest falsifiable experiment: a first-case failure already answers the production-authorization question and prevents unnecessary compute. `run_qwen_levels_qualification.sh --all` exists only for intentionally collecting all three diagnostic samples without interactive gates.

Do not purchase API inference, hosted compute, rented GPUs, or additional hardware for this qualification. The maximum planned external/API inference cost is **$0.00**.
