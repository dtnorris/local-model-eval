# Phase-6 Social Interaction Emphasis Diagnosis

## Version 0.1 — FROZEN DIAGNOSIS

**Status:** Pre-inference remediation hypothesis
**Model:** `qwen3.6:35b-a3b`
**Dimension:** Social Interaction Emphasis
**Baseline scorer profile:** current production Social guardrail v0.2
**Purpose:** Freeze the demonstrated failure mechanism before selecting or running Phase-6 remediation cases.

---

## 1. Evidence being diagnosed

The Phase-5 overnight Social Interaction batch produced 10 attempts and 9 valid assessments:

- 6/9 exact;
- 2/9 adjacent;
- 1/9 hard score error;
- 8/9 within ±1; and
- one validator failure on ADV-0303 — Storm King's Thunder, whose embedded attempted score was 3 but is excluded from valid-assessment counts.

All three substantive scoring misses were downward:

| Adventure | Accepted score | Qwen score | Error class |
| --- | ---: | ---: | --- |
| ADV-0229 — Danger at Dunwater | 5 | 4 | Adjacent downward |
| ADV-0257 — The Magister's Masquerade | 4 | 3 | Adjacent downward |
| ADV-0287 — House of Lament | 3 | 1 | Hard downward |

The directionality is therefore coherent rather than mixed.

---

## 2. House of Lament is the kill-test failure

ADV-0287 is diagnostic because the model did not fail to find the relevant material. It found the investigators, recurring séances, spirit communication, and plot-driving requests, but then excluded much of that material from Social Interaction.

The published adventure gives the spirits distinct goals, personalities, attitudes, and deceptive or cooperative intentions. Characters are explicitly encouraged to ask questions. The spirit decides what it will answer. The text directs the spirits to build rapport through at least three interactions before accepting the characters. The same contacted spirit recurs across multiple séances, makes requests, tests the party, can deceive or manipulate it, and helps determine the adventure's climax and escape route.

Qwen nevertheless scored Social Interaction 1 and reasoned that:

- the séances are principally divination / information delivery;
- their responses are too scripted or cryptic to constitute meaningful social engagement; and
- the adventure lacks enough negotiation, persuasion, relationship building, or faction interaction.

That is incompatible with the frozen AFAO definition. Social Interaction is substantive when engagement with NPC goals, attitudes, relationships, cooperation, opposition, information, or decisions constitutes meaningful player-facing play. A scene may qualify simultaneously as Social Interaction and Investigation. Investigation content does not subtract its social role.

**Diagnosis:** House is not an evidence-retrieval failure. It is an admission-rule failure: Qwen applies an overly narrow test for what is allowed to count as substantive Social Interaction.

---

## 3. The upper misses show the same general error

The two adjacent upper-ladder misses are consistent with the same failure at structural scale.

### ADV-0257 — The Magister's Masquerade: 4 → 3

Qwen recognized multiple major interaction-centered events, relationship mechanics, rivalry, fashion/dance participation, and recurring social play. It then rejected 4 largely because exploration, combat, investigation, and academic structures also carried substantial expected play.

The frozen High anchor does not require Social Interaction to independently carry the central plot or to outweigh every non-social mode added together. It requires Social Interaction itself to be one of the dominant modes and to regularly drive progress.

### ADV-0229 — Danger at Dunwater: 5 → 4

Qwen recognized diplomacy with the lizardfolk and allied factions as the intended primary path, including explicit attitude, goodwill, bribery, and faction-management mechanics. It then rejected 5 because lair exploration, guards, traps, and possible combat remained an independently organized non-social structure.

The frozen Dominant anchor does not require other modes to disappear. It asks whether sustained interaction with NPCs, relationships, or factions fundamentally organizes expected play, with other modes largely occurring within or being enabled by those interactions.

---

## 4. Frozen failure hypothesis

### `SOCIAL_CROSS_MODE_COMPETITION_BIAS`

**Hypothesis:** Qwen systematically under-scores Social Interaction when substantive social play overlaps another play mode or coexists with substantial non-social structure. It behaves as though Social must be comparatively pure, open-ended, or independently progression-bearing before receiving full credit.

This appears in two forms:

1. **Admission failure:** a scene is discounted or excluded from Social because it also functions as Investigation, exposition, ritual, or another mode, even when players substantively engage with an NPC's goals, attitudes, trust, deception, cooperation, opposition, information, or decisions.
2. **Structural ceiling:** already-qualifying recurring or dominant Social play is scored downward merely because exploration, combat, investigation, or another mode also carries substantial play.

These are treated as one hypothesis because both errors incorrectly make other play modes subtractive from Social Interaction rather than measuring Social's own structural role independently.

---

## 5. Narrow guardrail hypothesis

The Phase-6 intervention SHOULD branch from the current production Social guardrail v0.2 and add **only** a cross-mode competition clarification.

Proposed guardrail concept:

> **Social Interaction Cross-Mode Independence / Social-Actorship Clarification**
>
> Determine first whether a scene contains substantive engagement with an NPC as a social actor. Engagement can qualify through the NPC's goals, attitudes, trust, relationships, cooperation, opposition, deception, information choices, requests, or decisions. It does not require free-form negotiation, a Persuasion check, a faction system, or unrestricted dialogue.
>
> A scene does not stop counting as Social Interaction merely because it also functions as Investigation, exploration, ritual, exposition, or another mode. Constrained or mediated communication can still be substantive Social play when the NPC's goals, stance, choices, trust, deception, cooperation, or opposition materially shape the player-facing interaction. Conversely, passive exposition, a fixed quest handoff, a purely transactional exchange, or a predetermined answer with no substantive engagement with the NPC as a social actor remains insufficient by itself.
>
> After qualifying the social interaction, assess recurrence, dominance, and organizing role using the existing AFAO anchors. Do not lower the Social score merely because substantial non-social play also exists. Non-social structure is downward evidence only when it actually makes Social limited or secondary, prevents Social from being one of the dominant modes, or prevents sustained NPC/relationship/faction interaction from fundamentally organizing expected play under the relevant anchor.
>
> Keep dimensions analytically independent but allow the same scene to contribute to more than one dimension for different reasons. Do not force Social Interaction and Investigation, exploration, combat, or puzzle play into mutually exclusive accounting.

---

## 6. Anti-inflation requirements

The intervention MUST NOT:

- count NPC presence, dialogue volume, or Charisma checks by themselves;
- convert passive exposition or routine quest delivery into substantive Social Interaction;
- automatically count every information-bearing NPC conversation as Social;
- presume that spirits, rituals, or mediated communication are social merely because an NPC is involved;
- presume that recurring social scenes automatically establish score 4;
- presume that a socially preferred or intended resolution automatically establishes score 5;
- tell the scorer to prefer higher Social scores; or
- include any benchmark Adventure ID, title, accepted score, or target-specific fact in scorer-visible prompt text.

The intervention is successful only if it corrects cross-mode subtraction while preserving genuine Minimal, Low, and Mixed cases.

---

## 7. What this step does not authorize

This diagnosis does **not**:

- modify the production Social guardrail;
- authorize any inference call;
- select the final five-case Social remediation set;
- spend the optional sixth Social call;
- change AFAO anchors or accepted benchmark scores;
- reinterpret Phase-5 results; or
- confer `LOCAL_QUALIFIED` status.

The next Phase-6 step is to freeze the Social remediation pilot and its kill-test / control set before the candidate guardrail is wired into an executable scorer profile.
