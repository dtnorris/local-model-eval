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
- Failed hypotheses should stop early according to their predeclared stop rules.
- Do not rerun merely to seek a favorable sample.

## Current status

Workspace scaffold only. No Phase-6 scorer changes or inference manifests have been added yet.
