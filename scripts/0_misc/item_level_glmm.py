"""Item-level Bayesian binomial GLMM for DevToM-OpenRouter ToM accuracy.

The aggregate regressions (summarize_visualize_results.py, size_covariate_regression.py)
treat each model's accuracy as one exact number and fit OLS to those ~19 points.
That throws away three things: (1) each accuracy is really a sample proportion over
~60-184 binary items with its own binomial uncertainty, (2) accuracy is bounded in
[0,1] with a ceiling near 1.0 (OLS assumes an unbounded, homoscedastic response),
and (3) the same items are answered by every model (crossed non-independence).

This script instead works from the RAW per-item correct/incorrect outcomes pulled
straight out of the .eval logs, and fits a Bayesian binomial (Bernoulli/logit)
generalized linear mixed model:

    correct ~ years + log10(params) + C(family) [+ C(task)]
              + (1 | model) + (1 | item) + (1 | dimension)

- Fixed effects: the model-level covariates of interest — release date (years since
  2024-01-01), size (log10 total params), family, and task if both are present.
- Random intercepts: `model` (residual between-model heterogeneity after the fixed
  covariates), `item` (some questions are just harder), `dimension` (ToM-axis
  difficulty). These are the many-level, exchangeable units — the right place for
  random effects (family stays FIXED: only 5 levels, and we care about those
  specific families, not a population of families).

Why Bayesian: with weakly-informative priors the variance components are
regularized instead of collapsing to a singular fit, and every effect comes with an
honest posterior (mean, 94% interval, and P(direction)) rather than a fragile
p-value. This gives better-CALIBRATED coefficients; it does NOT manufacture power —
the between-family time signal is still limited by having only 5 families over a
short window, so expect wide intervals on `years`.

Fit with statsmodels' BinomialBayesMixedGLM via **variational Bayes** (mean-field).
That was chosen over PyMC/bambi because this environment's PyTensor C backend is
broken (arch-mismatched compile cache); VB is pure numpy/scipy, needs no
compilation, and runs in seconds. Caveat: mean-field VB gives Gaussian posteriors
and tends to *under*-state posterior width vs. full MCMC — so treat the intervals
as somewhat optimistic; the point estimates and directions are reliable. Predictors
`years` and `logp` are mean-centered; slopes are in original units (log-odds per
year / per log10-param).

    python scripts/0_misc/item_level_glmm.py --log-dir logs/Archive
"""
from __future__ import annotations

import argparse
import datetime
import sys
import warnings
from pathlib import Path

import numpy as np
import pandas as pd

PROJECT_ROOT = Path(__file__).parent.parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from inspect_ai.log import list_eval_logs, read_eval_log  # noqa: E402
from inspect_ai.scorer import CORRECT  # noqa: E402

from src.roster import (  # noqa: E402
    FAMILY_ORDER,
    PARAMS_B,
    model_family,
    model_params_b,
    model_release_date,
)

TASK_NAMES = {"tom_12dim_mcq", "tom_12dim_freeresponse"}
_EPOCH = datetime.date(2024, 1, 1)


def _is_correct(value) -> int:
    """Map an Inspect score value to 1 (correct) / 0. CORRECT is the 'C' token; the
    choice() and free-response scorers both emit C/I, but accept numeric/bool too."""
    if isinstance(value, str):
        return 1 if value.strip().upper().startswith("C") else 0
    return 1 if value in (CORRECT, 1, 1.0, True) else 0


def build_item_frame(log_dir: str) -> pd.DataFrame:
    """One row per (model, item): the raw Bernoulli outcome plus the model-level
    covariates. Skips non-success logs, out-of-family models, and models with no
    known release date or parameter count (with a stderr note)."""
    records: list[dict] = []
    for info in list_eval_logs(log_dir, formats=["eval"], recursive=False):
        log = read_eval_log(info)  # full log — need per-sample scores
        if log.eval.task not in TASK_NAMES:
            continue
        if log.status != "success":
            print(f"skipping {info.name}: status={log.status}", file=sys.stderr)
            continue
        model = log.eval.model
        family = model_family(model)
        date = model_release_date(model)
        params = model_params_b(model)
        if family not in FAMILY_ORDER or date is None or params is None:
            print(f"skipping {model}: unrecognized family / no date / no params", file=sys.stderr)
            continue
        years = (date - _EPOCH).days / 365.25
        logp = float(np.log10(params))
        for s in log.samples or []:
            if not s.scores:
                continue
            score = next(iter(s.scores.values()))  # one scorer per task
            records.append({
                "model": model.split("/")[-1],
                "family": family,
                "task": log.eval.task,
                "item": str(s.id),
                "dimension": (s.metadata or {}).get("tom_dimension", "unknown"),
                "correct": _is_correct(score.value),
                "years": years,
                "logp": logp,
            })
    return pd.DataFrame(records)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--log-dir", default="logs", help="directory to scan for .eval logs")
    ap.add_argument("--results-dir", default="results",
                    help="parent dir; posterior summary CSV + forest plot go in a timestamped subfolder")
    args = ap.parse_args()

    df = build_item_frame(args.log_dir)
    if df.empty or df["model"].nunique() < 4:
        print(f"Not enough usable item-level data under {args.log_dir}/ "
              f"(need >=4 models). Run a sweep first.", file=sys.stderr)
        return 1

    n_models = df["model"].nunique()
    n_items = df["item"].nunique()
    tasks = sorted(df["task"].unique())
    print(f"{len(df)} item-responses | {n_models} models | {n_items} items | "
          f"{df['dimension'].nunique()} dimensions | tasks={tasks}")
    print("family counts (models): "
          + ", ".join(f"{f}:{df[df['family'] == f]['model'].nunique()}"
                      for f in FAMILY_ORDER if (df['family'] == f).any()))

    # Mean-center continuous predictors (sampling geometry + interpretable intercept);
    # slopes are unchanged and reported in original units below.
    df["years_c"] = df["years"] - df["years"].mean()
    df["logp_c"] = df["logp"] - df["logp"].mean()

    from statsmodels.genmod.bayes_mixed_glm import BinomialBayesMixedGLM
    from scipy.stats import norm

    fixed = "correct ~ years_c + logp_c + C(family)"
    if len(tasks) > 1:
        fixed += " + C(task)"  # only identifiable if both tasks are present
    # Random INTERCEPTS as variance components (the many-level, exchangeable units).
    vc = {"model": "0 + C(model)", "item": "0 + C(item)", "dimension": "0 + C(dimension)"}
    print(f"\nFixed:  {fixed}")
    print(f"Random intercepts (variance components): {list(vc)}")
    print("family=Binomial (logit link), variational Bayes, weakly-informative priors")
    print("NOTE: mean-field VB — posterior widths are approximate (tend tighter than MCMC).\n")

    glmm = BinomialBayesMixedGLM.from_formula(fixed, vc, df)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        res = glmm.fit_vb()

    z94 = norm.ppf(0.97)  # 94% central interval (matches the earlier HDI convention)
    names = list(glmm.exog_names)

    print("=== Fixed effects (log-odds scale) ===")
    print(f"  {'term':28} {'mean':>7} {'sd':>6}  {'94% interval':>20} {'P(>0)':>7}")
    fe_rows = []
    for nm, m, s in zip(names, res.fe_mean, res.fe_sd):
        lo, hi = m - z94 * s, m + z94 * s
        p_pos = float(norm.cdf(m / s)) if s > 0 else float("nan")
        print(f"  {nm:28} {m:+.3f} {s:.3f}  [{lo:+.3f}, {hi:+.3f}]  {p_pos:.3f}")
        fe_rows.append({"term": nm, "mean": m, "sd": s, "lo94": lo, "hi94": hi, "P_gt_0": p_pos})

    def _interest(term: str, unit: str) -> dict:
        i = names.index(term)
        m, s = res.fe_mean[i], res.fe_sd[i]
        lo, hi = m - z94 * s, m + z94 * s
        p_pos = float(norm.cdf(m / s))
        print(f"\n  {term} ({unit}):")
        print(f"    log-odds : mean={m:+.3f}  94% [{lo:+.3f}, {hi:+.3f}]")
        print(f"    odds ratio: {np.exp(m):.3f}  94% [{np.exp(lo):.3f}, {np.exp(hi):.3f}]")
        print(f"    P(effect>0) = {p_pos:.3f}   P(<0) = {1 - p_pos:.3f}")
        return {"term": term, "unit": unit, "logodds_mean": m, "OR": float(np.exp(m)), "P_gt_0": p_pos}

    print("\n=== Effects of interest ===")
    interest = [_interest("years_c", "per year"), _interest("logp_c", "per 10x params")]

    n_families = df["family"].nunique()
    print(f"\n  CAVEAT: years_c and logp_c are MODEL-LEVEL predictors (constant within a\n"
          f"  model), so despite {len(df)} item-responses they really rest on {n_models} models /\n"
          f"  {n_families} families. Mean-field VB understates uncertainty for such group-level\n"
          f"  slopes — the intervals/P(>0) above are OPTIMISTIC. The trustworthy uncertainty\n"
          f"  on the release-date slope is the aggregate one (size_covariate_regression.py:\n"
          f"  years p=0.26, ns). What the item level adds reliably is item-difficulty structure\n"
          f"  and the size effect (which agrees across methods), not new certainty about time.")

    # Variance-component posteriors are on the log-SD scale; exponentiate to an SD.
    print("\n=== Random-effect SDs (log-odds) ===")
    vc_rows = []
    for nm, m, s in zip(list(vc), res.vcp_mean, res.vcp_sd):
        print(f"  {nm:12} SD={np.exp(m):.3f}  (log-SD mean={m:+.3f}, sd={s:.3f})")
        vc_rows.append({"group": nm, "logSD_mean": float(m), "logSD_sd": float(s), "SD": float(np.exp(m))})

    run_dir = Path(args.results_dir) / datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(fe_rows).to_csv(run_dir / "item_level_glmm_fixed_effects.csv", index=False)
    pd.DataFrame(interest).to_csv(run_dir / "item_level_glmm_effects_of_interest.csv", index=False)
    pd.DataFrame(vc_rows).to_csv(run_dir / "item_level_glmm_variance_components.csv", index=False)
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        fig, ax = plt.subplots(figsize=(7, 0.5 * len(names) + 1))
        ys = list(range(len(names)))
        ax.errorbar(list(res.fe_mean), ys, xerr=[z94 * s for s in res.fe_sd],
                    fmt="o", color="#4292c6", capsize=3)
        ax.axvline(0, color="gray", ls="--", lw=1)
        ax.set_yticks(ys)
        ax.set_yticklabels(names, fontsize=8)
        ax.invert_yaxis()
        ax.set_xlabel("log-odds (94% interval)")
        ax.set_title("Item-level GLMM fixed effects")
        fig.savefig(run_dir / "item_level_glmm_forest.png", dpi=150, bbox_inches="tight")
    except Exception as e:  # noqa: BLE001
        print(f"(forest plot skipped: {e})", file=sys.stderr)
    print(f"\nWrote posterior summaries + forest plot to {run_dir}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
