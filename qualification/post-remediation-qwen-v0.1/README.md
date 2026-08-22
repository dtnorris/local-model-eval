# Qwen post-remediation qualification v0.1

## Status

FROZEN PRE-INFERENCE qualification package for the remediated Qwen3.6 35B
Social Interaction Emphasis and Investigation Emphasis profiles.

This is qualification evidence, not additional prompt remediation. The scorer
profiles are frozen exactly as they succeeded in Phase 6:

- Social Interaction Emphasis:
  `AF_SOCIAL_INTERACTION_GUARDRAIL_PROFILE=phase6-v0.3`
- Investigation Emphasis:
  `AF_INVESTIGATION_GUARDRAIL_PROFILE=phase6-v0.4`

No prompt text, profile version, AFAO rubric, or oracle value may be changed
during this qualification wave.

## Cost and run envelope

- Candidate: `qwen` / `qwen3.6:35b-a3b`
- Local worker only
- External/API inference cost: `$0`
- One replicate per case
- Social: 5 maximum attempted calls
- Investigation: 5 maximum attempted calls
- Total: **10 maximum attempted local inference calls**
- No favorable reruns

The existing Local Model Acceptance Contract governs qualification. The
qualification runner may stop a candidate early after an invalid output or once
its local hard-error count exceeds the frozen Terra allowance. Failure of one
candidate does not prevent the other dimension from being evaluated.

## Blindness

Oracle and Terra values exist only in the qualification comparator files.
Qualification manifests contain no accepted score and use positional scorer
mode, not regression mode. The scorer therefore receives the canonical
Adventure ID, dimension, source material, AFAO/scoring instructions, and the
selected frozen remediation profile, but not the expected score.

Comparator values are applied only after the local assessment has been
persisted.

## Case selection

### Social Interaction Emphasis

Four of five cases were not used in the Phase-6 Social remediation pilot:

| Adventure | Role |
| --- | --- |
| ADV-0040 Expedition to the Barrier Peaks | fresh low/mid boundary |
| ADV-0062 No Honour Among Thieves | fresh low control |
| ADV-0262 Lost Mine of Phandelver | fresh middle control |
| ADV-0277 The Wild Beyond the Witchlight | fresh upper endpoint |
| ADV-0257 The Magister's Masquerade | remediated score-4 boundary confirmation |

The archived Terra comparator is 3/5 exact, 2/5 adjacent, 0 hard errors. Under
the frozen <=10 percentage-point exact-rate deficit rule, Qwen needs at least
3/5 exact on the full denominator, no hard errors beyond Terra's zero allowance,
and a clean human integrity review. Repeated identical adjacent shifts trigger
boundary-bias review under the acceptance contract.

The score-1 anti-inflation behavior was already explicitly protected by the
Phase-6 Tomb of Horrors control; no fresh score-1 Social case with accepted
archived Terra evidence is available in the frozen comparator archive used
here.

### Investigation Emphasis

Three of five cases were not used in the Phase-6 Investigation remediation
pilot; the two reused cases are the remediated endpoints:

| Adventure | Role |
| --- | --- |
| ADV-0053 Call of the Wild | fresh score-2 control |
| ADV-0262 Lost Mine of Phandelver | fresh score-3 control |
| ADV-0277 The Wild Beyond the Witchlight | fresh score-3 control |
| ADV-0034 Tomb of Horrors | remediated lower-endpoint confirmation |
| ADV-0234 The Styes | remediated upper-endpoint confirmation |

The archived Terra comparator is 5/5 exact, 0 adjacent, 0 hard errors. On a
five-case denominator, the frozen <=10 percentage-point exact-rate deficit rule
therefore requires Qwen to be 5/5 exact, with no hard errors and a clean human
integrity review.

Storm King's Thunder is intentionally excluded from both candidates because
the prior local evidence established a cross-dimension structured-validation
pathology on that source. Spending a qualification call on that known
operational confound would add less information than the selected cases.

## Archived Terra evidence

No new Terra/API inference is authorized. Comparator values are frozen from:

- `llm-response-data/full-19-first-calibration/social-interaction-emphasis-v0.2/rep1/regression/`
- `llm-response-data/full-19-first-calibration/investigation-emphasis-v0.3/rep1/regression/`

Exact archived artifact paths are listed in the two comparator YAML files.

## Launch

From the `local-model-eval` repository root:

```bash
./run_qwen_social_investigation_qualification.sh
```

The launcher first validates the qualification plan with `--dry-run`, verifies
the local worker/model for one manifest from each profile, and then runs the
frozen qualification plan under `caffeinate`.

Qualification output is written under:

`output/qualification/qwen-social-investigation-post-remediation-v0.1/`

The numeric harness result is not itself the final `LOCAL_QUALIFIED` decision.
After completion, perform the frozen human integrity review for grounding,
canonical-unit correctness, conceptual integrity, and any boundary-bias flag.
