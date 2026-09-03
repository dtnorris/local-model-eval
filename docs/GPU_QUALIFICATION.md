# Generic one-worker GPU qualification

This is the hardware qualification gate for the AdventureFinder direct matcher
before any multi-worker RunPod burst.

LME's normal RunPod defaults remain `NVIDIA A40` and 48 GB minimum VRAM. This
workflow overrides those values only for the selected qualification process.

## Read-only gate

Example: RTX 3090 Community.

```bash
bin/lme-qualify-gpu \
  --gpu "NVIDIA GeForce RTX 3090" \
  --vram 24 \
  --cloud COMMUNITY \
  --dry-run
```

This validates the local matcher harness, pins the exact local `gpt-oss:20b`
Ollama digest, and asks RunPod whether one exact requested GPU is currently
available at the live catalog price. It creates no pod.

There is no automatic cloud-tier fallback. Test another tier explicitly.

## Paid qualification

After a passing dry-run and acceptable live rate:

```bash
caffeinate -dimsu bin/lme-qualify-gpu \
  --gpu "NVIDIA GeForce RTX 3090" \
  --vram 24 \
  --cloud COMMUNITY
```

The underlying `runpod-create` still asks for confirmation before the paid
mutation unless `--yes` is deliberately supplied.

The qualification always keeps the workload fixed:

- exactly one worker;
- `gpt-oss:20b`;
- exact model digest;
- 32,768 context;
- matcher case Q3-R1;
- temperature and seed unset.

It verifies the exact selected GPU and full model residency during bootstrap,
runs the representative matcher request, checks `/api/ps` again afterward,
requires `size == size_vram` at context 32,768, and records request duration,
output-token count, generation duration, and generation tokens/sec.

A 15-minute best-effort watchdog attempts paid-pod teardown if the workflow gets
stuck. Normal success and error cleanup also destroy the pod.

Artifacts are written under:

```text
output/gpu-qualification/<timestamp>__<gpu-slug>__gpt-oss_20b/
```

## Stop condition

Do not proceed to an N-worker burst if:

- the model cannot remain fully GPU-resident;
- the 32,768 context cannot be maintained;
- the representative matcher request fails; or
- measured throughput makes the expected burst wall-clock unattractive.

A passing one-worker qualification does not itself authorize a burst. Query
live N-worker availability and price for that exact GPU next.
