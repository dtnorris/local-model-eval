# RunPod burst worker runbook

This runbook captures the manually validated RunPod/Ollama path for AdventureFinder burst inference. The goal is to make worker #2 the first validation of the automated path, not another manual infrastructure exercise.

## Scope and architecture

`local-model-eval` remains the Mac-side control plane. `af-cli-scoring-utility`, the canonical source corpus, prompt construction, structured-output validation, and result artifacts remain on the Mac. A RunPod worker only runs Ollama plus the requested model weights.

The two-worker LME concurrency gate has passed, so LME now includes bounded RunPod REST API v2 provisioning and teardown. Provisioning remains separate from Ollama bootstrap, tunnels, worker checks, and scoring; see `docs/RUNPOD_API_FLEET.md`.

## Validated worker class

The first pilot used one NVIDIA A40 with 48 GB VRAM and full `262144` Ollama context. Both remote Qwen test tags loaded with the entire Ollama model allocation in VRAM and produced normal AdventureFinder structured output.

See `docs/benchmarks/runpod-a40-speed-2026-08-26.md` for the evidence and an important model-digest caveat.

## RunPod configuration

Use a normal RunPod Pod, not Serverless. The manually validated template was a general PyTorch image. Required properties:

- NVIDIA GPU with at least 48 GB VRAM for the current full-context stress case;
- SSH public-key access;
- **Direct TCP port 22 mapping**;
- enough `/workspace` quota for the model(s) assigned to that worker.

Do not rely on RunPod's `ssh.runpod.io` proxy for Ollama tunneling. It accepted interactive SSH but rejected the forwarding channel with `unknown channel type`. Use the public/direct TCP host and external port mapped to container port 22.

## Storage behavior learned during the pilot

The RunPod root/overlay disk was fast but small (about 30 GB in the pilot). `/workspace` was network-backed and much slower for direct Ollama pulls. The reliable pattern is therefore:

1. run an Ollama server whose `OLLAMA_MODELS` points at the fast local/root staging store;
2. pull **one model at a time** locally;
3. stop that server;
4. `rsync --info=progress2` the completed Ollama store into `/workspace/ollama-models`;
5. delete the local staging copy before pulling the next model;
6. after all requested models are copied, start the final Ollama server with `OLLAMA_MODELS=/workspace/ollama-models`.

The server process owns `OLLAMA_MODELS`. Setting `OLLAMA_MODELS` only on a client-side `ollama pull` command does not redirect a separately running server's storage.

Interrupted/mixed pulls can leave very large `*-partial*` blobs. The setup script avoids mixing active stores and stages models one at a time. If a manual recovery is ever required, inspect the store before deleting blobs.

## Worker setup: automated path

From the local `local-model-eval` checkout, after creating a fresh RunPod pod and obtaining its direct TCP SSH host and port, stream the setup script to the pod:

```bash
RUNPOD_HOST=<direct-tcp-ip-or-host>
RUNPOD_SSH_PORT=<external-port-mapped-to-22>

ssh \
  -p "$RUNPOD_SSH_PORT" \
  -i ~/.ssh/id_ed25519 \
  root@"$RUNPOD_HOST" \
  'bash -s -- --clean --model qwen3.6:27b' \
  < scripts/setup_runpod_ollama_worker.sh
```

The script prints timestamped, incremental feedback throughout package installation, model pulling, copying, server startup, warmup, and verification. Long downloads use Ollama's native progress output; cross-filesystem copies use `rsync --info=progress2`.

For worker #2, digest-control the remote model against worker #1's validated remote digest:

```bash
ssh \
  -p "$RUNPOD_SSH_PORT" \
  -i ~/.ssh/id_ed25519 \
  root@"$RUNPOD_HOST" \
  'bash -s -- \
    --clean \
    --model qwen3.6:27b \
    --expect-digest qwen3.6:27b=9d5803d493a991af27b9441c098aa56f2ed7bbd260877f075ec09b575c049bc3' \
  < scripts/setup_runpod_ollama_worker.sh
```

If Ollama's tag has changed, that command intentionally fails instead of silently admitting a different model binary into the concurrency experiment.

The setup script leaves the final workspace-backed Ollama server running and writes evidence under:

```text
/workspace/lme-worker-state/<UTC timestamp>/
```

That evidence includes GPU state, disk state, model digests, `/api/tags`, `/api/ps`, `ollama ps`, warmup logs, and final worker metadata.

## Mac tunnel: automated path

Use the direct TCP endpoint, not `ssh.runpod.io`:

```bash
scripts/runpod_ollama_tunnel.sh \
  --name burst_2 \
  --host "$RUNPOD_HOST" \
  --ssh-port "$RUNPOD_SSH_PORT" \
  --local-port 11442
```

The helper:

- checks key-based direct SSH first;
- starts a background tunnel;
- waits for `/api/version` to become reachable;
- prints incremental status while it waits;
- writes a PID/log under `output/tunnels/`;
- prints the environment variable to export for LME.

For example:

```bash
export LME_BURST_2_URL=http://127.0.0.1:11442
```

Stop it with:

```bash
scripts/runpod_ollama_tunnel.sh --stop --local-port 11442
```

## LME worker configuration

Add two remote workers to the ignored `config/workers.yml`. Keep endpoint values in environment variables:

```yaml
workers:
  burst_1:
    type: ollama
    base_url: ${LME_BURST_1_URL}
    hourly_rate_usd: 0.44
    labels: [remote, burst, nvidia, a40, 48gb]
    scorer_env:
      AF_LLM_PROVIDER: ollama
      AF_OLLAMA_BASE_URL: ${LME_BURST_1_URL}

  burst_2:
    type: ollama
    base_url: ${LME_BURST_2_URL}
    hourly_rate_usd: 0.44
    labels: [remote, burst, nvidia, a40, 48gb]
    scorer_env:
      AF_LLM_PROVIDER: ollama
      AF_OLLAMA_BASE_URL: ${LME_BURST_2_URL}
```

Use the actual hourly rate shown when the pod is launched; `$0.44/hr` above is only the rate used in the pilot planning example.

## Endpoint-safe speed benchmark

The original ad-hoc benchmark exposed an important routing bug: `AF_OLLAMA_BASE_URL` routes the scorer, but plain `ollama run`, `ollama ps`, and `ollama stop` otherwise default to local port `11434`.

`scripts/benchmark_qwen_speed.sh` fixes this by forcing **both** the Ollama CLI and the scorer to one selected endpoint. It also refuses to auto-pull a missing model.

Example:

```bash
scripts/benchmark_qwen_speed.sh \
  --endpoint http://127.0.0.1:11442 \
  --scorer-repo ../af-cli-scoring-utility \
  --model qwen3.6:27b \
  --expect-digest qwen3.6:27b=9d5803d493a991af27b9441c098aa56f2ed7bbd260877f075ec09b575c049bc3
```

Output is written under the scorer's `output/speed/<timestamp>/` by default and includes the full model digest, context length, GPU-residency check, wall time, structured-output status, and native scorer artifacts.

## Worker #2 concurrency gate

After both tunnels are live and `config/workers.yml` contains `burst_1` and `burst_2`:

```bash
bin/lme worker-check experiments/runpod-two-worker-concurrency-v1.yml
bin/lme plan experiments/runpod-two-worker-concurrency-v1.yml
bin/lme run experiments/runpod-two-worker-concurrency-v1.yml
```

Predeclared success criteria:

- both workers expose the **same full model digest** before the test;
- both jobs complete with normal structured output;
- pool dispatch sends one job to each worker rather than serializing them;
- total wall clock is no more than roughly `1.3x` the slower individual remote job;
- estimated scoring-runtime cost remains under the experiment cap.

Stop after this gate if LME does not actually parallelize. Do not create workers #3-#5 until two-worker concurrency is demonstrated.

## Cost boundary

The purpose of this automation is to reduce repeated setup burden, not to justify larger spend. Two-worker A40 concurrency has passed, so the bounded five-worker A40 gate is the next qualified experiment. Do not expand beyond five workers or move to a more expensive GPU/cloud tier without new benchmark evidence.
