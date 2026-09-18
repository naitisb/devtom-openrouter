"""Longitudinal and scaling view: what improves, and what does not."""
from __future__ import annotations

import numpy as np
import pandas as pd
import streamlit as st

from devtom import charts as G
from devtom import compute as M
from devtom import constants as K
from devtom import data as D
from devtom import theme as T
from devtom import ui as U

U.boot()
if not U.snapshot_guard():
    st.stop()

st.title("Does it improve?")

U.header(
    kicker="Longitudinal and scaling",
    claim=(
        "Theory-of-mind accuracy climbs steeply release over release and with "
        "parameter count. Developmental <em>coherence</em> — whether a model's "
        "profile respects the human acquisition order — does not."
    ),
    sub=(
        "Two questions that a composite score conflates. The first is about "
        "level: are models getting better? The second is about shape: are they "
        "getting better in a way that looks more like the human trajectory? "
        "The answers point in different directions."
    ),
)

sel = U.sidebar_filters("traj")
if sel.frame.empty:
    st.warning("No models match the current filters.")
    st.stop()

summary = M.model_summary(sel.frame)
dim_acc = M.dimension_accuracy(sel.frame)
age = M.with_age_equivalent(dim_acc)
U.selection_caption(sel)

tab_level, tab_size, tab_shape = st.tabs(
    ["Level over time", "Level vs size", "Does the shape improve?"]
)

# --- Level over time --------------------------------------------------------
with tab_level:
    mastered = (
        dim_acc.groupby("model", as_index=False)
        .agg(n_mastered=("mastered", "sum"))
    )
    points = summary.merge(mastered, on="model", how="left")

    metric = st.radio(
        "Measure",
        ["Overall accuracy", "Dimensions mastered (of 12)"],
        horizontal=True,
        key="traj_metric",
    )
    color_by = st.radio(
        "Colour by", ["tier", "family"], horizontal=True, key="traj_color",
        format_func=lambda c: "Size tier" if c == "tier" else "Family",
    )

    if metric.startswith("Overall"):
        fig = G.trajectory_chart(
            points, y="accuracy", color_by=color_by, y_title="overall accuracy",
            y_format=".0%", y_range=(0, 1.05), hline=K.MCQ_CHANCE, height=480,
        )
        caption = (
            "Dotted line is the 25% multiple-choice chance level. Lines are "
            "ordinary least squares fits within each group."
        )
    else:
        fig = G.trajectory_chart(
            points, y="n_mastered", color_by=color_by,
            y_title="dimensions mastered (>=80%)", y_range=(0, 12.5),
            hline=12, height=480,
        )
        caption = (
            "Dotted line is the ceiling — all 12 dimensions mastered. Several "
            "models have reached it, which is where the instrument stops "
            "discriminating."
        )

    st.plotly_chart(fig, width="stretch", config={"displayModeBar": False})
    U.note(caption)

    oldest = points.nsmallest(1, "release_date").iloc[0]
    newest = points.nlargest(1, "release_date").iloc[0]
    U.stat_row(
        [
            (f"{oldest.accuracy:.0%}", f"oldest model in view — {oldest.short_model}, {oldest.release_date:%b %Y}"),
            (f"{newest.accuracy:.0%}", f"newest — {newest.short_model}, {newest.release_date:%b %Y}"),
            (f"{int(points['n_mastered'].max())}/12", "most dimensions mastered by any model in view"),
            (f"{int((points['accuracy'] >= K.SATURATION_CUTOFF).sum())}", f"models at or above {K.SATURATION_CUTOFF:.0%} — no headroom left"),
        ]
    )

# --- Level vs size ----------------------------------------------------------
with tab_size:
    sized = summary.dropna(subset=["params_b"])
    if sized.empty:
        st.info("No parameter counts available for the models in view.")
    else:
        import plotly.graph_objects as go

        palette = T.family_colors()
        fig = go.Figure()
        for family, g in sized.groupby("family"):
            fig.add_trace(
                go.Scatter(
                    x=g["params_b"], y=g["accuracy"], mode="markers", name=family,
                    marker=dict(size=12, color=palette.get(family, T.MUTED),
                                line=dict(color="white", width=1)),
                    hovertemplate=(
                        "<b>%{customdata[0]}</b><br>~%{x:g}B parameters<br>"
                        "accuracy %{y:.0%}<extra></extra>"
                    ),
                    customdata=np.stack([g["short_model"]], axis=-1),
                )
            )
        x = np.log10(sized["params_b"].to_numpy())
        y = sized["accuracy"].to_numpy()
        if len(sized) >= 3 and x.std() > 0:
            slope, intercept = np.polyfit(x, y, 1)
            xs = np.linspace(x.min(), x.max(), 50)
            fig.add_trace(
                go.Scatter(
                    x=10**xs, y=intercept + slope * xs, mode="lines",
                    line=dict(color=T.MUTED, width=1.6, dash="dash"),
                    name="pooled trend", hoverinfo="skip",
                )
            )
        fig.add_hline(y=K.MCQ_CHANCE, line=dict(color=T.MUTED, width=1, dash="dot"))
        fig.update_xaxes(title_text="parameters (billions, log scale)", type="log")
        fig.update_yaxes(title_text="overall accuracy", tickformat=".0%", range=[0, 1.05])
        fig.update_layout(height=480, margin=dict(l=10, r=10, t=30, b=10))

        st.plotly_chart(fig, width="stretch", config={"displayModeBar": False})
        st.caption(
            "Parameter counts for Claude and GPT models are **estimates** — "
            "these are closed-weight systems and the roster records approximate "
            "totals. Treat the right-hand side of this plot as indicative."
        )

# --- Shape ------------------------------------------------------------------
with tab_shape:
    st.markdown(
        "Developmental coherence asks a different question: within a model, is "
        "performance higher on the earlier, prerequisite skills than on the "
        "later ones that depend on them? Positive means child-like. Because "
        "raw coherence is mechanically tied to overall accuracy by ceiling "
        "compression, it is residualized on mean accuracy first."
    )

    coh = M.coherence(dim_acc)
    if coh.empty or coh["coherence_resid"].isna().all():
        st.info("Not enough models in view to residualize coherence.")
    else:
        x_axis = st.radio(
            "Against", ["release_date", "params_b"], horizontal=True,
            format_func=lambda c: "Release date" if c == "release_date" else "Parameter count",
            key="coh_x",
        )
        plot_df = coh.dropna(subset=[x_axis, "coherence_resid"])
        st.plotly_chart(
            G.coherence_scatter(plot_df, x=x_axis, height=440),
            width="stretch",
            config={"displayModeBar": False},
        )

        xs = (
            plot_df["release_date"].map(pd.Timestamp.toordinal)
            if x_axis == "release_date"
            else np.log10(plot_df["params_b"])
        )
        rho = M._spearman(xs.to_numpy(dtype=float), plot_df["coherence_resid"].to_numpy())
        U.stat_row(
            [
                (f"{rho:+.2f}", f"Spearman rho between residual coherence and {'release date' if x_axis == 'release_date' else 'parameter count'}"),
                (f"{int((coh['coherence_resid'] > 0).sum())}/{len(coh)}", "models more accurate on earlier skills than later ones"),
            ]
        )

    st.info(
        "**The regression finds nothing.** In the full model "
        "(`coherence ~ date + size + family`), neither release date "
        "(p = .09 raw, p = .25 residualized) nor parameter count "
        "(p = .08 raw, p = .45 residualized) reaches significance — and both "
        "point slightly *negative*. With 28 models this is underpowered, so "
        "the honest reading is: there is no evidence that newer or larger "
        "models acquire theory of mind in a more child-like order, and a weak "
        "hint they may do the opposite.",
        icon=":material/info:",
    )

    U.pull(
        "Scale buys you the level. Nothing in this panel shows it buying you "
        "the shape — and the shape is what tells you where the model breaks."
    )

U.about_the_numbers()
U.caveats(
    extra=[
        "**Release date is confounded with everything.** Newer models differ in "
        "training data, post-training, size and inference-time compute all at "
        "once. A date slope is not a causal estimate.",
        "**Tiers are not matched across families.** \"Llama large\" and "
        "\"Claude Opus\" are not the same thing; within-family comparison is "
        "the meaningful one.",
    ]
)
