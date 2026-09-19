"""Open exploration over the item-level data."""
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

st.title("Browse the data")

U.header(
    kicker="Explore",
    claim=(
        "The whole evaluation, without a narrative attached. Filter it, sort "
        "it, disagree with it."
    ),
    sub=(
        "Every figure in this app is computed from the table at the bottom of "
        "this page: one row per model × item × elicitation format."
    ),
)

sel = U.sidebar_filters("explore")
if sel.frame.empty:
    st.warning("No models match the current filters.")
    st.stop()

frame = sel.frame
dim_acc = M.dimension_accuracy(frame)
summary = M.model_summary(frame)
U.selection_caption(sel)

tab_heat, tab_models, tab_dims, tab_raw = st.tabs(
    ["Model × dimension", "Model leaderboard", "Dimension difficulty", "Raw table"]
)

with tab_heat:
    st.plotly_chart(
        G.dimension_heatmap(dim_acc, height=max(360, 22 * dim_acc["model"].nunique() + 190)),
        width="stretch",
        config={"displayModeBar": False},
    )
    U.note(
        "Rows run oldest to newest. Columns run in developmental order, "
        "earliest-acquired first. A model acquiring skills the way children do "
        "would show green on the left fading right."
    )

with tab_models:
    mastered = dim_acc.groupby("model", as_index=False).agg(n_mastered=("mastered", "sum"))
    table = (
        summary.merge(mastered, on="model", how="left")
        .sort_values("accuracy", ascending=False)[
            ["short_model", "family", "tier", "release_date", "params_b",
             "accuracy", "wilson_lo", "wilson_hi", "n", "n_mastered"]
        ]
    )

    st.dataframe(
        table.rename(
            columns={
                "short_model": "Model", "family": "Family", "tier": "Tier",
                "release_date": "Released", "params_b": "Params (B)",
                "accuracy": "Accuracy", "wilson_lo": "95% lo", "wilson_hi": "95% hi",
                "n": "Items", "n_mastered": "Mastered /12",
            }
        ),
        hide_index=True,
        width="stretch",
        height=520,
        column_config={
            "Released": st.column_config.DateColumn(format="MMM YYYY"),
            "Accuracy": st.column_config.ProgressColumn(
                format="percent", min_value=0, max_value=1
            ),
            "95% lo": st.column_config.NumberColumn(format="%.3f"),
            "95% hi": st.column_config.NumberColumn(format="%.3f"),
            "Params (B)": st.column_config.NumberColumn(format="%.0f"),
        },
    )
    st.caption(
        "Confidence intervals are Wilson score intervals. Parameter counts for "
        "Claude and GPT are estimates recorded in the roster."
    )

with tab_dims:
    by_dim = (
        dim_acc.groupby(["tom_dimension", "rank", "age_lo", "age_hi", "construct"],
                        as_index=False)
        .agg(
            accuracy=("accuracy", "mean"),
            sd=("accuracy", "std"),
            n_mastering=("mastered", "sum"),
            n_models=("model", "nunique"),
        )
        .sort_values("accuracy")
    )
    by_dim["band"] = (
        by_dim["age_lo"].map("{:g}".format) + "–" + by_dim["age_hi"].map("{:g}".format) + " yr"
    )
    st.dataframe(
        by_dim[["tom_dimension", "band", "construct", "accuracy", "sd",
                "n_mastering", "n_models"]].rename(
            columns={
                "tom_dimension": "Dimension", "band": "Age band",
                "construct": "Construct", "accuracy": "Mean accuracy",
                "sd": "SD across models", "n_mastering": "Models mastering",
                "n_models": "Models",
            }
        ),
        hide_index=True,
        width="stretch",
        column_config={
            "Mean accuracy": st.column_config.ProgressColumn(
                format="percent", min_value=0, max_value=1
            ),
            "SD across models": st.column_config.NumberColumn(format="%.3f"),
        },
    )
    U.note(
        "Hardest at the top. Note that difficulty here does not simply track "
        "the age band. See "
        "[does difficulty track age?](validity) for why that matters."
    )

with tab_raw:
    cols = [
        "short_model", "family", "tier", "release_date", "task_label",
        "item_id", "tom_dimension", "construct", "band", "correct",
    ]
    show = frame[cols].rename(
        columns={
            "short_model": "Model", "family": "Family", "tier": "Tier",
            "release_date": "Released", "task_label": "Format", "item_id": "Item",
            "tom_dimension": "Dimension", "construct": "Construct",
            "band": "Age band", "correct": "Correct",
        }
    )
    st.dataframe(show, hide_index=True, width="stretch", height=460)

    c1, c2 = st.columns(2)
    with c1:
        st.download_button(
            "Download filtered rows (CSV)",
            show.to_csv(index=False).encode("utf-8"),
            file_name="devtom_item_level_filtered.csv",
            mime="text/csv",
            width="stretch",
        )
    with c2:
        st.download_button(
            "Download model × dimension accuracy (CSV)",
            dim_acc.to_csv(index=False).encode("utf-8"),
            file_name="devtom_model_dimension_accuracy.csv",
            mime="text/csv",
            width="stretch",
        )

    prov = D.provenance()
    with st.expander("Provenance"):
        st.json(prov)

    excluded = D.excluded_models()
    if excluded:
        with st.expander(f"{len(excluded)} models the study intended to include but could not"):
            st.markdown(
                "The roster keeps an audit trail rather than deleting entries. "
                "These failed the availability or policy check at freeze time."
            )
            st.dataframe(
                pd.DataFrame(excluded).rename(
                    columns={"model": "Model", "family": "Family", "reason": "Reason"}
                ),
                hide_index=True,
                width="stretch",
                height=300,
            )

U.about_the_numbers()
