"""Cached loaders over the frozen snapshot in `app/data/`.

Every loader returns a copy-safe DataFrame and raises `SnapshotMissing` with an
actionable message if the snapshot has not been built.
"""
from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import streamlit as st

from . import constants as K

DATA_DIR = Path(__file__).resolve().parent.parent / "data"

# R writes the string "NA".
R_NA = ["NA", "NaN", "nan"]


class SnapshotMissing(RuntimeError):
    """The app was started before `python app/prepare_data.py` was run."""


def _require(path: Path) -> Path:
    if not path.exists():
        raise SnapshotMissing(
            f"Missing `{path.relative_to(DATA_DIR.parent)}`.\n\n"
            "Build the data snapshot first:\n\n"
            "```bash\npython app/prepare_data.py\n```"
        )
    return path


def snapshot_exists() -> bool:
    return (DATA_DIR / "item_level.parquet").exists()


@st.cache_data(show_spinner=False)
def provenance() -> dict:
    path = DATA_DIR / "provenance.json"
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


@st.cache_data(show_spinner=False)
def item_level() -> pd.DataFrame:
    """One row per (model, task, item). The spine of everything.

    Enriched at load time with the canonical dimension-level age bands, the
    app's own `rank` (see `constants.DIM_RANK_DIFFERS_FROM_SOURCE`), a friendly
    task label, and parameter counts from the roster.
    """
    df = pd.read_parquet(_require(DATA_DIR / "item_level.parquet"))

    # The item-level age_lo/age_hi/age_mid vary within a dimension. Keep them
    # under an `item_` prefix for the item explorer, and attach the canonical
    # dimension-level band as the developmental axis.
    df = df.rename(
        columns={
            "age_lo": "item_age_lo",
            "age_hi": "item_age_hi",
            "age_mid": "item_age_mid",
            "dim_rank": "source_dim_rank",
        }
    )

    bands = K.DIMENSIONS.rename(columns={"dimension": "tom_dimension"})[
        ["tom_dimension", "age_lo", "age_hi", "age_mid", "band", "rank", "construct"]
    ]
    df = df.merge(bands, on="tom_dimension", how="left")

    df["task_label"] = df["task"].map(K.TASK_LABELS).fillna(df["task"])
    df["short_model"] = df["model"].map(_short_model)
    df["release_date"] = pd.to_datetime(df["release_date"], errors="coerce")

    ref = _reference()
    df["params_b"] = df["model"].map(ref.get("model_params_b", {}))

    return df


def _short_model(model: str) -> str:
    from .theme import short_model

    return short_model(model)


@st.cache_data(show_spinner=False)
def _reference() -> dict:
    path = DATA_DIR / "reference.json"
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


@st.cache_data(show_spinner=False)
def item_bank() -> pd.DataFrame:
    """The instrument: 141 MCQ + 60 free-response items with metadata."""
    df = pd.read_parquet(_require(DATA_DIR / "items.parquet"))
    df["choices"] = df["choices"].apply(_parse_choices)
    df["rank"] = df["tom_dimension"].map(K.DIMENSION_RANK)
    return df.sort_values(["rank", "format", "item_id"]).reset_index(drop=True)


def _parse_choices(raw) -> list[str]:
    if isinstance(raw, list):
        return list(raw)
    if not raw:
        return []
    try:
        return json.loads(raw)
    except (TypeError, ValueError):
        return []


# --- Modeling artifacts -----------------------------------------------------
# These are read verbatim from the two subtrees that postdate the 2026-08-23
# regeneration of item_level.csv. Everything else is recomputed in `compute.py`.


def _modeling(subdir: str, name: str) -> pd.DataFrame:
    path = DATA_DIR / subdir / name
    if not path.exists():
        raise SnapshotMissing(
            f"Missing `{subdir}/{name}`. Rebuild the snapshot:\n\n"
            "```bash\npython app/prepare_data.py --force\n```"
        )
    if path.suffix == ".parquet":
        return pd.read_parquet(path)
    return pd.read_csv(path, na_values=R_NA)


def has_modeling(subdir: str, name: str) -> bool:
    return (DATA_DIR / subdir / name).exists()


@st.cache_data(show_spinner=False)
def guttman(name: str) -> pd.DataFrame:
    """A table from `results/modeling/guttman_sequence/latest/`."""
    return _modeling("guttman", name)


@st.cache_data(show_spinner=False)
def scale_validity(name: str) -> pd.DataFrame:
    """A table from `results/modeling/scale_validity/latest/`."""
    return _modeling("scale_validity", name)


@st.cache_data(show_spinner=False)
def permutation_draws() -> pd.DataFrame:
    """The 10,000-draw permutation null (stored as parquet in the snapshot)."""
    if has_modeling("guttman", "permutation_null_draws.parquet"):
        return _modeling("guttman", "permutation_null_draws.parquet")
    return _modeling("guttman", "permutation_null_draws.csv")


@st.cache_data(show_spinner=False)
def scale_validity_summary() -> dict[str, str]:
    """`summary.csv` is a long metric/value table; return it as a dict."""
    df = scale_validity("summary.csv")
    if {"metric", "value"} <= set(df.columns):
        return dict(zip(df["metric"].astype(str), df["value"].astype(str)))
    return {}


def excluded_models() -> list[dict]:
    return _reference().get("excluded_models", [])
