# 6_visualize — All visualization scripts

R/ggplot2 scripts that read the tidy CSV artifacts from `4_statistics/` and
`5_model/` and render publication-quality PNGs. No stats or model fitting here.

## Scripts

1. **`_theme.R`** — shared ggplot2 theme + color palettes + ordering helpers.
   Sourced by the other scripts; not run standalone.

### Descriptive

2. **`visualize_descriptives.R`** — reads `stats_dataset/` + `stats_results/`
   CSVs (from `4_statistics/`):
   - Composition bars, label balance
   - Coverage heatmap (dimension x target age)
   - CTT item map (facility vs. discrimination)
   - KR-20 reliability bars
   - Per-model accuracy caterpillar (Wilson CI)
   - Dimension difficulty ranking

3. **`visualize_dimension_profiles.R`** — reads `results/item_level.csv`:
   - Dimension profile heatmaps per family
   - Dimension difficulty rankings
   - Per-dimension regression grids

### Developmental age mapping

4. **`visualize_developmental_mapping.R`** — reads `modeling/mapping/` CSVs
   (from `developmental_scaling_irt.R`):
   - Profile-vector heatmap
   - Frontier trajectory
   - Theta trajectory (+ age-anchored)
   - Wright / item-person map
   - Difficulty vs age-band scatter with Spearman rho

5. **`visualize_developmental_age.R`** — reads `modeling/developmental_age_mapping/`
   CSVs: developmental age equivalent plots per model, per dimension, and per
   construct across methods (mastery, GLM, GLMM, IRT).

6. **`visualize_developmental_horizon.R`** — reads `modeling/developmental_horizon/`
   CSVs: logistic horizon curves showing each model's predicted accuracy as a
   function of developmental age.

7. **`visualize_mean_age_heatmap.R`** — cross-method mean developmental age
   heatmap (model x dimension/construct).

8. **`visualize_age_distances.R`** — distance from target developmental age per
   model, across dimensions and methods.

9. **`visualize_age_progression.R`** — developmental age progression over
   release date (longitudinal tracking of age-equivalents).

10. **`visualize_all_method_progressions.R`** — combined view of age progression
    across all estimation methods.

### Longitudinal trajectory

11. **`visualize_glmm_trajectory.R`** — reads `modeling/inference/` CSVs
    (from `glmm_trajectory.R`):
    - Predicted-probability trajectory per tier
    - Odds-ratio forest plot
    - Dimension x time slopes vs developmental rank
    - Task-split trajectory (MCQ vs free-response)

12. **`visualize_accuracy_trajectory.R`** — reads `results/item_level.csv`:
    - Accuracy vs release date by model tier
    - Accuracy vs release date by model family
    - MCQ vs FR comparison faceted per family

### Scaling and tier effects

13. **`visualize_size_scaling.R`** — reads `modeling/size_scaling/` CSVs:
    parameter count vs. ToM accuracy.

14. **`visualize_tier_effects.R`** — reads `modeling/tier_effects/` CSVs:
    tier effect summaries and comparisons.

## Prerequisites

R packages: `ggplot2`, `dplyr`, `tidyr`, `readr`, `patchwork`, `scales`
(all standard tidyverse + patchwork + scales).

## Quick start

```bash
# After running the upstream pipeline stages:
make visualize          # runs all visualization scripts
```

Or individually:

```bash
make viz-descriptives   # descriptive figures
make viz-inference      # GLMM trajectory figures
make viz-mapping        # developmental mapping figures
make viz-accuracy       # accuracy trajectory figures
make viz-profiles       # dimension profile heatmaps
make viz-size           # size scaling figures
```

Each script auto-detects the latest timestamped output directory under
`results/`, or you can point at a specific one via command-line arguments.
