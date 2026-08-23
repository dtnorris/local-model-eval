# Phase-6 Lethality / Failure Severity — Failure-State Topology Pilot v0.1

**Status:** FROZEN — pre-inference
**Dimension:** Lethality / Failure Severity
**Candidate:** Qwen3.6 35B
**Prompt profile:** `phase6-v0.3`
**Core-call budget:** 3
**Optional calls:** 0
**Maximum local inference calls:** 3
**External/API inference cost target:** `$0`

## Purpose

Test the materially different `FAILURE_STATE_TOPOLOGY_INSTABILITY` hypothesis after the failed `phase6-v0.2` mitigation-conversion remediation.

The scorer intervention must establish the severe-failure state transition before anchor selection:

`pre-failure state → failure threshold → immediate post-failure state → mitigation/recovery → final state`

This is a remediation discriminator, not qualification evidence. Passing this pilot does **not** establish `LOCAL_QUALIFIED`; it only permits preparation of a fresh benchmark-blind qualification set under the frozen `phase6-v0.3` profile.

## Why only three calls

The prior five-case v0.2 pilot already established that the score-1 and score-5 endpoints can remain stable, No Honour can be corrected at 2→3, and v0.2 nevertheless fails because Witchlight remains 2→1 and House regresses 4→2. The highest-information next experiment therefore isolates the three diagnostic interior morphologies. Repeating endpoint controls before this causal hypothesis survives would spend compute without answering the new question.

## Frozen three-case discriminator

| Sequence | Adventure | Adventure ID | Accepted | v0.2 result | Diagnostic role |
| ---: | --- | --- | ---: | ---: | --- |
| 1 | The Wild Beyond the Witchlight | ADV-0277 | **2** | **1** | literal post-failure-state semantics |
| 2 | The House of Lament | ADV-0287 | **4** | **2** | guidance-vs-conversion + mandatory escalation |
| 3 | No Honour Among Thieves | ADV-0062 | **3** | **3** | anti-regression / explicit topology control |

Accepted scores and prior results are evaluator-only metadata. They MUST NOT enter the scorer-visible prompt.

## Case-specific falsification

### P6-LETH-V03-01 — ADV-0277

The v0.3 hypothesis survives only if the scorer scores exactly **2**, determines the post-condition of the relevant death mechanic literally, does not treat corpse-state changes, preservation, or "no additional effect" as automatic reversal of already-realized death unless the source explicitly says the creature returns to life, and remains grounded to the canonical source. A numerically exact score supported by the same semantic inversion is not sufficient.

### P6-LETH-V03-02 — ADV-0287

The v0.3 hypothesis survives only if the scorer scores exactly **4**, distinguishes success guidance/prevention from post-failure consequence conversion or recovery, treats a mandatory authored dangerous phase as expected play rather than discounting it merely because earlier phases are safer, and remains grounded to the canonical source. A numerically exact score reached through indiscriminate upward pressure is not sufficient.

### P6-LETH-V03-03 — ADV-0062

The anti-regression control survives only if the scorer preserves exactly **3**, continues to distinguish exposure-limiting mitigation from the severe outcome itself and from continuation/recovery after failure, does not overcorrect upward, and remains grounded to the canonical source.

## Frozen success criterion

The only passing family result is:

> **3/3 exact, all three case-specific semantic falsification checks satisfied, 0 malformed outputs, and 0 material grounding/canonical-unit integrity failures.**

Any numeric miss, semantic-falsification failure, malformed output, or material grounding/canonical-unit failure means `REMEDIATION_FAILED`. There is no `INCONCLUSIVE` outcome and no fourth v0.3 remediation call.

## Diagnostic completion policy

Complete all three authorized calls by default, even after a numeric or semantic miss. Each case tests a different part of the topology hypothesis, so later cases retain diagnostic value after strict remediation success becomes impossible.

Pause or terminate early only for a **systemic experiment-integrity failure** that could invalidate later calls, such as wrong model/profile, oracle leakage, wrong canonical source unit, corrupted source, a scorer/harness defect affecting later cases, or an output-routing/provenance defect affecting later cases.

A case-specific unfavorable score, rationale disagreement, malformed model response, or validation failure is recorded against the attempted slot but does not by itself invalidate later cases.

## Frozen execution requirements

- Model alias: `qwen`
- Ollama model: `qwen3.6:35b-a3b`
- Worker: `mac`, local only
- One adventure × one dimension × one replicate per manifest
- Scorer mode: positional
- Explicit scorer profile: `AF_LETHALITY_GUARDRAIL_PROFILE=phase6-v0.3`
- Preserve target-score scrubbing and canonical source-boundary handling
- No favorable reruns
- External/API inference cost: `$0`
- Persist ordinary raw/normalized output and run provenance for every attempt

## Pre-inference evidence

The scorer-side v0.3 prompt was rendered with provider inference disabled for all three cases before this pilot was frozen. All three renders resolved `canonical_page_slice`, selected exactly one Lethality target, contained the v0.3 topology guardrail exactly once, contained no active v0.2 Lethality guardrail, and reported zero provider inference calls.
