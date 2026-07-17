"""Summarize tom_12dim_mcq / tom_12dim_freeresponse eval logs by ToM dimension
(OpenRouter open-weight edition).

Ported from the sibling devtom-eval project's analysis script, retargeted at
OPEN-WEIGHT model families served through OpenRouter (Llama, Qwen, DeepSeek,
Mistral, Gemma). The model identity constants (which models, their family,
size-tier, color, and release date) are NOT hard-coded here — they come from
src/roster.py, the single source of truth the shell runners also read, so
"what we ran" and "what we plotted" can't drift apart.

Reads every .eval log under --log-dir, pulls out the per-dimension
accuracy/stderr metrics that src/metrics.py's dimension_breakdown_metrics()
attaches to both tasks, and writes a tidy CSV, a printed model x dimension
pivot per task, and up to twenty-one seaborn figures (the last four require
free-response logs). Rows are individual models — NOT collapsed into a family
average — ordered oldest to newest within each open-weight family, so you can
see whether accuracy on each ToM dimension actually improves release over
release as you walk an open family forward in time (Llama 2 -> Llama 4, Mistral
7B -> Mistral Small 3, etc.):

  - dimension_heatmap.png                 heatmap, both tasks combined, all families
  - dimension_heatmap_mcq.png              heatmap, MCQ/true-false only, all families
  - dimension_heatmap_freeresponse.png     heatmap, free-response only, all families
  - dimension_heatmap_<family>.png         one heatmap per family (Llama, Qwen, ...)

  Every trend chart plots the raw per-release accuracies as markers per model TYPE
  (size tier: Llama small, Qwen large, ...) PLUS one linear regression line + 95% CI
  band PER MODEL TYPE (see _add_regression_band; a type is skipped, not the whole
  plot, if it has fewer than 3 dated points) — regressions are never pooled across
  types, and never collapsed to one line per family. The markers show the raw data
  (no connecting line — that would imply interpolation between releases); each
  type's dashed regression line answers "is THIS tier trending up over
  time, and is that significant?" Each type's regression p-value (slope != 0,
  two-sided) is in its own legend label, and a significance-star annotation
  (*/**/***/ns) per type is stacked in the top-left corner. y-axis starts at 0.5:

  - dimension_trend_by_family.png          both tasks + all families combined
  - dimension_trend_family_collapsed.png   as above but ONE line per family (the
                                            size tiers collapsed) + one pooled
                                            regression per family
  - dimension_trend_by_task.png            all families, MCQ vs. free response
  - dimension_trend_<family>.png           per family, both tasks combined
  - dimension_trend_<family>_by_task.png   per family, MCQ vs. free response
  - dimension_difficulty_ranking*.png      dimensions ranked hardest-to-easiest
                                            (overall / per task / per family)

  Free-response only (skipped if no free-response logs): a 3x4 grid of small
  subplots, one per ToM dimension (developmental order), each with its own
  linear regression + 95% CI + significance for that dimension vs. release date:

  - dimension_regression_<family>_freeresponse.png          pooled across tiers
  - dimension_regression_<family>_freeresponse_by_type.png  one line per tier

Only scans --log-dir itself (not subfolders, so a logs/Archive/ of old runs is
ignored), and only rows for models in a recognized family (see roster.FAMILY_ORDER)
are kept. Each run writes its CSV + PNGs into a fresh --results-dir/<timestamp>/.

    python scripts/0_misc/summarize_visualize_results.py
    python scripts/0_misc/summarize_visualize_results.py --all-runs
    python scripts/0_misc/summarize_visualize_results.py --no-plot
"""
from __future__ import annotations

import argparse
import datetime
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # headless-safe backend; this script has no interactive display
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns
from scipy import stats

from inspect_ai.log import list_eval_logs, read_eval_log

# Running as `python scripts/0_misc/summarize_visualize_results.py` puts the
# script's own dir on sys.path, not the project root, so `import src.roster`
# needs an explicit assist (same shim the task files use).
PROJECT_ROOT = Path(__file__).parent.parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

# Model identity constants come from the shared roster — see src/roster.py.
from src.roster import (
    FAMILY_CHRONOLOGICAL_ORDER,
    FAMILY_COLORS,
    FAMILY_ORDER,
    MODEL_RELEASE_DATE,
    MODEL_TYPE,
    TYPE_COLORS,
    TYPE_ORDER,
    model_family,
    model_release_date,
    model_sort_key,
    model_type,
)

# The developmental-construct grouping over the 12 dimensions — single source of
# truth in src/constructs.py, also written into the datasets by
# scripts/0_misc/add_construct_to_datasets.py.
from src.constructs import (
    CONSTRUCT_COLORS,
    CONSTRUCT_DEVELOPMENTAL_ORDER,
    DIMENSION_DEVELOPMENTAL_ORDER,
    construct_for_dimension,
    construct_sort_key,
    dimension_sort_key,
)

TASK_NAMES = {"tom_12dim_mcq", "tom_12dim_freeresponse"}
OVERALL_LABEL = "ALL (overall)"

def collect_rows(log_dir: str) -> list[dict]:
    rows: list[dict] = []
    # recursive=False: a logs/Archive/ subfolder (see the runAll scripts, which move
    # every prior run's logs there before starting a new one) is deliberately not
    # scanned, so this only ever reflects the most recent run.
    for info in list_eval_logs(log_dir, formats=["eval"], recursive=False):
        log = read_eval_log(info, header_only=True)
        task_name = log.eval.task
        if task_name not in TASK_NAMES:
            continue
        family = model_family(log.eval.model)
        if family not in FAMILY_ORDER:
            print(f"skipping {info.name}: model '{log.eval.model}' is not in a "
                  f"recognized open-weight family {FAMILY_ORDER} (stale/out-of-scope log?)",
                  file=sys.stderr)
            continue
        if log.status != "success":
            print(f"skipping {info.name}: status={log.status}", file=sys.stderr)
            continue
        if log.results is None:
            continue

        for score in log.results.scores:
            overall: dict[str, float] = {}
            per_dim_acc: dict[str, float] = {}
            per_dim_stderr: dict[str, float] = {}
            for metric_name, metric in score.metrics.items():
                if metric_name in ("accuracy", "stderr"):
                    overall[metric_name] = metric.value
                elif metric_name.startswith("accuracy/"):
                    per_dim_acc[metric_name.split("/", 1)[1]] = metric.value
                elif metric_name.startswith("stderr/"):
                    per_dim_stderr[metric_name.split("/", 1)[1]] = metric.value

            base = {
                "model": log.eval.model,
                "task": task_name,
                "created": log.eval.created,
                "log_file": info.name,
            }
            for dim, acc in per_dim_acc.items():
                rows.append({**base, "dimension": dim,
                             "construct": construct_for_dimension(dim),
                             "accuracy": acc, "stderr": per_dim_stderr.get(dim)})
            if "accuracy" in overall:
                rows.append({**base, "dimension": OVERALL_LABEL, "construct": OVERALL_LABEL,
                             "accuracy": overall.get("accuracy"),
                             "stderr": overall.get("stderr")})
    return rows


def build_model_pivot(df: pd.DataFrame, task: str | None = None) -> pd.DataFrame:
    """One row per individual model (not collapsed into a family average), one
    column per ToM dimension (+ overall). If `task` is given, restricts to that
    task only; otherwise averages a model's own mcq + freeresponse runs together.
    Rows are ordered family-by-family, oldest to newest within each family.
    Columns are ordered by developmental acquisition age, earliest first."""
    subset = df if task is None else df[df["task"] == task]
    pivot = subset.pivot_table(index="model", columns="dimension", values="accuracy", aggfunc="mean")

    cols = sorted((c for c in pivot.columns if c != OVERALL_LABEL), key=dimension_sort_key)
    if OVERALL_LABEL in pivot.columns:
        cols.append(OVERALL_LABEL)
    ordered_rows = sorted(pivot.index, key=model_sort_key)
    return pivot.loc[ordered_rows, cols]


def _short_name(model: str) -> str:
    """Last path segment of an OpenRouter model string, for compact plot labels:
    'openrouter/meta-llama/llama-3.1-8b-instruct' -> 'llama-3.1-8b-instruct'."""
    return model.split("/")[-1]


def plot_heatmap(pivot: pd.DataFrame, out_dir: Path, filename: str, title: str) -> Path:
    """Save a single seaborn heatmap of accuracy (rows=individual model, cols=dimension),
    with a horizontal rule marking each boundary between families."""
    display_index = [_short_name(m) for m in pivot.index]
    longest_row_label = max((len(s) for s in display_index), default=10)
    fig_width = 1.1 * len(pivot.columns) + 0.12 * longest_row_label + 2
    fig_height = 0.55 * len(pivot.index) + 2
    fig, ax = plt.subplots(figsize=(fig_width, fig_height))
    sns.heatmap(
        pivot.set_axis(display_index, axis=0),
        annot=True,
        fmt=".2f",
        vmin=0,
        vmax=1,
        cmap="RdYlGn",
        linewidths=0.5,
        cbar_kws={"label": "accuracy"},
        ax=ax,
    )
    ax.set_title(title)
    ax.set_xlabel("ToM dimension")
    ax.set_ylabel(None)  # model names in the tick labels already make this clear
    plt.setp(ax.get_xticklabels(), rotation=45, ha="right")
    plt.setp(ax.get_yticklabels(), rotation=0)

    # Mark family boundaries so the oldest->newest grouping is visually obvious.
    families_in_order = [model_family(m) for m in pivot.index]
    boundary = 0
    for family in FAMILY_ORDER[:-1]:
        boundary += families_in_order.count(family)
        if 0 < boundary < len(pivot.index):
            ax.axhline(boundary, color="black", linewidth=2)

    plot_path = out_dir / filename
    fig.savefig(plot_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return plot_path


def _types_present(pivot: pd.DataFrame) -> list[str]:
    types_present = [t for t in TYPE_ORDER if any(model_type(m) == t for m in pivot.index)]
    types_present += sorted({model_type(m) for m in pivot.index} - set(types_present))
    return types_present


def _plot_group_lines(
    ax: plt.Axes,
    pivot: pd.DataFrame,
    groups_present: list[str],
    group_of,
    color_of,
) -> None:
    """Plot the raw per-release accuracies as markers per GROUP on `ax`: x = real
    model release date, y = accuracy. Markers only — no connecting line (that would
    imply interpolation between releases, and zigzags misleadingly once tiers are
    mixed onto one family line); the dashed trend comes from the regression band.
    `group_of(model)` assigns a model to a group and `color_of(group)` gives its
    marker color — pass model_type/TYPE_COLORS for per-tier groups, or
    model_family/FAMILY_COLORS to collapse the tiers into one series per family.
    Models with no known release date are dropped (with a
    warning). Points on the exact same day (real same-day launches — e.g. the
    Qwen3 sizes, the two Llama 4 variants) are fanned out with a small horizontal
    jitter and their labels staggered, so they don't stack unreadably."""
    group_models: dict[str, list[str]] = {}
    for g in groups_present:
        members = [m for m in pivot.index if group_of(m) == g]
        known_models = [m for m in members if model_release_date(m) is not None]
        unknown_models = [m for m in members if model_release_date(m) is None]
        for m in unknown_models:
            print(f"dropping {m} from the trend plot: no known release date in the roster",
                  file=sys.stderr)
        known_models.sort(key=model_release_date)
        group_models[g] = known_models

    date_counts: dict[datetime.date, int] = {}
    for known_models in group_models.values():
        for m in known_models:
            d = model_release_date(m)
            date_counts[d] = date_counts.get(d, 0) + 1
    date_seen: dict[datetime.date, int] = {}
    jitter_x: dict[str, datetime.date] = {}
    label_rank: dict[str, int] = {}
    for g in groups_present:
        for m in group_models[g]:
            d = model_release_date(m)
            n = date_counts[d]
            idx = date_seen.get(d, 0)
            date_seen[d] = idx + 1
            label_rank[m] = idx
            spread_days = 0 if n <= 1 else round((idx / (n - 1) - 0.5) * 14)
            jitter_x[m] = d + datetime.timedelta(days=spread_days)

    for g in groups_present:
        known_models = group_models[g]
        if not known_models:
            continue
        y = pivot.loc[known_models, OVERALL_LABEL] if OVERALL_LABEL in pivot.columns else pivot.loc[known_models].mean(axis=1)
        x = [jitter_x[m] for m in known_models]
        # Markers only, no connecting line: the connect-the-dots line zigzags
        # misleadingly once tiers are mixed on one family line, and even per-tier
        # it implies interpolation between releases. The dashed regression line
        # (added separately) is the intended trend summary.
        ax.plot(x, y.values, marker="o", linestyle="none", label=g, color=color_of(g))
        for xi, model, yi in zip(x, known_models, y.values):
            short_name = _short_name(model)
            rank = label_rank[model]
            xytext = (3 + 4 * (rank % 3), 3 + 9 * (rank % 5))
            ax.annotate(short_name, (xi, yi), rotation=60, ha="left", va="bottom",
                        fontsize=5.5, xytext=xytext, textcoords="offset points")

    ax.axhline(0.5, color="gray", linewidth=1, linestyle="--", alpha=0.6)
    ax.text(0.005, 0.5, "chance", transform=ax.get_yaxis_transform(),
            fontsize=7, color="gray", va="bottom")
    ax.set_ylim(0.5, 1.05)
    ax.set_xlabel("model release date")
    ax.xaxis.set_major_locator(mdates.AutoDateLocator(minticks=4, maxticks=10))
    ax.xaxis.set_major_formatter(mdates.ConciseDateFormatter(ax.xaxis.get_major_locator()))


def _plot_type_lines(ax: plt.Axes, pivot: pd.DataFrame, types_present: list[str]) -> None:
    """One line per model TYPE (size tier). Thin wrapper over _plot_group_lines."""
    _plot_group_lines(ax, pivot, types_present, model_type, lambda t: TYPE_COLORS.get(t))


def _families_present(pivot: pd.DataFrame) -> list[str]:
    """Families appearing in `pivot`, in canonical FAMILY_ORDER."""
    return [f for f in FAMILY_ORDER if any(model_family(m) == f for m in pivot.index)]


def _plot_family_lines(ax: plt.Axes, pivot: pd.DataFrame, families_present: list[str]) -> None:
    """One line per FAMILY (size tiers collapsed). Thin wrapper over _plot_group_lines."""
    _plot_group_lines(ax, pivot, families_present, model_family, lambda f: FAMILY_COLORS.get(f))


def _filter_family(pivot: pd.DataFrame, family: str) -> pd.DataFrame:
    """Rows for one family only (e.g. just 'Llama' or 'Qwen'), same column set and
    ordering as the input pivot — used to build the per-family heatmap/trend plots."""
    return pivot.loc[[m for m in pivot.index if model_family(m) == family]]


_MIN_POINTS_FOR_REGRESSION = 3


def _significance_stars(p: float) -> str:
    """Standard significance-star convention for a regression p-value."""
    if p < 0.001:
        return "***"
    if p < 0.01:
        return "**"
    if p < 0.05:
        return "*"
    return "ns"


def _add_regression_band_grouped(
    ax: plt.Axes,
    pivot: pd.DataFrame,
    groups_present: list[str],
    group_of,
    color_of,
) -> None:
    """Overlay one linear regression line + shaded 95% CI band PER GROUP present in
    `pivot`. `group_of`/`color_of` select the grouping: model_type/TYPE_COLORS for
    a regression per size tier (never pooled), or model_family/FAMILY_COLORS for one
    pooled regression per family (tiers collapsed). Each group's regression uses only
    its own release-dated points, drawn dashed in its color to pair with its markers.
    Fit uses the real (unjittered) release dates.

    Each group's regression p-value (two-sided t-test on the slope, via
    scipy.stats.linregress) goes in its legend label; a significance-star annotation
    per group is stacked in the top-left corner, color-matched. A group is silently
    skipped (not the whole plot) if it has fewer than _MIN_POINTS_FOR_REGRESSION dated
    points, or if they all share one date."""
    stars_line = 0
    for g in groups_present:
        models = [m for m in pivot.index
                  if group_of(m) == g and model_release_date(m) is not None]
        if len(models) < _MIN_POINTS_FOR_REGRESSION:
            continue
        x = mdates.date2num([model_release_date(m) for m in models])
        if len(set(x)) < 2:
            continue
        y = (pivot.loc[models, OVERALL_LABEL] if OVERALL_LABEL in pivot.columns
             else pivot.loc[models].mean(axis=1)).values

        fit = stats.linregress(x, y)
        stars = _significance_stars(fit.pvalue)
        color = color_of(g) or "black"

        sns.regplot(x=x, y=y, ci=95, scatter=False, ax=ax, color=color,
                    label=f"{g} trend (95% CI), p={fit.pvalue:.3f}",
                    line_kws={"linewidth": 1.3, "linestyle": "--", "alpha": 0.8})
        ax.text(0.02, 0.97 - 0.035 * stars_line, f"{g}: {stars}",
                transform=ax.transAxes, ha="left", va="top", fontsize=7.5,
                fontweight="bold" if stars != "ns" else "normal", color=color)
        stars_line += 1


def _add_regression_band(ax: plt.Axes, pivot: pd.DataFrame) -> None:
    """Per-model-type regression bands (never pooled across types, never collapsed
    to one line per family). Thin wrapper over _add_regression_band_grouped."""
    _add_regression_band_grouped(ax, pivot, _types_present(pivot), model_type,
                                 lambda t: TYPE_COLORS.get(t, "black"))


def plot_model_type_trend(
    pivot: pd.DataFrame,
    out_dir: Path,
    filename: str = "dimension_trend_by_family.png",
    title: str = "Overall accuracy by release date, within each model type",
) -> Path:
    """Line chart: overall accuracy vs. release date, one line per model TYPE
    (size tier). Each tier has its own multi-release history worth trending on its
    own line; a single per-family line would hide whether a given tier improved
    release over release. Also overlays one linear regression line + 95% CI band
    per model type present (see _add_regression_band)."""
    types_present = _types_present(pivot)
    fig, ax = plt.subplots(figsize=(max(8, 1.1 * len(pivot.index) / max(len(types_present), 1)), 7.5))

    _plot_type_lines(ax, pivot, types_present)
    _add_regression_band(ax, pivot)
    ax.set_ylabel("overall accuracy")
    ax.set_title(title)
    ax.legend(title="model type", bbox_to_anchor=(1.02, 1), loc="upper left")

    plot_path = out_dir / filename
    fig.savefig(plot_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return plot_path


def plot_family_trend(
    pivot: pd.DataFrame,
    out_dir: Path,
    filename: str = "dimension_trend_family_collapsed.png",
    title: str = "Overall accuracy by release date, one line per family (size tiers collapsed)",
) -> Path:
    """Line chart: overall accuracy vs. release date, ONE line per family — the size
    tiers (small/mid/large/frontier, and DeepSeek's V/R) collapsed into a single
    per-family trajectory. Overlays one pooled linear regression line + 95% CI band
    per family (see _add_regression_band_grouped). This is the family-level companion
    to plot_model_type_trend, which keeps the tiers as separate lines; use this when
    you want the coarser "is this family improving over time?" read without per-tier
    detail."""
    families_present = _families_present(pivot)
    fig, ax = plt.subplots(figsize=(max(8, 1.1 * len(pivot.index) / max(len(families_present), 1)), 7.5))

    _plot_family_lines(ax, pivot, families_present)
    _add_regression_band_grouped(ax, pivot, families_present, model_family,
                                 lambda f: FAMILY_COLORS.get(f, "black"))
    ax.set_ylabel("overall accuracy")
    ax.set_title(title)
    ax.legend(title="family", bbox_to_anchor=(1.02, 1), loc="upper left")

    plot_path = out_dir / filename
    fig.savefig(plot_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return plot_path


def plot_model_type_trend_by_task(df: pd.DataFrame, out_dir: Path) -> Path:
    """Same model-type trend lines as plot_model_type_trend, but as two side-by-side
    subplots — one for tom_12dim_mcq, one for tom_12dim_freeresponse — so you can see
    whether a release-over-release pattern holds for both question formats. Each
    subplot also overlays one regression line + 95% CI band per model type present."""
    task_panels = [
        ("tom_12dim_mcq", "MCQ / true-false"),
        ("tom_12dim_freeresponse", "Free response"),
    ]
    fig, axes = plt.subplots(1, 2, figsize=(18, 7.5), sharey=True)

    legend_handles, legend_labels = [], []
    for ax, (task_name, title) in zip(axes, task_panels):
        if task_name not in df["task"].unique():
            ax.set_title(f"{title} (no data)")
            ax.set_ylim(0.5, 1.05)
            continue
        task_pivot = build_model_pivot(df, task=task_name)
        types_present = _types_present(task_pivot)
        _plot_type_lines(ax, task_pivot, types_present)
        _add_regression_band(ax, task_pivot)
        ax.set_title(title)
        handles, labels = ax.get_legend_handles_labels()
        if len(labels) > len(legend_labels):
            legend_handles, legend_labels = handles, labels

    axes[0].set_ylabel("overall accuracy")
    if legend_handles:
        fig.legend(legend_handles, legend_labels, title="model type",
                   bbox_to_anchor=(1.0, 0.9), loc="upper left")
    fig.suptitle("Overall accuracy by release date, within each model type — MCQ vs. free response")

    plot_path = out_dir / "dimension_trend_by_task.png"
    fig.savefig(plot_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return plot_path


def plot_model_type_trend_by_task_for_family(df: pd.DataFrame, family: str, out_dir: Path) -> Path:
    """Same as plot_model_type_trend_by_task, scoped to one family, with a regression
    line + 95% CI band overlaid on each subplot — the per-type lines show tier-by-tier
    detail, the regression summarizes the aggregate release-over-release trend."""
    task_panels = [
        ("tom_12dim_mcq", "MCQ / true-false"),
        ("tom_12dim_freeresponse", "Free response"),
    ]
    fig, axes = plt.subplots(1, 2, figsize=(18, 7.5), sharey=True)

    legend_handles, legend_labels = [], []
    for ax, (task_name, title) in zip(axes, task_panels):
        if task_name not in df["task"].unique():
            ax.set_title(f"{title} (no data)")
            ax.set_ylim(0.5, 1.05)
            continue
        task_pivot = _filter_family(build_model_pivot(df, task=task_name), family)
        if task_pivot.empty:
            ax.set_title(f"{title} (no {family} data)")
            ax.set_ylim(0.5, 1.05)
            continue
        types_present = _types_present(task_pivot)
        _plot_type_lines(ax, task_pivot, types_present)
        _add_regression_band(ax, task_pivot)
        ax.set_title(title)
        handles, labels = ax.get_legend_handles_labels()
        if len(labels) > len(legend_labels):
            legend_handles, legend_labels = handles, labels

    axes[0].set_ylabel("overall accuracy")
    if legend_handles:
        fig.legend(legend_handles, legend_labels, title="model type",
                   bbox_to_anchor=(1.0, 0.9), loc="upper left")
    fig.suptitle(f"Overall accuracy by release date, within each model type — "
                 f"MCQ vs. free response ({family} only)")

    plot_path = out_dir / f"dimension_trend_{family}_by_task.png"
    fig.savefig(plot_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return plot_path


_DIMENSION_GRID_SHAPE = (3, 4)  # rows, cols — fits all 12 DIMENSION_DEVELOPMENTAL_ORDER dims
_POOLED_REGRESSION_COLOR = "#333333"  # charcoal — used only when a subplot has one pooled line


def _fit_and_plot_regression_line(
    ax: plt.Axes, models: list[str], y_values, color: str, label_prefix: str
) -> float | None:
    """Fit a linear regression (scipy.stats.linregress) of accuracy vs. real release
    date across `models`/`y_values`, draw the data points + fit line + 95% CI band via
    seaborn regplot on `ax`, with a legend label combining `label_prefix` and the
    p-value/significance stars. Returns the p-value, or None if skipped (fewer than
    _MIN_POINTS_FOR_REGRESSION dated, non-NaN points, or all dates identical)."""
    dated = [(m, y) for m, y in zip(models, y_values)
             if model_release_date(m) is not None and pd.notna(y)]
    if len(dated) < _MIN_POINTS_FOR_REGRESSION:
        return None
    x = mdates.date2num([model_release_date(m) for m, _ in dated])
    if len(set(x)) < 2:
        return None
    y = [yv for _, yv in dated]

    fit = stats.linregress(x, y)
    stars = _significance_stars(fit.pvalue)
    sns.regplot(x=x, y=y, ci=95, scatter=True, ax=ax, color=color,
                label=f"{label_prefix} (p={fit.pvalue:.3f} {stars})",
                scatter_kws={"s": 14, "alpha": 0.75},
                line_kws={"linewidth": 1.2, "linestyle": "--", "alpha": 0.85})
    return fit.pvalue


def plot_dimension_regression_grid(
    df: pd.DataFrame, family: str, out_dir: Path, split_by_type: bool
) -> Path:
    """Free-response-only grid of small subplots, one per ToM dimension
    (developmental order), each showing a linear regression + 95% CI + significance
    of that dimension's accuracy vs. release date, scoped to one family.

    If split_by_type is False, each subplot pools every tier for that family into ONE
    regression line — answers "is this family improving on THIS dimension over time?"
    If True, each subplot draws one regression line per tier present instead — same
    question per tier. A subplot shows a "not enough data" placeholder rather than an
    empty/broken axis if every line in it would be skipped."""
    task_pivot = _filter_family(build_model_pivot(df, task="tom_12dim_freeresponse"), family)
    dims = [c for c in task_pivot.columns if c != OVERALL_LABEL]

    rows, cols = _DIMENSION_GRID_SHAPE
    fig, axes = plt.subplots(rows, cols, figsize=(cols * 4.5, rows * 3.5), sharex=True, sharey=True)
    axes_flat = axes.flatten()

    for ax, dim in zip(axes_flat, dims):
        ax.axhline(0.5, color="gray", linewidth=1, linestyle="--", alpha=0.5)
        any_line = False
        if split_by_type:
            for t in _types_present(task_pivot):
                type_models = [m for m in task_pivot.index if model_type(m) == t]
                p = _fit_and_plot_regression_line(
                    ax, type_models, task_pivot.loc[type_models, dim].values, TYPE_COLORS.get(t, "black"), t)
                any_line = any_line or (p is not None)
        else:
            p = _fit_and_plot_regression_line(
                ax, list(task_pivot.index), task_pivot[dim].values, _POOLED_REGRESSION_COLOR, family)
            any_line = p is not None

        if not any_line:
            ax.text(0.5, 0.5, "insufficient data", transform=ax.transAxes,
                    ha="center", va="center", fontsize=8, color="gray")
        else:
            ax.legend(fontsize=5.5 if split_by_type else 6.5, loc="lower left")

        ax.set_title(dim, fontsize=9)
        ax.set_ylim(0.45, 1.05)
        ax.tick_params(labelsize=7)
        ax.xaxis.set_major_locator(mdates.AutoDateLocator(minticks=2, maxticks=3))
        ax.xaxis.set_major_formatter(mdates.ConciseDateFormatter(ax.xaxis.get_major_locator()))
        plt.setp(ax.get_xticklabels(), rotation=30, ha="right")

    for ax in axes_flat[len(dims):]:
        ax.axis("off")

    scope = "per model type" if split_by_type else "pooled across model types"
    fig.suptitle(f"Free-response accuracy trend by ToM dimension, {family} only "
                 f"({scope}) — developmental order, hardest-to-easiest reading order "
                 f"not implied")
    fig.tight_layout(rect=[0, 0, 1, 0.96])

    suffix = "_by_type" if split_by_type else ""
    plot_path = out_dir / f"dimension_regression_{family}_freeresponse{suffix}.png"
    fig.savefig(plot_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return plot_path


_CONSTRUCT_GRID_SHAPE = (2, 3)  # rows, cols — fits all 6 CONSTRUCT_DEVELOPMENTAL_ORDER constructs


def plot_construct_regression_grid(
    df: pd.DataFrame, family: str, out_dir: Path, split_by_type: bool
) -> Path:
    """Free-response-only grid of small subplots, one per developmental CONSTRUCT
    (construct developmental order — see CONSTRUCT_DEVELOPMENTAL_ORDER), each showing a
    linear regression + 95% CI + significance of that construct's accuracy vs. release
    date, scoped to one family only. The construct analogue of
    plot_dimension_regression_grid — coarser (6 panels, not 12), so each trend pools
    the construct's member dimensions (build_construct_pivot's unweighted mean) and is
    less noisy than any single dimension's.

    If split_by_type is False, each subplot pools every model type for that family into
    ONE regression line ("is this family improving on THIS construct over time?"). If
    True, one regression line per model type present, color-matched via TYPE_COLORS,
    never collapsed across types. A subplot shows a "not enough data" placeholder rather
    than an empty/broken axis if every line would be skipped (see
    _fit_and_plot_regression_line). Panel titles are colored by construct (CONSTRUCT_COLORS).
    """
    task_pivot = _filter_family(build_construct_pivot(df, task="tom_12dim_freeresponse"), family)
    constructs = list(task_pivot.columns)  # already construct-developmental order

    rows, cols = _CONSTRUCT_GRID_SHAPE
    fig, axes = plt.subplots(rows, cols, figsize=(cols * 4.5, rows * 3.5), sharex=True, sharey=True)
    axes_flat = axes.flatten()

    for ax, construct in zip(axes_flat, constructs):
        ax.axhline(0.5, color="gray", linewidth=1, linestyle="--", alpha=0.5)
        any_line = False
        if split_by_type:
            for t in _types_present(task_pivot):
                type_models = [m for m in task_pivot.index if model_type(m) == t]
                p = _fit_and_plot_regression_line(
                    ax, type_models, task_pivot.loc[type_models, construct].values,
                    TYPE_COLORS.get(t, "black"), t)
                any_line = any_line or (p is not None)
        else:
            p = _fit_and_plot_regression_line(
                ax, list(task_pivot.index), task_pivot[construct].values,
                _POOLED_REGRESSION_COLOR, family)
            any_line = p is not None

        if not any_line:
            ax.text(0.5, 0.5, "insufficient data", transform=ax.transAxes,
                    ha="center", va="center", fontsize=8, color="gray")
        else:
            ax.legend(fontsize=5.5 if split_by_type else 6.5, loc="lower left")

        ax.set_title(construct, fontsize=9, color=CONSTRUCT_COLORS.get(construct, "black"))
        ax.set_ylim(0.45, 1.05)
        ax.tick_params(labelsize=7)
        ax.xaxis.set_major_locator(mdates.AutoDateLocator(minticks=2, maxticks=3))
        ax.xaxis.set_major_formatter(mdates.ConciseDateFormatter(ax.xaxis.get_major_locator()))
        plt.setp(ax.get_xticklabels(), rotation=30, ha="right")

    for ax in axes_flat[len(constructs):]:
        ax.axis("off")

    scope = "per model type" if split_by_type else "pooled across model types"
    fig.suptitle(f"Free-response accuracy trend by developmental construct, {family} only "
                 f"({scope}) — construct developmental order")
    fig.tight_layout(rect=[0, 0, 1, 0.96])

    suffix = "_by_type" if split_by_type else ""
    plot_path = out_dir / f"construct_regression_{family}_freeresponse{suffix}.png"
    fig.savefig(plot_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return plot_path


def _plot_ranking_bars(ax: plt.Axes, pivot: pd.DataFrame, title: str) -> None:
    """Draw the difficulty-ranking horizontal bars (mean accuracy per dimension,
    hardest at top, error bars = std across models) onto `ax`. Shared by
    plot_dimension_ranking and plot_dimension_ranking_by_task_for_family."""
    plot_cols = [c for c in pivot.columns if c != OVERALL_LABEL]
    means = pivot[plot_cols].mean(axis=0).sort_values(ascending=False)  # easiest -> bottom, hardest -> top
    stds = pivot[plot_cols].std(axis=0).reindex(means.index).fillna(0)

    cmap = plt.get_cmap("RdYlGn")
    bar_colors = [cmap(v) for v in means.clip(0, 1)]

    ax.barh(means.index, means.values, xerr=stds.values, color=bar_colors, edgecolor="black", capsize=3)
    ax.set_xlim(0, 1.05)
    ax.set_xlabel("mean accuracy across all tested models")
    ax.set_title(title)


def plot_dimension_ranking(
    pivot: pd.DataFrame,
    out_dir: Path,
    filename: str = "dimension_difficulty_ranking.png",
    title: str = "ToM dimension difficulty ranking (hardest at top; error bars = std across models)",
) -> Path:
    """Horizontal bar chart ranking dimensions by mean accuracy across every individual
    model tested (hardest at the top), with error bars showing the spread (std)."""
    plot_cols = [c for c in pivot.columns if c != OVERALL_LABEL]
    fig, ax = plt.subplots(figsize=(8, 0.5 * len(plot_cols) + 2))
    _plot_ranking_bars(ax, pivot, title)

    plot_path = out_dir / filename
    fig.savefig(plot_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return plot_path


def plot_dimension_ranking_by_task_for_family(df: pd.DataFrame, family: str, out_dir: Path) -> Path:
    """Same difficulty ranking as plot_dimension_ranking, scoped to one family, as two
    side-by-side subplots (MCQ vs. free response) — so you can see whether the same ToM
    dimensions are hardest for that family regardless of question format."""
    task_panels = [
        ("tom_12dim_mcq", "MCQ / true-false"),
        ("tom_12dim_freeresponse", "Free response"),
    ]
    fig, axes = plt.subplots(1, 2, figsize=(16, 7))

    for ax, (task_name, title) in zip(axes, task_panels):
        if task_name not in df["task"].unique():
            ax.set_title(f"{title} (no data)")
            ax.set_xlim(0, 1.05)
            continue
        task_pivot = _filter_family(build_model_pivot(df, task=task_name), family)
        if task_pivot.empty:
            ax.set_title(f"{title} (no {family} data)")
            ax.set_xlim(0, 1.05)
            continue
        _plot_ranking_bars(ax, task_pivot, title)

    fig.suptitle(f"ToM dimension difficulty ranking, {family} only — MCQ vs. free response "
                 f"(hardest at top; error bars = std across models)")

    plot_path = out_dir / f"dimension_difficulty_ranking_{family}_by_task.png"
    fig.savefig(plot_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return plot_path


# ------------------------------------------------------------------------------
# Construct-level views: the six developmental constructs (src/constructs.py) as a
# practical grouping over the 12 dimensions. A construct's per-model accuracy is
# the UNWEIGHTED mean of its member dimensions' accuracies — the same currency the
# per-dimension heatmaps use, aggregated one level up.
# ------------------------------------------------------------------------------

def task_label_slug(task_name: str) -> str:
    """'tom_12dim_mcq' -> 'mcq', 'tom_12dim_freeresponse' -> 'freeresponse'."""
    return task_name.replace("tom_12dim_", "")


def build_construct_pivot(df: pd.DataFrame, task: str | None = None) -> pd.DataFrame:
    """One row per model, one column per construct (developmental order). Averages
    the per-dimension accuracies within each construct (unweighted). Excludes the
    OVERALL rows. Rows ordered oldest->newest within family, like build_model_pivot."""
    subset = df[df["dimension"] != OVERALL_LABEL]
    if task is not None:
        subset = subset[subset["task"] == task]
    subset = subset[subset["construct"].notna() & (subset["construct"] != OVERALL_LABEL)]
    pivot = subset.pivot_table(index="model", columns="construct", values="accuracy", aggfunc="mean")

    cols = sorted(pivot.columns, key=construct_sort_key)
    ordered_rows = sorted(pivot.index, key=model_sort_key)
    return pivot.loc[ordered_rows, cols]


def plot_construct_heatmap(pivot: pd.DataFrame, out_dir: Path, filename: str, title: str) -> Path:
    """Heatmap of accuracy, rows = individual model (oldest->newest within family,
    short-named), columns = the six developmental constructs. x tick labels colored
    by construct (CONSTRUCT_COLORS); family boundaries drawn as horizontal rules."""
    display_index = [_short_name(m) for m in pivot.index]
    fig_width = 1.7 * len(pivot.columns) + 3
    fig_height = 0.55 * len(pivot.index) + 2
    fig, ax = plt.subplots(figsize=(fig_width, fig_height))
    sns.heatmap(pivot.set_axis(display_index, axis=0), annot=True, fmt=".2f", vmin=0, vmax=1,
                cmap="RdYlGn", linewidths=0.5, cbar_kws={"label": "accuracy"}, ax=ax)
    ax.set_title(title)
    ax.set_xlabel("developmental construct")
    ax.set_ylabel(None)
    plt.setp(ax.get_xticklabels(), rotation=30, ha="right")
    for lbl in ax.get_xticklabels():
        lbl.set_color(CONSTRUCT_COLORS.get(lbl.get_text(), "black"))
    plt.setp(ax.get_yticklabels(), rotation=0)

    families_in_order = [model_family(m) for m in pivot.index]
    boundary = 0
    for family in FAMILY_ORDER[:-1]:
        boundary += families_in_order.count(family)
        if 0 < boundary < len(pivot.index):
            ax.axhline(boundary, color="black", linewidth=2)

    plot_path = out_dir / filename
    fig.savefig(plot_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return plot_path


def plot_dimension_heatmap_by_construct(pivot: pd.DataFrame, out_dir: Path,
                                        filename: str, title: str) -> Path:
    """The per-DIMENSION heatmap, columns regrouped so the 12 dimensions sit under
    their construct (construct developmental order; dimensions in developmental order
    within each construct), with a colored construct band + label above each group and
    vertical separators between groups."""
    dim_cols = [c for c in pivot.columns if c != OVERALL_LABEL]
    ordered_dims = sorted(
        dim_cols,
        key=lambda d: (construct_sort_key(construct_for_dimension(d) or "")[0],
                       dimension_sort_key(d)))
    cols = ordered_dims + ([OVERALL_LABEL] if OVERALL_LABEL in pivot.columns else [])
    grouped = pivot[cols]

    display_index = [_short_name(m) for m in grouped.index]
    longest_row_label = max((len(s) for s in display_index), default=10)
    fig_width = 1.1 * len(grouped.columns) + 0.12 * longest_row_label + 2
    fig_height = 0.55 * len(grouped.index) + 2.6
    fig, ax = plt.subplots(figsize=(fig_width, fig_height))
    sns.heatmap(grouped.set_axis(display_index, axis=0), annot=True, fmt=".2f", vmin=0, vmax=1,
                cmap="RdYlGn", linewidths=0.5, cbar_kws={"label": "accuracy"}, ax=ax)
    ax.set_title(title, pad=28)
    ax.set_xlabel(None)
    ax.set_ylabel(None)
    plt.setp(ax.get_xticklabels(), rotation=45, ha="right")
    plt.setp(ax.get_yticklabels(), rotation=0)

    start = 0
    for construct in CONSTRUCT_DEVELOPMENTAL_ORDER:
        members = [d for d in ordered_dims if construct_for_dimension(d) == construct]
        if not members:
            continue
        end = start + len(members)
        if start > 0:
            ax.axvline(start, color="black", linewidth=2)
        color = CONSTRUCT_COLORS.get(construct, "black")
        ax.text((start + end) / 2, -0.6, construct, ha="center", va="bottom",
                fontsize=8, fontweight="bold", color=color, clip_on=False)
        ax.plot([start + 0.06, end - 0.06], [-0.15, -0.15], color=color, linewidth=3, clip_on=False)
        start = end
    if OVERALL_LABEL in cols and start < len(cols):
        ax.axvline(start, color="gray", linewidth=1.5, linestyle="--")

    plot_path = out_dir / filename
    fig.savefig(plot_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return plot_path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--log-dir", default="logs", help="directory to scan for .eval logs (default: logs)")
    ap.add_argument("--results-dir", default="results",
                     help="parent directory; each run writes its CSV + PNGs into a "
                          "timestamped subfolder here (default: results)")
    ap.add_argument("--all-runs", action="store_true",
                     help="keep every matching run instead of only the latest per (model, task)")
    ap.add_argument("--no-plot", action="store_true", help="skip writing the seaborn PNGs")
    args = ap.parse_args()

    sns.set_theme(style="white")

    rows = collect_rows(args.log_dir)
    if not rows:
        print(f"No tom_12dim_mcq / tom_12dim_freeresponse logs with per-dimension metrics found under "
              f"{args.log_dir}/. Run scripts/2a_runMCQ, scripts/2b_runFR, or scripts/3_runAll first.")
        return 1

    df = pd.DataFrame(rows)

    if not args.all_runs:
        latest = df.groupby(["model", "task"])["created"].transform("max")
        df = df[df["created"] == latest]

    run_stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir = Path(args.results_dir) / run_stamp
    run_dir.mkdir(parents=True, exist_ok=True)
    out_path = run_dir / "dimension_summary.csv"
    df.sort_values(["task", "model", "dimension"]).to_csv(out_path, index=False)
    print(f"Wrote {len(df)} rows to {out_path}")

    for task_name, task_df in df.groupby("task"):
        print(f"\n=== {task_name}: accuracy by dimension ===")
        pivot = build_model_pivot(task_df)
        print(pivot.round(3).to_string())
        print(f"\n=== {task_name}: accuracy by developmental construct ===")
        print(build_construct_pivot(task_df).round(3).to_string())

    if not args.no_plot:
        plot_dir = run_dir
        print()

        combined_pivot = build_model_pivot(df)
        plot_path = plot_heatmap(combined_pivot, plot_dir, "dimension_heatmap.png",
                                  "Accuracy by ToM dimension (per model, oldest -> newest within family, both tasks combined)")
        print(f"Wrote combined heatmap to {plot_path}")

        # Construct-level companions to the combined dimension heatmap.
        grouped_path = plot_dimension_heatmap_by_construct(
            combined_pivot, plot_dir, "dimension_heatmap_by_construct.png",
            "Accuracy by ToM dimension, grouped under developmental construct (both tasks combined)")
        print(f"Wrote construct-grouped dimension heatmap to {grouped_path}")

        combined_construct_pivot = build_construct_pivot(df)
        construct_heatmap_path = plot_construct_heatmap(
            combined_construct_pivot, plot_dir, "construct_heatmap.png",
            "Accuracy by developmental construct (per model, oldest -> newest within family, both tasks combined)")
        print(f"Wrote construct heatmap to {construct_heatmap_path}")

        for task_name, task_label, heatmap_filename, ranking_filename in [
            ("tom_12dim_mcq", "MCQ/true-false", "dimension_heatmap_mcq.png",
             "dimension_difficulty_ranking_mcq.png"),
            ("tom_12dim_freeresponse", "free-response", "dimension_heatmap_freeresponse.png",
             "dimension_difficulty_ranking_freeresponse.png"),
        ]:
            if task_name not in df["task"].unique():
                print(f"Skipping {heatmap_filename}/{ranking_filename}: no {task_name} logs found")
                continue
            task_pivot = build_model_pivot(df, task=task_name)
            plot_path = plot_heatmap(
                task_pivot, plot_dir, heatmap_filename,
                f"Accuracy by ToM dimension (per model, oldest -> newest within family, {task_label} only)")
            print(f"Wrote {task_name} heatmap to {plot_path}")

            task_ranking_path = plot_dimension_ranking(
                task_pivot, plot_dir, filename=ranking_filename,
                title=f"ToM dimension difficulty ranking, {task_label} only "
                      f"(hardest at top; error bars = std across models)")
            print(f"Wrote {task_name} dimension difficulty ranking to {task_ranking_path}")

            task_construct_pivot = build_construct_pivot(df, task=task_name)
            construct_task_heatmap = plot_construct_heatmap(
                task_construct_pivot, plot_dir, f"construct_heatmap_{task_label_slug(task_name)}.png",
                f"Accuracy by developmental construct (per model, oldest -> newest within family, {task_label} only)")
            print(f"Wrote {task_name} construct heatmap to {construct_task_heatmap}")

            construct_task_ranking = plot_dimension_ranking(
                task_construct_pivot, plot_dir,
                filename=f"construct_difficulty_ranking_{task_label_slug(task_name)}.png",
                title=f"Developmental-construct difficulty ranking, {task_label} only "
                      f"(hardest at top; error bars = std across models)")
            print(f"Wrote {task_name} construct difficulty ranking to {construct_task_ranking}")

        trend_path = plot_model_type_trend(combined_pivot, plot_dir)
        print(f"Wrote model-type trend line chart to {trend_path}")

        family_collapsed_path = plot_family_trend(combined_pivot, plot_dir)
        print(f"Wrote family-collapsed trend line chart to {family_collapsed_path}")

        trend_by_task_path = plot_model_type_trend_by_task(df, plot_dir)
        print(f"Wrote model-type trend by task chart to {trend_by_task_path}")

        for family in FAMILY_ORDER:
            family_pivot = _filter_family(combined_pivot, family)
            if family_pivot.empty:
                print(f"Skipping {family}-only heatmap/trend: no {family} models in this run")
                continue
            family_heatmap_path = plot_heatmap(
                family_pivot, plot_dir, f"dimension_heatmap_{family}.png",
                f"Accuracy by ToM dimension (per model, oldest -> newest, {family} only, both tasks combined)")
            print(f"Wrote {family}-only heatmap to {family_heatmap_path}")

            family_trend_path = plot_model_type_trend(
                family_pivot, plot_dir, filename=f"dimension_trend_{family}.png",
                title=f"Overall accuracy by release date, within each model type ({family} only)")
            print(f"Wrote {family}-only trend line chart to {family_trend_path}")

            family_trend_by_task_path = plot_model_type_trend_by_task_for_family(df, family, plot_dir)
            print(f"Wrote {family}-only trend by task chart (with regression) to {family_trend_by_task_path}")

            family_ranking_path = plot_dimension_ranking(
                family_pivot, plot_dir, filename=f"dimension_difficulty_ranking_{family}.png",
                title=f"ToM dimension difficulty ranking, {family} only "
                      f"(hardest at top; error bars = std across models)")
            print(f"Wrote {family}-only dimension difficulty ranking to {family_ranking_path}")

            family_ranking_by_task_path = plot_dimension_ranking_by_task_for_family(df, family, plot_dir)
            print(f"Wrote {family}-only dimension difficulty ranking by task to {family_ranking_by_task_path}")

            family_construct_pivot = _filter_family(combined_construct_pivot, family)
            if not family_construct_pivot.empty:
                family_construct_heatmap = plot_construct_heatmap(
                    family_construct_pivot, plot_dir, f"construct_heatmap_{family}.png",
                    f"Accuracy by developmental construct (per model, oldest -> newest, {family} only, both tasks combined)")
                print(f"Wrote {family}-only construct heatmap to {family_construct_heatmap}")

                family_construct_ranking = plot_dimension_ranking(
                    family_construct_pivot, plot_dir, filename=f"construct_difficulty_ranking_{family}.png",
                    title=f"Developmental-construct difficulty ranking, {family} only "
                          f"(hardest at top; error bars = std across models)")
                print(f"Wrote {family}-only construct difficulty ranking to {family_construct_ranking}")

            if "tom_12dim_freeresponse" not in df["task"].unique():
                print(f"Skipping {family}-only dimension-wise regression grids: no free-response logs found")
            else:
                pooled_path = plot_dimension_regression_grid(df, family, plot_dir, split_by_type=False)
                print(f"Wrote {family}-only per-dimension regression grid (pooled across types) to {pooled_path}")

                by_type_path = plot_dimension_regression_grid(df, family, plot_dir, split_by_type=True)
                print(f"Wrote {family}-only per-dimension regression grid (by type) to {by_type_path}")

                construct_pooled_path = plot_construct_regression_grid(df, family, plot_dir, split_by_type=False)
                print(f"Wrote {family}-only per-construct regression grid (pooled across types) to {construct_pooled_path}")

                construct_by_type_path = plot_construct_regression_grid(df, family, plot_dir, split_by_type=True)
                print(f"Wrote {family}-only per-construct regression grid (by type) to {construct_by_type_path}")

        ranking_path = plot_dimension_ranking(combined_pivot, plot_dir)
        print(f"Wrote dimension difficulty ranking to {ranking_path}")

        construct_ranking_path = plot_dimension_ranking(
            combined_construct_pivot, plot_dir, filename="construct_difficulty_ranking.png",
            title="Developmental-construct difficulty ranking "
                  "(hardest at top; error bars = std across models)")
        print(f"Wrote construct difficulty ranking to {construct_ranking_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
