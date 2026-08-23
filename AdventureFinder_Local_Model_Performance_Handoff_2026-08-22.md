# AdventureFinder Local-Model Work Handoff
## Adventure-major execution experiment — paused state

**Date:** 2026-08-22  
**Project:** AdventureFinder  
**Status:** Performance-enhancement thread intentionally paused; safe handoff point.

---

## 1. Purpose of this handoff

This document is intended to be pasted or uploaded into a new ChatGPT conversation so work can resume with minimal reconstruction.

The immediate thread being paused was an attempt to improve local-model calibration / qualification throughput by changing execution order from **dimension-major** to **adventure-major** while keeping every scoring prompt atomic and unchanged.

The experiment was completed. The simple ordering optimization did **not** produce a meaningful speedup in the test we ran.

Do **not** repeat the completed benchmark unless there is a new experimental reason to do so.

---

## 2. Relevant repositories

### `local-model-eval`

Local checkout used for this work:

```text
/Users/davidnorris/code/local-model-eval2
```

GitHub repo:

```text
https://github.com/dtnorris/local-model-eval
```

Open PR containing the adventure-major orchestration work:

```text
https://github.com/dtnorris/local-model-eval/pull/3
```

PR title:

```text
add adventure-major batch ordering
```

PR base:

```text
main
```

PR branch:

```text
adventure-major-ordering
```

PR head commit at benchmark time:

```text
70c1892c305466adac3dfc19924fc09c39713566
```

The PR was intentionally narrow and additive. It changed only:

```text
bin/lme-batch
lib/local_model_evaluation/manifest_batch.rb
test/manifest_batch_test.rb
```

It did **not** modify:

```text
bin/lme
lib/local_model_evaluation/runner.rb
af-cli-scoring-utility
```

Local tests passed.

### `af-cli-scoring-utility`

Local checkout expected by the benchmark manifests:

```text
/Users/davidnorris/code/af-cli-scoring-utility
```

Scorer commit used during the completed benchmark:

```text
b90684c3f65b1d6ac95381f8bb5dd2c11ef38822
```

Important architectural boundary:

- `af-cli-scoring-utility` remains authoritative for scoring behavior, source resolution, prompts, rubrics, guardrails, validation, and output.
- `local-model-eval` is the orchestration / experiment-management layer.
- The performance experiment deliberately did **not** change scorer prompt semantics.

---

## 3. Why adventure-major ordering was investigated

Existing calibration / qualification work frequently represents each inference as an atomic unit:

```text
one model
× one adventure
× one dimension
× one replicate
```

Historically, many batches were effectively dimension-major:

```text
Dimension A:
  ADV-0034
  ADV-0040
  ADV-0053
  ...

Dimension B:
  ADV-0034
  ADV-0040
  ADV-0053
  ...
```

The hypothesis was that a large adventure source might be repeatedly prefetched / evaluated by the model, and that local Ollama prompt/KV caching could be exploited by changing only the execution order:

```text
ADV-0034:
  Dimension A
  Dimension B
  Dimension C

ADV-0040:
  Dimension A
  Dimension B
  Dimension C
```

This was attractive because it could potentially improve throughput without changing calibration methodology.

The desired first-stage optimization was therefore:

> **Support adventure-major ordering without changing the scoring prompt shape at all.**

---

## 4. What PR #3 implements

PR #3 adds a separate additive executable:

```text
bin/lme-batch
```

It consumes a list of existing atomic experiment manifests and sorts them deterministically:

```text
worker → model → adventure → dimension
```

Then it invokes the existing command for every manifest:

```text
bin/lme run MANIFEST.yml
```

Therefore:

- each dimension remains a separate model call;
- existing scorer prompts remain unchanged;
- existing output namespaces remain separate;
- validation behavior remains unchanged;
- resume / retry behavior still comes from `bin/lme run`;
- no grouped multi-dimension inference is introduced.

The batch implementation intentionally requires each listed manifest to contain exactly:

```text
1 worker
1 model
1 adventure
1 replicate
```

This was done so cache locality could actually be associated with the same Ollama worker.

---

## 5. Completed benchmark design

A tiny local $0 benchmark was created.

Model:

```text
qwen3.6:35b-a3b
```

Ollama version:

```text
0.32.14
```

Worker:

```text
mac
```

Adventures:

```text
ADV-0034
ADV-0062
```

Dimensions:

```text
Social Interaction Emphasis
Investigation Emphasis
Seriousness
```

There were 6 atomic calls per arm.

### Arm A — dimension-major control

```text
Social        ADV-0034
Social        ADV-0062
Investigation ADV-0034
Investigation ADV-0062
Seriousness   ADV-0034
Seriousness   ADV-0062
```

Adventure sequence:

```text
0034 → 0062 → 0034 → 0062 → 0034 → 0062
```

### Arm B — adventure-major experimental

```text
ADV-0034 Investigation
ADV-0034 Seriousness
ADV-0034 Social

ADV-0062 Investigation
ADV-0062 Seriousness
ADV-0062 Social
```

Adventure sequence:

```text
0034 → 0034 → 0034 → 0062 → 0062 → 0062
```

Both arms used fresh benchmark-specific output namespaces.

Before each arm the benchmark:

1. unloaded Qwen;
2. performed a tiny unrelated model warm-up before timing;
3. cleared only that arm's benchmark outputs;
4. then measured the six scoring calls.

The benchmark was explicitly designed to measure execution-order differences, not prompt changes.

---

## 6. Predeclared benchmark gate

Before execution, the decision rule was frozen as:

```text
>= 40% wall-clock reduction    STRONG PASS
>= 25% wall-clock reduction    PASS
15% to <25% reduction          INCONCLUSIVE
< 15% reduction                FAIL
```

Only an inconclusive result was supposed to justify one reverse-order BA rerun.

---

## 7. Benchmark result

Completed result file:

```text
/Users/davidnorris/code/local-model-eval2/output/adventure-major-ordering-benchmark/result-20260822-191303.txt
```

Execution order:

```text
AB
```

### Aggregate timing

Arm A — dimension-major:

```text
wall-clock_seconds:      790.906
scoring-runtime_seconds: 790.012
```

Arm B — adventure-major:

```text
wall-clock_seconds:      786.096
scoring-runtime_seconds: 785.161
```

Adventure-major improvement:

```text
wall-clock reduction:      0.6%
scoring-runtime reduction: 0.6%
```

Decision:

```text
FAIL
```

External shell timing for the complete benchmark:

```text
26:46.23 total
```

Do **not** run the reverse-order BA benchmark based on this result. The result was nowhere near the predefined inconclusive band.

---

## 8. Per-call timing analysis

The full benchmark archive was inspected.

Corresponding A/B calls were essentially identical in runtime:

| Adventure / dimension | Arm A | Arm B | Approx. B change |
|---|---:|---:|---:|
| ADV-0034 Investigation | 146.188s | 144.305s | -1.3% |
| ADV-0034 Seriousness | 131.373s | 129.485s | -1.4% |
| ADV-0034 Social | 131.981s | 132.131s | +0.1% |
| ADV-0062 Investigation | 136.365s | 136.284s | -0.1% |
| ADV-0062 Seriousness | 124.896s | 124.137s | -0.6% |
| ADV-0062 Social | 119.209s | 118.819s | -0.3% |

There was **no hidden within-adventure acceleration** in Arm B.

In particular, B's second and third calls on the same adventure did not suddenly become materially faster.

---

## 9. Experimental integrity findings

The benchmark was unusually clean.

All 12 calls:

- completed successfully;
- exited with status 0;
- had empty stderr;
- used the same LME commit;
- used the same scorer commit;
- used the same worker;
- used the same Qwen model;
- used the same Ollama endpoint;
- used the same replicate count.

The corresponding A/B prompt-token counts were identical:

```text
ADV-0034 Investigation   30,188 / 30,188
ADV-0034 Seriousness     28,542 / 28,542
ADV-0034 Social          29,011 / 29,011

ADV-0062 Investigation   26,278 / 26,278
ADV-0062 Seriousness     24,877 / 24,877
ADV-0062 Social          24,952 / 24,952
```

Completion-token counts were also identical.

Most importantly:

> For every corresponding A/B pair, the complete assistant message was byte-for-byte identical, including Ollama's hidden `reasoning` field.

Therefore the 0.6% result was not caused by one arm producing longer or shorter reasoning/completions.

---

## 10. Score-quality comparison

A and B returned the same scores.

Observed benchmark comparison:

| Adventure / Dimension | Local A | Local B | AFAO |
|---|---:|---:|---:|
| ADV-0034 Social | 1 | 1 | 1 |
| ADV-0062 Social | 2 | 2 | 2 |
| ADV-0034 Investigation | 2 | 2 | 1 |
| ADV-0062 Investigation | 2 | 2 | 1 |
| ADV-0034 Seriousness | 5 | 5 | 5 |
| ADV-0062 Seriousness | 4 | 4 | 3 |

Summary:

```text
3 exact
3 adjacent
0 hard
```

The ordering change introduced no observed scoring-quality change.

---

## 11. What the benchmark DOES establish

The completed evidence supports:

> **On Qwen3.6 35B via Ollama 0.32.14, adventure-major ordering provides no meaningful performance advantage over alternating between two large adventure contexts.**

The measured difference was only 0.6%.

It also establishes:

- Ruby/process orchestration overhead is negligible compared with inference time;
- identical focused scoring calls remain quality-stable under the changed order;
- there is no meaningful second/third-call acceleration simply from placing the same adventure calls consecutively in this two-adventure setup.

---

## 12. What the benchmark does NOT establish

There is one significant experimental limitation:

Arm A alternated only two large adventure prefixes.

It is plausible that Ollama could retain both prompt-prefix states simultaneously.

That differs from realistic calibration batches where reuse may occur only after 8–10 other adventure contexts.

Therefore this benchmark does **not** establish:

> adventure-major ordering has no benefit after realistic 8–10-adventure cache churn.

It establishes only the two-adventure case.

This distinction matters if the performance thread is ever resumed.

---

## 13. Important architectural observation from the benchmark

The source text appears early in the scorer prompt.

The focused prompt structure is broadly:

```text
SYSTEM_INSTRUCTIONS

# Canonical Target
Adventure ID
Adventure Title
Source Book
Publisher
...

# Published Source Material
<large canonical source extraction>

# AdventureFinder Production Assessment Rules
...

# AFAO rubric / dimension-specific guardrail
...

# Focused Assessment Task
Scoring dimension: ...
```

That means multiple dimensions for the same adventure do share a very large common prompt prefix.

However, despite that theoretical reuse opportunity, the completed two-adventure benchmark showed essentially no wall-clock benefit from merely making those calls contiguous.

---

## 14. Another performance finding: reasoning itself is expensive

The raw Ollama responses contained substantial hidden reasoning.

Approximate hidden reasoning character counts observed:

```text
ADV-0034 Investigation   ~13,310 chars
ADV-0034 Seriousness     ~10,219 chars
ADV-0034 Social          ~11,275 chars

ADV-0062 Investigation   ~13,732 chars
ADV-0062 Seriousness     ~12,142 chars
ADV-0062 Social          ~11,049 chars
```

The visible structured outputs were much smaller.

This suggests that repeated **reasoning/generation**, not only prompt prefill, may account for a substantial fraction of the 120–146 second per-call runtime.

That observation makes a future experiment in **multi-dimension grouped inference** potentially more interesting than simple scheduling, because grouped inference might reduce duplicated reasoning about the same adventure.

No grouped-scoring production change has been made or accepted.

---

## 15. If the performance thread is resumed later

Do not immediately run another full scoring benchmark.

The highest-information / lowest-compute diagnostic proposed at the pause point was:

### Direct Ollama prefix-cache microbenchmark

Use synthetic ~25–30K-token prompts but cap model output to essentially nothing.

Measure native Ollama prompt-evaluation timing for:

```text
Cold A
Warm A
```

Then:

```text
A
B
A
```

Then realistic churn:

```text
A
B
C
D
E
F
G
H
I
J
A
```

Questions:

1. How expensive is a cold 25–30K-token prefill?
2. How much faster is an exact cached prefix?
3. Can Ollama retain two AF-sized prefixes?
4. Does an AF-sized prefix survive 8–10 intervening contexts?

Decision logic:

- If cache reuse is large and A survives 2 contexts but not realistic 8–10 context churn, PR #3 may still be operationally useful.
- If cold vs cached prompt evaluation is small, or A survives realistic churn, close/deprioritize PR #3.
- Do not spend another 20–30 minutes on full reasoning-heavy scorer calls merely to diagnose the cache.

### Separate future possibility: grouped inference

Potential experiment:

```text
one adventure
one inference
3 dimensions
```

versus:

```text
same adventure
3 independent focused inferences
```

This would change the experimental/scoring condition and therefore requires explicit quality validation.

It should not be conflated with PR #3.

---

## 16. Current decision on PR #3

At the pause point:

- PR #3 is open.
- Tests pass.
- Implementation is clean and narrow.
- The first performance benchmark failed decisively at 0.6%.
- The benchmark has a two-context cache-retention limitation.
- No recommendation was made to merge it merely because the code exists.
- No recommendation was made to spend more inference time immediately.

Preferred state while this work is paused:

> **Leave PR #3 open/unmerged until there is a reason to resume performance investigation.**

Do not let sunk implementation effort drive the decision.

---

## 17. Cost-discipline requirement

This is a hard AdventureFinder project constraint.

Before recommending:

- paid APIs;
- hosted inference;
- rented compute;
- hardware purchases;
- larger/more expensive local infrastructure;

the next chat must:

1. evaluate materially cheaper viable alternatives first;
2. default to the cheapest experiment capable of answering the question;
3. quantify expected cost before recommending execution;
4. prefer small falsifiable pilots with explicit success/failure criteria;
5. require benchmark evidence before escalating compute;
6. never justify an expensive approach because money has already been spent;
7. optimize information gained per dollar;
8. explicitly push back on escalation when a cheaper plausible tier remains untested.

For the performance investigation described here, the next proposed cache diagnostic is local and effectively $0.

---

## 18. Broader local-model qualification state

The performance work was being conducted in parallel with local-model qualification.

Known high-level state at this handoff:

### Locally qualified

```text
Combat Emphasis
Structural Openness
Darkness / Horror Intensity
```

Primary successful local model:

```text
Qwen3.6 35B
```

### Not yet locally qualified / still under targeted evaluation

```text
Investigation Emphasis
Social Interaction Emphasis
Puzzle / Problem-Solving Emphasis
Lethality / Failure Severity
Seriousness
Fantastic Weirdness
```

Important examples of known Qwen tendencies:

- Investigation: lower-bound / endpoint issues; Tomb and No Honour have scored 2 where oracle is 1.
- Seriousness: tendency to score some interior cases upward; No Honour has scored 4 where oracle is 3.
- Fantastic Weirdness: notable hard miss on Into Dreamland in prior qualification work; model can underweight fundamentally weird fictional reality when activity verbs remain familiar.

Do not reinterpret these qualification results from the performance benchmark. The performance benchmark intentionally reused known focused dimensions only as timing workloads.

---

## 19. Do not redo these things

A new chat should **not** spend time re-establishing the following:

- whether PR #3 changes scorer prompt semantics — it does not;
- whether `af-cli-scoring-utility` needed a change for simple adventure-major ordering — it did not;
- whether the initial adventure-major benchmark passed — it decisively failed at 0.6%;
- whether the A/B calls differed in prompt token count — they did not;
- whether model output variability masked the result — corresponding A/B assistant messages were identical;
- whether a BA rerun is justified from the existing gate — it is not;
- whether orchestration overhead is a major bottleneck — it is not;
- whether grouped multi-dimension inference has already been validated — it has not.

---

## 20. Recommended prompt for a future continuation

A future chat can begin with:

> We are resuming the AdventureFinder local-model performance investigation from the attached handoff. Treat it as authoritative project state. Do not rerun the completed two-adventure A/B benchmark or re-derive PR #3. First inspect the current checked-out branches/commits because repository state may have changed since 2026-08-22. The performance work was intentionally paused after adventure-major ordering produced only a 0.6% improvement. If we resume performance optimization, default to the cheapest falsifiable next experiment and preserve the project's cost-discipline rules.

If the new task is unrelated to performance, the handoff still supplies enough context to avoid accidentally reopening this optimization thread.

---

# Bottom line

The adventure-major idea was implemented cleanly and tested fairly in a two-adventure workload.

Result:

```text
Dimension-major: 790.906 s
Adventure-major: 786.096 s
Improvement:       0.6%
Decision:          FAIL
```

The optimization is **paused**.

The only unresolved performance question worth retaining is whether realistic 8–10-adventure prompt-cache churn behaves differently from the two-adventure benchmark. If this work is resumed, answer that with a cheap direct Ollama cache microbenchmark before doing more full scorer inference.

