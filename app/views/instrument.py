"""The instrument: the 12 dimensions, the item bank, and its quality."""
from __future__ import annotations

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

st.title("The instrument")

U.header(
    kicker="What was actually asked",
    claim=(
        "Twelve theory-of-mind dimensions, each anchored to a validated age "
        "band from the child-development literature, each item run twice — "
        "once as multiple choice, once as free response."
    ),
    sub=(
        "Theory of mind develops in a particular order. Children generally pass "
        "belief-reasoning tasks before they pass sarcasm, because understanding "
        "sarcasm requires reasoning about beliefs. That ordering is the ruler; "
        "these items are the marks on it."
    ),
)

bank = D.item_bank()
df = D.item_level()

tab_scale, tab_items, tab_design, tab_quality = st.tabs(
    ["The scale", "Browse items", "Item design", "Does the instrument work?"]
)

# --- The scale --------------------------------------------------------------
with tab_scale:
    counts = (
        bank.groupby(["tom_dimension", "format"]).size().unstack(fill_value=0)
    )
    acc = df.groupby("tom_dimension")["correct"].mean()

    table = K.DIMENSIONS.copy()
    table["MCQ"] = table["dimension"].map(counts.get("MCQ", pd.Series(dtype=int))).fillna(0)
    table["Free response"] = (
        table["dimension"].map(counts.get("Free response", pd.Series(dtype=int))).fillna(0)
    )
    table["Panel accuracy"] = table["dimension"].map(acc)
    display = table[
        ["rank", "dimension", "band", "construct", "MCQ", "Free response",
         "Panel accuracy", "citation"]
    ].rename(
        columns={
            "rank": "#",
            "dimension": "Dimension",
            "band": "Age band",
            "construct": "Construct",
            "citation": "Source",
        }
    )
    display["#"] = display["#"] + 1

    st.dataframe(
        display,
        hide_index=True,
        width="stretch",
        column_config={
            "Panel accuracy": st.column_config.ProgressColumn(
                "Panel accuracy",
                help="Mean accuracy across all 28 models, both formats pooled.",
                format="percent",
                min_value=0,
                max_value=1,
            ),
            "MCQ": st.column_config.NumberColumn("MCQ", width="small"),
            "Free response": st.column_config.NumberColumn("FRQ", width="small"),
        },
    )

    U.note(
        "Dimensions 1–5 follow the canonical Wellman & Liu (2004) ToM-scale "
        "ordering. Dimensions 6–12 are 'advanced ToM', where the literature has "
        "no settled acquisition order — that ordering is a best-effort "
        "synthesis, approximate rather than a strict ruler."
    )

    scored = set(df["item_id"])
    unscored = bank[~bank["item_id"].isin(scored)]
    if len(unscored):
        with st.expander(
            f"{len(unscored)} items in the bank have no results", expanded=False
        ):
            st.markdown(
                f"The bank holds **{len(bank)}** items, but **{len(scored)}** "
                "carry scored responses — the counts in the table above are "
                "bank counts, while every accuracy figure in this app is "
                "computed over the scored set only. The gap is entirely "
                "multiple-choice items, concentrated in belief reasoning:"
            )
            st.dataframe(
                unscored.groupby(["tom_dimension", "format"])
                .size()
                .reset_index(name="items")
                .rename(columns={"tom_dimension": "Dimension", "format": "Format",
                                 "items": "Unscored"}),
                hide_index=True,
                width="stretch",
            )
            st.caption(
                "Most likely these were added to the bank after the eval sweep "
                "was run. Re-running the MCQ task would fold them in."
            )

    with st.expander("Two band disagreements the norms document records"):
        for caveat in K.BAND_CAVEATS:
            st.markdown(f"- {caveat}")
        st.markdown(f"- {K.TIED_RANK_NOTE}")

# --- Browse items -----------------------------------------------------------
with tab_items:
    if K.REVEAL_ALL_ITEMS:
        st.warning(
            "`DEVTOM_REVEAL_ITEMS` is set, so the full stimulus text is shown "
            "for every item. Do not run a public instance this way.",
            icon=":material/lock_open:",
        )
    else:
        examples = bank[bank["item_id"].isin(K.WORKED_EXAMPLE_IDS)]
        where = " and ".join(
            f"**{r.item_id}** ({r.tom_dimension} → {r['format']})"
            for _, r in examples.iterrows()
        ) or "none configured"
        st.info(
            "**Item text is shown for worked examples only.** Every item's "
            "metadata and difficulty is here, but the stimulus text, answer "
            "options and rubrics are withheld for all but the worked examples "
            "— these are validated instruments, and rendering the whole bank "
            "as a crawlable page would feed it to the next generation of "
            "training crawlers, the exact outcome the zero-data-retention "
            "routing policy was chosen to avoid at eval time.\n\n"
            f"Open in full: {where}. They are the same scenario in both "
            "elicitation formats, so together they show how the dual-format "
            "design works.",
            icon=":material/visibility_off:",
        )

    c1, c2 = st.columns([2, 1])
    with c1:
        dimension = st.selectbox(
            "Dimension", K.DIMENSION_ORDER, key="item_dim",
            format_func=lambda d: (
                f"{K.DIMENSION_RANK[d] + 1}. {d}  ·  "
                f"{K.DIMENSION_BAND[d][0]:g}–{K.DIMENSION_BAND[d][1]:g} yr"
            ),
        )
    with c2:
        fmt = st.radio(
            "Format", ["MCQ", "Free response"], key="item_fmt", horizontal=True
        )

    subset = bank[(bank["tom_dimension"] == dimension) & (bank["format"] == fmt)]
    if subset.empty:
        st.info("No items of that format in this dimension.")
    else:
        # How hard was each item for the panel?
        item_acc = (
            df[df["item_id"].isin(subset["item_id"])]
            .groupby("item_id")["correct"]
            .agg(["mean", "size"])
        )
        ctt = M.ctt_item_stats(df).set_index("item_id")

        def _label(i: str) -> str:
            acc = item_acc["mean"].get(i)
            parts = [i]
            if acc is not None and pd.notna(acc):
                parts.append(f"{acc:.0%} of models correct")
            if K.item_is_disclosed(i) and not K.REVEAL_ALL_ITEMS:
                parts.append("worked example")
            return "  ·  ".join(parts)

        pick = st.selectbox(
            "Item", subset["item_id"].tolist(), key="item_pick", format_func=_label
        )
        item = subset[subset["item_id"] == pick].iloc[0]
        disclosed = K.item_is_disclosed(pick)

        body, side = st.columns([2.1, 1], gap="large")
        with body:
            if disclosed:
                st.markdown(
                    f"""
<div style="border:1px solid {T.HAIRLINE};border-radius:12px;padding:1.2rem 1.35rem;
            background:{T.WASH}">
  <div style="font-size:1.03rem;line-height:1.66;color:{T.INK}">{item['prompt']}</div>
</div>
""",
                    unsafe_allow_html=True,
                )

                if item["format"] == "MCQ" and item["choices"]:
                    st.markdown("")
                    letters = "ABCDEFGH"
                    target = str(item["target"]).strip().upper()
                    for i, choice in enumerate(item["choices"]):
                        letter = letters[i] if i < len(letters) else str(i)
                        correct = letter == target
                        mark = "✓" if correct else "&nbsp;&nbsp;"
                        color = T.TEAL if correct else T.HAIRLINE
                        weight = "600" if correct else "400"
                        st.markdown(
                            f"""
<div style="display:flex;gap:0.7rem;align-items:baseline;padding:0.45rem 0.8rem;
            border-left:3px solid {color};margin-bottom:0.3rem">
  <span style="color:{T.MUTED};font-size:0.82rem;width:1rem">{letter}</span>
  <span style="color:{T.INK};font-weight:{weight};line-height:1.5">{choice}</span>
  <span style="color:{T.TEAL};margin-left:auto">{mark}</span>
</div>
""",
                            unsafe_allow_html=True,
                        )
                else:
                    st.markdown("**Target answer**")
                    st.markdown(
                        f'<div style="color:{T.BODY};line-height:1.62;padding:0.2rem 0 0.6rem">'
                        f'{item["target"]}</div>',
                        unsafe_allow_html=True,
                    )
                    if item["rubric"]:
                        st.markdown("**Scoring rubric**")
                        st.markdown(
                            f'<div style="color:{T.BODY};line-height:1.62;'
                            f'border-left:3px solid {T.ACCENT};padding:0.25rem 0 0.25rem 0.9rem">'
                            f'{item["rubric"]}</div>',
                            unsafe_allow_html=True,
                        )
            else:
                shape = (
                    f"Multiple choice, {int(item['n_choices'])} options with one "
                    "correct."
                    if item["format"] == "MCQ"
                    else "Free response, scored against an explicit rubric."
                )
                st.markdown(
                    f"""
<div style="border:1px dashed {T.HAIRLINE};border-radius:12px;padding:1.5rem 1.35rem;
            background:{T.WASH};text-align:center">
  <div style="font-size:0.72rem;letter-spacing:0.12em;text-transform:uppercase;
              color:{T.MUTED};font-weight:600">Item text withheld</div>
  <div style="color:{T.BODY};line-height:1.6;margin-top:0.7rem;max-width:46ch;
              margin-left:auto;margin-right:auto">
    <b>{pick}</b> probes <b>{item['tom_dimension']}</b>, which children
    typically acquire at {item['validated_age_band']}. {shape}
  </div>
  <div style="font-size:0.85rem;color:{T.MUTED};margin-top:0.9rem;max-width:48ch;
              margin-left:auto;margin-right:auto;line-height:1.5">
    Its difficulty and discrimination are on the right. To see what an item
    looks like, open one of the two worked examples, or the
    <b>Item design</b> tab for a before/after rewording.
  </div>
</div>
""",
                    unsafe_allow_html=True,
                )
                st.caption(
                    "The complete bank lives in `data/*.jsonl` in the "
                    "repository for anyone reproducing the study."
                )

        with side:
            if pick in item_acc.index:
                U.stat_row(
                    [(f"{item_acc['mean'][pick]:.0%}", f"of {int(item_acc['size'][pick])} models correct")]
                )
            if pick in ctt.index:
                row = ctt.loc[pick]
                if isinstance(row, pd.DataFrame):
                    row = row.iloc[0]
                disc = row["discrimination"]
                disc_text = f"{disc:.2f}" if pd.notna(disc) else "—"
                st.markdown("")
                U.note(
                    f"<b>Facility</b> {row['facility']:.2f}"
                    f"<span style='color:{T.MUTED}'> — proportion of models correct</span>"
                    f"<br><b>Discrimination</b> {disc_text}"
                    f"<span style='color:{T.MUTED}'> — correlation with total score</span>"
                )
                if row["flag"]:
                    st.caption(f"Flagged: {row['flag']}")

            st.markdown("")
            st.markdown(
                f"""
<div class="dv-note">
<b>Dimension</b><br>{item['tom_dimension']}<br><br>
<b>Construct</b><br>{item['tom_construct']}<br><br>
<b>Normed age band</b><br>{item['validated_age_band']}<br><br>
<b>Format</b><br>{item['format']}<br><br>
<b>Literature basis</b><br>{item['literature_basis']}
</div>
""",
                unsafe_allow_html=True,
            )

            # Which models missed this item? Aggregate, so safe to show.
            missed = df[(df["item_id"] == pick) & (df["correct"] == 0)]
            if len(missed):
                with st.expander(f"{missed['model'].nunique()} models got this wrong"):
                    for name in sorted(missed["short_model"].unique()):
                        st.markdown(f"- {name}")

# --- Item design ------------------------------------------------------------
with tab_design:
    st.markdown("### Removing the semantic shortcut")
    st.markdown(
        "Items were pulled from validated instruments, then reworded wherever "
        "the semantic structure gave the answer away — most often because the "
        "answer word appeared verbatim in the premise. A model can retrieve "
        "that by lexical matching without reasoning about anyone's mind. "
        "All multiple-choice items were also expanded to four options, so "
        "chance is 25% rather than 50%."
    )

    before, after = st.columns(2, gap="large")
    with before:
        st.markdown(
            f"""
<div style="border:1px solid {T.HAIRLINE};border-radius:12px;padding:1.15rem 1.3rem;height:100%">
<div style="font-size:0.72rem;letter-spacing:0.12em;text-transform:uppercase;
            color:{T.MUTED};font-weight:600;margin-bottom:0.7rem">As published</div>
<div style="color:{T.INK};line-height:1.62">
Mr. Tan likes <b style="color:{T.CRIMSON}">eggs</b> for breakfast.
Mrs. Tan likes <b style="color:{T.CRIMSON}">pancakes</b> for breakfast.
It's Mrs. Tan's turn to decide what they eat. What will they most likely have?
</div>
<div style="margin-top:0.9rem;color:{T.BODY};font-size:0.94rem;line-height:1.9">
&nbsp;&nbsp;A&nbsp;&nbsp;Eggs<br>
&nbsp;&nbsp;B&nbsp;&nbsp;<b>Pancakes</b>
</div>
<div style="margin-top:0.9rem;font-size:0.85rem;color:{T.CRIMSON};line-height:1.55">
The answer string appears in the premise, and there are only two options.
Lexical matching gets you there without modelling Mrs. Tan at all.
</div>
</div>
""",
            unsafe_allow_html=True,
        )

    with after:
        st.markdown(
            f"""
<div style="border:1px solid {T.TEAL};border-radius:12px;padding:1.15rem 1.3rem;height:100%">
<div style="font-size:0.72rem;letter-spacing:0.12em;text-transform:uppercase;
            color:{T.TEAL};font-weight:600;margin-bottom:0.7rem">As administered</div>
<div style="color:{T.INK};line-height:1.62">
Mr. Tan likes <b style="color:{T.TEAL}">savory foods</b> for breakfast.
Mrs. Tan likes <b style="color:{T.TEAL}">sweet foods</b> for breakfast.
It's Mrs. Tan's turn to decide what they eat. What will they most likely have?
</div>
<div style="margin-top:0.9rem;color:{T.BODY};font-size:0.94rem;line-height:1.9">
&nbsp;&nbsp;A&nbsp;&nbsp;Whatever is quickest to make, regardless of taste<br>
&nbsp;&nbsp;B&nbsp;&nbsp;<b>Pancakes</b><br>
&nbsp;&nbsp;C&nbsp;&nbsp;Toast, since it's a safe middle ground<br>
&nbsp;&nbsp;D&nbsp;&nbsp;Eggs
</div>
<div style="margin-top:0.9rem;font-size:0.85rem;color:{T.TEAL};line-height:1.55">
Answering now requires mapping "sweet" onto pancakes <i>and</i> holding that
it is Mrs. Tan's preference that governs. The distractors absorb the two
plausible non-mentalising strategies.
</div>
</div>
""",
            unsafe_allow_html=True,
        )

    st.markdown("### Dual elicitation")
    st.markdown(
        "Every scenario was administered both ways: 141 multiple-choice items "
        "and 60 free-response items, the latter scored against an explicit "
        "rubric. There are no matched control items in the bank — the two "
        "formats *are* the robustness check. A finding that shows up in only "
        "one format is flagged as format-fragile, and the "
        "[scale validity](validity) page measures how often that happens."
    )

# --- Instrument quality -----------------------------------------------------
with tab_quality:
    st.markdown(
        "An instrument that cannot separate models tells you nothing about "
        "them. These statistics are recomputed here from the current 28-model "
        "panel rather than read from the pre-exclusion tables."
    )

    stats = M.ctt_item_stats(df)
    rel = M.kr20(df)

    tiles = []
    for row in rel.itertuples():
        tiles.append((f"{row.kr20:.2f}", f"KR-20 internal consistency, {row.task_label} ({row.n_items} items)"))
    tiles.append((f"{(stats['flag'] == 'too easy').mean():.0%}", "of items are at ceiling (>95% of models correct)"))
    U.stat_row(tiles)

    st.plotly_chart(
        G.item_map(stats, height=440),
        width="stretch",
        config={"displayModeBar": False},
    )
    U.note(
        "Facility is the proportion of models answering correctly; "
        "discrimination is the corrected point-biserial correlation with total "
        "score. Items in the shaded band are informative. Items at the far "
        "right are at ceiling for this panel — they separated models in "
        "children's samples but no longer separate frontier models, which is "
        "itself a finding about where the instrument's headroom has gone."
    )

    with st.expander("Item statistics table"):
        st.dataframe(
            stats[
                ["task_label", "item_id", "tom_dimension", "facility",
                 "discrimination", "n_models", "flag"]
            ].rename(
                columns={
                    "task_label": "Format",
                    "item_id": "Item",
                    "tom_dimension": "Dimension",
                    "facility": "Facility",
                    "discrimination": "Discrimination",
                    "n_models": "n models",
                    "flag": "Flag",
                }
            ),
            hide_index=True,
            width="stretch",
            height=420,
        )

st.markdown('<hr class="dv-rule">', unsafe_allow_html=True)
st.markdown("**Next:** [what the profiles look like](sawtooth).")

U.about_the_numbers()
