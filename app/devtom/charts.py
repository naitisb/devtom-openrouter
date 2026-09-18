"""Plotly figures.

The visual grammar deliberately mirrors the R figures so the app and the paper
figures read as one body of work: grey rectangles for the normative
developmental window, a dashed rule at the passing age, faded dots for
individual models, bold connected dots for tier means.
"""
from __future__ import annotations

import numpy as np
import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots

from . import constants as K
from . import theme as T


def _dimension_axis(dimensions: list[str]) -> tuple[list[int], list[str]]:
    ranks = [K.DIMENSION_RANK[d] for d in dimensions]
    labels = [
        f"{d}<br><span style='font-size:10px;color:{T.MUTED}'>{K.DIMENSION_BAND[d][0]:g}-"
        f"{K.DIMENSION_BAND[d][1]:g} yr</span>"
        for d in dimensions
    ]
    return ranks, labels


def _add_bands(fig, dimensions: list[str], row=None, col=None) -> None:
    """Grey normative window + dashed passing age, behind everything else."""
    kwargs = {}
    if row is not None:
        kwargs = dict(row=row, col=col)
    for dim in dimensions:
        rank = K.DIMENSION_RANK[dim]
        lo, hi = K.DIMENSION_BAND[dim]
        mid = K.DIMENSION_AGE_MID[dim]
        fig.add_shape(
            type="rect",
            x0=lo, x1=hi, y0=rank - 0.42, y1=rank + 0.42,
            fillcolor=T.BAND_FILL, line=dict(width=0),
            layer="below", **kwargs,
        )
        fig.add_shape(
            type="line",
            x0=mid, x1=mid, y0=rank - 0.42, y1=rank + 0.42,
            line=dict(color=T.BAND_LINE, width=1.4, dash="dash"),
            layer="below", **kwargs,
        )


def sawtooth_chart(
    dim_acc: pd.DataFrame,
    facet_by: str | None = "family",
    group_by: str = "tier",
    height: int = 620,
    show_models: bool = True,
    title: str | None = None,
) -> go.Figure:
    """The headline figure: developmental profile against the human sequence.

    y = the 12 ToM dimensions, earliest-acquired at the bottom.
    x = the model's age equivalent on that dimension.
    Grey band = the normative acquisition window; dashed rule = the passing age.
    Faded dots = individual models; bold connected dots = group means.

    A child-like profile would be a line rising steadily bottom-to-top and
    sitting inside the grey bands. Departures from that are the finding.
    """
    dimensions = [d for d in K.DIMENSION_ORDER if d in set(dim_acc["tom_dimension"])]
    ranks, labels = _dimension_axis(dimensions)

    facets = (
        [f for f in T.family_order() if f in set(dim_acc[facet_by])]
        if facet_by
        else [None]
    )
    if not facets:
        facets = [None]

    fig = make_subplots(
        rows=1,
        cols=len(facets),
        shared_yaxes=True,
        horizontal_spacing=0.012,
        subplot_titles=[f or "" for f in facets],
    )

    groups = T.tier_order(sorted(dim_acc[group_by].dropna().unique().tolist()))
    palette = (
        T.tier_colors(groups) if group_by == "tier" else T.family_colors()
    )
    seen_legend: set[str] = set()

    for i, facet in enumerate(facets, start=1):
        block = dim_acc if facet is None else dim_acc[dim_acc[facet_by] == facet]
        _add_bands(fig, dimensions, row=1, col=i)

        if show_models:
            fig.add_trace(
                go.Scatter(
                    x=block["age_equiv"],
                    y=block["rank"] + np.random.default_rng(7).uniform(
                        -0.16, 0.16, len(block)
                    ),
                    mode="markers",
                    marker=dict(
                        size=6,
                        color=[palette.get(g, T.MUTED) for g in block[group_by]],
                        opacity=0.30,
                        line=dict(width=0),
                    ),
                    hovertemplate=(
                        "<b>%{customdata[0]}</b><br>%{customdata[1]}<br>"
                        "accuracy %{customdata[2]:.0%}<br>"
                        "age equivalent %{x:.1f} yr<extra></extra>"
                    ),
                    customdata=np.stack(
                        [block["short_model"], block["tom_dimension"], block["accuracy"]],
                        axis=-1,
                    ),
                    showlegend=False,
                ),
                row=1, col=i,
            )

        for group, gdf in block.groupby(group_by):
            means = (
                gdf.groupby(["tom_dimension", "rank"], as_index=False)
                .agg(age_equiv=("age_equiv", "mean"), accuracy=("accuracy", "mean"),
                     n_models=("model", "nunique"))
                .sort_values("rank")
            )
            show = group not in seen_legend
            seen_legend.add(group)
            fig.add_trace(
                go.Scatter(
                    x=means["age_equiv"],
                    y=means["rank"],
                    mode="lines+markers",
                    name=str(group),
                    legendgroup=str(group),
                    showlegend=show,
                    line=dict(color=palette.get(group, T.MUTED), width=2),
                    marker=dict(
                        size=9,
                        color=palette.get(group, T.MUTED),
                        line=dict(color="white", width=1.2),
                    ),
                    hovertemplate=(
                        f"<b>{group}</b><br>%{{customdata[0]}}<br>"
                        "mean accuracy %{customdata[1]:.0%}<br>"
                        "mean age equivalent %{x:.1f} yr<br>"
                        "%{customdata[2]} model(s)<extra></extra>"
                    ),
                    customdata=np.stack(
                        [means["tom_dimension"], means["accuracy"], means["n_models"]],
                        axis=-1,
                    ),
                ),
                row=1, col=i,
            )

        fig.update_xaxes(
            range=[K.AGE_MIN - 0.4, K.AGE_MAX + 0.4],
            title_text="age equivalent (yr)" if i == (len(facets) + 1) // 2 else "",
            row=1, col=i,
        )

    fig.update_yaxes(
        tickmode="array",
        tickvals=ranks,
        ticktext=labels,
        range=[-0.6, len(dimensions) - 0.4],
        showgrid=False,
        row=1, col=1,
    )
    fig.update_layout(
        height=height,
        title=title,
        legend=dict(orientation="h", yanchor="bottom", y=-0.16, xanchor="left", x=0),
        margin=dict(l=10, r=10, t=56, b=70),
    )
    for annotation in fig.layout.annotations:
        annotation.font.update(size=12, color=T.INK)
    return fig


def profile_lines(
    dim_acc: pd.DataFrame,
    color_by: str = "family",
    height: int = 420,
    highlight: str | None = None,
) -> go.Figure:
    """Accuracy across the 12 dimensions, one thin line per model.

    The accuracy-space companion to the sawtooth chart — useful because it makes
    no modelling assumption at all: it is just the raw scores in developmental
    order.
    """
    dimensions = [d for d in K.DIMENSION_ORDER if d in set(dim_acc["tom_dimension"])]
    ranks, labels = _dimension_axis(dimensions)
    palette = T.family_colors() if color_by == "family" else T.tier_colors(
        sorted(dim_acc[color_by].dropna().unique().tolist())
    )

    fig = go.Figure()
    for model, group in dim_acc.groupby("model"):
        g = group.sort_values("rank")
        key = g[color_by].iloc[0]
        is_focus = highlight is not None and model == highlight
        fig.add_trace(
            go.Scatter(
                x=g["rank"],
                y=g["accuracy"],
                mode="lines+markers" if is_focus else "lines",
                name=g["short_model"].iloc[0],
                line=dict(
                    color=palette.get(key, T.MUTED),
                    width=3 if is_focus else 1.1,
                ),
                marker=dict(size=7) if is_focus else None,
                opacity=1.0 if is_focus else (0.22 if highlight else 0.45),
                hovertemplate=(
                    f"<b>{g['short_model'].iloc[0]}</b><br>"
                    "%{customdata}<br>accuracy %{y:.0%}<extra></extra>"
                ),
                customdata=g["tom_dimension"],
                showlegend=False,
            )
        )

    fig.add_hline(
        y=K.MASTERY_THRESHOLD,
        line=dict(color=T.ACCENT, width=1.4, dash="dash"),
        annotation_text="80% mastery criterion",
        annotation_position="top left",
        annotation_font=dict(size=11, color=T.ACCENT),
    )
    fig.update_xaxes(
        tickmode="array", tickvals=ranks,
        ticktext=[d.replace(" (Appearance vs. Reality)", "") for d in dimensions],
        tickangle=-38, title_text="",
    )
    fig.update_yaxes(range=[0, 1.04], tickformat=".0%", title_text="accuracy")
    fig.update_layout(height=height, margin=dict(l=10, r=10, t=30, b=120))
    return fig


def scalogram(matrix: pd.DataFrame, errors: pd.DataFrame, height: int = 640) -> go.Figure:
    """Guttman scalogram: who mastered what, with deviations marked.

    A perfect developmental scale is a staircase — every model's mastered
    dimensions form an unbroken run from the easiest. Cells outlined in orange
    break that pattern.
    """
    dimensions = list(matrix.columns)
    models = list(matrix.index)
    short = {m: T.short_model(m) for m in models}
    z = matrix.to_numpy(dtype=float)

    fig = go.Figure(
        go.Heatmap(
            z=z,
            x=[d.replace(" (Appearance vs. Reality)", "") for d in dimensions],
            y=[short[m] for m in models],
            colorscale=[[0, "#ececed"], [1, T.TEAL]],
            showscale=False,
            xgap=2,
            ygap=2,
            hovertemplate="<b>%{y}</b><br>%{x}<br>%{customdata}<extra></extra>",
            customdata=np.where(z >= 0.5, "mastered (>=80%)", "not mastered"),
        )
    )

    # Outline the cells that break the staircase.
    err_by_model = dict(zip(errors["model"], errors["guttman_errors"]))
    for yi, model in enumerate(models):
        v = matrix.loc[model].to_numpy(dtype=float)
        n = len(v)
        best_k, best_cost = 0, None
        for k in range(n + 1):
            cost = int((v[:k] == 0).sum() + (v[k:] == 1).sum())
            if best_cost is None or cost < best_cost:
                best_cost, best_k = cost, k
        for xi in range(n):
            ideal = 1.0 if xi < best_k else 0.0
            if not np.isnan(v[xi]) and v[xi] != ideal:
                fig.add_shape(
                    type="rect",
                    x0=xi - 0.5, x1=xi + 0.5, y0=yi - 0.5, y1=yi + 0.5,
                    line=dict(color=T.ACCENT, width=2.2),
                    fillcolor="rgba(0,0,0,0)",
                    layer="above",
                )

    fig.update_xaxes(tickangle=-38, side="bottom")
    fig.update_yaxes(
        autorange="reversed",
        ticktext=[
            f"{short[m]}  <span style='color:{T.ACCENT}'>"
            f"{'●' * min(int(err_by_model.get(m, 0)), 6)}</span>"
            for m in models
        ],
        tickvals=[short[m] for m in models],
        tickfont=dict(size=10),
    )
    fig.update_layout(height=height, margin=dict(l=10, r=10, t=20, b=130))
    return fig


def permutation_null_chart(
    draws: pd.DataFrame, results: pd.DataFrame, dataset: str = "pooled", height: int = 340
) -> go.Figure:
    """Where the developmental ordering falls among 10,000 random orderings."""
    d = draws[draws["dataset"] == dataset] if "dataset" in draws.columns else draws
    r = results[results["dataset"] == dataset] if "dataset" in results.columns else results

    fig = go.Figure()
    fig.add_trace(
        go.Histogram(
            x=d["perm_cr"],
            nbinsx=46,
            marker=dict(color="#d9d9de", line=dict(width=0)),
            name="random orderings",
            hovertemplate="CR %{x:.3f}<br>%{y} draws<extra></extra>",
        )
    )

    label_map = {
        "developmental": "Developmental order",
        "construct_grouped": "Construct-grouped",
        "empirical_best": "Empirical best",
        "reverse": "Reverse",
    }
    for row in r.itertuples():
        key = str(getattr(row, "order", ""))
        color = T.ORDER_COLORS.get(key, T.MUTED)
        fig.add_vline(
            x=row.CR,
            line=dict(color=color, width=2.4),
            annotation_text=label_map.get(key, key),
            annotation_position="top",
            annotation_font=dict(size=11, color=color),
        )

    fig.update_xaxes(title_text="coefficient of reproducibility")
    fig.update_yaxes(title_text="random orderings")
    fig.update_layout(height=height, showlegend=False, bargap=0.02,
                      margin=dict(l=10, r=10, t=44, b=10))
    return fig


def trajectory_chart(
    points: pd.DataFrame,
    y: str,
    color_by: str = "tier",
    trend: bool = True,
    height: int = 460,
    y_title: str = "",
    y_range: tuple[float, float] | None = None,
    y_format: str | None = None,
    hline: float | None = None,
) -> go.Figure:
    """Any per-model quantity against release date, with per-group OLS trend."""
    groups = sorted(points[color_by].dropna().unique().tolist())
    palette = (
        T.tier_colors(T.tier_order(groups)) if color_by == "tier" else T.family_colors()
    )

    fig = go.Figure()
    for group, g in points.groupby(color_by):
        g = g.sort_values("release_date")
        color = palette.get(group, T.MUTED)
        fig.add_trace(
            go.Scatter(
                x=g["release_date"], y=g[y], mode="markers", name=str(group),
                legendgroup=str(group),
                marker=dict(size=9, color=color, line=dict(color="white", width=1)),
                hovertemplate=(
                    "<b>%{customdata[0]}</b><br>%{x|%b %Y}<br>"
                    f"{y_title or y}: %{{y:.2f}}<extra></extra>"
                ),
                customdata=np.stack([g["short_model"]], axis=-1),
            )
        )
        if trend and len(g) >= 3:
            x_num = g["date_years"] if "date_years" in g else (
                g["release_date"].map(pd.Timestamp.toordinal)
            )
            mask = x_num.notna() & g[y].notna()
            if mask.sum() >= 3 and x_num[mask].std() > 0:
                slope, intercept = np.polyfit(x_num[mask], g.loc[mask, y], 1)
                xs = np.linspace(x_num[mask].min(), x_num[mask].max(), 40)
                dates = pd.to_datetime(
                    np.interp(
                        xs,
                        x_num[mask],
                        g.loc[mask, "release_date"].astype("int64"),
                    )
                )
                fig.add_trace(
                    go.Scatter(
                        x=dates, y=intercept + slope * xs, mode="lines",
                        line=dict(color=color, width=1.6, dash="solid"),
                        opacity=0.55, showlegend=False, hoverinfo="skip",
                        legendgroup=str(group),
                    )
                )

    if hline is not None:
        fig.add_hline(y=hline, line=dict(color=T.MUTED, width=1, dash="dot"))

    fig.update_xaxes(title_text="model release date")
    fig.update_yaxes(title_text=y_title or y)
    if y_range:
        fig.update_yaxes(range=list(y_range))
    if y_format:
        fig.update_yaxes(tickformat=y_format)
    fig.update_layout(height=height, margin=dict(l=10, r=10, t=30, b=10))
    return fig


def format_scatter(agreement: pd.DataFrame, height: int = 460) -> go.Figure:
    """MCQ vs free response accuracy. Distance from the diagonal = format fragility."""
    palette = T.family_colors()
    fig = go.Figure()
    fig.add_trace(
        go.Scatter(
            x=[0, 1], y=[0, 1], mode="lines",
            line=dict(color=T.MUTED, width=1, dash="dash"),
            showlegend=False, hoverinfo="skip",
        )
    )
    for family, g in agreement.groupby("family"):
        fig.add_trace(
            go.Scatter(
                x=g["MCQ"], y=g["Free response"], mode="markers", name=family,
                marker=dict(
                    size=11, color=palette.get(family, T.MUTED),
                    line=dict(color="white", width=1),
                    symbol=np.where(g["headroom"], "circle", "circle-open"),
                ),
                hovertemplate=(
                    "<b>%{customdata[0]}</b><br>MCQ %{x:.0%}<br>"
                    "Free response %{y:.0%}<extra></extra>"
                ),
                customdata=np.stack([g["short_model"]], axis=-1),
            )
        )
    fig.update_xaxes(title_text="MCQ accuracy", tickformat=".0%", range=[0, 1.03])
    fig.update_yaxes(title_text="free-response accuracy", tickformat=".0%", range=[0, 1.03])
    fig.update_layout(height=height, margin=dict(l=10, r=10, t=30, b=10))
    return fig


def dimension_heatmap(dim_acc: pd.DataFrame, height: int = 700) -> go.Figure:
    """Model x dimension accuracy, chronological down the rows."""
    dimensions = [d for d in K.DIMENSION_ORDER if d in set(dim_acc["tom_dimension"])]
    order = dim_acc.drop_duplicates("model").sort_values("release_date")
    wide = dim_acc.pivot_table(
        index="short_model", columns="tom_dimension", values="accuracy"
    )
    wide = wide.reindex(order["short_model"]).reindex(columns=dimensions)

    fig = go.Figure(
        go.Heatmap(
            z=wide.to_numpy(),
            x=[d.replace(" (Appearance vs. Reality)", "") for d in dimensions],
            y=wide.index.tolist(),
            colorscale=[[0, "#d73027"], [0.5, "#fee08b"], [1, "#1a9850"]],
            zmin=0, zmax=1, xgap=1, ygap=1,
            colorbar=dict(title="accuracy", tickformat=".0%", thickness=12, len=0.6),
            hovertemplate="<b>%{y}</b><br>%{x}<br>accuracy %{z:.0%}<extra></extra>",
        )
    )
    fig.update_xaxes(tickangle=-38)
    fig.update_yaxes(autorange="reversed", tickfont=dict(size=10))
    fig.update_layout(height=height, margin=dict(l=10, r=10, t=20, b=130))
    return fig


def coherence_scatter(
    coh: pd.DataFrame, x: str = "release_date", height: int = 420
) -> go.Figure:
    """Developmental coherence against release date or parameter count.

    Positive = child-like (stronger on the earlier, prerequisite skills).
    """
    palette = T.family_colors()
    fig = go.Figure()
    for family, g in coh.groupby("family"):
        fig.add_trace(
            go.Scatter(
                x=g[x], y=g["coherence_resid"], mode="markers", name=family,
                marker=dict(
                    size=11, color=palette.get(family, T.MUTED),
                    line=dict(color="white", width=1),
                ),
                hovertemplate=(
                    "<b>%{customdata[0]}</b><br>residual coherence %{y:+.3f}"
                    "<extra></extra>"
                ),
                customdata=np.stack([g["short_model"]], axis=-1),
            )
        )
    fig.add_hline(y=0, line=dict(color=T.MUTED, width=1, dash="dot"))
    fig.update_xaxes(
        title_text="release date" if x == "release_date" else "parameters (B)",
        type="date" if x == "release_date" else "log",
    )
    fig.update_yaxes(title_text="coherence (residualized on overall accuracy)")
    fig.update_layout(height=height, margin=dict(l=10, r=10, t=30, b=10))
    return fig


def cv_logloss_bars(cv: pd.DataFrame, height: int = 340) -> go.Figure:
    """Out-of-sample log-loss: the 1-parameter developmental-age scale vs rivals."""
    d = cv.sort_values("logloss")
    labels = {
        "devage": "Developmental age (1 parameter)",
        "overall": "Model's own overall mean",
        "saturated": "Per-dimension (12 parameters)",
        "grand": "Grand mean",
        "family": "Family mean",
        "date_size": "Release date + size",
    }
    names = [labels.get(str(m), str(m)) for m in d["method"]]
    colors = [T.TEAL if str(m) == "devage" else "#c9c9d2" for m in d["method"]]

    fig = go.Figure(
        go.Bar(
            x=d["logloss"], y=names, orientation="h",
            marker=dict(color=colors),
            text=[f"{v:.3f}" for v in d["logloss"]],
            textposition="outside",
            hovertemplate="%{y}<br>log-loss %{x:.4f}<extra></extra>",
        )
    )
    fig.update_xaxes(title_text="held-out log-loss (lower is better)")
    fig.update_yaxes(autorange="reversed")
    fig.update_layout(height=height, showlegend=False, margin=dict(l=10, r=60, t=30, b=10))
    return fig


def pca_scree(variance: pd.DataFrame, loadings: pd.DataFrame, height: int = 340):
    """Scree against a parallel-analysis threshold, plus PC1 loadings."""
    fig = make_subplots(
        rows=1, cols=2, horizontal_spacing=0.12,
        subplot_titles=("Variance explained", "PC1 loadings"),
    )
    v = variance.head(8).copy()
    # `pct_var` is stored as a fraction (0.805) while `parallel_95` is an
    # eigenvalue. Put both on a percent-of-total-variance axis.
    total = float(variance["eigenvalue"].sum())
    v["pct"] = v["pct_var"] * 100
    retained = v["retain"].astype(str).str.upper().eq("TRUE") if "retain" in v else None
    fig.add_trace(
        go.Bar(
            x=v["PC"], y=v["pct"],
            marker=dict(
                color=[T.ACCENT if r else "#c9c9d2" for r in retained]
                if retained is not None else T.ACCENT
            ),
            hovertemplate="PC%{x}<br>%{y:.1f}% of variance<extra></extra>",
            showlegend=False,
        ),
        row=1, col=1,
    )
    if "parallel_95" in v.columns and total > 0:
        fig.add_trace(
            go.Scatter(
                x=v["PC"], y=v["parallel_95"] / total * 100, mode="lines+markers",
                line=dict(color=T.MUTED, width=1.4, dash="dash"),
                marker=dict(size=5, color=T.MUTED),
                name="parallel analysis (95th pct)",
                hovertemplate="PC%{x}<br>threshold %{y:.1f}%<extra></extra>",
            ),
            row=1, col=1,
        )

    lo = loadings.sort_values("dim_rank")
    fig.add_trace(
        go.Bar(
            x=lo["PC1_loading"],
            y=[str(d).replace(" (Appearance vs. Reality)", "") for d in lo["tom_dimension"]],
            orientation="h", marker=dict(color=T.TEAL),
            hovertemplate="%{y}<br>loading %{x:.2f}<extra></extra>",
            showlegend=False,
        ),
        row=1, col=2,
    )
    fig.update_yaxes(autorange="reversed", tickfont=dict(size=10), row=1, col=2)
    fig.update_xaxes(title_text="% of variance", row=1, col=1)
    fig.update_layout(
        height=height,
        legend=dict(orientation="h", y=-0.25, x=0),
        margin=dict(l=10, r=10, t=44, b=10),
    )
    for annotation in fig.layout.annotations:
        annotation.font.update(size=12, color=T.INK)
    return fig


def item_map(stats: pd.DataFrame, height: int = 420) -> go.Figure:
    """Item facility vs discrimination — the instrument's own quality check."""
    colors = T.construct_colors()
    fig = go.Figure()
    for construct, g in stats.groupby("construct"):
        fig.add_trace(
            go.Scatter(
                x=g["facility"], y=g["discrimination"], mode="markers",
                name=str(construct),
                marker=dict(size=8, color=colors.get(construct, T.MUTED), opacity=0.85,
                            line=dict(color="white", width=0.6)),
                hovertemplate=(
                    "<b>%{customdata[0]}</b><br>%{customdata[1]}<br>"
                    "facility %{x:.2f}<br>discrimination %{y:.2f}<extra></extra>"
                ),
                customdata=np.stack([g["item_id"], g["tom_dimension"]], axis=-1),
            )
        )
    fig.add_vrect(x0=0.25, x1=0.95, fillcolor="rgba(42,157,143,0.07)", line_width=0,
                  layer="below")
    fig.add_hline(y=0.15, line=dict(color=T.MUTED, width=1, dash="dot"))
    fig.update_xaxes(title_text="facility (proportion of models correct)", range=[0, 1.03])
    fig.update_yaxes(title_text="discrimination (corrected point-biserial)")
    fig.update_layout(height=height, margin=dict(l=10, r=10, t=30, b=10),
                      legend=dict(orientation="h", y=-0.22, x=0, font=dict(size=10)))
    return fig
