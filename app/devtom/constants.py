"""Canonical constants for the DevToM app.

The developmental age bands live in `docs/dev_norms.md` §1, which the docs
declare the single source of truth. Until now they were duplicated as three
separate `tibble::tribble` literals across the R visualization scripts
(`visualize_dimension_progress.R`, `visualize_dimension_progress_frq.R`,
`visualize_dimension_age_vs_date.R`). This module is the Python consolidation.

## Two deliberate choices, both documented in the app's "About the numbers"

1. **Dimension-level bands, not item-level.** `results/item_level.csv` carries
   `age_lo/age_hi/age_mid` per *item*, and those vary within a dimension (the
   Emotion Recognition items span midpoints 3.5 to 7.5, because the source
   tasks were normed on different samples). For the developmental axis we use
   the 12 canonical dimension-level bands below, which is what the headline
   strip charts do. The per-item bands remain visible in the item explorer.

2. **Irony before Faux Pas.** We sort strictly by `age_mid`, so Irony (6-8 yr)
   is 11th and Faux Pas Detection (9-11 yr) is 12th. `src/constructs.py` and
   `scripts/6_visualize/_theme.R` used to have these transposed; that was fixed
   on 2026-09-18 and they now agree with this module. The `source_dim_rank`
   column carried in `item_level.csv` still reflects the old ordering until
   `make extract` is re-run — the app never uses it, but
   `DIM_RANK_DIFFERS_FROM_SOURCE` records the situation.
"""
from __future__ import annotations

import os

import pandas as pd

# The mastery criterion used everywhere in the R pipeline.
MASTERY_THRESHOLD = 0.80

# The developmental scale's floor and ceiling (docs/dev_norms.md: "the overall
# scale is 2-11 years"). Age equivalents are clamped here.
AGE_MIN = 2.5
AGE_MAX = 11.0

# MCQ items all have four options, so chance is 0.25. Free response has no
# meaningful chance level; the R pipeline never pools the two IRT scales for
# exactly this reason.
MCQ_CHANCE = 0.25

TASK_LABELS = {
    "tom_12dim_mcq": "MCQ",
    "tom_12dim_freeresponse": "Free response",
}

# A model at or above this overall accuracy is saturated — its profile shape
# carries almost no signal. `scale_validity` uses the same 0.95 cut to define
# its "discriminating" subgroup.
SATURATION_CUTOFF = 0.95

# --- The instrument ---------------------------------------------------------
# dimension, age_lo, age_hi, construct, citation. Ordered by age_mid.
_DIMENSION_ROWS = [
    ("Diverse Desires", 2.0, 3.0, "Desire / intention inference", "Wellman & Liu (2004)"),
    ("Diverse Beliefs", 3.0, 4.0, "Belief reasoning", "Wellman & Liu (2004)"),
    ("Knowledge Access / Ignorance", 3.0, 4.0, "Knowledge access", "Wimmer, Hogrefe & Perner (1988)"),
    ("Emotion Recognition", 3.0, 4.0, "Emotion recognition", "Widen & Russell (2008)"),
    ("First-Order False Belief", 4.0, 5.0, "Belief reasoning", "Wimmer & Perner (1983)"),
    ("Intention vs. Accident", 4.0, 5.0, "Desire / intention inference", "Piaget (1932)"),
    ("Hidden Emotion (Appearance vs. Reality)", 4.0, 6.0, "Emotion recognition", "Harris et al. (1986)"),
    ("White Lies / Prosocial Deception", 5.0, 7.0, "Deception", "Talwar & Lee (2002)"),
    ("Second-Order False Belief", 6.0, 7.0, "Belief reasoning", "Perner & Wimmer (1985)"),
    ("Sarcasm", 6.0, 8.0, "Pragmatic understanding", "Winner & Leekam (1991)"),
    ("Irony", 6.0, 8.0, "Pragmatic understanding", "Hancock, Dunham & Purdy (2000)"),
    ("Faux Pas Detection", 9.0, 11.0, "Pragmatic understanding", "Baron-Cohen et al. (1999)"),
]

DIMENSIONS = pd.DataFrame(
    _DIMENSION_ROWS,
    columns=["dimension", "age_lo", "age_hi", "construct", "citation"],
)
DIMENSIONS["age_mid"] = (DIMENSIONS["age_lo"] + DIMENSIONS["age_hi"]) / 2
DIMENSIONS["band"] = (
    DIMENSIONS["age_lo"].astype(int).astype(str)
    + "-"
    + DIMENSIONS["age_hi"].astype(int).astype(str)
    + " yr"
)
DIMENSIONS = DIMENSIONS.sort_values(
    ["age_mid", "age_lo"], kind="stable"
).reset_index(drop=True)
DIMENSIONS["rank"] = DIMENSIONS.index

DIMENSION_ORDER: list[str] = DIMENSIONS["dimension"].tolist()
DIMENSION_RANK: dict[str, int] = dict(zip(DIMENSIONS["dimension"], DIMENSIONS["rank"]))
DIMENSION_AGE_MID: dict[str, float] = dict(
    zip(DIMENSIONS["dimension"], DIMENSIONS["age_mid"])
)
DIMENSION_BAND: dict[str, tuple[float, float]] = {
    row.dimension: (row.age_lo, row.age_hi) for row in DIMENSIONS.itertuples()
}
DIMENSION_TO_CONSTRUCT: dict[str, str] = dict(
    zip(DIMENSIONS["dimension"], DIMENSIONS["construct"])
)
DIMENSION_CITATION: dict[str, str] = dict(
    zip(DIMENSIONS["dimension"], DIMENSIONS["citation"])
)

CONSTRUCT_ORDER: list[str] = [
    "Desire / intention inference",
    "Belief reasoning",
    "Knowledge access",
    "Emotion recognition",
    "Deception",
    "Pragmatic understanding",
]

# Recorded so the app can be honest about it rather than silently re-sorting.
DIM_RANK_DIFFERS_FROM_SOURCE = (
    "Dimensions are ranked strictly by normative age midpoint, so Irony "
    "(6-8 yr) is 11th and Faux Pas Detection (9-11 yr) is 12th. "
    "`src/constructs.py` and `_theme.R` had these two transposed until "
    "2026-09-18 and now agree. The `dim_rank` column stored in "
    "`item_level.csv`, and the Guttman artifacts computed from it, still carry "
    "the old ordering until the analysis pipeline is re-run; the app derives "
    "its own rank and does not read that column."
)

# Dimensions whose relative rank is convention rather than a measured
# difference (docs/dev_norms.md flags this explicitly).
TIED_RANK_NOTE = (
    "Sarcasm and Irony share the 6-8 yr band; their relative order is a "
    "convention, not a measured difference. Dimensions 6-12 are 'advanced ToM', "
    "where the literature has no settled acquisition order."
)

# --- Item disclosure --------------------------------------------------------
# The item browser shows metadata and difficulty for every item, but the full
# stimulus text, answer options and rubrics only for the worked examples below.
#
# The bank is validated instrumentation. Rendering all 184 items as a crawlable
# web page would put them in front of the next generation of training crawlers,
# which is the one thing the zero-data-retention routing policy was chosen to
# avoid at eval time. The items are already in a public repo, so this is about
# not amplifying them rather than keeping a secret.
#
# The pair below is one scenario in both elicitation formats. It is the
# earliest-acquired, least discriminating dimension in the scale, so it costs
# the least to disclose — and showing the same scenario as MCQ and as free
# response is what makes the dual-elicitation design legible.
WORKED_EXAMPLE_IDS: tuple[str, ...] = ("DD_01", "DD_FR_01")

# Set DEVTOM_REVEAL_ITEMS=1 to browse the full bank — intended for local work,
# never for a deployed instance.
REVEAL_ALL_ITEMS: bool = os.environ.get("DEVTOM_REVEAL_ITEMS", "").strip().lower() in {
    "1",
    "true",
    "yes",
}


def item_is_disclosed(item_id: str) -> bool:
    return REVEAL_ALL_ITEMS or item_id in WORKED_EXAMPLE_IDS


# Two unresolved band disagreements the norms doc records (verified 2026-07-14).
BAND_CAVEATS = [
    "**Knowledge Access / Ignorance** is 3-4 yr via Wimmer, Hogrefe & Perner "
    "(1988) but ~4-4.5 yr via Wellman & Liu. The item bank uses 3-4 yr.",
    "**Faux Pas Detection** is 9-11 yr via Baron-Cohen et al. (1999) but 7-8 yr "
    "via Osterhaus & Koerber. The item bank uses 9-11 yr.",
]
