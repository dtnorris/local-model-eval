# local-model-evaluation

Small experiment harness for running controlled `af-cli-scoring-utility` model evaluations across local and remote Ollama workers.

## Scope

This repository answers **what to test, where to run it, and what the experiment established**. It deliberately does **not** contain AdventureFinder scoring semantics, AFAO interpretation, prompts, guardrails, cloud provisioning, or autoscaling.

`af-cli-scoring-utility` remains authoritative for scoring behavior.

## v0.1 capabilities

- define Ollama workers as URLs plus environment variables;
- health-check workers and verify required models;
- define experiments declaratively in YAML;
- run either a worker-by-worker **matrix** or a shared **pool**;
- invoke the existing `bin/af-score` CLI;
- preserve native scorer output plus stdout/stderr/metadata;
- resume interrupted experiments without rerunning successful jobs;
- retry only failed jobs when requested;
- consolidate operational results into `jobs.csv`, `results.csv`, and `summary.md`;
- estimate per-worker scoring-runtime cost when an hourly rate is configured.

## Non-goals for v0.1

No RunPod/Vast API integration, GPU purchasing, Terraform, Docker orchestration, SSH fleet management, queues, databases, dashboards, autoscaling, or automatic model downloads.

The concrete first pilot is committed as `experiments/granite-platform-equivalence-v1.yml`. See `docs/SCORER_INTEGRATION_GATE.md` before starting paid compute.

## Requirements

- Ruby 3.1+
- an existing checkout of `af-cli-scoring-utility`
- one or more reachable Ollama-compatible endpoints
- the target model already installed on each worker used by the experiment

## Setup

```bash
bundle install
cp config/workers.example.yml config/workers.yml
$EDITOR config/workers.yml
```

Keep credentials and private endpoint URLs out of Git. `config/workers.yml` is ignored.

Environment variables in YAML may be written as `${NAME}` or `${NAME:-default}`.

## Worker configuration

```yaml
workers:
  mac:
    type: ollama
    base_url: http://127.0.0.1:11434
    hourly_rate_usd: 0.0
    labels: [local, apple-silicon]
    scorer_env:
      AF_LLM_PROVIDER: ollama
      AF_OLLAMA_BASE_URL: http://127.0.0.1:11434

  cloud_a:
    type: ollama
    base_url: ${LME_CLOUD_A_URL}
    hourly_rate_usd: 0.33
    labels: [cloud, nvidia, a6000]
    scorer_env:
      AF_LLM_PROVIDER: ollama
      AF_OLLAMA_BASE_URL: ${LME_CLOUD_A_URL}
```

The harness intentionally treats scorer environment variables as configuration rather than hard-coding the scorer's remote-endpoint variable name. If the scorer uses a different endpoint variable, change `scorer_env` without changing this repository.

## Dry-run the experiment plan

```bash
bin/lme plan experiments/my-experiment.yml
```

This expands the manifest without running inference and shows the job count, workers, rates, and configured pilot cap.

## Check workers

```bash
bin/lme worker-check
```

For a particular experiment/model:

```bash
bin/lme worker-check experiments/granite-platform-equivalence-v1.yml
```

The check calls Ollama's `/api/version` and `/api/tags` endpoints.

## Define an experiment

See `experiments/templates/model-viability.yml`.

The two dispatch modes are:

- `matrix`: every configured worker runs every model/adventure/replicate combination. Use this for platform-equivalence tests.
- `pool`: each model/adventure/replicate combination runs once and is assigned to the next available compatible worker. Use this to parallelize an evaluation campaign.

## Run

```bash
bin/lme run experiments/my-experiment.yml
```

By default, completed jobs are never rerun.

```bash
bin/lme run experiments/my-experiment.yml --rerun-failed
bin/lme run experiments/my-experiment.yml --force
```

## Report

A report is written automatically after a run. It can also be regenerated:

```bash
bin/lme report output/my-experiment
```

Output layout:

```text
output/<experiment>/
├── experiment.yml
├── environment.json
├── jobs.csv
├── results.csv
├── summary.md
└── runs/
    └── <job-id>/
        ├── metadata.json
        ├── stdout.log
        ├── stderr.log
        └── native/        # untouched af-score output
```

`results.csv` performs only lightweight extraction of common `score` and `confidence` fields from scorer JSON output. The native files remain authoritative.

## Cost discipline

The harness does not provision paid compute. A worker's `hourly_rate_usd` produces a **scoring-runtime estimate**, not a provider invoice. If `cost_cap_usd` is set, v0.1 stops dispatching new jobs once completed-job estimated runtime reaches that cap. This is deliberately a **soft cap**: already-running jobs can finish, and provider idle/storage/network charges are outside the estimate.

Before adding cloud-provider automation, v0.1 should first establish:

1. remote Ollama produces legitimate comparable scoring evidence;
2. parallel execution materially improves throughput;
3. enough repeated use exists to justify automation work.

## Tests

```bash
bundle exec ruby -Itest test/config_test.rb
bundle exec ruby -Itest test/experiment_test.rb
bundle exec ruby -Itest test/scheduler_test.rb
bundle exec ruby -Itest test/runner_test.rb
```
