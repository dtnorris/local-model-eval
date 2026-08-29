# RunPod Fleet Bootstrap

`bin/lme runpod-bootstrap` is the fleet-level launcher for configuring already-provisioned RunPod workers with Ollama models.

It replaces hand-written background shell loops such as `for ... & ... wait`. Each worker is spawned directly as its own process group with stdin detached, full output captured to a fleet-scoped log, and visible progress emitted by the controlling command.

## Example

```bash
bin/lme runpod-bootstrap \
  --workers 1-5 \
  --clean \
  --model gemma4:26b \
  --expect-digest gemma4:26b=<full-digest>
```

Every requested model must have an exact 64-hex `--expect-digest`. The managed launcher also derives the exact expected GPU from current fleet state and always pins an explicit context (262144 unless overridden). Missing or mismatched model/digest/context/GPU provenance fails closed.

The command requires an active fleet created by `bin/lme runpod-create`. It reads the authoritative current fleet from `output/runpod-fleets/current`; it never discovers current work by scanning arbitrary historical output directories.

## Operator feedback

The launcher prints an immediate start line for every selected worker, stage changes while logs advance, a heartbeat at least every 10 seconds by default, and an immediate PASS/FAIL line when each worker exits.

A heartbeat includes:

- running / passed / failed worker counts;
- the current stage for each running worker;
- pull/copy percentage when it can be recovered from the worker log;
- the full fleet hourly rate;
- elapsed bootstrap time; and
- approximate fleet cost during the bootstrap window.

The cost number is intentionally labeled **bootstrap-window cost**. It is not the complete RunPod bill because the pods may have existed before bootstrap began.

## Fleet-scoped evidence

Every invocation creates its own bootstrap run beneath the current fleet:

```text
output/runpod-fleets/<fleet-id>/bootstrap/
  current
  <bootstrap-run-id>/
    bootstrap.json
    burst_1.log
    burst_2.log
    ...
```

`bootstrap/current` points only at the latest bootstrap invocation for that fleet. Historical runs remain preserved but cannot become current merely because their log files still exist.

`bootstrap.json` is atomically updated as workers start, change stage, complete, fail, or are interrupted. It records the requested models, exact expected digests, exact expected GPU, context, worker pod IDs/endpoints, child PIDs, per-worker stage/status, exit status, timestamps, elapsed time, and bootstrap-window cost.

On successful remote setup, each worker emits machine-readable provenance markers. LME records the detected GPU name/VRAM and, for every model, the observed digest, context length, model size, VRAM-resident size, and full-residency result. A worker cannot be marked `passed` unless those markers exactly satisfy the requested provenance contract.

## Interruption

`Ctrl-C` is handled explicitly. The launcher sends TERM to every still-running local bootstrap process group, waits briefly, escalates to KILL if needed, reaps the children, records the run as interrupted, and exits with status 130.

The wrapper's SSH process is in the same local process group, so the local SSH/bootstrap processes are not intentionally left running after interruption. A later status/reconciliation feature may add explicit remote-process inspection as an additional guardrail.

## Options

- `--workers 1-5` — explicit worker indices from the current fleet.
- `--model MODEL` — model to install; repeatable.
- `--expect-digest MODEL=DIGEST` — required exact 64-hex digest for each model; repeatable.
- `--clean` — delete staging and shared Ollama stores before setup. Omit when adding a model to an existing worker store.
- `--context N` — exact context length; defaults to 262144 and is always passed explicitly to remote setup.
- `--heartbeat-seconds N` — heartbeat interval; default 10 seconds.

The command fails before spawning if no current active fleet exists, a requested worker is absent/destroyed, the remote bootstrap wrapper is missing, or another bootstrap command holds the fleet bootstrap lock.
