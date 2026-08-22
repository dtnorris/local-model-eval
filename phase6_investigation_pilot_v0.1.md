# Phase-6 Investigation Emphasis Remediation Pilot v0.1

**Status:** FROZEN — pre-inference  
**Dimension:** Investigation Emphasis  
**Candidate:** Qwen3.6 35B  
**Prompt profile:** `phase6-v0.4`  
**Core-call budget:** 5  
**Optional calls:** 0  
**External/API inference cost target:** $0

## Purpose

Test the single Phase-6 Investigation remediation hypothesis already implemented in
`af-cli-scoring-utility`: correct the demonstrated **Minimal ↔ Low (1 ↔ 2)**
qualifying-inquiry error and **High ↔ Very High (4 ↔ 5)** independent-spine error
without disturbing correct lower-middle and upper-middle behavior.

This pilot is a deliberately compact discriminator ladder, not a fresh qualification
run. Passing it earns only the right to proceed to a later benchmark-blind
qualification set.

## Frozen five-case ladder

| Order | Adventure | Adventure ID | Accepted target | Role |
| ---: | --- | --- | ---: | --- |
| P6-INV-01 | Tomb of Horrors | ADV-0034 | **1** | Minimal endpoint / known 1→2 failure |
| P6-INV-02 | No Honour Among Thieves | ADV-0062 | **1** | Second Minimal morphology / known 1→2 failure |
| P6-INV-03 | Expedition to the Barrier Peaks | ADV-0040 | **2** | Low anti-overcorrection control |
| P6-INV-04 | The House of Lament | ADV-0287 | **4** | High upper-ladder control |
| P6-INV-05 | The Styes | ADV-0234 | **5** | Very High endpoint / known 5→4 failure |

The accepted target values are evaluation metadata only and MUST NOT appear in the
blind scorer input.

## Execution order and stop conditions

Run the cases in the frozen order above.

### Gate A — lower-boundary remediation

1. Run **P6-INV-01 — Tomb of Horrors**.
2. If Tomb is not scored **1**, stop immediately and classify the pilot
   `REMEDIATION_FAILED`.
3. If Tomb is exact, run **P6-INV-02 — No Honour Among Thieves**.
4. If No Honour is not scored **1**, stop immediately and classify the pilot
   `REMEDIATION_FAILED`.

The lower-boundary hypothesis is deliberately held to an exact standard because the
v0.4 intervention was written specifically to repair the repeated 1→2 error. An
adjacent 2 on either known Minimal case means that remediation did not solve the
demonstrated failure.

### Gate B — anti-overcorrection and upper endpoint

5. If both Minimal cases are exact, run **P6-INV-03 — Expedition to the Barrier Peaks**.
6. If Barrier Peaks is not scored **2**, stop immediately and classify the pilot
   `REMEDIATION_FAILED`; the lower-boundary fix has overcorrected or otherwise damaged
   a known Low control.
7. Run **P6-INV-04 — The House of Lament**.
8. If House is not scored **4**, stop immediately and classify the pilot
   `REMEDIATION_FAILED`; v0.4 must not damage the established High control.
9. Run **P6-INV-05 — The Styes**.
10. If The Styes is not scored **5**, classify the pilot `REMEDIATION_FAILED`.

## Success criterion

The only passing result is:

> **5/5 exact, 0 hard errors, 0 malformed outputs.**

Any numeric miss, malformed output, canonical-unit error, or material grounding failure
makes this pilot `REMEDIATION_FAILED`.

There is no `INCONCLUSIVE` outcome and there is no sixth Investigation call in the
Phase-6 budget.

## Interpretation

`REMEDIATION_SUCCESS` means only that the targeted v0.4 prompt intervention repaired
the known discriminator set without damaging its controls. It does **not** establish
`LOCAL_QUALIFIED`.

A success permits preparation of a fresh benchmark-blind Investigation qualification
plan using the v0.4 profile. A failure ends routine prompt tuning of this Qwen
Investigation hypothesis unless a materially different, independently justified
hypothesis is proposed and separately budgeted.

## Frozen execution requirements

- Model: Qwen3.6 35B local route used by the Phase-5 Qwen candidate.
- One adventure × one dimension × one replicate per manifest.
- Explicit prompt profile: `AF_INVESTIGATION_GUARDRAIL_PROFILE=phase6-v0.4`.
- Preserve the existing canonical source-boundary and target-scrubbing behavior.
- Preserve the existing structured-output schema and validator.
- Do not rerun a failed case to seek a favorable sample.
- Stop as soon as a stop condition above is met.
- Persist raw response, normalized assessment, run metadata, model identity, prompt
  profile, and guardrail SHA for every attempted inference.
