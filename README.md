# DevToM-OpenRouter

**Developmental theory-of-mind trajectories for *open-weight* LLMs, via OpenRouter.**

A parallel of [devtom-eval](../devtom-eval) that runs the **same 12-dimension
theory-of-mind instrument** across open-weight model families served through
OpenRouter — **Llama, Qwen, DeepSeek, Mistral, Gemma** — deliberately reaching
**back in time to older releases** (Llama 2, Mistral 7B, the original DeepSeek
LLM, Gemma 1) so each family has a real multi-year history. The central output
is a **developmental trajectory**: for each size tier within each family, does
theory-of-mind accuracy on each ToM axis actually improve release over release?

Where devtom-eval traces closed frontier families (Anthropic, OpenAI) within
themselves, this repo asks the same question of the open-weight ecosystem — and
does it under a documented **non-training / zero-data-retention** OpenRouter
routing policy (see [`docs/METHODS_non_training_openrouter.md`](docs/METHODS_non_training_openrouter.md)).

## Why

Most ToM benchmarks report one accuracy number for one model at one point in
time. This project reports accuracy **per ToM dimension** (12 axes, ordered by
child developmental-acquisition age — diverse desires → false belief → sarcasm →
irony) **× per model × across release time**, so you can see whether an open
family's ToM competence grew as it scaled and matured, and whether it grew
*evenly* across axes or jaggedly. See [`docs/taxonomy.md`](docs/taxonomy.md) and
[`docs/dev_norms.md`](docs/dev_norms.md) for the instrument.

## Two things make this a distinct study, not just a re-run

1. **Longitudinal, open-weight.** The roster (`src/roster.py`) spans Jul 2023 →
   mid 2025 across five families and their size tiers, each tier trended on its
   own regression line with a significance test. Older releases are treated as
   first-class data points, not legacy noise.
2. **Non-training routing is a first-class control.** Every call carries
   OpenRouter provider-routing preferences (`data_collection:"deny"`, `zdr:true`)
   from a single source of truth (`src/openrouter.py`), backing up the
   workspace-level ZDR/no-logging toggles. Models with no policy-compliant
   upstream fail closed and are simply absent from results.

## Architecture

- **Inspect** (`inspect-ai`) builds and runs the eval: `dataset → Task → Solver → Scorer → eval log`.
- **OpenRouter** is the single provider (`openrouter/<author>/<slug>` model strings, one API key).
- `src/roster.py` is the single source of truth for *which* models, their family,
  size tier, release date, and color — read by both the runners and the analysis.
- `src/openrouter.py` is the single source of truth for the no-training/ZDR routing policy.

## Quickstart

```bash
python3.10 -m venv .venv && source .venv/bin/activate
pip install --upgrade pip && pip install -r requirements.txt
cp .env.example .env            # add OPENROUTER_API_KEY (and optionally DEVTOM_GRADER_MODEL)

# 1. verify key + that each family has a policy-compliant route (tiny real calls)
python scripts/1_check-functionality/check_providers.py --live

# 2. end-to-end smoke: one hello-world MCQ per family (cents)
bash scripts/1_check-functionality/run_hello_world_all_families.sh

# 3. run the sweep (both tasks, whole roster) — or scope to one family
bash scripts/3_runAll/run_tom_12dim_all_within_family.sh
ONLY_FAMILY=Qwen bash scripts/3_runAll/run_tom_12dim_all_within_family.sh
#   cheaper first pass (MCQ only), or free-response only:
bash scripts/2a_runMCQ/run_tom_12dim_mcq_within_family.sh
bash scripts/2b_runFR/run_tom_12dim_fr_within_family.sh
#   arbitrary subset:
bash scripts/3_runAll/run_tom_12dim_selective.sh meta-llama/llama-3.1-8b-instruct qwen/qwen3-32b

# 4. build the trajectory figures + CSV into results/<timestamp>/
python scripts/0_misc/summarize_visualize_results.py
```

`make setup | check | smoke | run | run-mcq | run-fr | analyze` wrap the same steps.

## What you get

`scripts/0_misc/summarize_visualize_results.py` writes a tidy CSV and up to
~21 figures into a fresh `results/<timestamp>/`:

- **Trajectory trend charts** — overall accuracy vs. release date, one line per
  size tier, each with a dashed linear-regression line + 95% CI + significance
  star (is *this* tier trending up over time?). Combined, per task (MCQ vs. free
  response), and per family.
- **Per-dimension heatmaps** — model (oldest→newest within family) × 12 ToM
  dimensions, with family boundary rules.
- **Difficulty rankings** — which ToM axes are hardest across all tested models.
- **Per-dimension regression grids** (free-response) — one small regression per
  ToM axis, per family, pooled and split-by-tier.

## Repo layout

```
src/        roster (model registry), openrouter (routing policy), scorer, solver, metrics
tasks/      hello_world_mcq.py + _smoke.py (pipeline smoke tests) + toy data
data/       the shared 12-dimension MCQ + free-response datasets, SOURCES.md
scripts/    1_check → 2a_runMCQ / 2b_runFR → 3_runAll → 4_statistics → 5_model → 6_visualize (+ _provider_prefs.sh helper)
docs/       models roster, non-training methods note, privacy checklist, taxonomy, dev norms
logs/       eval logs (gitignored; runners archive prior runs to logs/Archive/)
results/    per-run CSV + trajectory figures (gitignored bulk)
```

## Relationship to devtom-eval

This is a **sibling**, not a fork: it reuses devtom-eval's dataset, metrics,
solver, and scorer design verbatim (so results are directly comparable), and
swaps the model layer for OpenRouter open-weight families plus the non-training
routing controls. The analysis script is the same plotting logic retargeted at
open families via `src/roster.py`. Differences worth knowing:

- `model_family()` parses `openrouter/<author>/<slug>` (the router prefix is
  stripped; the *author* segment is the family), not the first path segment.
- The model roster is a single importable source of truth, not duplicated arrays.
- The free-response grader is pinned via `DEVTOM_GRADER_MODEL`. The study uses
  `openai/gpt-4o-2024-08-06` as the primary judge for all non-GPT subject families,
  and `anthropic/claude-sonnet-4-5-20250929` as the alternate judge for GPT subjects
  (cross-family grading via `DEVTOM_GRADER_MODEL_SAMEFAMILY` — no subject is graded
  by a same-lab judge). Both judges are pinned to snapshot ids for reproducibility.
  Limitation: GPT-4o may favor non-GPT outputs; Claude may disfavor GPT outputs —
  both directions are noted in the methods.

## Datasets & licenses

Same instrument as devtom-eval — see [`data/SOURCES.md`](data/SOURCES.md).
Authored items are MIT (this repo); any upstream-derived components retain their
upstream licenses.

## Citation

```bibtex
@software{bhatt_devtom_openrouter_2026,
  author  = {Bhatt, Naiti S.},
  title   = {DevToM-OpenRouter: Developmental Theory-of-Mind Trajectories for Open-Weight LLMs},
  year    = {2026},
  url      = {https://github.com/naitisb/devtom-openrouter}
}
```

## License

MIT — see `LICENSE`. (Dataset components retain their upstream licenses; see `data/SOURCES.md`.)
