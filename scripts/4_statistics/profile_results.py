"""Descriptive profiling of eval outcomes + Classical Test Theory item analysis.

Reads results/item_level.csv (produced by extract_item_level.py) and computes:
accuracy summaries (Wilson 95% CI), dimension difficulty ranking, CTT item
analysis (facility, discrimination), KR-20 reliability, and response quality
metrics. Emits tidy CSVs and a markdown summary — no plots.

    python scripts/4_statistics/profile_results.py
    python scripts/4_statistics/profile_results.py --item-csv results/item_level.csv
"""
from __future__ import annotations

import argparse
import datetime
import sys
from pathlib import Path

import numpy as np
import pandas as pd

PROJECT_ROOT = Path(__file__).parent.parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from src.roster import FAMILY_ORDER, model_sort_key  # noqa: E402
from src.constructs import DIMENSION_DEVELOPMENTAL_ORDER  # noqa: E402


def _wilson_ci(n_correct: int, n_total: int, z: float = 1.96) -> tuple[float, float, float]:
    """Wilson score interval for a proportion. Returns (p, lo, hi)."""
    if n_total == 0:
        return np.nan, np.nan, np.nan
    p = n_correct / n_total
    denom = 1 + z ** 2 / n_total
    centre = (p + z ** 2 / (2 * n_total)) / denom
    spread = z * np.sqrt((p * (1 - p) + z ** 2 / (4 * n_total)) / n_total) / denom
    return p, max(0, centre - spread), min(1, centre + spread)


def _point_biserial(item_scores: np.ndarray, total_scores: np.ndarray) -> float:
    """Point-biserial correlation between a binary item and a continuous total."""
    if item_scores.std() == 0 or total_scores.std() == 0:
        return 0.0
    return float(np.corrcoef(item_scores, total_scores)[0, 1])


def _kr20(item_matrix: np.ndarray) -> float:
    """Kuder-Richardson 20 (Cronbach's alpha for dichotomous items)."""
    n_items = item_matrix.shape[1]
    if n_items < 2:
        return np.nan
    p = item_matrix.mean(axis=0)
    pq_sum = (p * (1 - p)).sum()
    total_var = item_matrix.sum(axis=1).var(ddof=1)
    if total_var == 0:
        return np.nan
    return (n_items / (n_items - 1)) * (1 - pq_sum / total_var)


def profile_accuracy(df: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Per-model accuracy with Wilson CI, per-model×dimension, per-dimension summaries."""
    # Per-model overall
    model_acc = []
    for model, g in df.groupby("model"):
        n = len(g)
        nc = g["correct"].sum()
        p, lo, hi = _wilson_ci(nc, n)
        model_acc.append({
            "model": model, "family": g["family"].iloc[0], "tier": g["tier"].iloc[0],
            "n": n, "n_correct": nc, "accuracy": p, "wilson_lo": lo, "wilson_hi": hi,
        })
    model_acc_df = pd.DataFrame(model_acc).sort_values(
        "model", key=lambda s: s.map(lambda m: model_sort_key(m)))

    # Per-model×dimension
    model_dim = df.groupby(["model", "tom_dimension"]).agg(
        n=("correct", "count"), n_correct=("correct", "sum"),
        accuracy=("correct", "mean")).reset_index()

    # Per-dimension (mean/sd across models)
    dim_acc = df.groupby("tom_dimension").agg(
        mean_accuracy=("correct", "mean"),
        n_items=("item_id", "nunique"),
        n_responses=("correct", "count"),
    ).reset_index()
    dim_model_means = df.groupby(["tom_dimension", "model"])["correct"].mean().reset_index()
    dim_spread = dim_model_means.groupby("tom_dimension")["correct"].agg(["std", "min", "max"])
    dim_acc = dim_acc.merge(dim_spread, left_on="tom_dimension", right_index=True, how="left")
    dim_acc["rank"] = dim_acc["tom_dimension"].map(
        lambda d: DIMENSION_DEVELOPMENTAL_ORDER.index(d)
        if d in DIMENSION_DEVELOPMENTAL_ORDER else len(DIMENSION_DEVELOPMENTAL_ORDER))
    dim_acc = dim_acc.sort_values("mean_accuracy")

    return model_acc_df, model_dim, dim_acc


def profile_ctt(df: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    """CTT item analysis: facility, discrimination, flagging. Returns (item_stats, reliability)."""
    item_rows = []
    reliability_rows = []

    for task, task_df in df.groupby("task"):
        # Build model × item matrix
        pivot = task_df.pivot_table(index="model", columns="item_id",
                                    values="correct", aggfunc="first")
        pivot = pivot.dropna(axis=1, how="all").fillna(0)

        total_scores = pivot.sum(axis=1).values
        item_matrix = pivot.values

        for col_idx, item_id in enumerate(pivot.columns):
            item_scores = item_matrix[:, col_idx]
            facility = item_scores.mean()
            disc = _point_biserial(item_scores, total_scores)
            dim = task_df[task_df["item_id"] == item_id]["tom_dimension"].iloc[0]

            flag = ""
            if facility > 0.9:
                flag = "too-easy"
            elif facility < 0.2:
                flag = "too-hard"
            if disc < 0.3:
                flag = (flag + "+" if flag else "") + "low-disc"

            item_rows.append({
                "task": task, "item_id": item_id, "tom_dimension": dim,
                "facility": round(facility, 4), "discrimination": round(disc, 4),
                "flag": flag, "n_models": len(pivot),
            })

        # KR-20 overall
        kr = _kr20(item_matrix)
        reliability_rows.append({"task": task, "scope": "overall",
                                  "kr20": round(kr, 4) if not np.isnan(kr) else None,
                                  "n_items": item_matrix.shape[1],
                                  "n_models": item_matrix.shape[0]})

        # KR-20 per dimension
        for dim in sorted(task_df["tom_dimension"].unique()):
            dim_items = task_df[task_df["tom_dimension"] == dim]["item_id"].unique()
            dim_cols = [c for c in pivot.columns if c in dim_items]
            if len(dim_cols) >= 2:
                dim_matrix = pivot[dim_cols].values
                kr_dim = _kr20(dim_matrix)
                reliability_rows.append({
                    "task": task, "scope": dim,
                    "kr20": round(kr_dim, 4) if not np.isnan(kr_dim) else None,
                    "n_items": len(dim_cols), "n_models": len(pivot),
                })

    return pd.DataFrame(item_rows), pd.DataFrame(reliability_rows)


def profile_response_quality(df: pd.DataFrame) -> pd.DataFrame:
    """Per-model response quality: coverage and failure rates."""
    rows = []
    for model, g in df.groupby("model"):
        total = len(g)
        for task, tg in g.groupby("task"):
            n = len(tg)
            nc = tg["correct"].sum()
            rows.append({
                "model": model, "family": g["family"].iloc[0],
                "tier": g["tier"].iloc[0], "task": task,
                "n_items": n, "n_correct": nc,
                "accuracy": nc / n if n > 0 else np.nan,
            })
    return pd.DataFrame(rows)


def _write_summary(df: pd.DataFrame, model_acc: pd.DataFrame, dim_acc: pd.DataFrame,
                    reliability: pd.DataFrame, out_dir: Path) -> None:
    """Write a markdown results-profiling summary."""
    lines = [
        "# Results Profile",
        "",
        f"Generated: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        "",
        "## Overview",
        "",
        f"- Models: {df['model'].nunique()}",
        f"- Items: {df['item_id'].nunique()}",
        f"- Total responses: {len(df)}",
        f"- Tasks: {', '.join(sorted(df['task'].unique()))}",
        f"- Families: {', '.join(sorted(df['family'].unique()))}",
        "",
        "## Model accuracy (Wilson 95% CI)",
        "",
    ]
    for _, row in model_acc.iterrows():
        short = row["model"].split("/")[-1]
        lines.append(f"- {short}: {row['accuracy']:.3f} [{row['wilson_lo']:.3f}, {row['wilson_hi']:.3f}] (n={row['n']})")

    lines += ["", "## Dimension difficulty (hardest first)", ""]
    for _, row in dim_acc.iterrows():
        lines.append(f"- {row['tom_dimension']}: mean={row['mean_accuracy']:.3f}, sd={row.get('std', 0):.3f}")

    lines += ["", "## Reliability (KR-20)", ""]
    for _, row in reliability[reliability["scope"] == "overall"].iterrows():
        kr = row["kr20"] if row["kr20"] is not None else "N/A"
        lines.append(f"- {row['task']}: KR-20={kr} (n_items={row['n_items']}, n_models={row['n_models']})")

    summary_path = out_dir / "results_profile.md"
    summary_path.write_text("\n".join(lines) + "\n")
    print(f"Wrote {summary_path}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--item-csv", default="results/item_level.csv",
                    help="item-level CSV from extract_item_level.py")
    ap.add_argument("--results-dir", default="results",
                    help="parent results directory")
    args = ap.parse_args()

    csv_path = Path(args.item_csv)
    if not csv_path.exists():
        print(f"{csv_path} not found. Run extract_item_level.py first.", file=sys.stderr)
        return 1

    df = pd.read_csv(csv_path)
    print(f"Loaded {len(df)} rows from {csv_path}")

    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = Path(args.results_dir) / "stats" / "results" / stamp
    out_dir.mkdir(parents=True, exist_ok=True)

    model_acc, model_dim, dim_acc = profile_accuracy(df)
    model_acc.to_csv(out_dir / "model_accuracy.csv", index=False)
    model_dim.to_csv(out_dir / "model_dimension_accuracy.csv", index=False)
    dim_acc.to_csv(out_dir / "dimension_difficulty.csv", index=False)

    item_stats, reliability = profile_ctt(df)
    item_stats.to_csv(out_dir / "ctt_item_stats.csv", index=False)
    reliability.to_csv(out_dir / "reliability_kr20.csv", index=False)

    quality = profile_response_quality(df)
    quality.to_csv(out_dir / "response_quality.csv", index=False)

    # Per-family/tier summaries
    fam_summary = df.groupby(["family", "tier"]).agg(
        n_models=("model", "nunique"), mean_accuracy=("correct", "mean"),
        sd_accuracy=("correct", "std"), n=("correct", "count"),
    ).reset_index().round(4)
    fam_summary.to_csv(out_dir / "family_tier_summary.csv", index=False)

    _write_summary(df, model_acc, dim_acc, reliability, out_dir)
    print(f"Wrote stats CSVs to {out_dir}/")

    # Print flagged items
    flagged = item_stats[item_stats["flag"] != ""]
    if not flagged.empty:
        print(f"\n{len(flagged)} flagged items (too-easy/too-hard/low-discrimination):")
        for _, row in flagged.head(10).iterrows():
            print(f"  {row['item_id']} ({row['tom_dimension']}): "
                  f"p={row['facility']:.2f} rpb={row['discrimination']:.2f} [{row['flag']}]")
        if len(flagged) > 10:
            print(f"  ... and {len(flagged) - 10} more (see ctt_item_stats.csv)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
