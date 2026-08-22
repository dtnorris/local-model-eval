# Phase-6 Local Call Budget

## Version 0.1 — FROZEN

**Status:** Frozen before Phase-6 remediation inference

**Scope:** `local-model-eval` Phase-6 boundary-remediation pilots

**External inference cost:** `$0`

---

## 1. Purpose

This file freezes the maximum local inference budget for the initial Phase-6 remediation wave before any Phase-6 result is observed.

The budget exists to prevent result-driven expansion, benchmark chasing, and silent reallocation of compute after a hypothesis performs poorly.

A budget allocation is a **ceiling**, not a requirement to spend every call. Predeclared per-dimension stop rules may terminate a pilot early.

---

## 2. Frozen envelope

The initial Phase-6 wave is limited to **25 core local inference calls / 26 calls maximum**.

| Dimension | Core allocation | Optional allocation | Hard maximum |
| --- | ---: | ---: | ---: |
| Social Interaction Emphasis | 5 | 1 | 6 |
| Investigation Emphasis | 5 | 0 | 5 |
| Lethality / Failure Severity | 5 | 0 | 5 |
| Puzzle / Problem-Solving Emphasis | 5 | 0 | 5 |
| Seriousness | 5 | 0 | 5 |
| **Total** | **25** | **1** | **26** |

No other model × dimension remediation work is authorized under this budget.

---

## 3. What counts as a call

A **call** is one attempted local model inference for one Phase-6 remediation manifest.

Every inference attempt counts against the budget whether the output is:

- exact, adjacent, or non-adjacent;
- validator-compliant or validator-failed;
- interrupted after model generation has begun; or
- otherwise operationally unusable after inference was attempted.

No favorable rerun is authorized merely because an output was malformed, inconvenient, or unfavorable. A genuinely pre-inference failure that never invokes the model does not consume an inference call.

---

## 4. Allocation rules

1. **Allocations are dimension-specific.** Unused calls from one dimension do not transfer automatically to another.
2. **Five core calls is the maximum default pilot size per dimension.** Stop rules may reduce actual usage.
3. **The single optional call is reserved exclusively for Social Interaction Emphasis.** It cannot be reassigned to Investigation, Lethality, Puzzle, Seriousness, another model, or another dimension under v0.1.
4. **The Social optional call is not a favorable rerun.** It may be used only when the five predeclared core Social calls leave a genuinely unresolved boundary question that was identified in the experiment plan before the optional call is selected.
5. **A failed hypothesis does not unlock unused budget.** Stop the pilot instead of spending remaining calls to improve its apparent percentage.
6. **A successful hypothesis does not unlock extra remediation calls.** Success earns a separately planned fresh qualification run; qualification calls are outside this remediation budget and require their own predeclared plan.
7. **No paid API, hosted inference, rented compute, or larger-model escalation is included.** Any such escalation requires a separate costed decision.

---

## 5. Execution accounting

Use the following fixed accounting slots when manifests are later created:

| Budget slots | Dimension | Authorization |
| --- | --- | --- |
| P6-01 through P6-05 | Social Interaction Emphasis | Core remediation |
| P6-06 | Social Interaction Emphasis | Optional discriminator only |
| P6-07 through P6-11 | Investigation Emphasis | Core remediation |
| P6-12 through P6-16 | Lethality / Failure Severity | Core remediation |
| P6-17 through P6-21 | Puzzle / Problem-Solving Emphasis | Core remediation |
| P6-22 through P6-26 | Seriousness | Core remediation |

The numbering is an accounting namespace, not a required chronological execution order. At most **26 inference attempts** may occur under this budget.

For run logs, record both the manifest ID and its budget slot. A skipped slot remains unused; do not renumber completed evidence after the fact.

---

## 6. Amendment rule

This v0.1 budget is frozen before Phase-6 inference.

Any proposal to exceed a per-dimension cap, reassign the Social optional call, add another model or dimension, or exceed 26 total local inference attempts requires a **new version of this file written before the additional inference is executed**. The amendment must state:

- what new question the added call can answer;
- why existing evidence and the cheaper frozen calls cannot answer it;
- the exact additional call count;
- the success/failure criterion; and
- the stop condition.

Poor or ambiguous results are not by themselves justification for increasing the budget.

---

## 7. Frozen decision

**Authorized now:** 25 core local calls, plus at most one Social-only optional discriminator.

**Maximum:** 26 local inference attempts.

**External inference spend authorized:** `$0`.

**Qualification runs after successful remediation:** not authorized by this file.
