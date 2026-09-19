"""What the framework actually buys you, and what it does not."""
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

st.title("What this buys you")

U.header(
    kicker="So what",
    claim=(
        "Where a model's competence departs from the human sequence "
        "tells you where to build a safeguard. It characterizes "
        "the nuance, unlike a composite score."
    ),
    sub=(
        "The mathematician using a model to disprove an age-old conjecture should "
        "stay in the driver's seat of that discovery. Staying there requires "
        "knowing the tool's shape, not just its score."
    ),
)

# --- Reliability card -------------------------------------------------------
st.markdown("## A reliability card, per model")

st.markdown(
    "Everything below is read off the evaluation, not asserted. Pick a model "
    "and this is what its profile licenses you to say about where it is and is "
    "not dependable at reasoning about other minds."
)

df = D.item_level()
dim_acc = M.dimension_accuracy(df)
age = M.with_age_equivalent(dim_acc)
summary = M.model_summary(df).sort_values("release_date", ascending=False)
violations = M.prerequisite_violations(dim_acc)

labels = {
    row.model: f"{row.short_model}  ·  {row.family}  ·  {row.release_date:%b %Y}"
    for row in summary.itertuples()
}
picked = st.selectbox(
    "Model", summary["model"].tolist(), format_func=lambda m: labels.get(m, m)
)

row = summary[summary["model"] == picked].iloc[0]
profile = age[age["model"] == picked].sort_values("rank")
metrics = M.sawtooth_metrics(profile)
mine = violations[violations["model"] == picked]

weak = profile[~profile["mastered"]].sort_values("accuracy")
fragile = profile[
    (profile["accuracy"] >= K.MASTERY_THRESHOLD) & (profile["accuracy"] < 0.9)
]

card_l, card_r = st.columns([1.15, 1], gap="large")

with card_l:
    st.markdown(f"### {row.short_model}")
    U.note(
        f"{row.family} · {row.tier} · released {row.release_date:%B %Y}"
        + (f" · ~{row.params_b:g}B parameters (estimated)" if pd.notna(row.params_b) else "")
    )
    st.markdown("")
    m1, m2, m3 = st.columns(3)
    m1.metric("Composite", f"{row.accuracy:.0%}")
    m2.metric("Mastered", f"{int(profile['mastered'].sum())}/12")
    m3.metric("Dissociations", f"{len(mine)}")

    st.plotly_chart(
        G.profile_lines(profile, highlight=picked, height=330),
        width="stretch",
        config={"displayModeBar": False},
    )

with card_r:
    st.markdown("#### Do not rely on it for")
    if weak.empty:
        st.markdown(
            f'<div class="dv-note">Nothing in this battery — it clears the 80% '
            f"criterion on all twelve dimensions. That is a statement about "
            f"this instrument's ceiling, not about the absence of failure "
            f"modes.</div>",
            unsafe_allow_html=True,
        )
    else:
        for item in weak.head(5).itertuples():
            st.markdown(
                f"""
<div style="border-left:3px solid {T.CRIMSON};padding:0.35rem 0 0.35rem 0.85rem;
            margin-bottom:0.55rem">
  <div style="color:{T.INK};font-weight:560">{item.tom_dimension}</div>
  <div style="font-size:0.84rem;color:{T.MUTED}">
    {item.accuracy:.0%} accuracy · children acquire this at
    {item.age_lo:g}–{item.age_hi:g} yr
  </div>
</div>
""",
                unsafe_allow_html=True,
            )

    if not fragile.empty:
        st.markdown("#### Marginal")
        st.markdown(
            f'<div class="dv-note">Above the criterion but below 90%: '
            + ", ".join(f"<b>{d}</b>" for d in fragile["tom_dimension"])
            + ". Passing, but not with margin.</div>",
            unsafe_allow_html=True,
        )

    if len(mine):
        st.markdown("#### Reasoning by a different route")
        top = mine.nlargest(3, "age_inversion")
        for item in top.itertuples():
            st.markdown(
                f"""
<div style="border-left:3px solid {T.ACCENT};padding:0.35rem 0 0.35rem 0.85rem;
            margin-bottom:0.55rem">
  <div style="color:{T.INK};font-size:0.92rem;line-height:1.45">
    Passes <b>{item.passed}</b> ({item.passed_acc:.0%}) while failing
    <b>{item.failed}</b> ({item.failed_acc:.0%})
  </div>
  <div style="font-size:0.84rem;color:{T.MUTED}">
    a {item.age_inversion:.1f}-year inversion of the human order
  </div>
</div>
""",
                unsafe_allow_html=True,
            )
        U.note(
            "Whatever supports the later skill here, it is not the earlier one. "
            "Do not assume competence on the harder task implies competence on "
            "the easier one it nominally depends on."
        )

# --- What is and is not established ----------------------------------------
st.markdown("## What this project establishes")

established, suggestive, unsupported = st.columns(3, gap="large")

CARD = """
<div style="border:1px solid {border};border-top:3px solid {accent};border-radius:10px;
            padding:1rem 1.1rem;height:100%">
  <div style="font-size:0.72rem;letter-spacing:0.1em;text-transform:uppercase;
              color:{accent};font-weight:700;margin-bottom:0.7rem">{title}</div>
  {body}
</div>
"""


def _items(points: list[str]) -> str:
    return "".join(
        f'<div style="color:{T.BODY};font-size:0.9rem;line-height:1.55;'
        f'margin-bottom:0.65rem">{p}</div>'
        for p in points
    )


with established:
    st.markdown(
        CARD.format(
            border=T.HAIRLINE, accent=T.TEAL, title="Established",
            body=_items([
                "The 12-dimension profile is <b>essentially unidimensional</b> "
                "(PC1 = 81%, one component retained).",
                "A <b>1-parameter</b> developmental-age model predicts held-out "
                "items better than a 12-parameter per-dimension model.",
                "In multiple choice, the human developmental ordering "
                "organizes mastery <b>significantly better than chance</b> "
                "(p = .008).",
                "In <b>free response</b>, among models with headroom, "
                "<b>no</b> model produces a monotonic developmental profile; "
                "the median largest backward step is ~3.8 years.",
                "Accuracy <b>improves markedly</b> with release date and size.",
            ]),
        ),
        unsafe_allow_html=True,
    )

with suggestive:
    st.markdown(
        CARD.format(
            border=T.HAIRLINE, accent=T.AMBER, title="Suggestive",
            body=_items([
                "A minority of models show outright <b>prerequisite "
                "dissociations</b> — passing a skill while failing one it "
                "depends on.",
                "Newer and larger models may be <b>slightly less</b> "
                "developmentally coherent, not more — but every coefficient is "
                "non-significant at n = 28.",
                "Faux pas detection is the <b>hardest dimension</b> for the "
                "panel, echoing Strachan et al. (2024).",
            ]),
        ),
        unsafe_allow_html=True,
    )

with unsupported:
    st.markdown(
        CARD.format(
            border=T.HAIRLINE, accent=T.CRIMSON, title="Not supported",
            body=_items([
                "That the developmental ordering holds in <b>free response</b> "
                "— there it is indistinguishable from a random ordering "
                "(p = .12).",
                "That the age scale <b>predicts better</b> than a model's own "
                "overall accuracy. It does not.",
                "That normative age predicts <b>item</b> difficulty. It "
                "explains 3% of variance, and nothing once dimension is "
                "accounted for.",
                "Any claim that a model <b>is</b> a child of some age. That "
                "remains a category error.",
            ]),
        ),
        unsafe_allow_html=True,
    )

# --- Where next -------------------------------------------------------------
st.markdown("## Where this goes next")

st.markdown(
    """
The bottleneck is headroom. Six models in this panel score at or above 99%,
so the instrument has stopped discriminating exactly where the interesting
systems are. Three directions follow directly:

1. **Extend the ceiling.** The sequence continues past faux pas detection into
   recursive mentalising of order 3 and above, which is fragile even in
   10–11-year-olds. That is where frontier models would still vary.
2. **Fix the format gap.** MCQ and free response correlate at r = .28 among
   models with headroom. Until that is understood, every finding needs a
   format qualifier. Free response is the more demanding, more
   informative of the two.
3. **Move from batteries to agents.** These items are single-turn and
   static. The same ordinal logic applies to multi-step agentic behaviour,
   where a dissociation between a skill and its prerequisite has immediate
   consequences for what the system does, not just what it answers.
"""
)

U.pull(
    "Translating measures from developmental psychology that "
    "encode a logical sequence of acquisition helps us check that a "
    "system's reasoning follows a progression we can recognise, describe, and "
    "therefore trust. That check is worth running before deployment rather "
    "than after."
)

st.markdown('<hr class="dv-rule">', unsafe_allow_html=True)
st.markdown(
    "Read the essay: [Towards a Mental Model for Understanding Machine "
    "Reasoning](https://naiti.substack.com/p/towards-a-mental-model-for-understanding) · "
    "Or [browse the underlying data](explore)."
)

U.about_the_numbers()
