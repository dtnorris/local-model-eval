# Phase-6 Seriousness Remediation Pilot v0.1

**Status:** FROZEN — pre-inference
**Dimension:** Seriousness
**Candidate:** Qwen3.6 35B
**Prompt profile:** `phase6-v0.3`
**Core-call budget:** 5
**Optional calls:** 0
**External/API inference cost target:** $0

## Purpose

Test the Phase-6 direct-register-comparison decision method against the demonstrated
Qwen failure mode: upward Seriousness inflation caused by converting plot gravity,
stakes, urgency, danger, and objective importance into tonal weight while discounting
substantive lighter player-facing material.

This is a remediation discriminator, not a fresh qualification run. Passing it only
earns the right to proceed to a later benchmark-blind qualification exercise.

## Frozen five-case ladder

| Accepted score | Adventure | Adventure ID | Phase-5 Qwen result | Role |
| ---: | --- | --- | ---: | --- |
| **1** | A Conspiracy Most Cracked | ADV-0013 | **1** | low-end anti-downward-shift control |
| **2** | Witchlight Carnival | ADV-0278 | **3** | known 2→3 inflation / lighter-register predominance |
| **3** | Expedition to the Barrier Peaks | ADV-0040 | **4** | known 3→4 proxy-weighting failure |
| **4** | Lost Mine of Phandelver | ADV-0262 | **5** | known 4→5 lighter-register undercount |
| **5** | House of Lament | ADV-0287 | **5** | genuine sustained-high Seriousness control |

The accepted scores, prior model results, and diagnostic roles are evaluation metadata
only. They MUST NOT appear in the blind scorer input.

## Why these five cases

The three interior cases directly exercise every boundary implicated by the Phase-6
diagnosis:

- **Witchlight Carnival** tests whether an important serious objective still gets
  overcounted until it becomes coequal with a clearly predominant lighter register.
- **Expedition to the Barrier Peaks** is the clearest 3↔4 diagnostic: recurring comic
  and absurd player-facing material must not be demoted merely because the adventure
  also contains lethal danger and serious survival stakes.
- **Lost Mine of Phandelver** tests whether recurring interactive lighter material is
  still mislabeled as rare/peripheral merely because the earnest adventure spine is
  more plot-central.

The controls test both possible overcorrections:

- **House of Lament** must remain 5. The intervention must not turn direct register
  comparison into a general downward preference or manufacture lighter weight where
  the published experience is genuinely sustained-serious.
- **A Conspiracy Most Cracked** must remain 1. The intervention must not mechanically
  subtract one from outputs or otherwise distort the low endpoint.

**No Honour Among Thieves is intentionally excluded.** Its 3↔4 placement is known to
be boundary-sensitive, including archived Terra disagreement, so spending one of the
five frozen remediation calls on it would provide less falsifiable information than
the selected cases.

## Frozen execution order

Run in this order:

1. **P6-SER-01 — Expedition to the Barrier Peaks — target 3**
2. **P6-SER-02 — Witchlight Carnival — target 2**
3. **P6-SER-03 — Lost Mine of Phandelver — target 4**
4. **P6-SER-04 — House of Lament — target 5**
5. **P6-SER-05 — A Conspiracy Most Cracked — target 1**

The score ladder is conceptually 1 through 5, but execution is deliberately ordered
for information gain. Barrier Peaks is the strongest direct test of the diagnosed
proxy-weighting mechanism and therefore runs first. The other two known upward misses
follow. The two controls run afterward regardless of earlier numeric outcomes so the
completed five-case set can distinguish targeted correction from partial improvement,
no effect, control regression, or a blanket directional shift.

## Strict remediation classification

Run all five core cases in the frozen order above unless a systemic experiment-integrity
failure makes subsequent evidence invalid or non-comparable. Numeric results classify
the remediation hypothesis; they do not control whether the remaining authorized core
diagnostics run.

### Upward-bias remediation cases

Each of the first three cases must be exact for `REMEDIATION_SUCCESS`:

- **P6-SER-01 — Expedition to the Barrier Peaks** must score exactly **3**.
- **P6-SER-02 — Witchlight Carnival** must score exactly **2**.
- **P6-SER-03 — Lost Mine of Phandelver** must score exactly **4**.

Any persistent upward miss means the targeted proxy-weighting hypothesis has not been
cleanly corrected and makes the strict pilot classification `REMEDIATION_FAILED`.

A downward overshoot also fails. For example, Barrier Peaks 3→2, Carnival 2→1, or
Lost Mine 4→3 is evidence that the intervention has become a directional correction
rather than a decision-method correction.

If any of these numeric failures occurs, record that strict remediation success is no
longer possible, then continue the remaining frozen core diagnostics under
`phase6_diagnostic_completion_policy_v0.1.md`. Completing those calls is diagnostic
evidence collection, not an attempt to rescue the aggregate percentage.

### Genuine-high Seriousness control

Run **P6-SER-04 — House of Lament** after the three remediation cases regardless of
their numeric outcomes. It must remain exactly **5** for `REMEDIATION_SUCCESS`.

A 5→4 result is `REMEDIATION_FAILED`. The intervention must preserve genuinely
sustained high Seriousness rather than merely lowering ambiguous or mixed cases.

### Low-end anti-shift control

Run **P6-SER-05 — A Conspiracy Most Cracked** after House of Lament regardless of
House's numeric outcome. It must remain exactly **1** for `REMEDIATION_SUCCESS`.

Any numeric change fails. This final control protects against a hidden uniform offset
or unintended distortion of the unaffected 1↔2 endpoint.

## Success criterion

The only passing result is:

> **5/5 exact, 0 hard errors, 0 malformed outputs, and no integrity failure.**

There is no `INCONCLUSIVE` outcome and no sixth Seriousness remediation call.

A malformed output, canonical-unit failure, material grounding failure, or any
numeric miss is `REMEDIATION_FAILED`.

## Interpretation

`REMEDIATION_SUCCESS` means only that the Phase-6 v0.3 decision method corrected the
demonstrated 2→3, 3→4, and 4→5 upward inflation while preserving both a genuine score-5
case and the unaffected score-1 endpoint.

It does **not** establish `LOCAL_QUALIFIED`. Success permits preparation of a fresh,
benchmark-blind Seriousness qualification plan using `phase6-v0.3`.

After all five authorized core diagnostics are complete, `REMEDIATION_FAILED` ends
this routine decision-method tuning hypothesis. Do not authorize additional calls merely
to rescue the percentage. Further work requires a materially different, independently
justified hypothesis and a separately frozen budget.

## Frozen execution requirements

- Model: Qwen3.6 35B local route used by the Phase-5 Qwen candidate.
- One adventure × one dimension × one replicate per manifest.
- Explicit profile: `AF_SERIOUSNESS_GUARDRAIL_PROFILE=phase6-v0.3`.
- Preserve canonical source-boundary handling and target-score scrubbing.
- Preserve the existing structured-output schema and validator.
- No favorable stochastic reruns.
- Complete all five core calls unless a systemic experiment-integrity failure makes
  subsequent evidence invalid or non-comparable.
- A numeric miss may establish `REMEDIATION_FAILED` before the family completes, but it
  does not terminate the remaining authorized core diagnostics.
- Persist raw response, normalized assessment, run metadata, model identity, prompt
  profile, and guardrail SHA for every attempted inference.
