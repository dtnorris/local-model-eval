# Phase-6 Puzzle / Problem-Solving Emphasis Diagnosis v0.1

**Status:** FROZEN DIAGNOSIS — no prompt intervention yet
**Dimension:** Puzzle / Problem-Solving Emphasis
**Candidate:** Qwen3.6 35B
**Observed failure:** repeated accepted-score-2 → local-score-1 compression
**External/API inference cost:** $0

## Purpose

Diagnose the repeated Phase-5 Puzzle / Problem-Solving Emphasis 2→1 misses before
writing any Phase-6 remediation prompt text.

This artifact freezes the conceptual failure hypothesis only. It does not modify the
AFAO ontology, the production scorer, the current Puzzle v0.1 guardrail, or any
experiment manifest.

## Evidence reviewed

Three valid Phase-5 cases share the same accepted score and local miss:

| Adventure | Adventure ID | Accepted | Qwen | What Qwen identified | What Qwen treated as disqualifying |
| --- | --- | ---: | ---: | --- | --- |
| Call of the Wild | ADV-0053 | 2 | 1 | An explicit sliding-tile puzzle box plus other procedural obstacles | The puzzle is optional, localized, non-essential to progression, and rapidly resolved; no “sustained how-to solution space” |
| No Honour Among Thieves | ADV-0062 | 2 | 1 | Heist constraints, “clever deceits,” locks, traps, and authored bypass opportunities | Standard checks/social resolution and the absence of a discrete bounded reasoning sequence |
| The House of Lament | ADV-0287 | 2 | 1 | Séance guidance, item/mechanism interactions, and authored noncombat obstacle handling | Prescribed or signposted solutions, lack of complex traps/logic/resource puzzles, and absence of a bounded problem-solving sequence |

The important commonality is that Qwen generally **found candidate authored material
before rejecting it**. This is therefore not primarily an evidence-retrieval failure.

## Frozen diagnosis

**Diagnostic label:** `PUZZLE_LOW_ANCHOR_OVERQUALIFICATION_BIAS`

Qwen is applying an over-demanding admission test at the Minimal ↔ Low boundary.
It effectively asks whether the adventure contains an independently developed,
sustained, sufficiently complex, or mode-pure puzzle sequence before allowing score 2.

That is stricter than the frozen score-2 concept. Low permits meaningful Puzzle /
Problem-Solving play that **occurs and matters while remaining limited in extent or
clearly secondary to other modes**.

The recurring error is therefore:

> **Conflating “meaningful/substantive enough to count at all” with
> “developed/extended enough to constitute a recurring or independently important
> Puzzle mode.”**

Those are different questions. Recurrence and broad structural weight principally
separate Low from higher anchors; they must not silently become prerequisites for
entering Low.

## Contributing prompt mechanism

The current production Puzzle 1↔2 guardrail contains a useful anti-inflation audit, but
its wording creates a model-specific failure surface by asking the scorer to identify
a **“meaningfully developed player-facing how-problem or bounded problem-solving
sequence.”**

It later supplies explicit counter-pressure against requiring recurrence, multiple
puzzles, difficult deduction, or a large share of play. Phase-5 Qwen nevertheless
repeatedly latches onto the earlier “meaningfully developed” / “bounded sequence”
language and turns it into a stronger admission requirement.

This diagnosis therefore treats the observed bias as an **interaction between Qwen and
the existing v0.1 application guardrail**, not as evidence that the frozen ontology
itself is defective.

## Wrong lower-boundary proxies observed

The following properties may affect how much Puzzle / Problem-Solving the adventure
contains, but they must not independently disqualify score 2 once meaningful authored
problem-solving is present:

- optional or path-sensitive rather than mandatory;
- localized rather than recurring;
- secondary to exploration, social interaction, investigation, or combat;
- short rather than sustained;
- partially signposted rather than opaque;
- resolved with checks as part of a broader authored problem;
- lacking a formal riddle, logic puzzle, complex mechanism, or large solution tree;
- not independently responsible for major adventure progression.

In particular, “other modes dominate the adventure” is compatible with score 2 by
definition.

Duration still matters as evidence: the frozen Minimal anchor expressly allows
incidental or rapidly resolved material. The error is treating short duration itself as
a veto rather than asking whether the player-facing how-problem is substantively
meaningful despite being limited.

## Anti-inflation boundary retained

This diagnosis does **not** mean that any obstacle, choice, check, or opportunity for
player cleverness establishes score 2.

Score 1 must remain available when the strongest candidates reduce to:

- a check that directly resolves the obstacle with no substantive player-facing
  how-question;
- merely locating a hidden feature;
- an explicitly prescribed action or obvious trigger with no meaningful reasoning,
  experimentation, resource combination, or supported creative choice left to players;
- ordinary route selection, searching, or environmental interaction;
- generic GM-permitted improvisation unsupported by an authored problem/constraint;
- combat tactics rather than a substantive noncombat problem;
- incidental material whose player-facing problem-solving is too slight to constitute
  meaningful play.

The corrective target is therefore **admission calibration**, not blanket upward
movement.

## Narrow remediation hypothesis

A future Phase-6 intervention should clarify only the 1↔2 admission decision:

1. First identify the strongest authored noncombat problem, mechanism, constraint, or
   challenge.
2. Ask whether players meaningfully have to determine **how to overcome it** through
   reasoning, experimentation, combining information/resources, or a supported
   creative approach.
3. If yes, do not reject Low merely because that qualifying play is localized,
   optional/path-sensitive, short, secondary, overlaps another mode, or is partly
   signposted.
4. If the authored material leaves no substantive how-question for players after its
   direct prescribed resolution is accounted for, preserve Minimal.
5. Do not modify the 2↔3, 3↔4, or 4↔5 decision rules.

This is a hypothesis for later implementation, **not prompt text**.

## Falsification requirements for a later pilot

Any future remediation must show both sides of the boundary:

- recover multiple previously compressed accepted-score-2 morphologies; and
- preserve true score-1 controls rather than simply shifting the lower ladder upward.

A remediation that converts the known 2→1 misses by also inflating accepted-score-1
controls is rejected.

The Phase-6 Puzzle call budget remains five core local calls. No inference is
authorized by this diagnosis artifact.

## Stop / scope rules

- Do not change AFAO anchor wording.
- Do not encode adventure names, Adventure IDs, or target scores in scorer prompt text.
- Do not alter upper Puzzle boundaries as part of this hypothesis.
- Do not run remediation inference until the implementation and five-case pilot are
  separately frozen.
- Do not spend paid inference on this diagnosis or remediation pilot.
