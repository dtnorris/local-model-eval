# Phase-6 Social Interaction Remediation Pilot

## Version 0.1 — FROZEN

**Status:** Frozen before any Phase-6 Social Interaction inference

**Dimension:** Social Interaction Emphasis

**Model:** `qwen3.6:35b-a3b`

**Experimental scorer profile:** `phase6-v0.3`

**Hypothesis:** `SOCIAL_CROSS_MODE_COMPETITION_BIAS`

**Core budget:** 5 calls (`P6-01` through `P6-05`)

**Optional budget:** `P6-06` remains reserved but is not authorized by this file

**External inference cost:** `$0`

---

## 1. Purpose

This pilot tests one narrow hypothesis: the current Qwen Social Interaction scorer undercounts substantive social play when the same scenes also serve Investigation or another mode, and it uses substantial non-social play as a downward veto even when Social Interaction independently satisfies its own anchor.

The experimental `phase6-v0.3` guardrail is intended only to correct that cross-mode competition error. It must not create a general upward scoring preference.

This is a remediation experiment, not final qualification. Passing this pilot only makes the new scorer profile eligible for a separately planned blind qualification run.

---

## 2. Frozen evidence basis

The Phase-5 Qwen Social Interaction run produced 9 valid assessments from 10 attempts:

- 6 exact;
- 2 adjacent misses;
- 1 hard miss;
- all three substantive misses were downward.

The three diagnostic misses were:

| Adventure | Frozen AFAO target | Phase-5 Qwen | Error |
| --- | ---: | ---: | --- |
| `ADV-0287` — The House of Lament | 3 | 1 | hard, -2 |
| `ADV-0257` — The Magister's Masquerade | 4 | 3 | adjacent, -1 |
| `ADV-0229` — Danger at Dunwater | 5 | 4 | adjacent, -1 |

The two controls below were exact under the Phase-5 scorer and cover the untouched low end of the scale:

| Adventure | Frozen AFAO target | Phase-5 Qwen | Role |
| --- | ---: | ---: | --- |
| `ADV-0034` — Tomb of Horrors | 1 | 1 | score-1 anti-inflation control |
| `ADV-0053` — Call of the Wild | 2 | 2 | score-2 anti-inflation control |

Together the five core cases form a complete 1–5 Social Interaction ladder without adding benchmark cases merely to improve apparent performance.

---

## 3. Frozen core cases and execution order

The call order is intentionally diagnostic-first rather than score-order.

| Order / budget slot | Adventure | Target | Phase-5 baseline | Role |
| --- | --- | ---: | ---: | --- |
| **P6-01** | `ADV-0287` — The House of Lament | **3** | 1 | **primary kill test; cross-mode overlap failure** |
| **P6-02** | `ADV-0257` — The Magister's Masquerade | **4** | 3 | upper-boundary diagnostic |
| **P6-03** | `ADV-0229` — Danger at Dunwater | **5** | 4 | upper-end diagnostic |
| **P6-04** | `ADV-0034` — Tomb of Horrors | **1** | 1 | lower-end anti-inflation control |
| **P6-05** | `ADV-0053` — Call of the Wild | **2** | 2 | low-anchor anti-inflation control |

Each case is one model × one adventure × one dimension × one replicate.

The accepted target score is for post-run adjudication only and must not enter blind scorer input.

---

## 4. Mandatory House kill test

Run `P6-01` first.

For `ADV-0287` — The House of Lament, target **3**:

- score **1** or **5** is a hard error;
- score **2**, **3**, or **4** is within ±1.

### Immediate stop condition

If House produces another hard error, classify the pilot `REMEDIATION_FAILED` and stop Social Interaction remediation immediately.

Do **not** run `P6-02` through `P6-05`, and do not use optional slot `P6-06` to rescue the hypothesis.

Clearing the House kill test is necessary but not sufficient for remediation success.

---

## 5. Upper-diagnostic checkpoint

If House clears the kill test, run `P6-02` and `P6-03` next.

These cases test whether the same guardrail also removes the observed downward ceiling at the 3↔4 and 4↔5 boundaries.

Stop before the controls and classify `REMEDIATION_FAILED` if either of the following occurs:

1. either upper diagnostic becomes a hard error; or
2. both upper diagnostic cases reproduce their Phase-5 misses unchanged (`4→3` and `5→4`).

The second rule prevents spending control calls when the proposed cross-mode correction has shown no measurable effect on the upper-boundary behavior it was designed to address.

---

## 6. Anti-inflation controls

Only after the diagnostic checkpoint passes, run `P6-04` and `P6-05`.

The v0.3 clarification must not turn incidental, primarily expository/transactional, or clearly secondary NPC interaction into a higher Social score merely because scenes contain NPCs, information exchange, or player choice.

Therefore:

- Tomb of Horrors should remain **1**;
- Call of the Wild should remain **2**.

A hard error on either control is `REMEDIATION_FAILED`.

---

## 7. Frozen result classification

After all five core calls, classify the pilot using the following rules.

### `REMEDIATION_SUCCESS`

All five cases are exact:

- House = 3;
- Magister's Masquerade = 4;
- Danger at Dunwater = 5;
- Tomb of Horrors = 1;
- Call of the Wild = 2.

This result supports the narrow hypothesis strongly enough to proceed to a separately designed blind qualification run under `phase6-v0.3`.

### `REMEDIATION_FAILED`

Any mandatory early-stop condition fires, or the completed core set contains a hard error.

Do not spend additional Social calls to improve the percentage.

### `INCONCLUSIVE`

All five core cases complete with:

- no hard errors;
- at least 4/5 exact;
- 5/5 within ±1; and
- exactly one remaining adjacent disagreement.

An inconclusive result does **not** authorize an automatic sixth call. `P6-06` remains budget-reserved only. Before using it, freeze a one-case addendum identifying the unresolved boundary question, the exact discriminator adventure, its target, and its decision rule.

Any five-case result weaker than the definition above is `REMEDIATION_FAILED`, not `INCONCLUSIVE`.

---

## 8. No favorable reruns

Every attempted inference counts under the Phase-6 budget contract.

Do not rerun a completed case because its score is unfavorable. An operationally malformed or validator-failed inference still consumes its budget slot once model inference has begun and is adjudicated under the existing Phase-6 call-budget rules.

---

## 9. Frozen decision

The authorized Social Interaction remediation pilot is exactly the five core cases and order above.

**First action:** run House of Lament (`P6-01`).

**Hard stop:** if House remains a hard miss, terminate Social remediation immediately.

**Maximum currently authorized by this pilot:** 5 inference calls.

**Optional `P6-06`:** reserved by the global budget but requires a separately frozen one-case addendum before execution.
