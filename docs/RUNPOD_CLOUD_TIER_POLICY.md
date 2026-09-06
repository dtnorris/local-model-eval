# RunPod cloud-tier policy

## Scope

This is the AdventureFinder operator policy for choosing between local execution
and RunPod `SECURE` / `COMMUNITY` capacity. It does not change scoring semantics,
model qualification criteria, source boundaries, prompts, validation, or matcher
behavior.

## Default execution path

Local execution remains the default zero-cost path.

Paid RunPod execution is justified only when measured wall-clock needs make burst
capacity materially useful. Once an operator has deliberately entered the paid
RunPod provisioning path, `SECURE` is the default cloud tier.

`COMMUNITY` is opt-in experimental capacity. It is not part of the required
escalation ladder and MUST NOT block or delay an otherwise justified Secure
qualification.

## Community use

An operator MAY perform one read-only Community availability/cost probe when the
information is useful and the probe itself creates no paid resource.

Do not iterate through multiple Community GPU classes merely to avoid Secure
pricing.

Catalog availability is not qualification. A Community worker considered for
useful work MUST independently pass the same one-worker model, digest, context,
residency, and representative-workload qualification required of a Secure worker.

Community qualification is never a prerequisite for Secure qualification.

## Paid RunPod gate

Before useful paid remote execution:

1. confirm that local execution cannot meet the relevant wall-clock goal cheaply
   enough;
2. perform a live read-only price and availability dry run;
3. choose the cheapest suitable GPU on the selected tier;
4. qualify exactly one worker first;
5. pin the exact model digest;
6. verify required context and full GPU residency;
7. predeclare bootstrap and inference stop conditions; and
8. expand to N workers only after the one-worker gate passes and measured
   throughput justifies the burst.

LME MUST NOT silently switch GPU classes or cloud tiers.

The normal fleet hourly safety caps remain in force. Raising a cap requires
measured evidence that the more expensive experiment answers a question the
cheaper tested configuration cannot answer in the required time.

## Decision basis — 2026-09-06

This policy reflects the AdventureFinder RunPod evidence available through
2026-09-06:

- a Secure RTX 4090 eight-worker burst successfully provisioned all eight
  workers, bootstrapped `qwen3.6:27b`, and completed all eight independent
  inference requests;
- a Community A40 attempt was unavailable;
- a Community L40 candidate reported low catalog availability but was unavailable
  at the specific preflight;
- a Community L40S worker provisioned and reached model acquisition, but the
  model pull degraded near 96% to roughly 58–72 KB/s with a multi-hour remaining
  estimate, so the qualification was terminated before useful inference; and
- no recorded Community attempt has yet completed the full
  provision → bootstrap → useful-inference path for the AdventureFinder workloads
  represented by these experiments.

These observations are operational evidence, not a claim that Community can
never work.

## Change control

Revisit this policy if new evidence shows repeatable Community provisioning,
bootstrap, and useful inference with reliability and information-per-dollar that
materially improves on the Secure path.

Do not change the default merely because a Community catalog entry is cheaper or
reports transient availability. Prefer completed end-to-end evidence.
