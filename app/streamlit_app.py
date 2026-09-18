"""Developmental Theory of Mind Evaluations — entry point.

An interactive companion to "Towards a Mental Model for Understanding Machine
Reasoning". The app follows the essay's arc: a composite score hides the
structure that matters, developmental psychology gives us a way to expose it,
and the exposed structure says these models are not acquiring theory of mind
the way children do.

Run it with:

    make app          # builds the snapshot if needed, then serves
    streamlit run app/streamlit_app.py
"""
from __future__ import annotations

import sys
from pathlib import Path

import streamlit as st

APP_DIR = Path(__file__).resolve().parent
if str(APP_DIR) not in sys.path:
    sys.path.insert(0, str(APP_DIR))

st.set_page_config(
    page_title="Developmental Theory of Mind Evaluations",
    page_icon="🪜",
    layout="wide",
    initial_sidebar_state="expanded",
)

PAGES = {
    "Start": [
        st.Page("views/trust_gap.py", title="The trust gap", icon=":material/target:", default=True),
    ],
    "The argument": [
        st.Page("views/method.py", title="Why developmental psychology", icon=":material/psychology:"),
        st.Page("views/instrument.py", title="The instrument", icon=":material/quiz:"),
        st.Page("views/sawtooth.py", title="The sawtooth", icon=":material/stairs:"),
        st.Page("views/violations.py", title="Ordinal violations", icon=":material/rule:"),
    ],
    "Stress-testing it": [
        st.Page("views/trajectory.py", title="Does it improve?", icon=":material/trending_up:"),
        st.Page("views/validity.py", title="Is the scale trustworthy?", icon=":material/verified:"),
    ],
    "So what": [
        st.Page("views/implications.py", title="What this buys you", icon=":material/lightbulb:"),
    ],
    "Explore": [
        st.Page("views/explore.py", title="Browse the data", icon=":material/table_chart:"),
    ],
}

nav = st.navigation(PAGES)

with st.sidebar:
    st.markdown("### Developmental Theory of Mind Evaluations")
    st.caption(
        "Mapping language models onto the developmental sequence children "
        "follow when they acquire theory of mind."
    )
    st.markdown(
        "[Read the essay](https://naiti.substack.com/p/towards-a-mental-model-for-understanding)",
    )
    st.divider()

nav.run()

with st.sidebar:
    st.divider()
    st.caption(
        "12 ToM dimensions · 184 scored items · 28 models · 5 families · "
        "Sep 2023 – Jul 2026. Evaluated under a zero-data-retention, "
        "non-training routing policy."
    )
