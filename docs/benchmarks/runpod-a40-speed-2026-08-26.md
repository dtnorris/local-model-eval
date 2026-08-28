# RunPod A40 speed pilot — 2026-08-26

## Purpose

Validate the cheap remote-worker deployment/latency path before scaling `local-model-eval` beyond the Mac. The benchmark used the same AdventureFinder scoring case on the Mac and a single RunPod A40 worker:

- Adventure: `ADV-0200`
- Dimension: `Social Interaction Emphasis`
- Ollama context: `262144`
- Models/tags: `qwen3.6:27b` and `qwen3.6:35b-a3b`
- Structured-output handling: normal `af-cli-scoring-utility`; no JSON salvage

Authoritative run directories from the captured benchmark bundle:

- local: `speed/20260826-205002/`
- remote A40: `speed/20260826-230913/`

Earlier remote attempts `230439` and `230558` were infrastructure/routing debug attempts and are excluded from benchmark evidence.

## Observed results

| Tag | Platform | Full digest | Ollama loaded size | Context | Full GPU | Wall time | Structured output |
|---|---|---|---:|---:|---|---:|---|
| `qwen3.6:27b` | M4 Pro / local Ollama | `a50eda8ed977ab48a12431878896b27ffd5cef552c17af3317d9623b939a7f1e` | 33.52 GB | 262144 | yes | 603.141 s | PASS |
| `qwen3.6:27b` | RunPod A40 / Ollama | `9d5803d493a991af27b9441c098aa56f2ed7bbd260877f075ec09b575c049bc3` | 18.41 GB | 262144 | yes | 150.281 s | PASS |
| `qwen3.6:35b-a3b` | M4 Pro / local Ollama | `07d35212591fc27746f0a317c975a6d68754fb38e9053d82e25f06057af28522` | 28.58 GB | 262144 | yes | 136.884 s | PASS |
| `qwen3.6:35b-a3b` | RunPod A40 / Ollama | `096fdbd02fe620fc10cbeb6537e080f8041aece851e5d696aed024d4f70f2e47` | 23.04 GB | 262144 | yes | 117.001 s | PASS |

Naively dividing the wall times gives about `4.01x` for the 27B tag and `1.17x` for the 35B-A3B tag.

## Critical interpretation constraint

**Those ratios are not strict hardware/platform speedups.**

The Mac and RunPod pulls used the same human-readable tags but different full Ollama digests. The model metadata also differs slightly:

- local `qwen3.6:27b`: reported parameter size `27.8B`;
- remote `qwen3.6:27b`: reported parameter size `27.3B`;
- local `qwen3.6:35b-a3b`: reported parameter size `36.0B`;
- remote `qwen3.6:35b-a3b`: reported parameter size `35.5B`.

Therefore the experiment establishes **operational remote latency for the tested remote digests**, not a binary-identical M4-vs-A40 hardware comparison. Do not attribute the entire observed difference to the A40.

A strict platform-speed comparison would require the same model digest/weights on both platforms.

## What the pilot does establish

The single A40 pilot cleared the infrastructure gate:

1. A 48 GB A40 can serve the tested remote Qwen tags at `262144` context with the Ollama model allocation fully in VRAM.
2. The Mac scorer can route through an SSH tunnel to remote Ollama without moving the scorer or source corpus to the worker.
3. Both remote scoring calls completed through normal AdventureFinder structured-output validation.
4. Remote single-job latency was approximately 150 s for the tested 27B digest and 117 s for the tested 35B-A3B digest.
5. The remote worker is fast enough to justify testing whether two independent workers collapse two-job wall clock toward one-job latency.

## Next falsifiable gate

Worker #2 should be created using `scripts/setup_runpod_ollama_worker.sh` and should be required to match worker #1's full remote digest for the selected concurrency model.

For the first two-worker test, use `qwen3.6:27b` with expected digest:

```text
9d5803d493a991af27b9441c098aa56f2ed7bbd260877f075ec09b575c049bc3
```

Then run `experiments/runpod-two-worker-concurrency-v1.yml` in pool mode.

Success: two valid jobs finish in no more than about `1.3x` the slower individual remote job, with one job assigned to each worker.

Failure/stop: serial behavior, digest mismatch, structured-output failure attributable to the remote path, or cost cap reached. Do not scale to five workers after a failed two-worker gate.
