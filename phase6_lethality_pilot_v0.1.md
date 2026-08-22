# Phase-6 Lethality / Failure Severity Remediation Pilot v0.1

**Status:** FROZEN — pre-inference
**Dimension:** Lethality / Failure Severity
**Candidate:** Qwen3.6 35B
**Prompt profile:** `phase6-v0.2`
**Core-call budget:** 5
**Optional calls:** 0
**External/API inference cost target:** $0

## Purpose

Test the Phase-6 mitigation-conversion clarification against the demonstrated Qwen
failure mode: systematic downward compression across the interior of the frozen
Lethality / Failure Severity ladder caused by over-crediting warnings, retreat,
recovery, rescue, and fail-forward mechanisms.

This is a remediation discriminator, not a fresh qualification run. Passing it only
earns the right to proceed to a later benchmark-blind qualification exercise.

## Frozen five-case ladder

| Accepted score | Adventure | Adventure ID | Phase-5 Qwen result | Role |
| ---: | --- | --- | ---: | --- |
| **1** | Witchlight Carnival | ADV-0278 | **1** | lower-endpoint anti-overcorrection control |
| **2** | The Wild Beyond the Witchlight | ADV-0277 | **1** | known 2→1 downward miss |
| **3** | No Honour Among Thieves | ADV-0062 | **2** | known 3→2 downward miss |
| **4** | The House of Lament | ADV-0287 | **3** | known 4→3 downward miss |
| **5** | Tomb of Horrors | ADV-0034 | **5** | upper-endpoint anti-overcorrection control |

The accepted scores and prior Qwen results are evaluation metadata only. They MUST
NOT appear in the blind scorer input.

## Frozen execution order

The score ladder above is conceptually 1 through 5, but execution is deliberately
ordered for information gain and early stopping:

1. **P6-LETH-01 — The Wild Beyond the Witchlight — target 2**
2. **P6-LETH-02 — No Honour Among Thieves — target 3**
3. **P6-LETH-03 — The House of Lament — target 4**
4. **P6-LETH-04 — Witchlight Carnival — target 1**
5. **P6-LETH-05 — Tomb of Horrors — target 5**

The first three calls directly test whether the known 2→1, 3→2, and 4→3 compression
has been corrected. The endpoint controls are spent only after the interior
remediation has survived.

## Stop conditions

### Interior remediation gate

- If **P6-LETH-01** is not scored exactly **2**, stop immediately and classify
  `REMEDIATION_FAILED`.
- If P6-LETH-01 is exact but **P6-LETH-02** is not scored exactly **3**, stop
  immediately and classify `REMEDIATION_FAILED`.
- If the first two are exact but **P6-LETH-03** is not scored exactly **4**, stop
  immediately and classify `REMEDIATION_FAILED`.

Any surviving downward miss at scores 2, 3, or 4 is direct evidence that the targeted
compression remains. Do not spend endpoint-control calls trying to improve the
aggregate percentage.

### Endpoint anti-overcorrection gate

Only after all three interior cases are exact:

- Run **P6-LETH-04 — Witchlight Carnival**. It must remain exactly **1**.
- Run **P6-LETH-05 — Tomb of Horrors**. It must remain exactly **5**.

Any endpoint miss is `REMEDIATION_FAILED`; the intervention must not repair the
interior by indiscriminately shifting scores upward.

## Success criterion

The only passing result is:

> **5/5 exact, 0 hard errors, 0 malformed outputs, and no integrity failure.**

There is no `INCONCLUSIVE` outcome and no sixth Lethality remediation call.

A malformed output, canonical-unit failure, material grounding failure, or any
numeric miss is `REMEDIATION_FAILED`.

## Interpretation

`REMEDIATION_SUCCESS` means only that the Phase-6 v0.2 intervention repaired the
known interior downward-compression discriminator while preserving both endpoints.

It does **not** establish `LOCAL_QUALIFIED`. Success permits preparation of a fresh,
benchmark-blind Lethality qualification plan using `phase6-v0.2`.

`REMEDIATION_FAILED` ends this routine prompt-tuning hypothesis. Do not consume
additional local calls merely to rescue the percentage; further work requires a
materially different, independently justified hypothesis and a separately frozen
budget.

## Frozen execution requirements

- Model: Qwen3.6 35B local route used by the Phase-5 Qwen candidate.
- One adventure × one dimension × one replicate per manifest.
- Explicit profile:
  `AF_LETHALITY_GUARDRAIL_PROFILE=phase6-v0.2`.
- Preserve canonical source-boundary handling and target-score scrubbing.
- Preserve the existing structured-output schema and validator.
- No favorable stochastic reruns.
- Stop immediately when a stop condition is met.
- Persist raw response, normalized assessment, run metadata, model identity, prompt
  profile, and guardrail SHA for every attempted inference.
