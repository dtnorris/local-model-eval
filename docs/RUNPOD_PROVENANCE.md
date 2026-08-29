# RunPod Exact Provenance Gate

Managed RunPod scoring is fail-closed on model identity and runtime provenance.

The provenance contract is established during `bin/lme runpod-bootstrap` and enforced again immediately before `bin/lme run` starts scoring on any `burst_N` worker.

## Bootstrap contract

For every requested model, bootstrap requires an exact 64-hex Ollama digest:

```bash
bin/lme runpod-bootstrap \
  --workers 1-5 \
  --model gemma4:26b \
  --expect-digest gemma4:26b=<64-hex-digest>
```

The launcher derives the expected GPU from the current fleet state and passes it to remote setup. The context is always explicit; when `--context` is omitted it is pinned to `262144`.

Remote setup fails before model download if the detected GPU name does not exactly match the fleet GPU. It already fails on digest mismatch, context mismatch, and partial GPU residency.

At the end of setup the remote worker emits machine-readable evidence for:

- exact GPU name and VRAM;
- exact Ollama model name;
- exact model digest;
- context length;
- model size;
- VRAM-resident size; and
- whether the complete model is GPU-resident.

LME parses those markers and independently validates them before marking the worker bootstrap `passed`. The observed values are persisted under that worker's `provenance` key in the fleet-scoped `bootstrap.json`.

## Pre-scoring gate

`bin/lme run EXPERIMENT.yml` inspects the experiment's model aliases and burst workers before constructing the scoring runner.

For a RunPod burst experiment it requires:

1. a current active fleet;
2. a latest bootstrap run for that exact fleet;
3. bootstrap state `passed`;
4. every selected burst worker present and `passed` in that bootstrap;
5. the exact Ollama model required by the experiment;
6. a pinned 64-hex digest for that model;
7. each selected worker reporting that exact digest;
8. context `262144`;
9. exact detected GPU equal to the fleet GPU; and
10. `size == size_vram` for complete model residency.

If any condition differs, scoring does not start. A fleet bootstrapped with Qwen cannot silently run an experiment configured for Gemma merely because both workers answer Ollama health checks.

Local-only experiments are unaffected; the gate applies only when the experiment names one or more `burst_N` workers.

The gate is intentionally based on durable local bootstrap evidence rather than a fuzzy model-name prefix match. The normal `worker-check` remains useful for live Ollama/tunnel health, while exact provenance answers a different question: **is this the same verified model/runtime we intended to score with?**
