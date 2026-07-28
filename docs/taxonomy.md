# Dimension taxonomy

The DevToM instrument uses **12 theory-of-mind dimensions** drawn from validated
developmental psychology tasks to evaluate LLMs and map them to developmental ages
using empirical norms. This document describes the taxonomy — the dimension set,
construct grouping, and developmental ordering that structure the item bank and the
age-mapping analyses.

## The unit of labeling: `tom_dimension` (+ its `tom_construct` parent)

Each item in the benchmark is labeled with a single **`tom_dimension`** (one of 12), its
**`tom_construct`** (one of 6 developmental-construct parents), a `validated_age_band` anchored to the
empirical child development literature, and a `literature_basis`, stored under `metadata` in
`data/12dimToM_mcq_dataset.jsonl` and `data/12dimToM_freeresponse_dataset.jsonl` (free-response items
add a `rubric`). The developmental *ordering* is carried by the 12 dimensions themselves (see
`DIMENSION_DEVELOPMENTAL_ORDER` in `src/constructs.py`), while the coarser construct *grouping* is a
first-class field.

`tom_construct` is derived from `tom_dimension` by the canonical map in **`src/constructs.py`** (the
single source of truth, shared with the sibling devtom-eval project) and written into the datasets by
`scripts/0_misc/add_construct_to_datasets.py` (idempotent; `--check` to verify). The analysis scripts
read the same module, so the grouping in the datasets, the developmental age mapping, and the
visualizations can never drift.

## The 12 dimensions (developmental-acquisition order)

Grouped under their interpretive developmental **construct** (grouping only — not a data field). Bands
and citations are canonical in `docs/dev_norms.md` §1.

| # | `tom_dimension` | Age band | Construct grouping |
|---|---|---|---|
| 1 | Diverse Desires | 2–3 yr | desire / intention inference |
| 2 | Diverse Beliefs | 3–4 yr | belief reasoning |
| 3 | Knowledge Access / Ignorance | 3–4 yr | knowledge access |
| 4 | Emotion Recognition | 3–4 yr | emotion recognition |
| 5 | First-Order False Belief | 4–5 yr | belief reasoning |
| 6 | Intention vs. Accident | 4–5 yr | desire / intention inference |
| 7 | Hidden Emotion (Appearance vs. Reality) | 4–6 yr | emotion recognition |
| 8 | White Lies / Prosocial Deception | 5–7 yr | deception |
| 9 | Second-Order False Belief | 6–7 yr | belief reasoning |
| 10 | Sarcasm | 6–8 yr | pragmatic understanding |
| 11 | Irony | 6–8 yr | pragmatic understanding |
| 12 | Faux Pas Detection | 9–11 yr | pragmatic understanding |

## Construct grouping (now a canonical field — `src/constructs.py`)

Six constructs, listed in **construct developmental order** (by the earliest age-of-acquisition among
each construct's member dimensions) — the order used for construct-level visualizations:

1. **Desire / intention inference** → Diverse Desires (2–3) · Intention vs. Accident (4–5).
2. **Belief reasoning** → Diverse Beliefs (3–4) · First-Order False Belief (4–5) · Second-Order False
   Belief (6–7). The old recursive-order axis (`order0–order3plus`) is expressed by these three graded
   dimensions; order0 (reality/desire) is covered by Diverse Desires; order3+ is a candidate v0.2
   extension.
3. **Knowledge access** → Knowledge Access / Ignorance (3–4).
4. **Emotion recognition** → Emotion Recognition (3–4) · Hidden Emotion (Appearance vs. Reality) (4–6).
5. **Deception** → White Lies / Prosocial Deception (5–7). For a **five-group** view it folds under
   Desire / intention inference as its interpretive parent — see `FIVE_GROUP_PARENT` /
   `construct_five_group()` in `src/constructs.py`.
6. **Pragmatic understanding** → Sarcasm (6–8) · Irony (6–8) · Faux Pas Detection (9–11).

## Design decisions

Several taxonomy questions that were open during early development are resolved by the 12-dimension
scheme:

1. **Belief reasoning's two tier schemes (recursive order vs. milestone Tier 0/2/2+).** Resolved by
   three explicit, band-ordered belief dimensions instead of a tier axis. No dual scheme remains.
2. **Knowledge access had a band but no tier.** Resolved — it is now a first-class dimension
   (3–4 yr).
3. **Faux-pas construct ownership (emotion vs. pragmatic).** Resolved — Faux Pas Detection is its own
   dimension (9–11 yr, Baron-Cohen et al. 1999), grouped under pragmatic/advanced social cognition.
4. **Deception disposition.** Resolved — surfaced as its own dimension (White Lies / Prosocial
   Deception, 5–7 yr) rather than folded into belief reasoning or dropped.

## Controls & confound handling

The 12-dimension item banks do not carry an `is_control` field or matched control items. The pipeline
reports per-dimension accuracy directly, and the two elicitation formats (forced-choice MCQ vs.
open-ended free-response) serve as the main robustness check: a finding that appears only in MCQ is
flagged as format-fragile.
