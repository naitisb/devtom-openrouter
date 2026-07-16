"""Integrity checks for the shared model roster (src/roster.py).

These guard the single source of truth the runners and the analysis script both
depend on: catch a duplicated slug, a family/type typo, or a missing color before
it silently drops a model from a (paid) sweep or a plot.
"""
import datetime
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from src.roster import (
    AUTHOR_TO_FAMILY,
    FAMILY_ORDER,
    ROSTER,
    TYPE_COLORS,
    TYPE_ORDER,
    all_models,
    models_for_family,
)


def test_slugs_unique():
    slugs = [e.slug for e in ROSTER]
    assert len(slugs) == len(set(slugs)), "duplicate slug in ROSTER"


def test_model_strings_route_via_known_prefix_and_end_in_slug():
    # Most models route through OpenRouter; the oldest few that OpenRouter has
    # delisted are served locally via an OpenAI-compatible endpoint. Either way the
    # model string ends in its slug and must be classifiable into a family.
    for e in ROSTER:
        assert e.model.endswith(e.slug), f"{e.model} does not end with slug {e.slug}"
        assert e.model.startswith(("openrouter/", "openai-api/local/")), \
            f"{e.model} uses an unknown router prefix"
        # The family must be recoverable from the raw model string: strip the
        # router prefix and map the author segment via AUTHOR_TO_FAMILY (the
        # same scheme src/scorer.py and the analysis script rely on).
        tail = e.model.removeprefix("openai-api/local/").removeprefix("openrouter/")
        author = tail.split("/", 1)[0]
        assert AUTHOR_TO_FAMILY.get(author) == e.family, \
            f"{e.model} author {author!r} does not map to family {e.family}"


def test_every_family_is_known_and_nonempty():
    fams = {e.family for e in ROSTER}
    assert fams == set(FAMILY_ORDER), f"family set {fams} != FAMILY_ORDER {FAMILY_ORDER}"
    for fam in FAMILY_ORDER:
        assert models_for_family(fam), f"no models for family {fam}"


def test_every_type_has_a_color_and_is_ordered():
    types = {e.type for e in ROSTER}
    missing_color = types - set(TYPE_COLORS)
    assert not missing_color, f"types with no TYPE_COLORS entry: {missing_color}"
    missing_order = types - set(TYPE_ORDER)
    assert not missing_order, f"types missing from TYPE_ORDER: {missing_order}"


def test_dates_are_valid_and_plausible():
    for e in ROSTER:
        d = datetime.date(*e.date)  # raises if invalid
        assert datetime.date(2023, 1, 1) <= d <= datetime.date(2026, 12, 31), \
            f"{e.slug} date {d} outside plausible range"


def test_family_lists_are_chronological():
    for fam in FAMILY_ORDER:
        dates = [datetime.date(*e.date) for e in ROSTER if e.family == fam]
        ordered = [datetime.date(*next(x for x in ROSTER if x.model == m).date)
                   for m in models_for_family(fam)]
        assert ordered == sorted(dates), f"{fam} not sorted oldest->newest"


def test_all_models_covers_roster():
    assert set(all_models()) == {e.model for e in ROSTER}
