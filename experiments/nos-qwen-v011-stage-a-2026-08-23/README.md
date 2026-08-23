# Qwen # of Sessions v0.1.1 — Stage A

Purpose: determine whether the experimental NoS source-grounded duration-
reconciliation clarification fixes Qwen's duration compression without damaging
short-duration controls.

## Frozen execution order

1. ADV-0200 — Lake Monster
2. ADV-0287 — The House of Lament
3. ADV-0040 — Expedition to the Barrier Peaks

One replicate per case. Do not rerun for a more favorable sample.

## Predeclared gates

### ADV-0200 — Lake Monster
Canonical: 1 normalized session.

PASS: Normalized Sessions = 1.
STOP: Any other point estimate. Do not continue to House.

### ADV-0287 — The House of Lament
Canonical: 3 normalized sessions.

PASS: Normalized Sessions = 3, with no evidence that a visible benchmark or
target value was used as scoring evidence.
STOP: Any other point estimate or benchmark contamination. Do not continue to
Barrier Peaks.

### ADV-0040 — Expedition to the Barrier Peaks
Canonical: 7 normalized sessions.
Previous Qwen v0.1 result: 3.

PASS FOR CONTINUED TESTING:
- Normalized Sessions is at least 6, and
- canonical 7 is inside the Practical Range, and
- rationale is source-grounded and internally duration-reconciled.

STOP:
- Normalized Sessions <= 5, or
- material grounding / structural / normalization failure.

A Barrier result of 6+ is evidence that v0.1.1 materially corrects the observed
duration-compression failure. It is not by itself qualification evidence.

## Methodology

These three cases are prompt-development/regression data after v0.1.1 was designed
from their earlier miss pattern. They cannot independently qualify the modified
profile.

If Stage A passes, proceed to Witchlight as the harder development discriminator,
then LMoP if warranted. Final qualification requires separate untouched holdout
evidence.

External API cost target: $0.
