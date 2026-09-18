"""Ordinal structure: Guttman scaling, the permutation null, and dissociations."""
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

st.title("Ordinal violations")

U.header(
    kicker="The diagnostic",
    claim=(
        "Does the developmental sequence actually organize these models — and "
        "where does it fail? The answer differs sharply by elicitation format, "
        "which is itself a result."
    ),
    sub=(
        "A perfect developmental scale produces a staircase: every model's "
        "mastered skills form an unbroken run from the easiest. The "
        "coefficient of reproducibility measures how close the data comes, and "
        "a permutation test asks whether the <em>human</em> ordering does "
        "better than an arbitrary one."
    ),
)

tab_scalogram, tab_null, tab_pairs = st.tabs(
    ["The staircase", "Is the human order special?", "Concrete dissociations"]
)

# --- Scalogram --------------------------------------------------------------
with tab_scalogram:
    sel = U.sidebar_filters("vio")
    if sel.frame.empty:
        st.warning("No models match the current filters.")
        st.stop()

    dim_acc = M.dimension_accuracy(sel.frame)
    matrix = M.mastery_matrix(dim_acc)
    errors = M.guttman_errors(matrix)
    cr = M.reproducibility_coefficient(matrix)

    U.selection_caption(sel)
    U.stat_row(
        [
            (f"{cr:.3f}", "coefficient of reproducibility — 1.0 is a perfect staircase"),
            (f"{int(errors['guttman_errors'].sum())}", f"cells that break the pattern, out of {matrix.notna().to_numpy().sum()}"),
            (f"{int((errors['guttman_errors'] > 0).sum())}/{len(errors)}", "models with at least one break"),
            (f"{errors['n_mastered'].median():.0f}/12", "dimensions mastered by the median model"),
        ]
    )

    st.plotly_chart(
        G.scalogram(matrix, errors, height=660),
        width="stretch",
        config={"displayModeBar": False},
    )
    U.note(
        "Teal = mastered at the 80% criterion. Cells outlined in orange break "
        "the staircase: either a skill mastered out of turn, or an early skill "
        "missed while later ones were passed. Dots beside a model name count "
        "its breaks. Models run oldest to newest, top to bottom."
    )

# --- Permutation null -------------------------------------------------------
with tab_null:
    st.markdown(
        "The staircase could look tidy for a boring reason: almost any "
        "ordering of twelve columns produces a decent coefficient when most "
        "models pass most items. The test is whether the *human developmental* "
        "ordering does better than orderings drawn at random."
    )

    try:
        perms = D.guttman("permutation_results.csv")
        draws = D.permutation_draws()
        scal = D.guttman("scalability_coefficients.csv")
    except Exception as exc:  # noqa: BLE001
        st.warning(f"Permutation artifacts unavailable: {exc}")
        perms = draws = scal = None

    if perms is not None:
        dataset = st.radio(
            "Dataset",
            ["pooled", "mcq", "frq"],
            horizontal=True,
            format_func=lambda d: {"pooled": "Both formats pooled", "mcq": "MCQ only",
                                   "frq": "Free response only"}[d],
            key="perm_ds",
        )
        row = perms[(perms["dataset"] == dataset) & (perms["order"] == "developmental")]
        srow = scal[scal["dataset"] == dataset]

        if len(row):
            row = row.iloc[0]
            p = row["p_value"]
            verdict_color = T.TEAL if p < 0.05 else (T.AMBER if p < 0.12 else T.CRIMSON)
            verdict = (
                "beats random orderings"
                if p < 0.05
                else ("marginal" if p < 0.12 else "indistinguishable from random")
            )
            U.stat_row(
                [
                    (f"{row['CR']:.3f}", "CR of the human developmental ordering"),
                    (f"{row['null_mean']:.3f}", "mean CR of 10,000 random orderings"),
                    (f"p = {p:.3f}", f"the developmental ordering {verdict}"),
                    (
                        f"{srow['CR_empirical_best'].iloc[0]:.3f}" if len(srow) else "—",
                        "CR of the best *empirical* ordering — a ceiling on what any order achieves",
                    ),
                ]
            )

            st.plotly_chart(
                G.permutation_null_chart(draws, perms, dataset=dataset, height=360),
                width="stretch",
                config={"displayModeBar": False},
            )

        st.markdown("#### What the three datasets say together")
        summary_rows = []
        for ds in ("pooled", "mcq", "frq"):
            r = perms[(perms["dataset"] == ds) & (perms["order"] == "developmental")]
            s = scal[scal["dataset"] == ds]
            if not len(r) or not len(s):
                continue
            r, s = r.iloc[0], s.iloc[0]
            summary_rows.append(
                {
                    "Dataset": {"pooled": "Pooled", "mcq": "MCQ", "frq": "Free response"}[ds],
                    "CR (developmental)": r["CR"],
                    "Random-order mean": r["null_mean"],
                    "p": r["p_value"],
                    "Best empirical order": s["CR_empirical_best"],
                    "Loevinger H": s["loevinger_H"],
                }
            )
        st.dataframe(
            pd.DataFrame(summary_rows),
            hide_index=True,
            width="stretch",
            column_config={
                "CR (developmental)": st.column_config.NumberColumn(format="%.3f"),
                "Random-order mean": st.column_config.NumberColumn(format="%.3f"),
                "p": st.column_config.NumberColumn(format="%.3f"),
                "Best empirical order": st.column_config.NumberColumn(format="%.3f"),
                "Loevinger H": st.column_config.NumberColumn(format="%.3f"),
            },
        )

        st.warning(
            "**This is the most important qualification in the project.** The "
            "developmental ordering organizes multiple-choice responses "
            "significantly better than chance (p = .008). It does **not** do so "
            "for free-response answers (p = .12), where it performs slightly "
            "*worse* than the average random ordering. Pooled, it lands at "
            "p = .056 — marginal. And a purely empirical ordering beats the "
            "developmental one on every dataset, so the human sequence is not "
            "the best available description of these models, only a better-"
            "than-chance one in the forced-choice format.",
            icon=":material/warning:",
        )

# --- Concrete dissociations -------------------------------------------------
with tab_pairs:
    st.markdown(
        "The Guttman coefficient is a summary. This is the underlying evidence "
        "in the form the argument actually uses: every case where a model "
        "passes a skill while failing one that children acquire earlier."
    )

    dim_all = M.dimension_accuracy(D.item_level())
    violations = M.prerequisite_violations(dim_all)

    if violations.empty:
        st.success("No prerequisite dissociations in the current panel.")
    else:
        U.stat_row(
            [
                (f"{len(violations):,}", "prerequisite dissociations across the panel"),
                (f"{violations['model'].nunique()}/{dim_all['model'].nunique()}", "models showing at least one"),
                (f"{violations['age_inversion'].max():.1f} yr", "largest normative age inversion"),
                (f"{violations['acc_gap'].max():.0%}", "largest accuracy gap across an inversion"),
            ]
        )

        by_model = (
            violations.groupby(["short_model", "family"], as_index=False)
            .agg(n=("passed", "size"), worst=("age_inversion", "max"))
            .sort_values("n", ascending=False)
        )
        choice = st.selectbox(
            "Model",
            ["All models"] + by_model["short_model"].tolist(),
            format_func=lambda m: (
                m
                if m == "All models"
                else f"{m}  ·  {int(by_model.loc[by_model['short_model'] == m, 'n'].iloc[0])} dissociations"
            ),
        )
        shown = (
            violations
            if choice == "All models"
            else violations[violations["short_model"] == choice]
        )

        st.dataframe(
            shown[
                ["short_model", "passed", "passed_age", "passed_acc",
                 "failed", "failed_age", "failed_acc", "age_inversion"]
            ].rename(
                columns={
                    "short_model": "Model",
                    "passed": "Passed (later skill)",
                    "passed_age": "Normed age",
                    "passed_acc": "Accuracy",
                    "failed": "Failed (earlier skill)",
                    "failed_age": "Normed age ",
                    "failed_acc": "Accuracy ",
                    "age_inversion": "Inversion (yr)",
                }
            ),
            hide_index=True,
            width="stretch",
            height=420,
            column_config={
                "Normed age": st.column_config.NumberColumn(format="%.1f"),
                "Normed age ": st.column_config.NumberColumn(format="%.1f"),
                "Accuracy": st.column_config.NumberColumn(format="percent"),
                "Accuracy ": st.column_config.NumberColumn(format="percent"),
                "Inversion (yr)": st.column_config.NumberColumn(format="%.1f"),
            },
        )

        U.pull(
            "Each row is a model reaching a skill without the skill it is "
            "supposed to be built on. In the essay's terms, that is not noise — "
            "it is direct evidence the model got there by a different route, "
            "and it tells you which capability you cannot rely on transferring."
        )

U.about_the_numbers()
U.caveats(
    extra=[
        "**The 80% mastery cut is a convention.** Moving it moves the "
        "dissociation count. It is the threshold the R pipeline uses "
        "throughout, so it is kept here for comparability.",
        "**Guttman statistics are sensitive to marginal pass rates.** When most "
        "models pass most dimensions, CR is high almost regardless of ordering "
        "— which is exactly why the permutation null matters more than the "
        "coefficient itself.",
    ]
)
