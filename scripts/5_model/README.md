# 5_model — Statistical modeling (GLMM + IRT)

R scripts for the two primary analyses. These scripts **fit models and emit
tidy CSV artifacts only** — all visualization is in `scripts/6_visualize/`.

## Scripts

1. **`glmm_trajectory.R`** — Binomial GLMM trajectory (primary inference).
   Tests whether ToM accuracy improves release-over-release within each
   family/tier, with item-level random effects. Uses `lme4::glmer`.

2. **`developmental_scaling_irt.R`** — Developmental scaling + IRT (primary
   mapping). Places each model on a per-dimension profile vector and a
   developmental age band using Wilson-CI pass/fail, Guttman scaling, and
   `mirt` IRT (Rasch + 2PL).

## Prerequisites

Both scripts read `results/item_level.csv` — run
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
Rscript scripts/5_model/glmm_trajectory.R
Rscript scripts/5_model/developmental_scaling_irt.R
```

Or via Make:

```bash
make glmm
make irt
```

## Outputs

Each script writes to `results/<timestamp>/modeling_inference/` or
`results/<timestamp>/modeling_mapping/`:

### glmm_trajectory.R
- `glmm_or_table.csv` — fixed-effect odds ratios + CI + p
- `glmm_pred_trajectory.csv` — prediction grid (family, tier, date, pred prob)
- `glmm_observed_points.csv` — observed tier×date accuracy
- `glmm_dim_time_slopes.csv` — per-dimension time slopes + CI
- `glmm_pred_by_task.csv` — prediction grid split by task
- `glmm_lrt.csv` — nested-model likelihood ratio tests
- `glmm_log.txt` — convergence notes

### developmental_scaling_irt.R
- `profile_vectors.csv` — model×dimension accuracy + Wilson CI + pass flag
- `frontier.csv` — frontier age band + Guttman CR + scalability
- `frontier_trajectory.csv` — frontier vs release date + trend stats
- `irt_theta.csv` — model θ + SE + age-anchored θ
- `irt_item_params.csv` — item difficulty (b) + discrimination (a)
- `irt_difficulty_vs_age.csv` — Spearman ρ(b, age_mid)
- `wright_map.csv` — item difficulties + person θ coordinates
- `irt_dif.csv` — DIF-by-family flags

## Caveats (encoded in the scripts)

- **Small n**: 19 models = 19 "persons" for IRT — Rasch is the primary model;
  2PL is sensitivity only; SEs will be large.
- **Ceiling/separation**: dimensions at 100% are detected and flagged.
- **Per-task IRT**: MCQ and free-response are separate scales (different
  chance levels); never pooled.
- **Contamination**: not modeled (unpublished item bank mitigates; see
  ANALYSIS_PLAN.md Threat 7); caveat printed with outputs.
