# Phase-6 Puzzle / Problem-Solving Emphasis Remediation Pilot v0.1

**Status:** FROZEN — pre-inference
**Dimension:** Puzzle / Problem-Solving Emphasis
**Candidate:** Qwen3.6 35B
**Prompt profile:** `phase6-v0.2`
**Core-call budget:** 5
**Optional calls:** 0
**External/API inference cost target:** $0

## Purpose

Test the Phase-6 Low-anchor admission clarification against the demonstrated Qwen
failure mode: repeated accepted-score-2 material being compressed to score 1 because
localized, optional, short, secondary, partly signposted, or cross-mode problem-solving
was treated as insufficiently developed to enter the Low anchor.

This is a remediation discriminator, not a fresh qualification run. Passing it only
earns the right to proceed to a later benchmark-blind qualification exercise.

## Frozen five-case set

| Adventure | Adventure ID | Accepted score | Phase-5 Qwen | Role |
| --- | --- | ---: | ---: | --- |
| Call of the Wild | ADV-0053 | **2** | **1** | explicit localized/optional-puzzle recovery test |
| No Honour Among Thieves | ADV-0062 | **2** | **1** | constrained/open-ended planning recovery test |
| The House of Lament | ADV-0287 | **2** | **1** | prescribed/signposted-mechanism recovery test |
| Expedition to the Barrier Peaks | ADV-0040 | **1** | **1** | Minimal anti-inflation control |
| White Plume Mountain | ADV-0031 | **4** | **4** | upper-ladder anti-overcorrection control |

The accepted scores, prior model results, and diagnostic roles are evaluation metadata
only. They MUST NOT appear in the blind scorer input.

## Why these controls

The three accepted-score-2 cases directly span the demonstrated lower-boundary
failure morphologies identified in `phase6_puzzle_diagnosis_v0.1.md`.

**Expedition to the Barrier Peaks** is the lower control because the Phase-5 scorer
already preserved it at Minimal. The Phase-6 fix must not turn the clarified Low
admission rule into "any authored obstacle counts."

**White Plume Mountain** is the upper control because Phase-5 reproduced its accepted
score 4 exactly. It is more diagnostic for upward overcorrection than a score-5
control: an indiscriminate upward shift could move 4→5, whereas score 5 has no higher
numeric value available.

## Frozen execution order

Run in this order:

1. **P6-PUZZLE-01 — Call of the Wild — target 2**
2. **P6-PUZZLE-02 — No Honour Among Thieves — target 2**
3. **P6-PUZZLE-03 — The House of Lament — target 2**
4. **P6-PUZZLE-04 — Expedition to the Barrier Peaks — target 1**
5. **P6-PUZZLE-05 — White Plume Mountain — target 4**

The three known 2→1 failures run first. The two control calls are spent only after the
targeted admission fix has survived all three recovery cases.

## Stop conditions

### Recovery gate

- If **P6-PUZZLE-01 — Call of the Wild** is not scored exactly **2**, stop
  immediately and classify `REMEDIATION_FAILED`.
- If Call is exact but **P6-PUZZLE-02 — No Honour Among Thieves** is not scored
  exactly **2**, stop immediately and classify `REMEDIATION_FAILED`.
- If the first two are exact but **P6-PUZZLE-03 — The House of Lament** is not
  scored exactly **2**, stop immediately and classify `REMEDIATION_FAILED`.

Any persistent 2→1 miss means the targeted Low-anchor overqualification bias remains.
Do not spend control calls to improve the aggregate percentage.

A 2→3 miss also fails the pilot: the intervention must recover Low, not merely move
the cases upward.

### Anti-overcorrection gate

Only after all three recovery cases are exact:

- Run **P6-PUZZLE-04 — Expedition to the Barrier Peaks**. It must remain exactly
  **1**.
- Run **P6-PUZZLE-05 — White Plume Mountain**. It must remain exactly **4**.

Barrier 1→2 would show lower-boundary inflation. White Plume 4→5 would show that a
supposedly 1↔2-only intervention is leaking upward. Any other numeric miss also fails.

## Success criterion

The only passing result is:

> **5/5 exact, 0 hard errors, 0 malformed outputs, and no integrity failure.**

There is no `INCONCLUSIVE` outcome and no sixth Puzzle remediation call.

A malformed output, canonical-unit failure, material grounding failure, or any
numeric miss is `REMEDIATION_FAILED`.

## Interpretation

`REMEDIATION_SUCCESS` means only that the Phase-6 v0.2 intervention recovered all
three demonstrated Low morphologies while preserving the frozen lower and upper
controls.

It does **not** establish `LOCAL_QUALIFIED`. Success permits preparation of a fresh,
benchmark-blind Puzzle / Problem-Solving Emphasis qualification plan using
`phase6-v0.2`.

`REMEDIATION_FAILED` ends this routine prompt-tuning hypothesis. Do not consume
additional calls merely to rescue the percentage. Further work requires a materially
different, independently justified hypothesis and a separately frozen budget.

## Frozen execution requirements

- Model: Qwen3.6 35B local route used by the Phase-5 Qwen candidate.
- One adventure × one dimension × one replicate per manifest.
- Explicit profile: `AF_PUZZLE_GUARDRAIL_PROFILE=phase6-v0.2`.
- Preserve canonical source-boundary handling and target-score scrubbing.
- Preserve the existing structured-output schema and validator.
- No favorable stochastic reruns.
- Stop immediately when a stop condition is met.
- Persist raw response, normalized assessment, run metadata, model identity, prompt
  profile, and guardrail SHA for every attempted inference.
