# RunPod Fleet Status

`bin/lme runpod-status` answers the operator question: **what does LME believe the current paid RunPod fleet is doing, how long has it been tracked, and roughly what has it cost?**

The command is read-only. It consumes the fleet-scoped durable state under `output/runpod-fleets/<fleet-id>/` and the latest fleet-scoped bootstrap state. When `RUNPOD_API_KEY` is available, it also performs read-only RunPod pod lookups for workers that LME still considers active.

```bash
bin/lme runpod-status
```

Typical output includes:

```text
RunPod fleet status
  Fleet: 20260829T200000Z-pod_a
  LME state: ACTIVE
  Created: 2026-08-29T20:00:00Z
  Cloud/GPU: SECURE / NVIDIA A40
  Workers: 5 total; 5 active; 0 destroyed
  Recorded fleet rate: $2.2000/hr
  Current tracked rate: $2.2000/hr
  Tracked elapsed: 00:18:43
  Estimated accrued cost: $0.6860
  Provider check: enabled

WORKER    LME        RUNPOD       RATE       ELAPSED    EST.COST   BOOTSTRAP
burst_1   ACTIVE     RUNNING      $0.4400    00:18:43   $0.1372    WARMING
...
```

## Billing semantics

The cost is deliberately labeled an **estimate**. The fleet state is activated only after the requested pods have reached RunPod readiness and exposed SSH endpoints. Therefore the tracked clock begins slightly later than provider billing may begin.

For each worker, LME computes:

```text
recorded worker hourly rate × tracked active seconds / 3600
```

A partially destroyed fleet is handled per worker: a worker's tracked cost clock stops at its recorded `destroyed_at_utc`, while workers that remain active continue accruing estimated cost. The current tracked hourly rate includes only workers still marked active in LME state.

The estimate can differ from RunPod billing because of provisioning time before LME state activation, provider billing granularity, credits, taxes, or rate changes. It is operational burn visibility, not an invoice substitute.

## Provider-state mismatch

When an API key is available, active workers are checked against RunPod. A missing or failed provider lookup does **not** silently stop the local cost estimate, because LME cannot infer from a failed lookup exactly when provider billing stopped. Instead the status output shows `MISSING` or `ERROR` and emits a warning such as:

```text
WARNING: burst_3 is ACTIVE in LME state but RunPod status is MISSING (...).
```

That is a reconciliation signal rather than an automatic state mutation.

If no API key is available, the command still works from durable local state and reports that provider status was not checked.

## Bootstrap state

If the current fleet has a `bootstrap/current` pointer, status reads only that fleet-scoped run and shows its models, context, state, elapsed time, worker counts, evidence directory, and each worker's latest stage. Historical bootstrap directories are never treated as current merely because their log files exist.

If no current fleet pointer exists, the command prints:

```text
No current RunPod fleet.
```
