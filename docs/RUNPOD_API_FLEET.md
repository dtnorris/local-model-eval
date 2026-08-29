# RunPod API fleet provisioning

LME can provision and destroy the bounded RunPod burst fleet through the RunPod REST API v2. This automation was added only after the two-worker pool-dispatch concurrency gate passed.

Provisioning remains a separate control-plane step. It does **not** bootstrap Ollama, pull models, start SSH tunnels, run worker checks, or start AdventureFinder scoring.

## Local prerequisites

The ignored repo-local `.env` must contain a valid RunPod API key:

```dotenv
RUNPOD_API_KEY=<real-key>
```

The default SSH public key is `~/.ssh/id_ed25519.pub`. Override it with `RUNPOD_SSH_PUBLIC_KEY_PATH` or `--ssh-public-key PATH` if needed. Never provide a private key.

## Read-only preflight

Always start with:

```bash
bin/lme runpod-create --workers 5 --dry-run
```

The dry run performs only read-only RunPod API calls plus local prerequisite validation. It refuses duplicate managed pod names, verifies the pinned A40 has at least 48 GB VRAM and COMMUNITY availability, and prints the current catalog price, fleet hourly rate, projected 10-minute/30-minute cost, and hourly safety cap. No pod is created.

The default fleet safety cap is `$3.00/hr`; override it downward or upward explicitly with `--max-hourly-usd` or `RUNPOD_MAX_FLEET_HOURLY_USD`. LME never silently switches from COMMUNITY to a more expensive cloud tier or from A40 to another GPU.

## Create the fleet

After reviewing a clean dry run:

```bash
bin/lme runpod-create --workers 5
```

The command asks for confirmation before the first paid mutation. `--yes` exists for deliberate non-interactive use.

The provisioner pins:

- 1x `NVIDIA A40` per worker;
- `COMMUNITY` cloud;
- `runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404`;
- 30 GB container disk;
- 60 GB persistent storage mounted at `/workspace`;
- direct `22/tcp` exposure;
- the selected local OpenSSH public key through `PUBLIC_KEY`.

Pods are named `af-lme-burst-1` through `af-lme-burst-5`. LME polls until each pod is `RUNNING` and exposes a public TCP mapping for container port 22, then verifies the returned GPU configuration and actual hourly rate.

If any create, readiness, GPU, networking, timeout, or cost check fails, LME attempts to delete every pod created by that invocation and does not write new routing values to `.env`.

Only after every requested worker passes does LME atomically update the ignored `.env` with:

```text
LME_BURST_N_URL
RUNPOD_BURST_N_POD_ID
RUNPOD_BURST_N_HOST
RUNPOD_BURST_N_SSH_PORT
RUNPOD_BURST_N_HOURLY_RATE
```

Provisioning then stops. Continue with the existing worker bootstrap and tunnel scripts, followed by `worker-check` and `plan`, before any scoring run.

## Destroy the fleet

Destroy selected managed workers with:

```bash
bin/lme runpod-destroy --workers 1-5
```

The command confirms before deletion. It verifies the exact managed name before deleting a pod and clears generated pod/routing metadata from `.env` after successful deletion. If `.env` was never hydrated because provisioning failed, teardown can recover a uniquely named `af-lme-burst-N` pod from the live RunPod pod list.

`--yes` skips the teardown confirmation for deliberate non-interactive use.

## Cost boundary

This command exists to reduce paid idle/setup time, not to justify larger compute. The five-worker A40 fleet is the currently qualified next experiment. Do not change the GPU class, cloud tier, or fleet size beyond the tested gate merely because provisioning is now automated.
