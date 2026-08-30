# RunPod Pre-Inference Readiness Gate

`bin/lme runpod-ready EXPERIMENT.yml` is the single pre-inference gate for experiments that use managed `burst_N` RunPod workers.

It does **not** start pods, bootstrap models, start tunnels, warm a model, or invoke the scorer. It performs only control-plane and health reads, so it should be run after provisioning/bootstrap/tunnel setup and immediately before scoring.

## What must pass

For every managed RunPod worker selected by the experiment, the gate requires:

1. **Fleet state** — the current fleet exists, is active, and contains the selected active `burst_N` workers.
2. **RunPod provider state** — the selected pod IDs are still present in one live RunPod `list_pods` response, have the expected managed names, and report `RUNNING`.
3. **Exact provenance** — the latest current-fleet bootstrap passed and proves the experiment's exact Ollama model, pinned digest, 262144 context, expected GPU, and full GPU residency.
4. **Managed tunnels** — the selected fleet-scoped tunnel PIDs still match their recorded SSH identities, the processes are running, `/api/version` succeeds, and each tunnel endpoint exactly matches the corresponding configured worker endpoint.
5. **Worker health** — through those already-verified tunnels, Ollama `/api/version` and `/api/tags` succeed and the experiment's required models and worker labels are present.

A failed tunnel gate deliberately skips the subsequent worker-health request rather than waiting on endpoints already known to be unavailable.

## Usage

```bash
bin/lme runpod-ready experiments/example.yml
```

Successful output ends with:

```text
READY TO RUN -- all managed RunPod pre-inference gates passed.
```

A failed check exits nonzero and ends with `NOT READY`. No inference is started.

`bin/lme run EXPERIMENT.yml` invokes the same gate automatically before constructing the scorer runner. This prevents the standalone readiness command from becoming an optional operator ritual that can be accidentally skipped.

Experiments with no managed `burst_N` workers are reported as `NOT APPLICABLE`; their existing local/non-managed execution path is unchanged.

## Cost and latency

The gate issues no model-generation request. Its live work is limited to:

- one RunPod `list_pods` control-plane request for all selected pods;
- the managed-tunnel `/api/version` health checks; and
- the existing worker checks (`/api/version` plus `/api/tags`) through localhost tunnels.

It does not reload/warm a model or query `/api/ps`, because exact context/GPU-residency evidence was already captured during bootstrap. Billing figures shown by the gate are derived from fleet-scoped local state and remain estimates, not provider invoices.
