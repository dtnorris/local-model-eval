# Adventure-major ordering benchmark

Zero-cost local benchmark for `local-model-eval` PR #3.

It compares the same six atomic Qwen scoring calls in two orders:

- Arm A: dimension-major control
- Arm B: adventure-major execution

Cases are ADV-0034 and ADV-0062 across Social Interaction Emphasis, Investigation Emphasis, and Seriousness. The scorer prompt shape is unchanged.

Run from the repository root:

```bash
./run_adventure_major_ordering_benchmark.sh
```

Decision gate: >=40% STRONG PASS; >=25% PASS; <15% FAIL; 15% to <25% INCONCLUSIVE. For an inconclusive first run only, run one reverse-order tie-breaker:

```bash
BENCHMARK_ORDER=BA ./run_adventure_major_ordering_benchmark.sh
```
