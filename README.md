# DevToM-OpenRouter

**Mapping LLMs to developmental ages using validated theory-of-mind tasks from developmental psychology.**

DevToM-OpenRouter evaluates large language models on the same cognitive milestones that children pass between ages 2 and 11, then maps each model to a *developmental age equivalent* using empirical norms from the child development literature. The instrument spans **12 theory-of-mind dimensions** — ordered by the age at which children typically acquire each ability (diverse desires at 2-3 years through faux pas detection at 9-11 years) — and draws on validated tasks from the Wellman & Liu (2004) ToM Scale and the broader developmental ToM literature.

The project tests **38 models across 5 families** — Claude, GPT, Llama, Qwen, and Mistral — deliberately reaching back to older releases so each family has a real multi-year history. Open-weight models (Llama, Qwen) route through OpenRouter under a documented non-training / zero-data-retention policy; closed models (Claude, GPT) route via their direct APIs; Mistral routes via la Plateforme.

## Why developmental psychology tasks?

Most LLM benchmarks report a single accuracy number for a single model at a single point in time. DevToM differs in three ways:

1. **Grounded in empirical norms.** Each of the 12 dimensions is anchored to a validated age band from the child development literature (e.g., first-order false belief at 4-5 years, second-order false belief at 6-7 years). This lets us go beyond "Model X scores 80% on ToM" to "Model X has mastered the ToM abilities typically acquired by age 6 but not those acquired by age 9." See [`docs/dev_norms.md`](docs/dev_norms.md) for the full norms table and citations.

2. **Longitudinal, not cross-sectional.** The roster (`src/roster.py`) spans Jul 2023 - mid 2026 across five families and their size tiers. Each tier gets its own regression line so we can ask: does theory-of-mind competence improve release over release, and does it improve *evenly* across developmental dimensions or jaggedly?

3. **Dual elicitation.** Every item is tested in both forced-choice (MCQ) and open-ended (free-response) formats. A finding that appears in only one format is flagged as format-fragile, providing a built-in robustness check.

## The 12 ToM dimensions (developmental order)

| # | Dimension | Age band | Construct | Key citation |
|---|---|---|---|---|
| 1 | Diverse Desires | 2-3 yr | Desire / intention | Wellman & Liu (2004) |
| 2 | Diverse Beliefs | 3-4 yr | Belief reasoning | Wellman & Liu (2004) |
| 3 | Knowledge Access / Ignorance | 3-4 yr | Knowledge access | Wimmer, Hogrefe & Perner (1988) |
| 4 | Emotion Recognition | 3-4 yr | Emotion recognition | Ekman; Widen & Russell (2008) |
| 5 | First-Order False Belief | 4-5 yr | Belief reasoning | Wimmer & Perner (1983) |
| 6 | Intention vs. Accident | 4-5 yr | Desire / intention | Piaget (1932) |
| 7 | Hidden Emotion | 4-6 yr | Emotion recognition | Harris et al. (1986) |
| 8 | White Lies / Prosocial Deception | 5-7 yr | Deception | Talwar & Lee (2002) |
| 9 | Second-Order False Belief | 6-7 yr | Belief reasoning | Perner & Wimmer (1985) |
| 10 | Sarcasm | 6-8 yr | Pragmatic understanding | Winner & Leekam (1991) |
| 11 | Irony | 6-8 yr | Pragmatic understanding | Hancock, Dunham & Purdy (2000) |
| 12 | Faux Pas Detection | 9-11 yr | Pragmatic understanding | Baron-Cohen et al. (1999) |

See [`docs/taxonomy.md`](docs/taxonomy.md) for the full taxonomy and [`docs/dev_norms.md`](docs/dev_norms.md) for age norms, milestone detail, and BibTeX.

## Analyses

The analysis pipeline maps LLMs to developmental ages through four complementary approaches:

### Developmental age mapping (`scripts/5_model/developmental_age_mapping.R`)
- **Mastery-based age**: highest empirical age band at which a model achieves >= 80% accuracy (non-parametric)
- **GLM / GLMM age-equivalents**: logistic models predicting accuracy from developmental age, estimating each model's age-equivalent
- **IRT age-anchoring**: Rasch / 2PL item response theory with person-theta mapped to the age scale via item difficulties

### Developmental horizon (`scripts/5_model/developmental_horizon.R`)
Adapts METR's time-horizon methodology to developmental ToM: fits logistic(success ~ developmental_age) per model to estimate the *developmental age horizon* — the age at which the model's predicted accuracy crosses a threshold. Analogous to METR's "task duration at which AI succeeds 50% of the time," but on a developmental age axis.

### Longitudinal trajectory (`scripts/5_model/glmm_trajectory.R`)
Binomial GLMM testing whether ToM accuracy improves release-over-release within each family/tier, with item-level random effects.

### Size scaling & tier effects
- **Size scaling** (`scripts/5_model/size_scaling_glmm.R`): GLMM testing how parameter count predicts ToM accuracy, controlling for family and release date
- **Tier effects** (`scripts/5_model/tier_effects_analysis.R`): GLM, GLMM, and IRT approaches testing whether model tier predicts ToM accuracy above and beyond developmental age

All modeling scripts emit tidy CSV artifacts; visualization is in `scripts/6_visualize/`.

## Architecture

- **Inspect** (`inspect-ai`) builds and runs each eval: `dataset -> Task -> Solver -> Scorer -> eval log`.
- **OpenRouter** routes Llama and Qwen (one API key, non-training routing prefs). Claude, GPT, and Mistral route via their direct APIs.
- `src/roster.py` — single source of truth for which models, their family, size tier, release date, and color.
- `src/constructs.py` — canonical dimension-to-construct mapping, developmental ordering, and construct hierarchy.
- `src/openrouter.py` — single source of truth for the non-training/ZDR routing policy.

## Quickstart

```bash
python3.10 -m venv .venv && source .venv/bin/activate
pip install --upgrade pip && pip install -r requirements.txt
cp .env.example .env            # add API keys (see .env.example for details)

# 1. verify keys + that each family has a policy-compliant route
python scripts/1_check-functionality/check_providers.py --live

# 2. end-to-end smoke test: one hello-world MCQ per family (cents)
bash scripts/1_check-functionality/run_hello_world_all_families.sh

# 3. run the eval sweep (both tasks, whole roster) — or scope to one family
bash scripts/3_runAll/run_tom_12dim_all_within_family.sh
ONLY_FAMILY=Qwen bash scripts/3_runAll/run_tom_12dim_all_within_family.sh

# 4. run the full analysis + visualization pipeline
make pipeline
```

`make setup | check | smoke | run | run-mcq | run-fr | analyze | visualize | pipeline` wrap the same steps.

## What you get

### Developmental age outputs
- **Developmental age equivalents** — per model, per dimension, and per construct, via four methods (mastery, GLM, GLMM, IRT)
- **Developmental horizon curves** — logistic fits showing each model's predicted accuracy as a function of developmental age
- **Age distance matrices** — how far each model's estimated age is from the target age for each dimension

### Trajectory and scaling outputs
- **Trajectory trend charts** — overall accuracy vs. release date per size tier, with regression lines + 95% CI + significance tests
- **Per-dimension heatmaps** — model (oldest -> newest) x 12 ToM dimensions, showing which developmental abilities each model has mastered
- **Dimension profile comparisons** — per-family, per-construct
- **Size scaling figures** — parameter count vs. ToM accuracy
- **Tier effect summaries** — which size tiers predict ToM performance above and beyond developmental age

## Repo layout

```
src/           roster, constructs, openrouter policy, scorer, solver, metrics
tasks/         hello_world_mcq.py + _smoke.py (pipeline smoke tests) + toy data
data/          the 12-dimension MCQ + free-response datasets, SOURCES.md
configs/       task configuration
scripts/
  0_misc/      dataset tagging, log cleaning, utilities
  1_check/     provider connectivity + smoke tests
  2a_runMCQ/   MCQ-only runners
  2b_runFR/    free-response-only runners
  3_runAll/    full sweep runners
  4_statistics/ extract item-level data, profile datasets + results
  5_model/     GLMM trajectory, developmental age mapping, developmental horizon,
               IRT scaling, size scaling, tier effects
  6_visualize/ all visualization scripts (descriptives, trajectories, mapping,
               profiles, size scaling, tier effects, age heatmaps, horizons)
docs/          dev norms + citations, taxonomy, models roster, non-training methods,
               privacy checklist
logs/          eval logs (gitignored)
results/       per-run CSVs, modeling outputs, figures (gitignored bulk)
```

## Non-training routing

Every OpenRouter call carries request-level routing preferences (`data_collection:"deny"`, `zdr:true`) from a single source of truth (`src/openrouter.py`), backing up workspace-level ZDR/no-logging toggles. Models with no policy-compliant upstream fail closed and are absent from results. See [`docs/METHODS_non_training_openrouter.md`](docs/METHODS_non_training_openrouter.md) and [`docs/privacy_config_checklist.md`](docs/privacy_config_checklist.md).

## Cross-family grading

The free-response grader uses cross-family judging to avoid self-preference bias. `openai/gpt-4o-2024-08-06` grades all non-GPT subjects; `anthropic/claude-sonnet-4-5-20250929` grades GPT subjects. Both are pinned to snapshot IDs for reproducibility. No model is ever graded by a judge from its own lab.

## Relationship to devtom-eval

DevToM-OpenRouter is a **sibling** of [devtom-eval](../devtom-eval), not a fork. It reuses the same dataset, metrics, solver, and scorer design (so results are directly comparable) and extends the model panel to five families with multi-year release histories. The analysis pipeline adds developmental age mapping, developmental horizon estimation, IRT, and size-scaling analyses beyond devtom-eval's trajectory-focused scope.

## Datasets & licenses

Same instrument as devtom-eval — see [`data/SOURCES.md`](data/SOURCES.md). Authored items are MIT (this repo); upstream-derived components retain their upstream licenses.

## Citation

```bibtex
@software{bhatt_devtom_openrouter_2026,
  author  = {Bhatt, Naiti S.},
  title   = {{DevToM-OpenRouter}: Mapping {LLMs} to Developmental Ages Using Validated Theory-of-Mind Tasks},
  year    = {2026},
  url     = {https://github.com/naitisb/devtom-openrouter}
}
```

## License

MIT — see `LICENSE`. (Dataset components retain their upstream licenses; see `data/SOURCES.md`.)
