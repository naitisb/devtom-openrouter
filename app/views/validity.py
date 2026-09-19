"""Turning the instrument on itself: is the developmental scale any good?"""
from __future__ import annotations

import numpy as np
import pandas as pd
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

st.title("Is the scale trustworthy?")

U.header(
    kicker="Stress-testing the instrument",
    claim=(
        "The developmental scale is unidimensional and radically parsimonious. "
        "It does not predict better than simply knowing a model's overall accuracy, and it "
        "does not transfer across elicitation formats."
    ),
    sub=(
        "A framework that only ever confirms itself is not worth having. These "
        "are tests that could have shown the developmental axis to be "
        "decorative. It is useful to know which it passes and which it does not."
    ),
)

try:
    summary_vals = D.scale_validity_summary()
    cv = D.scale_validity("cv_logloss.csv")
    pca_var = D.scale_validity("pca_variance.csv")
    pca_load = D.scale_validity("pca_loadings.csv")
    transfer = D.scale_validity("format_transfer.csv")
    theta_cor = D.scale_validity("format_transfer_theta_cor.csv")
except Exception as exc:  # noqa: BLE001
    st.error(f"Scale-validity artifacts unavailable: {exc}")
    st.stop()


def _f(key: str, default: float = float("nan")) -> float:
    try:
        return float(summary_vals.get(key, default))
    except (TypeError, ValueError):
        return default


pc1 = _f("PC1 variance explained")
retained = _f("components retained (parallel analysis)")
ll_dev = _f("hold-out logloss: dev-age (1 param)")
ll_sat = _f("hold-out logloss: saturated (12 params)")
adv = _f("LODO dev-age advantage over overall-mean (discriminating models)")
r_fmt = _f("accuracy MCQ~FRQ Pearson r (all models)")

# --- Verdict cards ----------------------------------------------------------
verdicts = [
    ("Unidimensional?", "PASS", T.TEAL,
     f"One component explains <b>{pc1:.0%}</b> of the variance across the 12 "
     f"dimensions, and parallel analysis retains exactly <b>{retained:.0f}</b>. "
     "There is essentially one underlying ability here."),
    ("Parsimonious?", "PASS", T.TEAL,
     f"A 1-parameter developmental-age model reaches held-out log-loss "
     f"<b>{ll_dev:.3f}</b>, against <b>{ll_sat:.3f}</b> for the 12-parameter "
     "per-dimension model. Twelve free parameters buy nothing but overfitting."),
    ("Predicts better than overall accuracy?", "FAIL", T.CRIMSON,
     f"Leaving out one dimension at a time, the developmental-age model's "
     f"advantage over simply using the model's own mean accuracy is "
     f"<b>{adv:+.4f}</b> log-loss, so slightly worse. The scale earns its "
     "keep as interpretation, not as prediction."),
    ("Format-invariant?", "FAIL", T.CRIMSON,
     f"MCQ and free-response accuracy correlate at only <b>r = {r_fmt:.2f}</b> "
     "across the panel, and fitting on one format predicts the other poorly."),
]

cols = st.columns(4, gap="medium")
for col, (question, verdict, color, body) in zip(cols, verdicts):
    with col:
        st.markdown(
            f"""
<div style="border:1px solid {T.HAIRLINE};border-top:3px solid {color};
            border-radius:10px;padding:0.95rem 1rem;height:100%">
  <div style="font-size:0.72rem;letter-spacing:0.1em;text-transform:uppercase;
              color:{color};font-weight:700;margin-bottom:0.45rem">{verdict}</div>
  <div style="font-size:0.95rem;font-weight:600;color:{T.INK};margin-bottom:0.5rem;
              line-height:1.35">{question}</div>
</div>
""",
            unsafe_allow_html=True,
        )
        st.markdown(f'<div class="dv-note">{body}</div>', unsafe_allow_html=True)

st.markdown('<hr class="dv-rule">', unsafe_allow_html=True)

tab_dim, tab_pars, tab_fmt, tab_anchor = st.tabs(
    ["Dimensionality", "Parsimony", "Format transfer", "Does difficulty track age?"]
)

with tab_dim:
    st.plotly_chart(
        G.pca_scree(pca_var, pca_load, height=380),
        width="stretch",
        config={"displayModeBar": False},
    )
    U.note(
        "Parallel analysis compares each component's eigenvalue against the "
        "95th percentile of eigenvalues from random data of the same shape. "
        "Only PC1 clears it. Every dimension loads positively on PC1, which is "
        "what 'one underlying ability' looks like."
    )
    st.markdown(
        f"The correlation between a dimension's PC1 loading and its "
        f"developmental rank is **{_f('Spearman(PC1 loading, dev rank)'):.2f}** — "
        "positive but modest. The single factor is closer to general competence "
        "than to a strictly developmental ordering."
    )

with tab_pars:
    holdout = cv[cv["scheme"].str.contains("hold-out", case=False, na=False)]
    if len(holdout):
        st.plotly_chart(
            G.cv_logloss_bars(holdout, height=300),
            width="stretch",
            config={"displayModeBar": False},
        )
        U.note(
            "Five-fold hold-out over items. Lower is better. The developmental-"
            "age model uses one parameter per model."
        )

    lodo = cv[cv["scheme"].str.contains("dimension", case=False, na=False)]
    if len(lodo):
        st.markdown("#### Leave one dimension out")
        st.markdown(
            "A harder test: estimate each model's developmental age from 11 "
            "dimensions, then predict the held-out twelfth."
        )
        pivot = lodo.pivot_table(
            index="method", columns="subgroup", values="logloss"
        ).rename(
            index={
                "devage": "Developmental age (1 param)",
                "overall": "Model's own overall mean",
                "datesize": "Release date + size",
                "family": "Family mean",
                "grand": "Grand mean",
            }
        )
        st.dataframe(
            pivot.sort_values("all"),
            width="stretch",
            column_config={
                col: st.column_config.NumberColumn(format="%.3f") for col in pivot.columns
            },
        )
        st.caption(
            "Developmental age and the model's own overall mean are "
            "indistinguishable — and both beat date+size, family mean and the "
            "grand mean. Because the data is close to a single strong factor, "
            "dev-age and overall competence are nearly the same quantity for "
            "prediction purposes. The scale's value is that it is "
            "*interpretable*: it says which skills, in what order."
        )

with tab_fmt:
    df = D.item_level()
    agreement = M.format_agreement(df)
    st.plotly_chart(
        G.format_scatter(agreement, height=460),
        width="stretch",
        config={"displayModeBar": False},
    )
    U.note(
        "Filled markers are models with headroom (below 95% in both formats); "
        "hollow markers are saturated. Distance from the diagonal is format "
        "fragility."
    )

    if len(theta_cor):
        tc = theta_cor.iloc[0]
        U.stat_row(
            [
                (f"{tc['pearson']:.2f}", "MCQ–FRQ correlation across all 28 models"),
                (f"{tc['pearson_headroom']:.2f}", f"the same correlation among the {int(tc['n_headroom'])} models with headroom"),
            ]
        )
        st.error(
            "**Format agreement collapses where it matters.** Among saturated "
            "models both formats read ~100%, which inflates the pooled "
            "correlation. Restricted to the models that actually vary, MCQ and "
            "free-response ability correlate at only "
            f"r = {tc['pearson_headroom']:.2f}. Whatever the multiple-choice "
            "items measure, the free-response items are substantially not "
            "measuring the same thing.",
            icon=":material/error:",
        )

    if len(transfer):
        st.markdown("#### Fitting on one format, predicting the other")
        st.dataframe(
            transfer.rename(columns={"direction": "Direction", "logloss": "Log-loss"}),
            hide_index=True,
            width="stretch",
            column_config={"Log-loss": st.column_config.NumberColumn(format="%.3f")},
        )
        st.caption(
            "MCQ→FRQ transfer is severe (1.06 against 0.37 in-sample). The "
            "reverse direction holds up far better. Free-response ability "
            "implies multiple-choice ability; the converse does not follow."
        )

with tab_anchor:
    st.markdown(
        "The whole framework rests on one assumption: that items children "
        "acquire later are genuinely harder. If item difficulty does not track "
        "normative acquisition age, the age axis is decoration."
    )
    try:
        reg = D.guttman("item_age_regression.csv")
        diff = D.guttman("item_difficulty_vs_age.csv")
    except Exception as exc:  # noqa: BLE001
        st.warning(f"Item-difficulty artifacts unavailable: {exc}")
        reg = diff = None

    if diff is not None and len(diff):
        colors = T.construct_colors()
        fig = go.Figure()
        for construct, g in diff.groupby("tom_construct"):
            fig.add_trace(
                go.Scatter(
                    x=g["age_mid"] + np.random.default_rng(3).uniform(-0.12, 0.12, len(g)),
                    y=g["difficulty_logit"], mode="markers", name=str(construct),
                    marker=dict(size=7, color=colors.get(construct, T.MUTED), opacity=0.8,
                                line=dict(color="white", width=0.5)),
                    hovertemplate=(
                        "<b>%{customdata[0]}</b><br>%{customdata[1]}<br>"
                        "normed age %{x:.1f} yr<br>difficulty %{y:.2f} logits<extra></extra>"
                    ),
                    customdata=np.stack([g["item_id"], g["tom_dimension"]], axis=-1),
                )
            )
        pooled = reg[reg["dataset"] == "pooled"].iloc[0] if reg is not None and len(reg) else None
        if pooled is not None:
            xs = np.linspace(diff["age_mid"].min(), diff["age_mid"].max(), 30)
            intercept = diff["difficulty_logit"].mean() - pooled["ols_slope_logit_per_year"] * diff["age_mid"].mean()
            fig.add_trace(
                go.Scatter(
                    x=xs, y=intercept + pooled["ols_slope_logit_per_year"] * xs,
                    mode="lines", line=dict(color=T.INK, width=1.8, dash="dash"),
                    name="OLS fit", hoverinfo="skip",
                )
            )
        fig.update_xaxes(title_text="normative acquisition age of the item (yr)")
        fig.update_yaxes(title_text="item difficulty (logits)")
        fig.update_layout(height=440, margin=dict(l=10, r=10, t=30, b=10),
                          legend=dict(orientation="h", y=-0.2, x=0, font=dict(size=10)))
        st.plotly_chart(fig, width="stretch", config={"displayModeBar": False})

    if reg is not None and len(reg):
        st.dataframe(
            reg.rename(
                columns={
                    "dataset": "Dataset", "n_items": "Items",
                    "ols_slope_logit_per_year": "OLS slope (logits/yr)",
                    "ols_p": "OLS p", "ols_r2": "OLS r²",
                    "spearman_age_difficulty": "Spearman",
                    "mixed_slope_logit_per_year": "Mixed slope", "mixed_p": "Mixed p",
                }
            )[["Dataset", "Items", "OLS slope (logits/yr)", "OLS p", "OLS r²",
               "Spearman", "Mixed slope", "Mixed p"]],
            hide_index=True,
            width="stretch",
            column_config={
                c: st.column_config.NumberColumn(format="%.3f")
                for c in ["OLS slope (logits/yr)", "OLS p", "OLS r²", "Spearman",
                          "Mixed slope", "Mixed p"]
            },
        )
        st.warning(
            "**The weakest link.** Pooled, item difficulty does rise with "
            "normative age (slope 0.081 logits/yr, p = .013). It explains "
            "only **3%** of the variance in difficulty, and once dimension is "
            "included as a random effect, the slope reverses and vanishes "
            "(−0.008, p = .88). Items from later-acquired dimensions "
            "are somewhat harder on average across dimensions, but "
            "within the item bank, normative age is close to useless as a "
            "predictor of how hard an individual item is for a model. The age "
            "axis is a meaningful ordering of dimensions; it is not a "
            "difficulty metric for items.",
            icon=":material/warning:",
        )

U.pull(
    "This makes the developmental framing specific: "
    "the sequence is a good interpretive scaffold. It "
    "holds in forced choice and weakens in free response, and it should be "
    "reported with those boundaries attached rather than as a single headline."
)

U.about_the_numbers()
U.caveats()
