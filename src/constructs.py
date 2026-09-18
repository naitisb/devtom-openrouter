"""Canonical developmental-construct hierarchy over the 12 ToM dimensions.

Single source of truth for the *construct* grouping — a practical, interpretive
layer above `tom_dimension` that collapses the 12 fine-grained dimensions into
six developmental constructs. Both the data-tagging step
(scripts/0_misc/add_construct_to_datasets.py, which writes `tom_construct` into
each item's metadata), the analysis/visualization scripts
(scripts/0_misc/, scripts/4_statistics/), and the R modeling pipeline
(scripts/5_model/, scripts/6_visualize/) read from here, so the grouping can't
drift between the datasets and the plots.

The six constructs and their member dimensions (see docs/taxonomy.md,
docs/dev_norms.md §1 for age bands + citations):

- **Belief reasoning** — Diverse Beliefs (3–4) · First-Order False Belief (4–5)
  · Second-Order False Belief (6–7). The old "recursive order 0–3+" axis is
  expressed by these three graded dimensions rather than a separate `order`
  field (order0 ≈ Diverse Desires, order1 ≈ first-order, order2 ≈ second-order).
- **Knowledge access** — Knowledge Access / Ignorance (3–4).
- **Desire / intention inference** — Diverse Desires (2–3) · Intention vs.
  Accident (4–5).
- **Emotion recognition** — Emotion Recognition (3–4) · Hidden Emotion /
  Appearance vs. Reality (4–6).
- **Pragmatic understanding** — Sarcasm (6–8) · Irony (6–8) · Faux Pas
  Detection (9–11).
- **Deception** — White Lies / Prosocial Deception (5–7). Surfaced as its own
  construct; maps most naturally under Desire / intention inference as an
  interpretive parent if a five-group view is needed (see FIVE_GROUP_PARENT).
"""
from __future__ import annotations

# Metadata key written into each dataset item and used by the analysis.
METADATA_KEY = "tom_construct"

# Canonical construct names (Title case). These are the exact strings written
# into the data and used as plot/column labels — keep them stable.
BELIEF = "Belief reasoning"
KNOWLEDGE = "Knowledge access"
DESIRE = "Desire / intention inference"
EMOTION = "Emotion recognition"
PRAGMATIC = "Pragmatic understanding"
DECEPTION = "Deception"

# The one authoritative dimension -> construct map. Every one of the 12
# `tom_dimension` values must appear here exactly once.
DIMENSION_TO_CONSTRUCT: dict[str, str] = {
    "Diverse Desires": DESIRE,
    "Intention vs. Accident": DESIRE,
    "Diverse Beliefs": BELIEF,
    "First-Order False Belief": BELIEF,
    "Second-Order False Belief": BELIEF,
    "Knowledge Access / Ignorance": KNOWLEDGE,
    "Emotion Recognition": EMOTION,
    "Hidden Emotion (Appearance vs. Reality)": EMOTION,
    "White Lies / Prosocial Deception": DECEPTION,
    "Sarcasm": PRAGMATIC,
    "Irony": PRAGMATIC,
    "Faux Pas Detection": PRAGMATIC,
}

# Construct display order, by the earliest age-of-acquisition among each
# construct's member dimensions (Diverse Desires 2–3 makes Desire/intention
# earliest; Sarcasm 6–8 makes Pragmatic latest). Used to order construct-level
# visualizations and to group the dimension heatmap columns.
CONSTRUCT_DEVELOPMENTAL_ORDER: list[str] = [
    DESIRE,      # earliest member: Diverse Desires (2–3)
    BELIEF,      # earliest member: Diverse Beliefs (3–4)
    KNOWLEDGE,   # Knowledge Access / Ignorance (3–4)
    EMOTION,     # earliest member: Emotion Recognition (3–4)
    DECEPTION,   # White Lies / Prosocial Deception (5–7)
    PRAGMATIC,   # earliest member: Sarcasm (6–8)
]

# Optional five-group view: Deception folds under its interpretive parent
# (Desire / intention inference). Everything else maps to itself. Use
# construct_five_group() to apply.
FIVE_GROUP_PARENT: dict[str, str] = {DECEPTION: DESIRE}

# Distinct color per construct for grouped visualizations (band labels,
# construct heatmaps/rankings). Colorblind-friendly qualitative palette.
CONSTRUCT_COLORS: dict[str, str] = {
    DESIRE: "#4C72B0",
    BELIEF: "#DD8452",
    KNOWLEDGE: "#55A868",
    EMOTION: "#C44E52",
    DECEPTION: "#8172B3",
    PRAGMATIC: "#937860",
}


# Dimension display order by typical age of acquisition in children (earliest
# first). The first five are the canonical Wellman & Liu (2004) ToM Scale order;
# the remaining seven advanced-ToM dimensions follow a best-effort synthesis of
# the advanced-ToM literature.
#
# The order below is sorted by the normative age midpoint in docs/dev_norms.md
# §1. Irony (6-8 yr, midpoint 7.0) therefore precedes Faux Pas Detection
# (9-11 yr, midpoint 10.0). Until 2026-09-18 these two were transposed here and
# in scripts/6_visualize/_theme.R, which put the latest-acquired dimension in
# the scale ahead of one acquired three years earlier. `dim_rank` in
# results/item_level.csv is derived from this list (see
# scripts/4_statistics/extract_item_level.py), so re-running `make extract`
# is required for existing results to pick the corrected ranks up.
#
# Sarcasm and Irony share the 6-8 yr band; their relative order is a
# convention, not a measured difference (docs/dev_norms.md flags this).
DIMENSION_DEVELOPMENTAL_ORDER: list[str] = [
    "Diverse Desires",
    "Diverse Beliefs",
    "Knowledge Access / Ignorance",
    "Emotion Recognition",
    "First-Order False Belief",
    "Intention vs. Accident",
    "Hidden Emotion (Appearance vs. Reality)",
    "Second-Order False Belief",
    "White Lies / Prosocial Deception",
    "Sarcasm",
    "Irony",
    "Faux Pas Detection",
]


def dimension_sort_key(dim: str) -> tuple[int, str]:
    """(developmental rank, dimension) — a dimension not in
    DIMENSION_DEVELOPMENTAL_ORDER sorts after all listed ones, alphabetically."""
    rank = (DIMENSION_DEVELOPMENTAL_ORDER.index(dim) if dim in DIMENSION_DEVELOPMENTAL_ORDER
            else len(DIMENSION_DEVELOPMENTAL_ORDER))
    return (rank, dim)


def construct_for_dimension(dimension: str) -> str | None:
    """Construct label for a `tom_dimension`, or None if unrecognized (e.g. a
    dimension added to the item bank after this map was last updated) — callers
    decide whether to warn or skip rather than crashing."""
    return DIMENSION_TO_CONSTRUCT.get(dimension)


def construct_five_group(construct: str) -> str:
    """Collapse a six-group construct to its five-group parent (Deception ->
    Desire / intention inference); pass-through for the other five."""
    return FIVE_GROUP_PARENT.get(construct, construct)


def dimensions_for_construct(construct: str, dimension_order: list[str] | None = None) -> list[str]:
    """Member dimensions of a construct. If `dimension_order` is given (e.g. the
    analysis script's DIMENSION_DEVELOPMENTAL_ORDER), members are returned in that
    order; otherwise in DIMENSION_TO_CONSTRUCT insertion order."""
    members = [d for d, c in DIMENSION_TO_CONSTRUCT.items() if c == construct]
    if dimension_order is not None:
        members.sort(key=lambda d: dimension_order.index(d) if d in dimension_order else len(dimension_order))
    return members


def construct_sort_key(construct: str) -> tuple[int, str]:
    """(developmental rank, name) — a construct not in CONSTRUCT_DEVELOPMENTAL_ORDER
    sorts after all listed ones, alphabetically, rather than erroring."""
    rank = (CONSTRUCT_DEVELOPMENTAL_ORDER.index(construct)
            if construct in CONSTRUCT_DEVELOPMENTAL_ORDER
            else len(CONSTRUCT_DEVELOPMENTAL_ORDER))
    return (rank, construct)


# Derived: construct -> member dimensions (insertion order). Kept as a module
# constant for convenience; use dimensions_for_construct() for ordered members.
CONSTRUCT_TO_DIMENSIONS: dict[str, list[str]] = {
    c: [d for d, cc in DIMENSION_TO_CONSTRUCT.items() if cc == c]
    for c in CONSTRUCT_DEVELOPMENTAL_ORDER
}


def _self_check() -> None:
    """Fail loudly at import time if the map is internally inconsistent."""
    constructs = set(DIMENSION_TO_CONSTRUCT.values())
    assert constructs == set(CONSTRUCT_DEVELOPMENTAL_ORDER), (
        f"construct sets disagree: {constructs} vs {CONSTRUCT_DEVELOPMENTAL_ORDER}")
    assert constructs == set(CONSTRUCT_COLORS), "every construct needs a color"
    assert set(FIVE_GROUP_PARENT.values()) <= constructs


_self_check()
