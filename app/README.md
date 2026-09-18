# DevToM — Streamlit app

An interactive companion to [*Towards a Mental Model for Understanding Machine
Reasoning*](https://naiti.substack.com/p/towards-a-mental-model-for-understanding).

The app follows the essay's argument: a composite benchmark score hides the
structure that matters, developmental psychology gives us a way to expose it,
and the exposed structure says these models are not acquiring theory of mind
the way children do.

## Run it

```bash
make app-deps    # once
make app         # builds the data snapshot if needed, then serves
```

Or directly:

```bash
python app/prepare_data.py
streamlit run app/streamlit_app.py
```

Rebuild the snapshot after re-running the analysis pipeline:

```bash
make app-data
```

## Structure

```
app/
  streamlit_app.py     entry point + navigation
  prepare_data.py      builds the frozen snapshot in app/data/
  requirements.txt     app-only dependencies
  devtom/
    constants.py       the 12 dimensions, age bands, thresholds
    theme.py           colors (frozen from src/roster.py) + Plotly template
    data.py            cached loaders over the snapshot
    compute.py         Python ports of the R pipeline's derived quantities
    charts.py          the figures
    ui.py              claim banners, filters, caveat panels
  views/
    trust_gap.py       what a composite score hides
    method.py          why developmental psychology transfers
    instrument.py      the 12 dimensions, the item bank, item quality
    sawtooth.py        the headline figure
    violations.py      Guttman scaling, permutation null, dissociations
    trajectory.py      improvement over time and with scale
    validity.py        turning the instrument on itself
    implications.py    per-model reliability cards, what is established
    explore.py         open exploration + CSV download
  data/                generated snapshot (~0.5 MB) — safe to commit
```

## Where the numbers come from

The app reads a **frozen snapshot**, not the live `results/` tree. This is
deliberate, and not only for deployability.

`results/item_level.csv` was regenerated on **2026-08-23**, when two models were
excluded from the panel. Only two modeling subtrees were re-run after that:

| Subtree | Last run | Status |
|---|---|---|
| `modeling/guttman_sequence/latest/` | 2026-08-24 | current |
| `modeling/scale_validity/latest/` | 2026-08-23 | current |
| `modeling/mapping`, `inference`, `size_scaling`, `developmental_*` | 2026-07-26 | **predates the exclusions** |
| `modeling/tier_effects`, `stats/*` | 2026-07-28 / 07-26 | **predates the exclusions** |

So the app **recomputes** every descriptive, mastery, age-equivalent, Guttman
and coherence quantity in Python directly from `item_level.csv` (5,152 rows —
instant), and reads verbatim only the two current subtrees, for the things that
cannot be recomputed cheaply: the 10,000-draw permutation null, Rasch item
parameters, cross-validated log-loss, format transfer and the PCA.

That way every number in the app describes the same 28 models. If you re-run
the stale subtrees, nothing here needs to change — `prepare_data.py` picks up
whatever is in `latest/`.

## Two fidelity decisions

Both are surfaced in the app's "About the numbers" panel rather than hidden.

1. **Dimension-level age bands.** `item_level.csv` carries `age_lo/age_hi/age_mid`
   per *item*, and those vary within a dimension (Emotion Recognition items span
   midpoints 3.5–7.5 yr, because the source tasks were normed on different
   samples). The developmental axis uses the 12 canonical dimension-level bands
   from `docs/dev_norms.md` §1 — which is what the headline R strip charts do.
   `constants.py` is the single Python copy of that table; the R pipeline
   duplicates it as three separate `tribble` literals.

2. **Irony is ranked 11th, Faux Pas 12th**, sorting strictly by normative age
   midpoint. `src/constructs.py` and `scripts/6_visualize/_theme.R` had these
   two transposed — putting a 9–11 yr skill ahead of a 6–8 yr one — until that
   was fixed on 2026-09-18; they now agree with this module. The `dim_rank`
   column stored in `results/item_level.csv`, and the Guttman artifacts
   computed from it, still carry the old ordering until the pipeline is re-run.
   The app derives its own rank and never reads that column, so its figures are
   unaffected either way.

## Item disclosure

The **Browse items** tab shows every item's metadata, facility and
discrimination, and which models got it wrong — but the stimulus text, answer
options and rubrics only for the worked examples in
`constants.WORKED_EXAMPLE_IDS`.

The reasoning: this is validated instrumentation, and rendering all 184 items
as a crawlable page would put them in front of the next generation of training
crawlers — the outcome the zero-data-retention routing policy was chosen to
avoid at eval time. The bank is already in a public repo, so this is about not
amplifying it rather than keeping a secret; anyone reproducing the study reads
`data/*.jsonl` directly.

The default pair is `DD_01` / `DD_FR_01` — one scenario in both elicitation
formats. Diverse Desires is the earliest-acquired and least discriminating
dimension in the scale, so it costs the least to disclose, and showing the same
scenario twice is what makes the dual-format design legible.

To browse the full bank locally:

```bash
DEVTOM_REVEAL_ITEMS=1 streamlit run app/streamlit_app.py
```

The app shows a warning banner when that is set. Never set it on a deployed
instance.

## Known data gaps the app surfaces

- **The item bank and the scored set now reconcile exactly** at 184 items
  (124 MCQ + 60 free response). Until 2026-09-18 the MCQ bank held 17 extra
  items that were added after the eval sweep and never run; they were removed
  rather than re-run, so no figure is computed over a partially-evaluated bank.
  The instrument page keeps a guard that surfaces any future gap automatically.
- **Parameter counts for Claude and GPT are estimates** recorded in
  `src/roster.py`, not published figures.
- **Six models score ≥99% overall**, so the instrument has run out of headroom
  exactly where the frontier is. The "discriminating models only" filter
  reproduces the subgroup the scale-validity analysis uses.

## Deploying

The snapshot is ~0.5 MB and self-contained, so `app/` plus `app/data/` is
everything a deployment needs. No API keys, no secrets, no network access at
runtime.

**Streamlit Community Cloud** — point it at `app/streamlit_app.py`. Community
Cloud searches the entrypoint's directory before the repo root, so
`app/requirements.txt` is picked up rather than the repo-root eval
requirements (which do not contain Streamlit).

**Hugging Face Spaces** — build a deployable Space with:

```bash
make hf-space
```

Note that Spaces has **no first-class Streamlit SDK**: the API accepts only
`gradio`, `docker` or `static`, and rejects `sdk: streamlit` outright. Streamlit
apps therefore ship as **Docker Spaces**, so the build emits a `Dockerfile` and
declares `sdk: docker` / `app_port: 7860` in the Space README frontmatter.

`deploy/build_hf_space.py` assembles `build/hf-space/` from `app/`: it flattens
the layout to the Space root, pins Streamlit to the verified version, writes the
Dockerfile and frontmatter, and **strips the `DEVTOM_REVEAL_ITEMS` escape
hatch**, verifying afterwards that no code path can reveal the full item bank.
Each transformation must match exactly once or the build aborts, so it fails
loudly rather than shipping a half-patched Space.

Check the container before publishing:

```bash
docker build -t devtom-space build/hf-space && docker run --rm -p 7860:7860 devtom-space
```

`build/` is gitignored here; the Space directory is its own git repo pushed to
Hugging Face. Re-run `make hf-space` after `make app-data` to publish refreshed
results — rebuilds are idempotent and preserve the Space's git history.
