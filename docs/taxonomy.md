# Dimension taxonomy (Story 1.3)

> **DRAFT reconciliation for adjudication (2026-07-14).** Realigned from the earlier five-construct /
> recursive-order taxonomy to the **12-dimension** scheme the datasets, run scripts, and analysis
> actually use. Taxonomy decisions are yours to own — this is a first pass. Pre-reconciliation copy:
> `archive/pre_developmental_trajectory_docs_20260714/docs/taxonomy.md`. Ages/citations and the
> canonical dimension list live in `docs/dev_norms.md` §1 — treat that as the source of truth and this
> as its taxonomy-facing view.

## The unit of labeling: `tom_dimension` (+ its `tom_construct` parent)

The benchmark labels each item with a single **`tom_dimension`** (one of 12), plus its
**`tom_construct`** (one of 6 — the developmental-construct parent, added 2026-07-14), a
`validated_age_band`, and a `literature_basis`, stored under `metadata` in
`data/12dimToM_mcq_dataset.jsonl` and `data/12dimToM_freeresponse_dataset.jsonl` (free-response items
add a `rubric`). There is still **no** separate `order` or `tier` field — the developmental *ordering*
is carried by the 12 dimensions themselves (see `DIMENSION_DEVELOPMENTAL_ORDER`,
`scripts/0_misc/summarize_visualize_results.py`), while the coarser construct *grouping* is now a
first-class field.

`tom_construct` is derived from `tom_dimension` by the canonical map in **`src/constructs.py`** (the
single source of truth, shared verbatim with the sibling devtom-eval project) and written into the
datasets by `scripts/0_misc/add_construct_to_datasets.py` (idempotent; `--check` to verify). The
analysis script reads the same module, so the grouping in the datasets and in the plots can never
drift. Construct-level outputs: `construct_heatmap*.png`, `construct_difficulty_ranking*.png`, and
`dimension_heatmap_by_construct.png`, plus a `construct` column in `dimension_summary.csv`. Note the
analysis derives the construct from `tom_dimension` at read time too, so eval logs collected *before*
the datasets were tagged still group by construct correctly.

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

## Prior open questions — how they resolve under the 12-dimension scheme

The four "not yet adjudicated" callouts from the previous taxonomy are resolved by the item bank's
structure. Recommended dispositions (yours to confirm):

1. **Belief reasoning's two tier schemes (recursive order vs. milestone Tier 0/2/2+).** Resolved by
   three explicit, band-ordered belief dimensions instead of a tier axis. No dual scheme remains.
2. **Knowledge access had a band but no tier.** Resolved — it is now a first-class dimension
   (3–4 yr). (Band differs from the older ~4–4.5 yr note; see the reconcile flag in `dev_norms.md` §1.)
3. **Faux-pas construct ownership (emotion vs. pragmatic).** Resolved — Faux Pas Detection is its own
   dimension (9–11 yr, Baron-Cohen et al. 1999), grouped under pragmatic/advanced social cognition.
4. **Deception disposition.** Resolved — surfaced as its own dimension (White Lies / Prosocial
   Deception, 5–7 yr) rather than folded into belief reasoning or dropped.

## Controls & confound handling

The original taxonomy specified matched control items (reality / memory-factual / answerability) and a
ToM−control gap as the real signal. The current 12-dimension item banks do **not** carry an
`is_control` field or matched control items — the pipeline reports per-dimension accuracy directly, and
the two elicitation formats (forced-choice MCQ vs. open-ended free-response) serve as the main
shortcut/robustness check (a trend that appears only in MCQ is flagged as format-fragile; see
`docs/BRIEF.md` H5). **Open decision for you:** whether to (a) keep format-contrast as the sole
shortcut check for v0.1, or (b) re-introduce matched control items in v0.2.

## Code reconciliation TODO (not a docs change)

`src/schema.py` still encodes the **old** schema — `TIERS = (order0…order3plus)`, `belief_type`,
`is_control`, and a `source` field for ToMi/BigToM/FANToM loaders (`src/load_*.py`) — none of which the
live 12-dimension datasets use. That schema module and the loaders are effectively dead relative to the
current pipeline. Flagged here (and in `docs/PROJECT_PLAN.md` Spike 1.1) so the code either gets updated
to the `tom_dimension` schema or moved to the archive; **this file only documents the taxonomy, it
doesn't touch code.**
