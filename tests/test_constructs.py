"""Integrity checks for the developmental-construct hierarchy (src/constructs.py)
and its presence in the tagged datasets.

Guards the single source of truth that both the data-tagging step and the
analysis read: catch a dimension with no construct, a construct with no color,
or a dataset item that wasn't (re)tagged.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from src.constructs import (
    CONSTRUCT_COLORS,
    CONSTRUCT_DEVELOPMENTAL_ORDER,
    DIMENSION_TO_CONSTRUCT,
    FIVE_GROUP_PARENT,
    METADATA_KEY,
    construct_five_group,
    construct_for_dimension,
    dimensions_for_construct,
)

PROJECT_ROOT = Path(__file__).parent.parent
DATASETS = [
    PROJECT_ROOT / "data" / "12dimToM_mcq_dataset.jsonl",
    PROJECT_ROOT / "data" / "12dimToM_freeresponse_dataset.jsonl",
]

# The 12 canonical dimensions the item bank uses.
EXPECTED_DIMENSIONS = {
    "Diverse Desires", "Diverse Beliefs", "Knowledge Access / Ignorance",
    "Emotion Recognition", "First-Order False Belief", "Intention vs. Accident",
    "Hidden Emotion (Appearance vs. Reality)", "Second-Order False Belief",
    "White Lies / Prosocial Deception", "Sarcasm", "Faux Pas Detection", "Irony",
}


def test_all_twelve_dimensions_mapped():
    assert set(DIMENSION_TO_CONSTRUCT) == EXPECTED_DIMENSIONS


def test_six_constructs_all_colored_and_ordered():
    constructs = set(DIMENSION_TO_CONSTRUCT.values())
    assert len(constructs) == 6
    assert constructs == set(CONSTRUCT_DEVELOPMENTAL_ORDER) == set(CONSTRUCT_COLORS)


def test_construct_for_dimension_roundtrip():
    for dim, construct in DIMENSION_TO_CONSTRUCT.items():
        assert construct_for_dimension(dim) == construct
    assert construct_for_dimension("Not A Real Dimension") is None


def test_five_group_collapses_only_deception():
    assert construct_five_group("Deception") == "Desire / intention inference"
    assert len({construct_five_group(c) for c in CONSTRUCT_DEVELOPMENTAL_ORDER}) == 5
    assert set(FIVE_GROUP_PARENT) == {"Deception"}


def test_belief_reasoning_has_three_members():
    members = dimensions_for_construct("Belief reasoning")
    assert set(members) == {"Diverse Beliefs", "First-Order False Belief", "Second-Order False Belief"}


def test_datasets_are_tagged():
    for path in DATASETS:
        if not path.exists():
            continue
        with path.open() as f:
            for lineno, raw in enumerate(f, 1):
                if not raw.strip():
                    continue
                meta = json.loads(raw)["metadata"]
                dim = meta.get("tom_dimension")
                assert meta.get(METADATA_KEY) == construct_for_dimension(dim), \
                    f"{path.name}:{lineno} not correctly tagged"
