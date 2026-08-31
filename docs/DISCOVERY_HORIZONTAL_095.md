# Discovery-95 horizontal priority scoring

This patch adds a temporary, adventure-major production path for the frozen 95-adventure Discovery cohort.

It does **not** replace or mutate production backlogs 008-012. It reads `5e_Adventure_Master_Catalog_2.12.2.xlsx`, skips populated core cells, reuses an existing frozen manifest whenever the exact adventure/dimension pair already exists, and mechanically clones the appropriate frozen production template only when a blank pair has no existing manifest.

**Number of Sessions is intentionally excluded from this horizontal scoring queue.** Production Batch 8 is complete; those accepted local results are awaiting import from the LRD workflow. Blank `Number of Sessions` cells in AMC 2.12.2 therefore represent an ingestion backlog, not an inference backlog, and must not trigger re-scoring.

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

The frozen 95 IDs are all present in AMC 2.12.2. At initial patch construction time the workbook had 466 blank cells/operations across the 12 locally sortable core dimensions, including 92 blank `Number of Sessions` cells. Those 92 NoS cells are deliberately **not** part of this queue because Batch 8 inference is already complete and awaiting ingestion.

All blank Exploration Emphasis cases in this 95-adventure cohort were within the qualified 60-page EE envelope.

AMC 2.12.2 also contains three cohort adventures with both Levels cells blank but no Batch 9 Levels manifest: ADV-0031 (White Plume Mountain), ADV-0032 (Dead in Thay), and ADV-0230 (Salvage Operation). Batch 9's adventure-wide reservation logic excluded them because earlier production indexes already reserved other dimensions. The horizontal planner therefore permits Levels synthesis only for those three IDs, mechanically cloning the frozen Batch 9 `levels-v2.1` template. Any other missing non-EE manifest still fails closed.
