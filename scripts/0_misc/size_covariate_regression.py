"""Size-controlled trend regressions for DevToM-OpenRouter ToM accuracy.

Companion to summarize_visualize_results.py. That script fits accuracy-vs-release-
date regressions PER size tier or PER family; after the roster prune each such
group has only 3-6 dated points, so df = n-2 is 1-4 and the slope t-test has almost
no power — every family comes back "ns" even when r^2 is high (DeepSeek, Qwen).
Splitting further (per tier) is worse; collapsing tiers dumps size-driven variance
into the residuals.

This script instead POOLS across families and controls for model size as a
continuous covariate, log10(parameters). That costs a single degree of freedom
(vs k-1 for tier dummies) yet removes the dominant confound — size — so the
release-date effect is estimated with real df. Two models:

  Model A (common slope): accuracy ~ years + log10(params) + C(family)
      One improvement-per-year slope, adjusting for size and a per-family baseline.
      Answers "across open models, is there an overall time trend once size and
      family are accounted for?"

  Model B (per-family slopes): family-specific intercepts + family-specific year
      slopes + one shared log10(params) coefficient + one shared error variance.
      Each family keeps its own trajectory, but the size effect and the residual
      variance are pooled across all families, so each family's slope is tested
      with df = n - (2*n_families + 1) instead of n_family - 2. Answers "is THIS
      family improving over time, holding size fixed?" with usable power.

Both are ordinary least squares fit with numpy (no statsmodels dependency); slope
significance is a two-sided t-test on the coefficient. Interpretation caveat: OLS
still assumes independent, homoscedastic, normal errors — the model points are not
fully independent (shared lineages/checkpoints) and accuracy is a bounded
proportion, so treat p-values as directional, not definitive.

Data (which logs, per-model overall accuracy, family, release date) is pulled via
the sibling summarize_visualize_results module so log-dir semantics and the
family/date mapping can't drift from the rest of the pipeline. Model *size* is the
one identity attribute the roster doesn't carry yet, so it lives in PARAMS_B below;
if this proves durable it should migrate to a field on src.roster.ModelEntry.

    python scripts/0_misc/size_covariate_regression.py
    python scripts/0_misc/size_covariate_regression.py --log-dir logs/Archive
"""
from __future__ import annotations

import argparse
import datetime
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats

PROJECT_ROOT = Path(__file__).parent.parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

# Analysis-specific functions from the sibling script; model identity from roster.
from summarize_visualize_results import (  # type: ignore[import-not-found]  # noqa: E402
    OVERALL_LABEL,
    build_model_pivot,
    collect_rows,
)

from src.roster import (  # noqa: E402
    FAMILY_ORDER,
    PARAMS_B,
    model_family,
    model_params_b,
    model_release_date,
)

_EPOCH = datetime.date(2024, 1, 1)  # x=0 for the year axis, so slopes read as acc/yr


def _significance(p: float) -> str:
    if p < 0.001:
        return "***"
    if p < 0.01:
        return "**"
    if p < 0.05:
        return "*"
    return "ns"


def _ols(x_matrix: np.ndarray, y: np.ndarray) -> dict:
    """Ordinary least squares with inference. Returns beta, SE, t, p (two-sided),
    df, R^2, and residual SD. Assumes X has full column rank."""
    n, k = x_matrix.shape
    dof = n - k
    xtx_inv = np.linalg.inv(x_matrix.T @ x_matrix)
    beta = xtx_inv @ x_matrix.T @ y
    resid = y - x_matrix @ beta
    rss = float(resid @ resid)
    s2 = rss / dof
    se = np.sqrt(np.diag(s2 * xtx_inv))
    t = beta / se
    p = 2 * stats.t.sf(np.abs(t), dof)
    ss_tot = float(np.sum((y - y.mean()) ** 2))
    r2 = 1 - rss / ss_tot if ss_tot > 0 else float("nan")
    return {"beta": beta, "se": se, "t": t, "p": p, "df": dof,
            "r2": r2, "resid_sd": float(np.sqrt(s2))}


def _print_table(names: list[str], res: dict, only: set[str] | None = None) -> list[dict]:
    """Print a coefficient table and return it as a list of row dicts (for CSV)."""
    rows = []
    print(f"  df={res['df']}  R^2={res['r2']:.3f}  resid_sd={res['resid_sd']:.3f}  "
          f"t_crit(.05)=±{stats.t.ppf(0.975, res['df']):.2f}")
    for nm, b, se, t, p in zip(names, res["beta"], res["se"], res["t"], res["p"]):
        rows.append({"term": nm, "beta": b, "se": se, "t": t, "p": p, "sig": _significance(p)})
        if only is not None and nm not in only:
            continue
        print(f"    {nm:20} beta={b:+.4f}  SE={se:.4f}  t={t:+.2f}  p={p:.3f} {_significance(p)}")
    return rows


def build_overall_frame(log_dir: str) -> pd.DataFrame:
    """One row per model with its overall accuracy, family, release date (years
    since 2024-01-01), and log10(params). Drops models with no known release date
    or no mapped parameter count (with a stderr note)."""
    rows = collect_rows(log_dir)
    if not rows:
        return pd.DataFrame()
    df = pd.DataFrame(rows)
    # latest run per (model, task), then average a model's tasks into one accuracy
    latest = df.groupby(["model", "task"])["created"].transform("max")
    df = df[df["created"] == latest]
    pivot = build_model_pivot(df)  # index=model, includes the OVERALL_LABEL column

    records = []
    for model in pivot.index:
        acc = pivot.loc[model, OVERALL_LABEL] if OVERALL_LABEL in pivot.columns else np.nan
        date = model_release_date(model)
        params = model_params_b(model)
        if date is None:
            print(f"dropping {model}: no known release date", file=sys.stderr)
            continue
        if params is None:
            print(f"dropping {model}: no parameter count in PARAMS_B (add it)", file=sys.stderr)
            continue
        if pd.isna(acc):
            print(f"dropping {model}: no overall accuracy", file=sys.stderr)
            continue
        records.append({
            "model": model,
            "family": model_family(model),
            "years": (date - _EPOCH).days / 365.25,
            "logp": float(np.log10(params)),
            "accuracy": float(acc),
        })
    return pd.DataFrame(records)


def fit_common_slope(data: pd.DataFrame) -> tuple[dict, list[str], list[dict]]:
    """Model A: accuracy ~ 1 + years + log10(params) + C(family), Llama baseline."""
    fams = [f for f in FAMILY_ORDER if f != "Llama"]  # Llama = reference level
    cols = [np.ones(len(data)), data["years"].values, data["logp"].values]
    names = ["intercept", "years", "log10(params)"]
    for f in fams:
        cols.append((data["family"] == f).astype(float).values)
        names.append(f)
    res = _ols(np.column_stack(cols), data["accuracy"].values)
    return res, names, []


def fit_family_slopes(data: pd.DataFrame) -> tuple[dict, list[str]]:
    """Model B: per-family intercepts + per-family year slopes + one shared
    log10(params) coefficient + one shared error variance. Each family's slope is
    tested against the pooled residual variance, so df is n - (2*families + 1)."""
    fams = [f for f in FAMILY_ORDER if (data["family"] == f).any()]
    cols, names = [], []
    for f in fams:
        cols.append((data["family"] == f).astype(float).values)
        names.append(f"{f}:intercept")
    for f in fams:
        cols.append(((data["family"] == f).astype(float) * data["years"]).values)
        names.append(f"{f}:slope/yr")
    cols.append(data["logp"].values)
    names.append("log10(params)")
    res = _ols(np.column_stack(cols), data["accuracy"].values)
    return res, names


def naive_family_slopes(data: pd.DataFrame) -> None:
    """For comparison: the un-pooled per-family slope (stats.linregress on that
    family's points only) — the low-df version this script is meant to improve on."""
    print("\n=== Reference: naive per-family slope (no size control, own df) ===")
    for f in [f for f in FAMILY_ORDER if (data["family"] == f).any()]:
        g = data[data["family"] == f]
        if len(g) < 3 or g["years"].nunique() < 2:
            print(f"  {f:9} n={len(g)}  (skipped: n<3 or single date)")
            continue
        fit = stats.linregress(g["years"].values, g["accuracy"].values)
        print(f"  {f:9} n={len(g)}  slope={fit.slope:+.3f}/yr  r^2={fit.rvalue**2:.3f}  "
              f"p={fit.pvalue:.3f} {_significance(fit.pvalue)}  (df={len(g) - 2})")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--log-dir", default="logs", help="directory to scan for .eval logs")
    ap.add_argument("--results-dir", default="results",
                    help="parent dir; a coefficients CSV is written to a timestamped subfolder")
    args = ap.parse_args()

    data = build_overall_frame(args.log_dir)
    if data.empty or len(data) < 4:
        print(f"Not enough usable models under {args.log_dir}/ (need >=4 with a release "
              f"date, parameter count, and overall accuracy). Run a sweep first.",
              file=sys.stderr)
        return 1

    counts = ", ".join(
        f"{f}:{int((data['family'] == f).sum())}"
        for f in FAMILY_ORDER if (data["family"] == f).any()
    )
    print(f"n = {len(data)} models ({counts})")

    print("\n=== Model A: accuracy ~ years + log10(params) + C(family)  [common slope] ===")
    res_a, names_a, _ = fit_common_slope(data)
    rows_a = _print_table(names_a, res_a, only={"years", "log10(params)"})
    yr = res_a["beta"][names_a.index("years")]
    yr_p = res_a["p"][names_a.index("years")]
    print(f"  -> size+family-adjusted time trend: {yr:+.3f} accuracy/yr, p={yr_p:.3f} {_significance(yr_p)}")

    print("\n=== Model B: per-family slopes + shared size covariate + shared variance ===")
    res_b, names_b = fit_family_slopes(data)
    rows_b = _print_table(names_b, res_b,
                          only={n for n in names_b if "slope" in n or n == "log10(params)"})

    naive_family_slopes(data)

    # Persist the coefficient tables for the record.
    run_dir = Path(args.results_dir) / datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir.mkdir(parents=True, exist_ok=True)
    out = run_dir / "size_covariate_regression.csv"
    pd.concat([
        pd.DataFrame(rows_a).assign(model="A_common_slope"),
        pd.DataFrame(rows_b).assign(model="B_family_slopes"),
    ], ignore_index=True).to_csv(out, index=False)
    print(f"\nWrote coefficients to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
