# Eight-worker direct-matcher burst pilot

This bounded pilot uses `local-model-eval` as the RunPod control plane while
keeping `af-matcher-cli` local on the Mac.

Eight RunPod A40 workers are provisioned and bootstrapped as independent Ollama
appliances. Eight SSH tunnels are opened, then eight local `af-matcher-cli`
processes run concurrently through those tunnels: one process for each of the
four frozen queries × two logical repeats.

The remote pods never receive the private matcher repository or AMC snapshot as
files. They receive only the Ollama requests sent through their local tunnels.

## Frozen experiment

- model: `gpt-oss:20b`
- workers: 8
- context: 32,768
- cases: `Q1:R1`, `Q2:R1`, `Q3:R1`, `Q4:R1`, `Q1:R2`, `Q2:R2`, `Q3:R2`, `Q4:R2`
- temperature: unset
- seed: unset
- output-token cap: unset
- one independent request per worker

The exact local Ollama model digest is pinned across all eight workers before
paid creation proceeds to inference.

## Read-only cost / availability gate

Always run this first:

```bash
bin/lme-matcher-burst --dry-run
```

The command runs local matcher tests, resolves the exact `gpt-oss:20b` digest,
and invokes LME's existing read-only RunPod preflight for eight A40 workers. No
pod is created by `--dry-run`.

If Community capacity is unavailable, do not silently fall back. Test Secure
explicitly:

```bash
bin/lme-matcher-burst --dry-run --cloud SECURE
```

## Execute

After reviewing a passing dry-run and its live price:

```bash
caffeinate -dimsu bin/lme-matcher-burst
```

The underlying `runpod-create` command still asks for confirmation before the
first paid mutation. `--yes` is available only for deliberate non-interactive
execution.

The driver:

1. creates exactly 8 managed RunPod workers;
2. starts a 25-minute best-effort paid-fleet teardown watchdog;
3. bootstraps `gpt-oss:20b` on all workers in parallel with exact digest,
   32,768 context, and full-GPU-residency verification;
4. opens 8 local Ollama tunnels;
5. dispatches the 8 frozen matcher cases concurrently;
6. writes local provenance, case mapping, timing, logs, and native matcher
   artifacts to `output/matcher-burst/`;
7. stops tunnels and destroys all 8 paid pods; and
8. creates a ZIP only after successful teardown so teardown evidence is included.

On failure or interrupt, the exit trap still attempts tunnel shutdown and paid
pod destruction before returning control.

If automatic teardown itself fails, the command exits nonzero and prints the
manual `runpod-destroy` command.

## Cost discipline

Eight-worker mode exists for this embarrassingly parallel, wall-clock-bounded
experiment. It does not change the project's normal one-worker cheap path. The
live `--dry-run` price and safety caps are authoritative; do not raise a cap
merely to force the experiment through.
