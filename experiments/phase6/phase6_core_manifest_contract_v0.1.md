# Phase-6 core remediation manifest contract v0.1

**Status:** FROZEN — pre-inference

This package predeclares the complete authorized **25-call core remediation envelope**
before inference.

## Counts

- Social Interaction Emphasis: 5 manifests
- Investigation Emphasis: 5 manifests
- Lethality / Failure Severity: 5 manifests
- Puzzle / Problem-Solving Emphasis: 5 manifests
- Seriousness: 5 manifests
- **Total: 25 manifests / 25 maximum core attempted inferences**

The reserved optional Social `P6-06` slot is intentionally **not** represented by a
manifest. It remains unauthorized unless the frozen Social pilot first reaches
`INCONCLUSIVE` and a separate one-case addendum freezes its discriminator and decision
rule.

## Manifest invariants

Every core manifest predeclares:

- local model alias `qwen` and model identity `qwen3.6:35b-a3b`;
- exactly one canonical Adventure ID;
- exactly one AFAO dimension;
- exactly one replicate;
- the exact Phase-6 prompt profile and environment variable required to activate it;
- the frozen oracle score for post-run adjudication only;
- the pilot role and sequence;
- the stop condition that governs whether the next manifest in that dimension may run;
- no favorable rerun; and
- external/API inference cost `$0`.

## Blindness rule

`phase6_contract.oracle` is orchestration/evaluation metadata. The current
`local-model-eval` scorer command does not forward arbitrary manifest metadata to
`af-score`. The oracle MUST remain unavailable to scorer prompt construction.

## Execution boundary

These files freeze **what may be run**. They do not yet add an automatic cross-manifest
stop-condition runner. Until that runner is separately implemented and validated,
operators must not bulk-dispatch all 25 manifests without enforcing the frozen
per-dimension gates.

A remediation failure stops only the remainder of that dimension's pilot; it does not
invalidate or automatically cancel later independent dimension pilots.
