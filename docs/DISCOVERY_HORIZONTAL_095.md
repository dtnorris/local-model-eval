# Discovery-95 horizontal priority scoring

This patch adds a temporary, adventure-major production path for the frozen 95-adventure Discovery cohort.

It does **not** replace or mutate production backlogs 008-012. It reads `5e_Adventure_Master_Catalog_2.12.2.xlsx`, skips populated core cells, reuses an existing frozen manifest whenever the exact adventure/dimension pair already exists, and mechanically clones the appropriate frozen production template only when a blank pair has no existing manifest.

The queue remains local-only (`external_api_cost_usd: 0.0`) and preserves the no-favorable-rerun contract. Existing complete and failed samples are never rerun.

## Prepare — zero inference

```sh
bin/prepare-discovery-horizontal
./status_discovery_horizontal.sh
```

The planner freezes the AMC SHA-256 into `production_backlog/discovery-horizontal-095-v0.1/snapshot.yml`. The runner refuses to start if that workbook changes after preparation.

## Switch from an active vertical backlog

Gracefully pause the current production queue first:

```sh
./pause_production_backlog.sh
```

Wait for the active inference to finish and for the old runner to exit. Then clear the now-stale global pause sentinel:

```sh
rm -f output/production-backlog-control/pause
```

Do not clear the sentinel while another production call is still active. The horizontal runner also refuses to start while `output/production-backlog-control/current` exists.

## Run

```sh
./run_discovery_horizontal.sh
```

The runner performs a frozen-plan check and runtime source preflight before inference, then executes `run_order.txt` in adventure-major order. It uses the same global graceful-pause mechanism and circuit breaker as the normal production runner.

## Monitor / pause

```sh
./status_discovery_horizontal.sh
./pause_production_backlog.sh
```

## Expected behavior with AMC 2.12.2 used to design this patch

The frozen 95 IDs are all present in AMC 2.12.2. At patch construction time the workbook had 466 blank cells/operations across the 12 locally sortable core dimensions. Some of those operations may already have completed local outputs from batches 008/009; those manifests remain in the horizontal plan but are skipped at runtime rather than rerun.

All blank Exploration Emphasis cases in this 95-adventure cohort were within the qualified 60-page EE envelope.
