# Phase-6 experiment namespace

This directory contains only Phase-6 boundary-remediation experiment manifests.

## Naming

Use:

```text
phase6-remediation-<dimension-slug>-<adventure-id>-<role>-vN.yml
```

Examples:

```text
phase6-remediation-investigation-adv0034-minimal-control-v1.yml
phase6-remediation-lethality-adv0287-upper-boundary-v1.yml
```

## Manifest invariants

Every remediation manifest should declare or preserve:

- exactly one local model;
- exactly one canonical Adventure ID;
- exactly one target dimension;
- `replicates: 1`;
- the scorer prompt/guardrail profile version under test;
- no accepted target score in blind scorer input; and
- an experiment ID/output namespace beginning with `phase6-remediation-`.

## Evidence policy

- Phase-5 results are frozen baseline evidence, not files to overwrite.
- A remediation case is deliberately diagnostic and therefore is **not** final qualification evidence by itself.
- Successful remediation earns a separate benchmark-blind qualification run under the new scorer profile.
- Strict remediation success/failure criteria remain predeclared and unchanged.
- A numeric failure does not itself stop the rest of an authorized five-case diagnostic family.
- Complete the 25 authorized core calls by default so later cases can measure partial improvement, unchanged bias, control regression, or blanket directional movement.
- Stop or pause early only for a systemic integrity failure that would invalidate later evidence.
- Do not rerun merely to seek a favorable sample.

Execution precedence for the initial wave is defined in `../../phase6_diagnostic_completion_policy_v0.1.md`.

## Current status

Workspace scaffold plus frozen call budget only. No Phase-6 scorer changes or inference manifests have been added yet. See `../../phase6_call_budget_v0.1.md` for the 25-core / 26-maximum allocation and accounting rules.
