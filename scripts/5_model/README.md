# 5_model — Statistical modeling

R scripts that map LLMs to developmental ages and test longitudinal
trajectories. These scripts **fit models and emit tidy CSV artifacts only** —
all visualization is in `scripts/6_visualize/`.

## Scripts

### Developmental age mapping

1. **`developmental_age_mapping.R`** — Maps each model to a developmental age
   equivalent via four complementary methods:
   - Mastery-based age (non-parametric): highest empirical age band with >= 80% accuracy
   - Per-model GLM: logistic(correct ~ age_mid) per model, solving for age-equivalent
   - Cross-model GLMM: correct ~ age_mid + (1|model) + (1|item_id)
   - IRT age-anchoring: Rasch/2PL person-theta mapped to the developmental age
     scale via item difficulties correlated with empirical age norms

2. **`developmental_horizon.R`** — Developmental age horizon, adapting METR's
   time-horizon methodology to ToM. Fits logistic(success ~ developmental_age)
   per model to estimate the age at which predicted accuracy crosses a threshold.

3. **`compute_age_distances.R`** — Per-model distance between estimated and
   target developmental age, across dimensions, constructs, and methods.

### Longitudinal trajectory

4. **`glmm_trajectory.R`** — Binomial GLMM trajectory (primary inference).
   Tests whether ToM accuracy improves release-over-release within each
   family/tier, with item-level random effects. Uses `lme4::glmer`.

5. **`developmental_scaling_irt.R`** — Developmental scaling + IRT. Places each
   model on a per-dimension profile vector and a developmental age band using
   Wilson-CI pass/fail, Guttman scaling, and `mirt` IRT (Rasch + 2PL).

### Scaling and tier effects

6. **`size_scaling_glmm.R`** — Size-scaling GLMM testing how parameter count
   predicts ToM accuracy, controlling for family and release date.

7. **`tier_effects_analysis.R`** — Tests whether model tier (e.g., "Claude
   Opus", "Llama small") predicts ToM accuracy above and beyond developmental
   age and task format, via pooled GLM, GLMM, and IRT approaches.

## Prerequisites

All scripts read `results/item_level.csv` — run
`python scripts/4_statistics/extract_item_level.py` first.

### R packages

Already installed (typical R setup):
- `lme4`, `broom.mixed`, `tidyverse` (dplyr, tidyr, readr, ggplot2)

**Install once** (new for this pipeline):
```r
install.packages(c("mirt", "ggeffects", "PropCIs"))
```

## Quick start

```bash
# Run via Make (handles dependencies automatically):
make analyze        # all analyses: extract -> profile -> model
make pipeline       # all analyses + all visualizations

# Or individually:
Rscript scripts/5_model/glmm_trajectory.R
Rscript scripts/5_model/developmental_scaling_irt.R
Rscript scripts/5_model/developmental_age_mapping.R
Rscript scripts/5_model/developmental_horizon.R
Rscript scripts/5_model/size_scaling_glmm.R
Rscript scripts/5_model/tier_effects_analysis.R
Rscript scripts/5_model/compute_age_distances.R
```

## Outputs

Each script writes to `results/modeling/<analysis>/`:

### developmental_age_mapping.R -> `results/modeling/developmental_age_mapping/`
- `mastery_age_*.csv` — mastery-based developmental age per model/dimension/construct
- `glm_age_*.csv` — per-model GLM age-equivalents
- `glmm_age_*.csv` — cross-model GLMM age-equivalents
- `irt_age_*.csv` — IRT-anchored developmental ages
- `age_mapping_log.txt` — convergence notes

### developmental_horizon.R -> `results/modeling/developmental_horizon/`
- `horizon_*.csv` — developmental age horizon per model and method
- `horizon_log.txt` — fit diagnostics

### compute_age_distances.R -> `results/modeling/developmental_age_mapping/`
- `age_distances_*.csv` — distance from target age per model/scope/method

### glmm_trajectory.R -> `results/modeling/inference/`
- `glmm_or_table.csv` — fixed-effect odds ratios + CI + p
- `glmm_pred_trajectory.csv` — prediction grid (family, tier, date, pred prob)
- `glmm_observed_points.csv` — observed tier x date accuracy
- `glmm_dim_time_slopes.csv` — per-dimension time slopes + CI
- `glmm_pred_by_task.csv` — prediction grid split by task
- `glmm_lrt.csv` — nested-model likelihood ratio tests
- `glmm_log.txt` — convergence notes

### developmental_scaling_irt.R -> `results/modeling/mapping/`
- `profile_vectors.csv` — model x dimension accuracy + Wilson CI + pass flag
- `frontier.csv` — frontier age band + Guttman CR + scalability
- `frontier_trajectory.csv` — frontier vs release date + trend stats
- `irt_theta.csv` — model theta + SE + age-anchored theta
- `irt_item_params.csv` — item difficulty (b) + discrimination (a)
- `irt_difficulty_vs_age.csv` — Spearman rho(b, age_mid)
- `wright_map.csv` — item difficulties + person theta coordinates
- `irt_dif.csv` — DIF-by-family flags

## Caveats (encoded in the scripts)

- **Small n**: 38 models = 38 "persons" for IRT — Rasch is the primary model;
  2PL is sensitivity only; SEs will be large.
- **Ceiling/separation**: dimensions at 100% are detected and flagged.
- **Per-task IRT**: MCQ and free-response are separate scales (different
  chance levels); never pooled.
- **Contamination**: not modeled (unpublished item bank mitigates); caveat
  printed with outputs.
- **Age norms**: developmental age equivalents are anchored to empirical norms
  from the child development literature (see `docs/dev_norms.md`); the mapping
  is meaningful only insofar as item difficulty correlates with acquisition age,
  which is tested via IRT difficulty-vs-age Spearman correlation.
