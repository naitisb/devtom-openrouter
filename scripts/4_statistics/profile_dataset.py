"""Descriptive profiling of the ToM item banks (JSONL datasets).

Profiles the data/*.jsonl item banks along norms from NLP dataset profiling
(datasheets, HF dataset cards): composition, coverage, label balance, text
statistics, readability, duplicates, and conformance. Emits tidy CSVs and a
markdown summary — no plots (those go in scripts/6_visualize/).

    python scripts/4_statistics/profile_dataset.py
    python scripts/4_statistics/profile_dataset.py --data-dir data --results-dir results
"""
from __future__ import annotations

import argparse
import datetime
import json
import re
import sys
from collections import Counter
from pathlib import Path

import numpy as np
import pandas as pd

PROJECT_ROOT = Path(__file__).parent.parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from src.constructs import (  # noqa: E402
    DIMENSION_DEVELOPMENTAL_ORDER,
    DIMENSION_TO_CONSTRUCT,
    construct_for_dimension,
)


def _load_items(data_dir: str) -> pd.DataFrame:
    """Load all JSONL item banks into a single DataFrame."""
    records = []
    data_path = Path(data_dir)
    for jsonl_file in sorted(data_path.glob("12dimToM_*_dataset.jsonl")):
        if "backup" in jsonl_file.name:
            continue
        task_type = "mcq" if "mcq" in jsonl_file.name else "freeresponse"
        with open(jsonl_file) as f:
            for line in f:
                item = json.loads(line)
                meta = item.get("metadata", {})
                records.append({
                    "file": jsonl_file.name,
                    "task_type": task_type,
                    "id": item.get("id", ""),
                    "input": item.get("input", ""),
                    "target": item.get("target", ""),
                    "choices": item.get("choices", []),
                    "n_choices": len(item.get("choices", [])),
                    "rubric": item.get("rubric", ""),
                    "tom_dimension": meta.get("tom_dimension", ""),
                    "tom_construct": meta.get("tom_construct", ""),
                    "validated_age_band": meta.get("validated_age_band", ""),
                    "literature_basis": meta.get("literature_basis", ""),
                })
    return pd.DataFrame(records)


def _text_stats(texts: pd.Series) -> pd.DataFrame:
    """Compute char/word/sentence counts for a series of texts."""
    char_counts = texts.str.len()
    word_counts = texts.str.split().str.len()
    sentence_counts = texts.str.count(r'[.!?]+')
    return pd.DataFrame({
        "chars": char_counts,
        "words": word_counts,
        "sentences": sentence_counts,
    })


def _readability(texts: pd.Series) -> pd.DataFrame:
    """Compute readability metrics. Requires textstat."""
    try:
        import textstat
    except ImportError:
        print("WARNING: textstat not installed — skipping readability metrics. "
              "Install with: pip install textstat", file=sys.stderr)
        return pd.DataFrame({
            "flesch_reading_ease": [np.nan] * len(texts),
            "flesch_kincaid_grade": [np.nan] * len(texts),
        })
    fre = [textstat.flesch_reading_ease(t) if t.strip() else np.nan for t in texts]
    fkg = [textstat.flesch_kincaid_grade(t) if t.strip() else np.nan for t in texts]
    return pd.DataFrame({"flesch_reading_ease": fre, "flesch_kincaid_grade": fkg})


def _type_token_ratio(text: str) -> float:
    """Lexical richness: unique words / total words."""
    words = text.lower().split()
    if not words:
        return 0.0
    return len(set(words)) / len(words)


def _parse_age_lo(band: str) -> float | None:
    m = re.match(r"(\d+)", str(band))
    return float(m.group(1)) if m else None


def profile(df: pd.DataFrame, out_dir: Path) -> list[str]:
    """Run all profiling analyses and write CSVs. Returns list of written files."""
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []

    # --- Composition ---
    comp_dim = df.groupby(["task_type", "tom_dimension"]).size().reset_index(name="count")
    comp_dim.to_csv(out_dir / "composition_by_dimension.csv", index=False)
    written.append("composition_by_dimension.csv")

    comp_construct = df.groupby(["task_type", "tom_construct"]).size().reset_index(name="count")
    comp_construct.to_csv(out_dir / "composition_by_construct.csv", index=False)
    written.append("composition_by_construct.csv")

    comp_age = df.groupby(["task_type", "validated_age_band"]).size().reset_index(name="count")
    comp_age.to_csv(out_dir / "composition_by_age_band.csv", index=False)
    written.append("composition_by_age_band.csv")

    # --- Coverage matrices ---
    cov_dim_task = pd.crosstab(df["tom_dimension"], df["task_type"])
    cov_dim_task.to_csv(out_dir / "coverage_dimension_x_task.csv")
    written.append("coverage_dimension_x_task.csv")

    cov_dim_age = pd.crosstab(df["tom_dimension"], df["validated_age_band"])
    cov_dim_age.to_csv(out_dir / "coverage_dimension_x_age_band.csv")
    written.append("coverage_dimension_x_age_band.csv")

    # --- Label balance (MCQ only) ---
    mcq = df[df["task_type"] == "mcq"]
    if not mcq.empty:
        target_dist = mcq.groupby("tom_dimension")["target"].value_counts().unstack(fill_value=0)
        target_dist.to_csv(out_dir / "label_balance_mcq.csv")
        written.append("label_balance_mcq.csv")

        choice_counts = mcq.groupby("tom_dimension")["n_choices"].describe()
        choice_counts.to_csv(out_dir / "choice_counts_mcq.csv")
        written.append("choice_counts_mcq.csv")

    # --- Text statistics ---
    input_stats = _text_stats(df["input"])
    input_stats["tom_dimension"] = df["tom_dimension"].values
    input_stats["task_type"] = df["task_type"].values
    input_summary = input_stats.groupby(["task_type", "tom_dimension"]).agg(
        ["mean", "std", "min", "max"]).round(1)
    input_summary.to_csv(out_dir / "text_stats_input.csv")
    written.append("text_stats_input.csv")

    # --- Readability ---
    read_df = _readability(df["input"])
    read_df["tom_dimension"] = df["tom_dimension"].values
    read_df["task_type"] = df["task_type"].values
    read_df["validated_age_band"] = df["validated_age_band"].values
    read_df["age_lo"] = df["validated_age_band"].apply(_parse_age_lo)
    read_summary = read_df.groupby(["task_type", "tom_dimension"]).agg({
        "flesch_reading_ease": ["mean", "std"],
        "flesch_kincaid_grade": ["mean", "std"],
    }).round(2)
    read_summary.to_csv(out_dir / "readability_by_dimension.csv")
    written.append("readability_by_dimension.csv")

    read_vs_age = read_df.groupby("validated_age_band").agg({
        "flesch_reading_ease": ["mean", "std", "count"],
        "flesch_kincaid_grade": ["mean", "std"],
    }).round(2)
    read_vs_age.to_csv(out_dir / "readability_vs_age_band.csv")
    written.append("readability_vs_age_band.csv")

    # --- Lexical richness ---
    df_copy = df.copy()
    df_copy["ttr"] = df_copy["input"].apply(_type_token_ratio)
    ttr_summary = df_copy.groupby(["task_type", "tom_dimension"])["ttr"].agg(
        ["mean", "std"]).round(3)
    ttr_summary.to_csv(out_dir / "lexical_richness.csv")
    written.append("lexical_richness.csv")

    # --- Duplicates ---
    exact_dupes = df[df.duplicated(subset=["input"], keep=False)]
    norm_input = df["input"].str.lower().str.strip()
    norm_dupes = df[norm_input.duplicated(keep=False)]
    dupe_summary = pd.DataFrame([{
        "exact_duplicates": len(exact_dupes),
        "normalized_duplicates": len(norm_dupes),
        "total_items": len(df),
    }])
    dupe_summary.to_csv(out_dir / "duplicates.csv", index=False)
    written.append("duplicates.csv")

    # MCQ ↔ free-response scenario overlap
    mcq_inputs = set(df[df["task_type"] == "mcq"]["input"].str.lower().str.strip())
    fr_inputs = set(df[df["task_type"] == "freeresponse"]["input"].str.lower().str.strip())
    overlap = mcq_inputs & fr_inputs
    overlap_df = pd.DataFrame([{
        "mcq_items": len(mcq_inputs),
        "fr_items": len(fr_inputs),
        "overlapping_scenarios": len(overlap),
    }])
    overlap_df.to_csv(out_dir / "mcq_fr_overlap.csv", index=False)
    written.append("mcq_fr_overlap.csv")

    # --- Conformance ---
    missing = []
    for _, row in df.iterrows():
        issues = []
        if not row["tom_dimension"]:
            issues.append("missing tom_dimension")
        if not row["tom_construct"]:
            issues.append("missing tom_construct")
        if not row["validated_age_band"]:
            issues.append("missing validated_age_band")
        if row["task_type"] == "freeresponse" and not row["rubric"]:
            issues.append("missing rubric")
        if issues:
            missing.append({"id": row["id"], "task_type": row["task_type"],
                            "issues": "; ".join(issues)})
    if missing:
        pd.DataFrame(missing).to_csv(out_dir / "conformance_issues.csv", index=False)
        written.append("conformance_issues.csv")

    return written


def _write_summary(df: pd.DataFrame, out_dir: Path, written: list[str]) -> None:
    """Write a markdown profiling summary."""
    lines = [
        "# Dataset Profile",
        "",
        f"Generated: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        "",
        "## Composition",
        "",
        f"- Total items: {len(df)}",
    ]
    for tt in sorted(df["task_type"].unique()):
        n = (df["task_type"] == tt).sum()
        lines.append(f"- {tt}: {n} items")

    lines += ["", "## Dimensions", ""]
    for dim in DIMENSION_DEVELOPMENTAL_ORDER:
        n = (df["tom_dimension"] == dim).sum()
        construct = construct_for_dimension(dim) or "?"
        lines.append(f"- {dim} ({construct}): {n} items")

    lines += ["", "## Age bands", ""]
    for band, count in df["validated_age_band"].value_counts().sort_index().items():
        lines.append(f"- {band}: {count} items")

    lines += ["", "## Output files", ""]
    for f in written:
        lines.append(f"- `{f}`")

    summary_path = out_dir / "dataset_profile.md"
    summary_path.write_text("\n".join(lines) + "\n")
    print(f"Wrote {summary_path}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data-dir", default="data",
                    help="directory containing JSONL item banks (default: data)")
    ap.add_argument("--results-dir", default="results",
                    help="parent results directory (default: results)")
    args = ap.parse_args()

    df = _load_items(args.data_dir)
    if df.empty:
        print(f"No JSONL item banks found in {args.data_dir}/", file=sys.stderr)
        return 1

    print(f"Loaded {len(df)} items from {df['file'].nunique()} files")

    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = Path(args.results_dir) / "stats" / "dataset" / stamp
    written = profile(df, out_dir)
    _write_summary(df, out_dir, written)

    print(f"Wrote {len(written)} CSV files to {out_dir}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
