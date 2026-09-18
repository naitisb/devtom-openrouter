"""Everything the app derives from the item-level spine.

These are Python ports of the quantities the R pipeline computes. They are
recomputed at load time rather than read from `results/modeling/` because
`item_level.csv` was regenerated on 2026-08-23 (applying two model exclusions)
and most modeling subtrees predate that. Recomputation over 5,152 rows is
instant and guarantees every number in the app describes the same 28 models.

The genuinely expensive artifacts — the 10,000-draw permutation null, Rasch
item parameters, cross-validated log-loss, PCA — are read from the two subtrees
that *do* postdate the regeneration. See `data.py`.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from . import constants as K


# --- Basic aggregation ------------------------------------------------------
def filter_tasks(df: pd.DataFrame, tasks: list[str] | None) -> pd.DataFrame:
    """Restrict to a set of task labels ("MCQ", "Free response")."""
    if not tasks:
        return df
    return df[df["task_label"].isin(tasks)]


def model_summary(df: pd.DataFrame) -> pd.DataFrame:
    """One row per model: overall accuracy, provenance, saturation flag."""
    out = (
        df.groupby(["model", "short_model", "family", "tier"], as_index=False)
        .agg(
            accuracy=("correct", "mean"),
            n_correct=("correct", "sum"),
            n=("correct", "size"),
            release_date=("release_date", "first"),
            params_b=("params_b", "first"),
            date_years=("date_years", "first"),
        )
        .sort_values("release_date")
    )
    lo, hi = wilson(out["n_correct"], out["n"])
    out["wilson_lo"], out["wilson_hi"] = lo, hi
    out["saturated"] = out["accuracy"] >= K.SATURATION_CUTOFF
    return out.reset_index(drop=True)


def dimension_accuracy(df: pd.DataFrame, by: list[str] | None = None) -> pd.DataFrame:
    """Accuracy per (grouping x dimension), with the canonical age band attached."""
    by = by or ["model", "short_model", "family", "tier"]
    keys = by + ["tom_dimension"]
    out = df.groupby(keys, as_index=False).agg(
        accuracy=("correct", "mean"),
        n_correct=("correct", "sum"),
        n=("correct", "size"),
        release_date=("release_date", "first"),
        params_b=("params_b", "first"),
    )
    out["rank"] = out["tom_dimension"].map(K.DIMENSION_RANK)
    out["age_mid"] = out["tom_dimension"].map(K.DIMENSION_AGE_MID)
    out["age_lo"] = out["tom_dimension"].map(lambda d: K.DIMENSION_BAND[d][0])
    out["age_hi"] = out["tom_dimension"].map(lambda d: K.DIMENSION_BAND[d][1])
    out["construct"] = out["tom_dimension"].map(K.DIMENSION_TO_CONSTRUCT)
    out["mastered"] = out["accuracy"] >= K.MASTERY_THRESHOLD
    return out.sort_values(by + ["rank"]).reset_index(drop=True)


def wilson(k, n, z: float = 1.96) -> tuple[np.ndarray, np.ndarray]:
    """Wilson score interval — the CI the R pipeline uses for pass/fail."""
    k = np.asarray(k, dtype=float)
    n = np.asarray(n, dtype=float)
    with np.errstate(divide="ignore", invalid="ignore"):
        p = np.divide(k, n, out=np.full_like(k, np.nan), where=n > 0)
        denom = 1 + z**2 / n
        center = (p + z**2 / (2 * n)) / denom
        half = (z * np.sqrt(p * (1 - p) / n + z**2 / (4 * n**2))) / denom
    return np.clip(center - half, 0, 1), np.clip(center + half, 0, 1)


# --- The developmental axis -------------------------------------------------
AGE_FORMULAS = {
    "ratio": (
        "age_mid x (accuracy / 0.80)",
        "Scales the dimension's normative midpoint by how far the model is from "
        "the 80% mastery criterion. Equals the midpoint exactly at 80%, and can "
        "run **above** the band when a model exceeds it — so a model can appear "
        "ahead of as well as behind the normative window. This is the form used "
        "by `visualize_dimension_age_vs_date.R`.",
    ),
    "capped": (
        "min(age_mid, age_mid x accuracy / 0.80)",
        "Same scaling, but capped at the normative midpoint: a model can be "
        "behind the band but never ahead of it. This is the form used by the "
        "headline strip chart `visualize_dimension_progress_frq.R`.",
    ),
}


def age_equivalent(
    accuracy: pd.Series | np.ndarray,
    age_mid: pd.Series | np.ndarray,
    formula: str = "ratio",
    clamp: bool = True,
) -> np.ndarray:
    """Convert per-dimension accuracy into a developmental age equivalent.

    Both forms in the R pipeline are supported; see `AGE_FORMULAS`. The result
    is clamped to the scale's documented 2.5-11 yr range unless `clamp=False`.
    """
    accuracy = np.asarray(accuracy, dtype=float)
    age_mid = np.asarray(age_mid, dtype=float)
    est = age_mid * (accuracy / K.MASTERY_THRESHOLD)
    if formula == "capped":
        est = np.minimum(est, age_mid)
    if clamp:
        est = np.clip(est, K.AGE_MIN, K.AGE_MAX)
    return est


def with_age_equivalent(
    dim_acc: pd.DataFrame, formula: str = "ratio", clamp: bool = True
) -> pd.DataFrame:
    out = dim_acc.copy()
    out["age_equiv"] = age_equivalent(
        out["accuracy"], out["age_mid"], formula=formula, clamp=clamp
    )
    out["age_gap"] = out["age_equiv"] - out["age_mid"]
    return out


# --- The sawtooth ------------------------------------------------------------
def sawtooth_metrics(profile: pd.DataFrame, value: str = "age_equiv") -> dict:
    """Quantify how far one model's profile departs from the human sequence.

    `profile` is one model's 12 rows, with `rank` and `value`. Returns the
    numbers the post describes qualitatively: the size of the teeth, how many
    adjacent steps go backwards, and the rank correlation with the normative
    order.
    """
    p = profile.sort_values("rank")
    y = p[value].to_numpy(dtype=float)
    if len(y) < 3 or np.all(np.isnan(y)):
        return {
            "max_drop": np.nan,
            "max_swing": np.nan,
            "n_backward": 0,
            "n_steps": 0,
            "spearman": np.nan,
            "monotonic": False,
        }

    steps = np.diff(y)
    backward = steps < -1e-9
    ranks = p["rank"].to_numpy(dtype=float)

    # Spearman without scipy: Pearson on ranks.
    spearman = _spearman(ranks, y)

    return {
        "max_drop": float(-steps.min()) if steps.min() < 0 else 0.0,
        "max_swing": float(np.abs(steps).max()),
        "n_backward": int(backward.sum()),
        "n_steps": int(len(steps)),
        "spearman": spearman,
        "monotonic": bool(not backward.any()),
    }


def _spearman(a: np.ndarray, b: np.ndarray) -> float:
    mask = ~(np.isnan(a) | np.isnan(b))
    if mask.sum() < 3:
        return float("nan")
    ra = pd.Series(a[mask]).rank().to_numpy()
    rb = pd.Series(b[mask]).rank().to_numpy()
    if ra.std() == 0 or rb.std() == 0:
        return float("nan")
    return float(np.corrcoef(ra, rb)[0, 1])


def sawtooth_table(dim_acc: pd.DataFrame, value: str = "age_equiv") -> pd.DataFrame:
    """`sawtooth_metrics` for every model."""
    rows = []
    for model, group in dim_acc.groupby("model"):
        metrics = sawtooth_metrics(group, value=value)
        metrics["model"] = model
        for col in ("short_model", "family", "tier", "release_date", "params_b"):
            if col in group.columns:
                metrics[col] = group[col].iloc[0]
        rows.append(metrics)
    return pd.DataFrame(rows).sort_values("max_drop", ascending=False).reset_index(drop=True)


# --- Ordinal structure: Guttman + prerequisite violations -------------------
def mastery_matrix(dim_acc: pd.DataFrame) -> pd.DataFrame:
    """Models (rows, chronological) x dimensions (columns, developmental order)."""
    wide = dim_acc.pivot_table(
        index="model", columns="tom_dimension", values="mastered", aggfunc="first"
    )
    cols = [d for d in K.DIMENSION_ORDER if d in wide.columns]
    wide = wide[cols]
    order = (
        dim_acc.drop_duplicates("model")
        .sort_values("release_date")["model"]
        .tolist()
    )
    return wide.reindex([m for m in order if m in wide.index]).astype(float)


def guttman_errors(matrix: pd.DataFrame) -> pd.DataFrame:
    """Per model, count deviations from the perfect Guttman (staircase) pattern.

    The ideal pattern for a model that has mastered *k* skills is k ones
    followed by zeros. The error count is the minimum number of cells that would
    have to flip to reach the closest such pattern.
    """
    rows = []
    for model, values in matrix.iterrows():
        v = values.to_numpy(dtype=float)
        valid = ~np.isnan(v)
        v = v[valid]
        n = len(v)
        if n == 0:
            continue
        # Cost of the ideal pattern with cut at k: zeros before k + ones after.
        best = min(
            int((v[:k] == 0).sum() + (v[k:] == 1).sum()) for k in range(n + 1)
        )
        rows.append({"model": model, "guttman_errors": best, "n_mastered": int(v.sum())})
    return pd.DataFrame(rows)


def reproducibility_coefficient(matrix: pd.DataFrame) -> float:
    """Guttman's CR: 1 - errors / total cells."""
    errors = guttman_errors(matrix)["guttman_errors"].sum()
    total = matrix.notna().to_numpy().sum()
    return float(1 - errors / total) if total else float("nan")


def prerequisite_violations(
    dim_acc: pd.DataFrame, min_gap: float = 0.0
) -> pd.DataFrame:
    """The post's exact diagnostic, made concrete.

    Every (later dimension mastered, earlier dimension failed) pair. In the
    post's terms: "a model that passes false belief reasoning items but fails
    desire understanding items is a model doing something structurally
    different". Each row is one such dissociation.
    """
    rows = []
    for model, group in dim_acc.groupby("model"):
        g = group.sort_values("rank")
        mastered = g[g["mastered"]]
        failed = g[~g["mastered"]]
        for later in mastered.itertuples():
            for earlier in failed.itertuples():
                if earlier.rank >= later.rank:
                    continue
                gap = later.accuracy - earlier.accuracy
                if gap < min_gap:
                    continue
                rows.append(
                    {
                        "model": model,
                        "short_model": getattr(later, "short_model", model),
                        "family": getattr(later, "family", ""),
                        "tier": getattr(later, "tier", ""),
                        "passed": later.tom_dimension,
                        "passed_age": later.age_mid,
                        "passed_acc": later.accuracy,
                        "failed": earlier.tom_dimension,
                        "failed_age": earlier.age_mid,
                        "failed_acc": earlier.accuracy,
                        "age_inversion": later.age_mid - earlier.age_mid,
                        "acc_gap": gap,
                    }
                )
    if not rows:
        return pd.DataFrame(
            columns=[
                "model", "short_model", "family", "tier", "passed", "passed_age",
                "passed_acc", "failed", "failed_age", "failed_acc",
                "age_inversion", "acc_gap",
            ]
        )
    return pd.DataFrame(rows).sort_values(
        ["age_inversion", "acc_gap"], ascending=False
    ).reset_index(drop=True)


def coherence(dim_acc: pd.DataFrame) -> pd.DataFrame:
    """Continuous developmental coherence, ported from `guttman_sequence_analysis.R`.

    For each split point k, take mean(accuracy on dimensions <= k) minus
    mean(accuracy on dimensions > k), then average over all k. Positive means
    child-like: better on the earlier, easier skills. Negative means the model
    is doing better on late skills than on their prerequisites.

    Raw coherence is mechanically tied to overall accuracy by ceiling
    compression, so the R script residualizes it on mean accuracy. This does
    the same.
    """
    rows = []
    for model, group in dim_acc.groupby("model"):
        g = group.sort_values("rank")
        acc = g["accuracy"].to_numpy(dtype=float)
        n = len(acc)
        if n < 3:
            continue
        deltas = [acc[:k].mean() - acc[k:].mean() for k in range(1, n)]
        rows.append(
            {
                "model": model,
                "short_model": g["short_model"].iloc[0] if "short_model" in g else model,
                "family": g["family"].iloc[0] if "family" in g else "",
                "tier": g["tier"].iloc[0] if "tier" in g else "",
                "release_date": g["release_date"].iloc[0] if "release_date" in g else pd.NaT,
                "params_b": g["params_b"].iloc[0] if "params_b" in g else np.nan,
                "coherence": float(np.mean(deltas)),
                "mean_acc": float(acc.mean()),
            }
        )
    out = pd.DataFrame(rows)
    if out.empty:
        return out

    # Residualize on mean accuracy (OLS, one predictor).
    x = out["mean_acc"].to_numpy()
    y = out["coherence"].to_numpy()
    if len(out) > 2 and x.std() > 0:
        slope, intercept = np.polyfit(x, y, 1)
        out["coherence_fit"] = intercept + slope * x
        out["coherence_resid"] = y - out["coherence_fit"]
    else:
        out["coherence_fit"] = np.nan
        out["coherence_resid"] = np.nan
    return out.sort_values("coherence_resid").reset_index(drop=True)


# --- Instrument quality (recomputed, so it matches the current panel) -------
def ctt_item_stats(df: pd.DataFrame) -> pd.DataFrame:
    """Classical test theory per item: facility and discrimination.

    Facility = proportion of models answering correctly. Discrimination =
    point-biserial correlation between getting this item right and the model's
    total score on the rest of the instrument (corrected for part-whole overlap).
    """
    rows = []
    for task, block in df.groupby("task_label"):
        wide = block.pivot_table(
            index="model", columns="item_id", values="correct", aggfunc="first"
        )
        total = wide.sum(axis=1)
        for item in wide.columns:
            col = wide[item]
            rest = total - col.fillna(0)
            valid = col.notna()
            if valid.sum() < 3 or col[valid].std() == 0 or rest[valid].std() == 0:
                disc = np.nan
            else:
                disc = float(np.corrcoef(col[valid], rest[valid])[0, 1])
            rows.append(
                {
                    "task_label": task,
                    "item_id": item,
                    "facility": float(col[valid].mean()),
                    "discrimination": disc,
                    "n_models": int(valid.sum()),
                }
            )
    out = pd.DataFrame(rows)
    meta = df.drop_duplicates("item_id")[["item_id", "tom_dimension", "construct"]]
    out = out.merge(meta, on="item_id", how="left")
    out["rank"] = out["tom_dimension"].map(K.DIMENSION_RANK)
    out["flag"] = np.where(
        out["facility"] > 0.95,
        "too easy",
        np.where(
            out["facility"] < 0.25,
            "too hard",
            np.where(out["discrimination"] < 0.15, "low discrimination", ""),
        ),
    )
    return out.sort_values(["task_label", "rank", "item_id"]).reset_index(drop=True)


def kr20(df: pd.DataFrame) -> pd.DataFrame:
    """Kuder-Richardson 20 internal consistency, per task."""
    rows = []
    for task, block in df.groupby("task_label"):
        wide = block.pivot_table(
            index="model", columns="item_id", values="correct", aggfunc="first"
        ).dropna(axis=1, how="any")
        k = wide.shape[1]
        if k < 2 or wide.shape[0] < 3:
            continue
        p = wide.mean(axis=0)
        variance = wide.sum(axis=1).var(ddof=1)
        if variance == 0:
            continue
        value = (k / (k - 1)) * (1 - (p * (1 - p)).sum() / variance)
        rows.append(
            {"task_label": task, "kr20": float(value), "n_items": int(k),
             "n_models": int(wide.shape[0])}
        )
    return pd.DataFrame(rows)


def format_agreement(df: pd.DataFrame) -> pd.DataFrame:
    """Per-model MCQ vs free-response accuracy — the built-in robustness check."""
    pivot = (
        df.groupby(["model", "short_model", "family", "tier", "task_label"], as_index=False)
        .agg(accuracy=("correct", "mean"), n=("correct", "size"))
        .pivot_table(
            index=["model", "short_model", "family", "tier"],
            columns="task_label",
            values="accuracy",
        )
        .reset_index()
    )
    pivot.columns.name = None
    if "MCQ" in pivot.columns and "Free response" in pivot.columns:
        pivot["gap"] = pivot["MCQ"] - pivot["Free response"]
        pivot["headroom"] = pivot[["MCQ", "Free response"]].max(axis=1) < K.SATURATION_CUTOFF
    return pivot
