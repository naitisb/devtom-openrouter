"""The headline figure: developmental profiles against the human sequence."""
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

st.title("The sawtooth")

U.header(
    kicker="The finding",
    claim=(
        "When models have to <em>generate</em> an answer rather than pick one, "
        "their developmental profile stops climbing. Among free-response "
        "models with headroom, not one produces a monotonic profile, and the "
        "typical model's largest backward step is nearly four age-equivalent "
        "years."
    ),
    sub=(
        "Each panel is one model family. The vertical axis is the human "
        "developmental sequence, earliest-acquired at the bottom. The "
        "horizontal axis converts performance on each dimension into an age "
        "equivalent. Grey bands are the normative acquisition window; the "
        "dashed rule is the passing age. Faded dots are individual models; the "
        "connected dots are tier means. A child-like profile would rise "
        "steadily and stay inside the bands."
    ),
)

sel = U.sidebar_filters("saw", show_age_formula=True, default_format="Free response only")
if sel.frame.empty:
    st.warning("No models match the current filters.")
    st.stop()

dim_acc = M.dimension_accuracy(sel.frame)
age = M.with_age_equivalent(dim_acc, formula=sel.age_formula)
saw = M.sawtooth_table(age)

U.selection_caption(sel)

# --- Headline metrics -------------------------------------------------------
monotone = int(saw["monotonic"].sum())
outside = (
    (age["age_equiv"] < age["age_lo"]) | (age["age_equiv"] > age["age_hi"])
).mean()
U.stat_row(
    [
        (f"{saw['max_drop'].median():.1f} yr", "median model's largest backward step between adjacent skills"),
        (f"{saw['max_drop'].max():.1f} yr", "largest backward step anywhere in view"),
        (f"{monotone}/{len(saw)}", "models whose profile never goes backwards"),
        (f"{outside:.0%}", "of model × dimension cells fall outside the normative window"),
    ]
)

st.plotly_chart(
    G.sawtooth_chart(age, facet_by="family", group_by="tier", height=640),
    width="stretch",
    config={"displayModeBar": False},
)

formula_label, formula_help = M.AGE_FORMULAS[sel.age_formula]
U.note(
    f"Age equivalent = <code>{formula_label}</code>. {formula_help}"
)

# --- Read one model closely -------------------------------------------------
st.markdown("## Read one model closely")

summary = M.model_summary(sel.frame).sort_values("release_date", ascending=False)
labels = {
    row.model: f"{row.short_model}  ·  {row.accuracy:.0%}  ·  {row.release_date:%b %Y}"
    for row in summary.itertuples()
}
default = saw.iloc[0]["model"] if len(saw) else summary.iloc[0]["model"]
models = summary["model"].tolist()
picked = st.selectbox(
    "Model",
    models,
    index=models.index(default) if default in models else 0,
    format_func=lambda m: labels.get(m, m),
)

one = age[age["model"] == picked].sort_values("rank")
metrics = M.sawtooth_metrics(one)
row = summary[summary["model"] == picked].iloc[0]

c1, c2 = st.columns([2.3, 1], gap="large")
with c1:
    st.plotly_chart(
        G.sawtooth_chart(
            one, facet_by=None, group_by="tier", height=520, show_models=False
        ),
        width="stretch",
        config={"displayModeBar": False},
    )
with c2:
    st.markdown(f"#### {row.short_model}")
    U.note(
        f"{row.family} · {row.tier} · released {row.release_date:%B %Y}"
        + (f" · ~{row.params_b:g}B parameters" if pd.notna(row.params_b) else "")
    )
    st.markdown("")
    st.metric("Composite score", f"{row.accuracy:.1%}")
    st.metric(
        "Largest backward step",
        f"{metrics['max_drop']:.1f} yr",
        help=(
            "The biggest drop in age equivalent between two adjacent "
            "dimensions. A child-like profile has none."
        ),
    )
    st.metric(
        "Steps that go backwards",
        f"{metrics['n_backward']} of {metrics['n_steps']}",
    )
    st.metric(
        "Rank correlation with the human sequence",
        f"{metrics['spearman']:.2f}" if pd.notna(metrics["spearman"]) else "—",
        help="Spearman rho between the model's profile and the normative order. 1.00 = perfectly ordered.",
    )

    steps = one.sort_values("rank")
    diffs = steps["age_equiv"].diff()
    if diffs.notna().any():
        worst_idx = diffs.idxmin()
        if pd.notna(worst_idx) and diffs[worst_idx] < 0:
            worst = steps.loc[worst_idx]
            prev = steps.loc[steps["rank"] == worst["rank"] - 1]
            if len(prev):
                prev = prev.iloc[0]
                st.markdown("")
                U.note(
                    f"Its steepest tooth: <b>{prev.tom_dimension}</b> "
                    f"({prev.accuracy:.0%}, {prev.age_equiv:.1f} yr) drops to "
                    f"<b>{worst.tom_dimension}</b> ({worst.accuracy:.0%}, "
                    f"{worst.age_equiv:.1f} yr) — despite being the "
                    f"<i>later</i>-acquired skill in children."
                )

# --- Where the teeth are ----------------------------------------------------
st.markdown("## Which transitions break")

st.markdown(
    "Averaged across the panel, some steps in the sequence are reliably "
    "backwards. These are the places where the models' ordering and "
    "children's ordering disagree most."
)

steps_all = []
for model, group in age.groupby("model"):
    g = group.sort_values("rank")
    vals = g["age_equiv"].to_numpy()
    dims = g["tom_dimension"].tolist()
    for i in range(1, len(vals)):
        steps_all.append(
            {
                "transition": f"{dims[i-1]}  →  {dims[i]}",
                "rank": i,
                "delta": vals[i] - vals[i - 1],
                "model": model,
            }
        )
steps_df = pd.DataFrame(steps_all)
agg = (
    steps_df.groupby(["rank", "transition"], as_index=False)
    .agg(mean_delta=("delta", "mean"), pct_backward=("delta", lambda s: (s < 0).mean()))
    .sort_values("rank")
)

st.dataframe(
    agg[["transition", "mean_delta", "pct_backward"]].rename(
        columns={
            "transition": "Step in the human sequence",
            "mean_delta": "Mean change in age equivalent (yr)",
            "pct_backward": "Models going backwards",
        }
    ),
    hide_index=True,
    width="stretch",
    column_config={
        "Mean change in age equivalent (yr)": st.column_config.NumberColumn(format="%+.2f"),
        "Models going backwards": st.column_config.ProgressColumn(
            format="percent", min_value=0, max_value=1
        ),
    },
)

U.pull(
    "A composite score of the kind a Strachan-style comparison produces would "
    "hide every row of that table."
)

# --- The format dependency --------------------------------------------------
st.markdown("## The teeth are a free-response phenomenon")

st.markdown(
    "This is the single most consequential qualification on the finding, and "
    "it only shows up because every item was administered twice. Forced choice "
    "and free response give different answers about whether these models "
    "follow the human sequence at all."
)


@st.cache_data(show_spinner=False)
def _format_comparison() -> pd.DataFrame:
    base = D.item_level()
    overall = base.groupby("model")["correct"].mean()
    headroom = overall[overall < K.SATURATION_CUTOFF].index
    rows = []
    for label, block in (
        ("MCQ — all models", base[base["task_label"] == "MCQ"]),
        ("MCQ — headroom only", base[(base["task_label"] == "MCQ") & base["model"].isin(headroom)]),
        ("Free response — all models", base[base["task_label"] == "Free response"]),
        ("Free response — headroom only",
         base[(base["task_label"] == "Free response") & base["model"].isin(headroom)]),
    ):
        if block.empty:
            continue
        d = M.dimension_accuracy(block)
        a = M.with_age_equivalent(d)
        s = M.sawtooth_table(a)
        rows.append(
            {
                "View": label,
                "Models": len(s),
                "Median largest backward step (yr)": s["max_drop"].median(),
                "Monotonic profiles": s["monotonic"].sum() / len(s),
                "Median rank correlation": s["spearman"].median(),
            }
        )
    return pd.DataFrame(rows)


st.dataframe(
    _format_comparison(),
    hide_index=True,
    width="stretch",
    column_config={
        "Median largest backward step (yr)": st.column_config.NumberColumn(format="%.2f"),
        "Monotonic profiles": st.column_config.ProgressColumn(
            format="percent", min_value=0, max_value=1
        ),
        "Median rank correlation": st.column_config.NumberColumn(format="%.2f"),
    },
)

st.warning(
    "**Read across that table.** In multiple choice, most models produce a "
    "near-perfectly ordered profile — the human sequence describes them well. "
    "In free response, among the models that still have room to vary, **none** "
    "does, and the typical largest backward step is close to four years. The "
    "same models, the same scenarios, the same 80% criterion — only the "
    "response format changes.\n\n"
    "This lines up with everything else in the project: the developmental "
    "ordering beats random orderings in MCQ (p = .008) but not in free "
    "response (p = .12), and the two formats correlate at only r = .28 among "
    "models with headroom. The forced-choice format flatters these models. "
    "Selecting the right answer from four options is evidently reachable by a "
    "route that generating it is not.",
    icon=":material/warning:",
)

st.info(
    "**What this figure does and does not show.** The teeth are in the "
    "*continuous* profile — how far above or below the normative window each "
    "dimension sits. At the coarser, binary level of \"has this model mastered "
    "this skill at all\", the panel is more orderly: the "
    "[ordinal violations](violations) page shows only a minority of models "
    "pass a skill while outright failing one of its prerequisites. Both are "
    "true, and they are different claims.",
    icon=":material/info:",
)

U.about_the_numbers()
U.caveats(
    extra=[
        "**The age equivalent is a rescaling of accuracy, not an independent "
        "measurement.** It inherits every property of the accuracy it is "
        "derived from, including ceiling compression. Its value is that it puts "
        "performance on the same axis as the human norms."
    ]
)
