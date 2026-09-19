"""Landing page: what a composite benchmark score hides."""
from __future__ import annotations

import numpy as np
import plotly.graph_objects as go
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

st.title("A single score is the wrong resolution")

U.header(
    kicker="The trust gap",
    claim=(
        "While model-human teams now beat humans on tasks we designed to be hard, we still "
        "have not define how models reason through these tasks differently. "
        "A benchmark that reports aggregate statistics on performance only "
        "is not built to help characterize this."
    ),
    sub=(
        "To trust a system, I want to know which competencies generate its "
        "performance. Those are not directly observable, so they have to be "
        "inferred from patterns in behavior. Developmental psychology has "
        "spent decades solving exactly this inference problem on a subject that "
        "is also a bit of a black box: the young child."
    ),
)

df = D.item_level()
summary = M.model_summary(df)
dim_acc = M.dimension_accuracy(df)

U.stat_row(
    [
        ("28", "models evaluated, across 5 families and 14 size tiers"),
        ("12", "theory-of-mind dimensions, ordered by the age children acquire them"),
        ("184", "scored items, 124 multiple-choice and 60 free-response"),
        ("2.5–11", "years: the span of the developmental scale they map onto"),
    ]
)

st.markdown("## One number, then twelve")

st.markdown(
    "Pick any model. The left panel is what a benchmark leaderboard would "
    "report. The right panel is the same evaluation, disaggregated by "
    "developmental dimension."
)

options = summary.sort_values("accuracy", ascending=False)
labels = {
    row.model: f"{row.short_model}  ·  {row.accuracy:.0%}  ·  {row.family}"
    for row in options.itertuples()
}
default_idx = int(
    np.argmin(np.abs(options["accuracy"].to_numpy() - 0.90))
)  # a mid-pack model shows the structure best
picked = st.selectbox(
    "Model",
    options["model"].tolist(),
    index=default_idx,
    format_func=lambda m: labels[m],
    label_visibility="collapsed",
)

row = summary[summary["model"] == picked].iloc[0]
profile = dim_acc[dim_acc["model"] == picked].sort_values("rank")
profile_age = M.with_age_equivalent(profile)
metrics = M.sawtooth_metrics(profile_age)

left, right = st.columns([1, 2.35], gap="large")

with left:
    st.markdown(
        f"""
<div style="border:1px solid {T.HAIRLINE};border-radius:12px;padding:1.4rem 1.2rem;
            background:{T.WASH};text-align:center">
  <div style="font-size:0.74rem;letter-spacing:0.12em;text-transform:uppercase;
              color:{T.MUTED};font-weight:600">Composite score</div>
  <div style="font-size:3.4rem;font-weight:600;color:{T.INK};line-height:1.15;
              letter-spacing:-0.03em;margin:0.5rem 0">{row.accuracy:.1%}</div>
  <div style="font-size:0.88rem;color:{T.BODY}">{row.short_model}</div>
  <div style="font-size:0.78rem;color:{T.MUTED};margin-top:0.2rem">
      {row.n_correct:.0f} of {row.n:.0f} items · {row.family}
  </div>
</div>
""",
        unsafe_allow_html=True,
    )
    st.markdown("")
    best = profile.loc[profile["accuracy"].idxmax()]
    worst = profile.loc[profile["accuracy"].idxmin()]
    st.markdown(
        f"""
<div class="dv-note">
Behind that number: <b>{best.accuracy:.0%}</b> on {best.tom_dimension}
(normed {K.DIMENSION_BAND[best.tom_dimension][0]:g}–{K.DIMENSION_BAND[best.tom_dimension][1]:g} yr)
but <b>{worst.accuracy:.0%}</b> on {worst.tom_dimension}
(normed {K.DIMENSION_BAND[worst.tom_dimension][0]:g}–{K.DIMENSION_BAND[worst.tom_dimension][1]:g} yr)
— a spread of <b>{(best.accuracy - worst.accuracy):.0%}</b> that the composite
averages away.
</div>
""",
        unsafe_allow_html=True,
    )

with right:
    st.plotly_chart(
        G.profile_lines(profile_age, highlight=picked, height=400),
        width="stretch",
        config={"displayModeBar": False},
    )
    U.note(
        "Dimensions run left to right in the order children acquire them. "
        "A model acquiring theory of mind the way children do would decline "
        "gently from left to right, not zig-zag."
    )

# --- Same score, different shape -------------------------------------------
st.markdown("## Two models, one score, different minds")

st.markdown(
    "The composite is actively ambiguous. These are the "
    "two models in the panel whose overall scores are closest together while "
    "their per-dimension profiles are furthest apart."
)


@st.cache_data(show_spinner=False)
def _twin_pair() -> tuple[str, str, float, float]:
    """Find the pair with the smallest composite gap and largest profile distance."""
    wide = dim_acc.pivot_table(
        index="model", columns="tom_dimension", values="accuracy"
    )[K.DIMENSION_ORDER]
    overall = summary.set_index("model")["accuracy"]
    models = [m for m in wide.index if m in overall.index]

    best = None
    for i, a in enumerate(models):
        for b in models[i + 1 :]:
            score_gap = abs(overall[a] - overall[b])
            if score_gap > 0.02:  # "the same score" to a leaderboard reader
                continue
            shape_gap = float(np.nanmean(np.abs(wide.loc[a] - wide.loc[b])))
            if best is None or shape_gap > best[3]:
                best = (a, b, score_gap, shape_gap)
    return best


pair = _twin_pair()
if pair is None:
    U.note("No two models in the current panel share a composite score closely enough.")
else:
    a, b, score_gap, shape_gap = pair
    sub = dim_acc[dim_acc["model"].isin([a, b])]
    sub_age = M.with_age_equivalent(sub)
    name_a = summary.loc[summary["model"] == a, "short_model"].iloc[0]
    name_b = summary.loc[summary["model"] == b, "short_model"].iloc[0]
    acc_a = summary.loc[summary["model"] == a, "accuracy"].iloc[0]
    acc_b = summary.loc[summary["model"] == b, "accuracy"].iloc[0]

    fig = go.Figure()
    for model, name, color in ((a, name_a, T.ACCENT), (b, name_b, T.SLATE)):
        g = sub_age[sub_age["model"] == model].sort_values("rank")
        fig.add_trace(
            go.Scatter(
                x=g["rank"],
                y=g["accuracy"],
                mode="lines+markers",
                name=f"{name} ({g['accuracy'].mean():.0%} mean)",
                line=dict(color=color, width=2.4),
                marker=dict(size=8, line=dict(color="white", width=1)),
                hovertemplate=f"<b>{name}</b><br>%{{customdata}}<br>%{{y:.0%}}<extra></extra>",
                customdata=g["tom_dimension"],
            )
        )
    fig.add_hline(
        y=K.MASTERY_THRESHOLD,
        line=dict(color=T.MUTED, width=1.2, dash="dash"),
        annotation_text="80% mastery",
        annotation_position="bottom right",
        annotation_font=dict(size=11, color=T.MUTED),
    )
    ranks = [K.DIMENSION_RANK[d] for d in K.DIMENSION_ORDER]
    fig.update_xaxes(
        tickmode="array",
        tickvals=ranks,
        ticktext=[d.replace(" (Appearance vs. Reality)", "") for d in K.DIMENSION_ORDER],
        tickangle=-38,
    )
    fig.update_yaxes(range=[0, 1.04], tickformat=".0%", title_text="accuracy")
    fig.update_layout(
        height=420,
        margin=dict(l=10, r=10, t=30, b=130),
        legend=dict(orientation="h", y=1.1, x=0),
    )

    c1, c2 = st.columns([2.4, 1], gap="large")
    with c1:
        st.plotly_chart(fig, width="stretch", config={"displayModeBar": False})
    with c2:
        U.stat_row([(f"{score_gap:.1%}", "difference in composite score")])
        st.markdown("")
        U.stat_row([(f"{shape_gap:.0%}", "mean per-dimension difference")])
        st.markdown("")
        U.note(
            f"**{name_a}** scores {acc_a:.1%} and **{name_b}** scores {acc_b:.1%}. "
            "A leaderboard ranking them next to each other would call them "
            "equivalent, even though they are behaving differently."
        )

U.pull(
    "The claim of this project is that the shape of what models are "
    "good at does not match any developmental trajectory we have ever measured "
    "in a child. That shape tells you where a model will break."
)

st.markdown('<hr class="dv-rule">', unsafe_allow_html=True)
st.markdown(
    "**Next:** [why developmental psychology has the right tools for this] "
    "(method) → [the instrument](instrument) → [the sawtooth](sawtooth)."
)

U.about_the_numbers()
