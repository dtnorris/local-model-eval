# RunPod Serverless scale-zero-to-eight probe

This is a disposable infrastructure experiment, not another fleet
orchestrator. It creates one RunPod Serverless template and one scale-zero
endpoint, submits eight copies of one trivial prompt, records burst latency,
and deletes both resources on success, failure, timeout, or interrupt.

## Frozen experiment

- runtime: `runpod/worker-v1-vllm:v2.26.0`
- model: `openai/gpt-oss-20b`
- GPU: 8 × Secure RTX 4090
- scale: `workersMin=0`, `workersMax=8`
- scaler: `REQUEST_COUNT`, one queued/in-progress request per worker
- prompt: `Reply with exactly: OK`
- generation cap: 8 tokens
- hard measurement deadline: 90 seconds

`openai/gpt-oss-20b` is an infrastructure proxy of the same model family and
size used by the existing Ollama pilot. This test makes no claim that it is
bit-identical or behaviorally equivalent to the frozen Ollama digest.

## Run

First perform the authenticated, read-only check:

```bash
bin/lme-runpod-serverless-burst-probe --dry-run
```

Then run the paid probe while preventing the Mac from sleeping:

```bash
caffeinate -dimsu bin/lme-runpod-serverless-burst-probe
```

The command reads `RUNPOD_API_KEY` from the process environment or the repo's
`.env` without evaluating `.env` as shell. It prints the frozen plan and asks
for the exact confirmation `RUN` before creating anything. `--yes` is available
for deliberate non-interactive execution.

The RunPod account must permit at least eight Serverless workers. RunPod's
documented balance-based limit is normally five workers below $100 balance and
ten workers at $100 or above. Failure to create an endpoint with
`workersMax=8` occurs before any inference job is submitted.

## Metrics and gate

All durations use a monotonic clock starting immediately before the eight
concurrent `/run` submissions:

1. `request submitted → eight workers ready`: first `/health` response where
   `idle + running >= 8`;
2. `request submitted → eight first tokens`: the latest first non-empty text
   observed across the eight `/stream/{job_id}` responses.

The result is:

- **STRONG PASS**: eight workers ready in 30 seconds or less, eight first-token
  observations, and eight completed jobs;
- **PASS**: the same requirements with workers ready in 60 seconds or less;
- **FAIL**: any other result, including queue-draining by fewer than eight
  workers or the 90-second deadline.

The official worker's `MODEL_NAME` route is eligible for RunPod's managed
Hugging Face model cache. RunPod does not expose independent per-worker network
transfer telemetry through this probe, so “no public download” is not asserted
directly. A cache miss should instead appear as startup delay and likely trip
the deadline.

## Artifacts and teardown

Each attempt writes `plan.json`, the created resource IDs, timestamped health
and stream observations, `summary.json`, and `cleanup.json` beneath:

```text
output/serverless-burst-probe/<UTC timestamp>__<run id>/
```

Cleanup deletes the endpoint (terminating its jobs and workers) and then deletes
the template. The command exits nonzero unless both deletion checks return `404`. If the process
is killed in a way that bypasses `finally` (for example `kill -9`), use the
commands recorded in `resource-ids.json`. The endpoint has a five-second idle
worker timeout as an additional GPU-spend backstop.

At the current catalog rate encoded by the experiment ($0.00031/GPU-second),
90 seconds with all eight GPUs billed would cost $0.2232. The final summary also
computes a more conservative estimate across the full submission-to-cleanup
interval and labels it as an estimate rather than billing telemetry.
