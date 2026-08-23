# Qwen `# of Sessions` Qualification Criteria v0.1

**Status:** Frozen before the five fresh qualification inferences.

**Candidate:** Qwen3.6 35B (`qwen` => `qwen3.6:35b-a3b`)
**Dimension:** `# of Sessions`
**Execution cost:** local Mac only; **$0 external/API inference**
**Fresh inference budget:** exactly **5** one-replicate cases; no favorable reruns.

## Purpose

Determine whether Qwen can be accepted for local production `# of Sessions` assessment using the frozen AFAO 1.5 normalized-duration framework. This dimension is a positive whole-number duration estimate with Practical Range, Confidence, and Path Sensitive support fields; it is **not** a 1--5 ordinal score.

The ordinary AFAO interpretation of blind validation applies. Exact integer identity is useful but is not required for every case when the estimates are in practical agreement. Do not import the small-sample exact-rate gate previously used for ordinal Phase-6 qualification.

## Fresh benchmark coverage

Accepted reference values below are used **only after inference** and are intentionally absent from the executable case manifests.

| Adventure | AFAO normalized sessions | Calibration regime | Qualification role |
| --- | ---: | --- | --- |
| ADV-0200 — Lake Monster | **1** | Very Short (1--2) | Critical 1-vs-2 one-session boundary |
| ADV-0287 — House of Lament | **3** | Short (3--5) | Compact multi-session coverage |
| ADV-0040 — Expedition to the Barrier Peaks | **7** | Medium (6--11) | Substantial standalone coverage |
| ADV-0277 — The Wild Beyond the Witchlight | **18** | Short Campaign-scale (12--23) | Campaign-scale practical-agreement test |
| ADV-0262 — Lost Mine of Phandelver | **10** | Medium (6--11) | Upper-Medium duration coverage and bridge toward campaign-scale material |

Two previously completed clean local Sessions cases, **ADV-0230 — Salvage Operation** and **ADV-0053 — Call of the Wild**, may be included as supplemental qualification evidence after their raw artifacts are reverified. Do not rerun them solely to enlarge the sample.

### Deferred long-campaign extension

**ADV-0303 — Storm King's Thunder = 26** remains the frozen AFAO Long Campaign-scale reference, but it is deliberately excluded from this fresh pre-production qualification wave. Repeated Qwen operational/scope problems on the unusually long SKT canonical source make it a confounded and expensive first-line qualification case. A future SKT run should be treated separately as a long-source / Long Campaign-scale reliability extension, not as a prerequisite for this ordinary Sessions qualification decision.

## Qualification interpretation

Classify each fresh case using the frozen AFAO agreement categories:

1. **Exact agreement** — same best whole-number estimate.
2. **Practical agreement** — a modest best-estimate difference with materially overlapping Practical Ranges and substantially the same expected playable body, optional-content weighting, and 2.5--3.0-hour normalization logic.
3. **Material numeric disagreement** — difference large enough to imply meaningfully different practical duration.
4. **Structural disagreement** — materially different view of what published play belongs in ordinary completion.
5. **Normalization disagreement** — similar playable body but materially different translation into normalized sessions.

The accepted AFAO blind-validation precedent treats **Witchlight 16 vs 18** and **Storm King's Thunder 24 vs 26** as successful practical reproduction because the ranges strongly overlapped, the duration regimes were unchanged, and the same playable structure was identified. Use that precedent rather than demanding campaign-scale integer identity.

## `LOCAL_QUALIFIED` decision rule

Call Qwen **LOCAL_QUALIFIED for `# of Sessions`** when all of the following hold:

- all five fresh cases produce valid, canonical-source-grounded Sessions assessments;
- **Lake Monster reproduces 1 session**, preserving the product-important one-shot / near-one-shot distinction;
- every other fresh case is either **exact** or in **practical agreement** under the AFAO definition above;
- there are **no material numeric, structural, or normalization disagreements**;
- the five-case pattern does not show systematic duration compression or inflation large enough to distort matching; and
- supporting-field differences such as `Path Sensitive` are reviewed but do **not** fail qualification by themselves.

If a case fails before inference because of infrastructure, missing source, or configuration, classify the qualification as **INCOMPLETE**, not as a model miss. Repairing a true pre-inference operational failure is allowed; rerunning a completed inference because its estimate is unfavorable is not.

## Execution policy

Run all five fresh cases in the frozen order regardless of numeric outcomes. Numeric results never stop the following production batch. Stop the qualification block early only for a systemic integrity problem that makes later evidence invalid or non-comparable; the normal overnight runner otherwise logs isolated operational failures and continues.

Do not purchase API inference, hosted compute, or additional hardware for this qualification. The five local calls are sufficient to answer the current question unless their evidence is genuinely ambiguous.
