"""The methodological argument: why developmental psychology transfers."""
from __future__ import annotations

import pandas as pd
import streamlit as st

from devtom import compute as M
from devtom import constants as K
from devtom import data as D
from devtom import theme as T
from devtom import ui as U

U.boot()
if not U.snapshot_guard():
    st.stop()

st.title("Why developmental psychology")

U.header(
    kicker="The method",
    claim=(
        "Early childhood cognition is a black box with noisy inputs and "
        "unreliable outputs. Developmental psychologist have already built the tools "
        "for the situation we are considering with language models."
    ),
    sub=(
        "Infants cannot self-report. Young children cannot follow multi-step "
        "instructions, fatigue within minutes, and produce verbal output that "
        "is absent or unreliable. The entire methodology of the field is built "
        "around inferring latent structure from a severely constrained "
        "behavioural signal. This is the position we are in with models."
    )
)

# --- The parallel -----------------------------------------------------------
left, right = st.columns(2, gap="large")

with left:
    st.markdown(
        f"""
<div style="border:1px solid {T.HAIRLINE};border-radius:12px;padding:1.1rem 1.25rem;height:100%">
<div style="font-size:0.72rem;letter-spacing:0.12em;text-transform:uppercase;
            color:{T.MUTED};font-weight:600;margin-bottom:0.6rem">The child</div>

<p style="color:{T.BODY};line-height:1.62;margin:0">
Cannot be instructed. Cannot introspect. So tasks are designed to be
minimal by isolating a single construct with the fewest possible
confounds, such that passing is hard to explain before the targe age
reaches this competency.
</p>
</div>
""",
        unsafe_allow_html=True,
    )

with right:
    st.markdown(
        f"""
<div style="border:1px solid {T.HAIRLINE};border-radius:12px;padding:1.1rem 1.25rem;height:100%">
<div style="font-size:0.72rem;letter-spacing:0.12em;text-transform:uppercase;
            color:{T.MUTED};font-weight:600;margin-bottom:0.6rem">The model</div>

<p style="color:{T.BODY};line-height:1.62;margin:0">
Can be instructed, and will answer anything. A model
cannot be expected to introspect and give a trustworthy answer about its own
processes. The same minimal-task discipline applies, and the
behavior has to carry the inference.
</p>
</div>
""",
        unsafe_allow_html=True,
    )

# --- The category error -----------------------------------------------------
st.markdown("## What this is not")

st.warning(
    "**This does not assign models a single age.** That would be a category "
    "error. A psychometric framework borrowed from developmental psychology "
    "does not license treating a model as a human of one age. What it "
    "licenses is placing systems on a **developmental progression axis** with an "
    "ordering of competencies, validated across human populations, along which "
    "a system's profile can be located.",
    icon=":material/warning:",
)

# --- The ordinal dependency logic ------------------------------------------
st.markdown("## The diagnostic: ordinal dependencies")

st.markdown(
    "Across dozens of constructs we have decades of data on the *order* in "
    "which competencies are reliably acquired, and which depend on which. "
    "Children acquire A before B, consistently, across populations, because B "
    "depends on A. That regularity is what turns a behavioural pattern into "
    "evidence about mechanism."
)

U.pull(
    "If a model demonstrates B without A, that is not noise. It is direct "
    "evidence that the model is reaching B by a different route than humans do "
    "and this constrains the space of hypotheses about what the model is "
    "actually doing."
)

st.markdown("#### Try the inference")
st.caption(
    "Set a model's performance on a prerequisite skill and on a skill that "
    "depends on it, and read off what the pattern licenses you to conclude."
)

demo_a, demo_b, demo_out = st.columns([1, 1, 1.5], gap="large")
with demo_a:
    prereq = st.select_slider(
        "**A** — Diverse Desires  \n*normed 2–3 yr*",
        options=["fails", "passes"],
        value="fails",
    )
with demo_b:
    dependent = st.select_slider(
        "**B** — Sarcasm  \n*normed 6–8 yr, requires belief reasoning*",
        options=["fails", "passes"],
        value="passes",
    )

with demo_out:
    if prereq == "passes" and dependent == "passes":
        st.success(
            "**Consistent with the human route.** Both acquired, in an order "
            "that respects the dependency. Uninformative on its own, but it is "
            "what a child-like profile looks like.",
            icon=":material/check_circle:",
        )
    elif prereq == "passes" and dependent == "fails":
        st.info(
            "**Consistent with the human route.** The prerequisite is in place "
            "and the later skill is not. This is exactly the pattern a child in "
            "the middle of the sequence produces.",
            icon=":material/schedule:",
        )
    elif prereq == "fails" and dependent == "fails":
        st.info(
            "**Uninformative.** Nothing acquired, so the ordering is not tested.",
            icon=":material/help:",
        )
    else:
        st.error(
            "**Dissociation.** The model reaches the dependent skill without "
            "the prerequisite. No validated human population produces this "
            "pattern, so whatever the model is doing to answer sarcasm items, "
            "it is not building on desire understanding the way a child does. "
            "This is the signal the whole project is designed to detect.",
            icon=":material/priority_high:",
        )

# --- How common is it, really ----------------------------------------------
st.markdown("## How often does that actually happen here?")

df = D.item_level()
dim_acc = M.dimension_accuracy(df)
violations = M.prerequisite_violations(dim_acc)
matrix = M.mastery_matrix(dim_acc)
errors = M.guttman_errors(matrix)

n_models = int(dim_acc["model"].nunique())
n_with = int(violations["model"].nunique()) if len(violations) else 0
clean = n_models - n_with
worst_gap = violations["age_inversion"].max() if len(violations) else 0

U.stat_row(
    [
        (f"{n_with}/{n_models}", "models that pass at least one skill while failing one of its developmental prerequisites"),
        (f"{len(violations):,}", "distinct prerequisite dissociations across the panel"),
        (f"{worst_gap:.1f} yr", "largest normative age inversion observed"),
        (f"{clean}", "models with a fully ordered profile"),
    ]
)

U.note(
    "Pooled across both elicitation formats, using the 80% mastery criterion. "
    "Every one of these is enumerable. The "
    "[ordinal violations](violations) page lists them model by model."
)

st.markdown('<hr class="dv-rule">', unsafe_allow_html=True)
st.markdown("**Next:** [the instrument that produces these numbers](instrument).")

U.about_the_numbers()
U.caveats()
