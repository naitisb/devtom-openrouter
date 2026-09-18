"""Shared UI furniture: the claim banner, stat rows, filters, caveat panels.

Every analysis page opens with a one-sentence claim and closes with the caveats
that qualify it. That pairing is deliberate — the R scripts carry their caveats
in figure subtitles, and dropping them in translation would misrepresent the
work.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

import pandas as pd
import streamlit as st

from . import compute as M
from . import constants as K
from . import data as D
from . import theme as T

CSS = f"""
<style>
  .block-container {{ max-width: 1180px; padding-top: 2.4rem; }}
  .dv-kicker {{
      font-size: 0.72rem; letter-spacing: 0.13em; text-transform: uppercase;
      color: {T.MUTED}; font-weight: 600; margin-bottom: 0.35rem;
  }}
  .dv-claim {{
      font-size: 1.45rem; line-height: 1.42; color: {T.INK};
      font-weight: 520; margin: 0 0 0.5rem 0; letter-spacing: -0.012em;
  }}
  .dv-sub {{ font-size: 1.0rem; color: {T.BODY}; line-height: 1.62; margin-bottom: 0.4rem; }}
  .dv-rule {{ border: none; border-top: 1px solid {T.HAIRLINE}; margin: 1.5rem 0 1.3rem 0; }}
  .dv-stat {{
      border: 1px solid {T.HAIRLINE}; border-radius: 10px; padding: 0.85rem 1rem;
      background: {T.WASH}; height: 100%;
  }}
  .dv-stat-value {{
      font-size: 1.62rem; font-weight: 600; color: {T.INK};
      line-height: 1.12; letter-spacing: -0.02em;
  }}
  .dv-stat-label {{
      font-size: 0.78rem; color: {T.MUTED}; margin-top: 0.3rem; line-height: 1.38;
  }}
  .dv-pull {{
      border-left: 3px solid {T.ACCENT}; padding: 0.15rem 0 0.15rem 1rem;
      color: {T.BODY}; font-size: 1.02rem; line-height: 1.6; margin: 1.1rem 0;
  }}
  .dv-note {{ font-size: 0.85rem; color: {T.MUTED}; line-height: 1.55; }}
  div[data-testid="stMetricValue"] {{ font-size: 1.5rem; }}
  h1 {{ letter-spacing: -0.028em; }}
  h2 {{ letter-spacing: -0.018em; font-size: 1.32rem; margin-top: 1.6rem; }}
  h3 {{ font-size: 1.06rem; color: {T.INK}; }}
</style>
"""


def boot() -> None:
    """Inject CSS once per page render."""
    st.markdown(CSS, unsafe_allow_html=True)


def header(kicker: str, claim: str, sub: str | None = None) -> None:
    """The claim-first page opening."""
    st.markdown(f'<div class="dv-kicker">{kicker}</div>', unsafe_allow_html=True)
    st.markdown(f'<p class="dv-claim">{_inline_md(claim)}</p>', unsafe_allow_html=True)
    if sub:
        st.markdown(f'<div class="dv-sub">{_inline_md(sub)}</div>', unsafe_allow_html=True)
    st.markdown('<hr class="dv-rule">', unsafe_allow_html=True)


_BOLD = re.compile(r"\*\*(.+?)\*\*", re.DOTALL)
_ITALIC = re.compile(r"(?<![\*\w])\*(?!\s)(.+?)(?<!\s)\*(?![\*\w])", re.DOTALL)


def _inline_md(text: str) -> str:
    """Convert **bold** and *italic* to HTML tags.

    These helpers inject raw HTML, and Streamlit does not run its Markdown
    parser inside a raw HTML block — so `**x**` would otherwise render as
    literal asterisks. Doing the conversion here means callers can write
    Markdown emphasis anywhere without having to remember which helper escapes
    it.
    """
    text = _BOLD.sub(r"<b>\1</b>", text)
    return _ITALIC.sub(r"<i>\1</i>", text)


def pull(text: str) -> None:
    st.markdown(f'<div class="dv-pull">{_inline_md(text)}</div>', unsafe_allow_html=True)


def note(text: str) -> None:
    st.markdown(f'<div class="dv-note">{_inline_md(text)}</div>', unsafe_allow_html=True)


def stat_row(stats: list[tuple[str, str]]) -> None:
    """A row of big-number tiles: (value, label)."""
    cols = st.columns(len(stats))
    for col, (value, label) in zip(cols, stats):
        with col:
            st.markdown(
                f'<div class="dv-stat"><div class="dv-stat-value">{value}</div>'
                f'<div class="dv-stat-label">{_inline_md(label)}</div></div>',
                unsafe_allow_html=True,
            )


# --- Filters ----------------------------------------------------------------
@dataclass
class Selection:
    tasks: list[str]
    families: list[str]
    discriminating_only: bool
    age_formula: str = "ratio"
    frame: pd.DataFrame = field(default_factory=pd.DataFrame)

    @property
    def n_models(self) -> int:
        return int(self.frame["model"].nunique()) if len(self.frame) else 0

    @property
    def task_caption(self) -> str:
        if len(self.tasks) == 2:
            return "MCQ and free response pooled"
        return self.tasks[0] if self.tasks else "no format selected"


FORMAT_CHOICES = ["Both (pooled)", "MCQ only", "Free response only"]


def sidebar_filters(
    key: str,
    show_format: bool = True,
    show_family: bool = True,
    show_saturation: bool = True,
    show_age_formula: bool = False,
    default_format: str = "Both (pooled)",
) -> Selection:
    """The shared filter set. Returns the selections plus the filtered frame."""
    df = D.item_level()

    with st.sidebar:
        st.markdown("### Filters")

        tasks = ["MCQ", "Free response"]
        if show_format:
            choice = st.radio(
                "Elicitation format",
                FORMAT_CHOICES,
                index=FORMAT_CHOICES.index(default_format),
                key=f"{key}_fmt",
                help=(
                    "Every item was run in both formats. A finding that appears "
                    "in only one is flagged as format-fragile."
                ),
            )
            tasks = {
                "Both (pooled)": ["MCQ", "Free response"],
                "MCQ only": ["MCQ"],
                "Free response only": ["Free response"],
            }[choice]

        all_families = [f for f in T.family_order() if f in set(df["family"])]
        families = all_families
        if show_family:
            families = st.multiselect(
                "Model families", all_families, default=all_families, key=f"{key}_fam"
            )
            if not families:
                families = all_families

        discriminating = False
        if show_saturation:
            discriminating = st.toggle(
                "Discriminating models only",
                value=False,
                key=f"{key}_sat",
                help=(
                    f"Hide models scoring at or above {K.SATURATION_CUTOFF:.0%} "
                    "overall. Saturated models have no profile shape left to "
                    "read — this is the same subgroup the scale-validity "
                    "analysis uses."
                ),
            )

        age_formula = "ratio"
        if show_age_formula:
            label = st.radio(
                "Age-equivalent formula",
                ["Ratio (can exceed the band)", "Capped at the band"],
                key=f"{key}_age",
                help="Both forms appear in the R pipeline; see 'About the numbers'.",
            )
            age_formula = "ratio" if label.startswith("Ratio") else "capped"

    frame = M.filter_tasks(df, tasks)
    frame = frame[frame["family"].isin(families)]

    if discriminating:
        overall = frame.groupby("model")["correct"].mean()
        keep = overall[overall < K.SATURATION_CUTOFF].index
        frame = frame[frame["model"].isin(keep)]

    return Selection(
        tasks=tasks,
        families=families,
        discriminating_only=discriminating,
        age_formula=age_formula,
        frame=frame,
    )


def selection_caption(sel: Selection) -> None:
    bits = [f"**{sel.n_models}** models", sel.task_caption]
    if sel.discriminating_only:
        bits.append(f"saturated models (≥{K.SATURATION_CUTOFF:.0%}) hidden")
    note(" · ".join(bits))


# --- Recurring explanatory panels ------------------------------------------
def about_the_numbers() -> None:
    with st.expander("About the numbers", expanded=False):
        prov = D.provenance()
        src = prov.get("sources", {}).get("item_level", {})
        st.markdown(
            f"""
**Where the data comes from.** Every figure here is computed from
`results/item_level.csv` — one row per (model × item × format),
**{src.get('rows', 0):,} rows** covering **{src.get('models', 0)} models** and
**{src.get('items', 0)} items**. That file was regenerated on
**{src.get('mtime', 'unknown')[:10]}** when two models were excluded from the
panel. Most subtrees under `results/modeling/` predate that regeneration and
still contain the excluded models, so this app **recomputes** descriptives,
mastery, age equivalents, Guttman structure and coherence in Python rather
than reading those stale tables.

Only two modeling subtrees postdate the regeneration, and only their results
are read verbatim — the things that cannot be recomputed cheaply: the
10,000-draw permutation null and Rasch item parameters
(`guttman_sequence/latest`, {prov.get('sources', {}).get('guttman', {}).get('mtime', '?')[:10]}),
and the cross-validated log-loss, format transfer and PCA
(`scale_validity/latest`, {prov.get('sources', {}).get('scale_validity', {}).get('mtime', '?')[:10]}).

**The developmental axis.** Age bands are the 12 dimension-level norms from
`docs/dev_norms.md` §1. The item table also carries a per-*item* age band, and
those vary within a dimension (the Emotion Recognition items span midpoints
3.5–7.5 yr, because the source tasks were normed on different samples). The
dimension-level band is what the headline figures use; per-item bands stay
visible in the item explorer.

**Age equivalents** convert accuracy on a dimension into a point on the
developmental scale:

- *Ratio* — `age_mid × (accuracy / 0.80)`. Equals the normative midpoint
  exactly at the 80% mastery criterion, and can run above the band.
- *Capped* — the same, capped at the midpoint, so a model can fall behind the
  band but never lead it.

Both appear in the R pipeline. Results are clamped to the scale's documented
{K.AGE_MIN:g}–{K.AGE_MAX:g} yr range.

**Ordering.** {K.DIM_RANK_DIFFERS_FROM_SOURCE}

**Ties.** {K.TIED_RANK_NOTE}
"""
        )


def caveats(extra: list[str] | None = None) -> None:
    items = [
        "**Small panel.** 28 models is a small sample for the model-level "
        "statistics; treat individual coefficients as suggestive.",
        "**Ceiling effects.** Six models score ≥99% overall. A profile with no "
        "variance has no shape to read, which is why the discriminating-models "
        "filter exists — the sawtooth claim is about *shape*, not *level*.",
        "**Contamination is not modelled.** These are validated tasks from the "
        "published literature; some may appear in training data. The item "
        "wording was modified to remove semantic priming, which helps but does "
        "not rule it out.",
        "**The age scale is a progression axis, not a mental age.** Assigning a "
        "model a human-calibrated age would be a category error. The axis "
        "orders competencies; it does not claim a model *is* a six-year-old.",
        "**Advanced-ToM ordering is approximate.** Dimensions 6–12 have no "
        "settled acquisition order in the literature.",
    ]
    if extra:
        items = extra + items
    with st.expander("Caveats that qualify this page", expanded=False):
        for item in items:
            st.markdown(f"- {item}")


def snapshot_guard() -> bool:
    """Render a helpful message and return False if the snapshot is missing."""
    if D.snapshot_exists():
        return True
    st.error("The data snapshot has not been built yet.")
    st.markdown(
        "This app reads a frozen snapshot rather than the live `results/` tree. "
        "Build it once:"
    )
    st.code("python app/prepare_data.py", language="bash")
    st.caption(
        "The snapshot is ~2 MB: the item-level table, the item bank, and the "
        "two modeling subtrees that postdate the last data regeneration."
    )
    return False
