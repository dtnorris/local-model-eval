# Phase-6 Seriousness Diagnosis v0.1

**Status:** FROZEN DIAGNOSIS — no prompt intervention yet
**Dimension:** Seriousness
**Candidate:** Qwen3.6 35B
**Observed failure:** four valid Phase-5 disagreements, all +1
**External/API inference cost:** $0

## Purpose

Diagnose the repeated Phase-5 upward Seriousness disagreements before writing any
Phase-6 remediation prompt text.

This artifact freezes the conceptual failure hypothesis only. It does not modify the
AFAO ontology, the production scorer, the accepted Seriousness production profile, or
any experiment manifest.

## Phase-5 failure pattern

Across eight valid Phase-5 Seriousness assessments, Qwen produced four exact results
and four adjacent misses. Every valid miss was upward:

| Adventure | Adventure ID | Accepted | Qwen | Boundary |
| --- | --- | ---: | ---: | --- |
| Witchlight Carnival | ADV-0278 | 2 | 3 | Light → Mixed |
| Expedition to the Barrier Peaks | ADV-0040 | 3 | 4 | Mixed → Serious |
| No Honour Among Thieves | ADV-0062 | 3 | 4 | Mixed → Serious |
| Lost Mine of Phandelver | ADV-0262 | 4 | 5 | Serious → Sustained Serious |

The tested score-1 and score-5 endpoints were reproduced exactly. This is therefore
not evidence of a globally shifted scale or inability to recognize the endpoints.

## Evidence-strength note

The four misses are not equally strong benchmark failures.

**No Honour Among Thieves** is a known 3↔4 boundary-sensitive case: archived Terra
calibration itself split 3 / 3 / 4. Its Phase-5 +1 should therefore receive low weight
as evidence of numeric model failure.

Its rationale remains highly diagnostic, however, because it exposes the same
construct-substitution mechanism visible in the other upward misses.

**Lost Mine of Phandelver** is also a deliberately pressure-tested 4↔5 boundary:
blind validation initially produced 5, but focused full-source adjudication retained
4 because recurring authored lighter material materially lightens a meaningful
portion of expected play. It is therefore useful specifically for diagnosing how the
model treats the lighter register near the upper boundary.

## Frozen diagnosis

**Diagnostic label:** `SERIOUSNESS_EARNEST_PROXY_WEIGHTING_BIAS`

Qwen is not merely "scoring Seriousness too high." The recurring error is an
asymmetric method for constructing tonal hierarchy:

1. it treats **plot gravity** — danger, urgency, deadlines, lethality, betrayal,
   villainy, severe consequences, survival pressure, political fallout, or the
   importance of the central objective — as positive evidence that the
   earnest/dramatic *register* predominates; then
2. it discounts authored lighter player-facing material as "flavor," "contrast," a
   façade, an opening phase, or isolated characterization when that material is not
   equally central to the plot objective.

That method compares **narrative stakes / objective centrality** against **surface
levity**, rather than comparing the substantive player-facing earnest and lighter
registers against each other.

The frozen Seriousness construct requires the latter comparison.

### Core conceptual mistake

> **Plot gravity is being converted into tonal weight, while lighter experiential
> material is required to prove plot-level centrality before receiving equal weight.**

This produces a systematic upward asymmetry:

- earnest evidence receives credit because it is dangerous, urgent, consequential, or
  plot-central;
- lighter evidence is discounted unless it appears equally plot-central or dominant.

The resulting "clear tonal hierarchy" can therefore be manufactured even when both
actual player-facing registers are substantial.

## Rationale evidence

### ADV-0040 — Expedition to the Barrier Peaks: 3 → 4

Qwen correctly identifies recurring authored comedy across the adventure, including
absurd technology and multiple comic encounters. It nevertheless makes the decisive
3↔4 comparison using survival stakes, deadly threats, the mold outbreak, hostile alien
fauna, and Aphelion's manipulation, then demotes the lighter material to "situational
flavor" or tonal contrast.

This is the clearest 3↔4 proxy-weighting example. The calibrated Mixed placement is
specifically based on lethal derelict-spacecraft danger coexisting with recurring
authored absurd technological comedy. Danger is not itself evidence that the earnest
register wins that tonal comparison.

### ADV-0062 — No Honour Among Thieves: 3 → 4

Qwen identifies the festival/caper register, bard competition, whimsical password,
and light thieves'-den material, but concludes that the serious register predominates
after emphasizing the one-hour deadline, deadly traps and monsters, betrayal,
political fallout, and the party being hunted.

That is almost exactly the proxy failure previously documented during production
Seriousness prompt validation: urgency, lethal defenses, betrayal, catastrophic
consequences, and strict deadlines were used as substitutes for direct tonal
comparison.

Because the oracle itself is boundary-sensitive here, this case is supporting
mechanism evidence rather than a high-weight numeric failure.

### ADV-0262 — Lost Mine of Phandelver: 4 → 5

Qwen describes the rescue, criminal threat, antagonist plot, and ancient magical
stakes as sustained serious framing, then treats lighter material as isolated NPC
quirks or peripheral contrast.

The adjudicated score-4 record says the opposite about the *extent* of that lighter
register: the central Phandalin/Redbrand phase repeatedly contains authored comic and
eccentric player-facing material that meaningfully lightens a substantial portion of
play while remaining secondary to the earnest spine.

The mistake here is not failure to see that the adventure is predominantly earnest;
score 4 already says that. The mistake is **under-counting meaningful secondary
lighter material until it becomes "rare/peripheral," thereby manufacturing score 5.**

### ADV-0278 — Witchlight Carnival: 2 → 3

Qwen correctly recognizes that rides, games, contests, costumes, eccentric NPCs, and
the carnival's presentation occupy substantial interactive space. It nevertheless
raises the earnest register to coequal status because the serious conspiracy,
personal-loss threads, moral problems, and central objectives are narratively
important.

This exposes the lower-side form of the same mistake: **central dramatic business is
not automatically coequal tonal experience**. Score 2 already permits recurring,
meaningful earnest material. The 2↔3 question is whether that earnest register becomes
comparably substantial in expected player-facing experience, not whether it drives an
important objective or explains the plot.

## Relationship to the accepted Seriousness scorer work

AdventureFinder has seen this failure class before.

The accepted Seriousness production validation identified a
**Tonal-Hierarchy / Proxy-Weighting** problem in which a scorer used danger, urgency,
lethality, catastrophic stakes, betrayal, consequences, deadlines, whimsical genre
vocabulary, or other proxies instead of directly comparing substantive player-facing
registers.

That intervention materially improved the prior scorer and was accepted without
changing the ontology.

The Phase-5 Qwen evidence therefore does not suggest that the frozen Seriousness
rubric is defective. It suggests that this local model still under-applies the
existing construct separation and reconstructs tonal hierarchy from prohibited
proxies.

## What the diagnosis is NOT

This is **not**:

- a reason to subtract one point from Qwen Seriousness outputs;
- a rule that stakes, danger, tragedy, or villainy never participate in earnest tone;
- a direction to treat every joke, eccentric NPC, or whimsical object as substantial
  lighter material;
- evidence that every Mixed case should resist score 4;
- evidence that every Serious case should resist score 5; or
- a reason to alter the AFAO anchors.

Objective circumstances can be presented in an earnest dramatic register. The error
is using their objective gravity as a substitute for evidence about how the published
adventure actually frames and sustains the player-facing register.

Likewise, incidental humor remains incidental. The error is dismissing recurring,
interactive, materially experience-shaping lighter content merely because it is less
central to the plot objective than the earnest material.

## Narrow remediation hypothesis

A later Phase-6 implementation should alter **decision method**, not score direction.

The candidate hypothesis is:

1. inventory the substantive player-facing **earnest/dramatic register**;
2. independently inventory the substantive player-facing
   **playful/light/comic register**;
3. exclude objective stakes, urgency, lethality, difficulty, villainy, deadlines,
   consequence severity, and plot importance as standalone evidence of tonal
   predominance;
4. do not demote recurring interactive lighter material to flavor or contrast merely
   because it is less plot-central;
5. only then determine the tonal hierarchy required by the existing 2↔3, 3↔4, and
   4↔5 anchors.

The intervention must remain bidirectional. If the direct register comparison really
shows clear earnest predominance, score 4 remains correct. If meaningful lighter
material really is only rare, peripheral, or contrastive, score 5 remains correct.

This is a hypothesis for later implementation, **not prompt text**.

## Falsification requirements for a later pilot

A useful five-case remediation pilot should demonstrate that the intervention can:

- correct multiple upward misses spanning 2↔3, 3↔4, and 4↔5;
- preserve at least one exact genuinely high-Seriousness control;
- preserve at least one exact low/light control or otherwise show it has not created a
  blanket downward shift; and
- fail rather than pass if it merely moves every result down one point.

The Phase-6 Seriousness call budget remains five core local calls. No inference is
authorized by this diagnosis artifact.

## Stop / scope rules

- Do not change AFAO Seriousness definition or anchor wording.
- Do not encode adventure names, Adventure IDs, or target scores in scorer prompt text.
- Do not implement a numeric "-1" correction.
- Do not weaken the existing rule that incidental jokes or eccentric characters do not
  independently reduce Seriousness.
- Do not run remediation inference until the implementation and five-case pilot are
  separately frozen.
- Do not spend paid inference on this diagnosis or remediation pilot.
