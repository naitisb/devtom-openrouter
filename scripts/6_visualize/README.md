# 6_visualize — All visualization scripts

R/ggplot2 scripts that read the tidy CSV artifacts from `4_statistics/` and
`5_model/` and render publication-quality PNGs. No stats or model fitting here.

## Scripts

1. **`_theme.R`** — shared ggplot2 theme + color palettes + ordering helpers.
   Sourced by the other scripts; not run standalone.

2. **`visualize_descriptives.R`** — reads `stats_dataset/` + `stats_results/`
   CSVs (from `4_statistics/`):
   - Composition bars, label balance
   - Coverage heatmap (dimension x target age): age-band ranges are expanded
     to individual years and each item's count is divided by the span width,
     so a "3-5 yrs" item contributes 1/3 to each of ages 3, 4, and 5
   - CTT item map (facility vs. discrimination)
   - KR-20 reliability bars
   - Per-model accuracy caterpillar (Wilson CI)
   - Dimension difficulty ranking

3. **`visualize_glmm_trajectory.R`** — reads `modeling_inference/` CSVs
   (from `5_model/glmm_trajectory.R`):
   - Predicted-probability trajectory per tier (headline)
   - Odds-ratio forest plot
   - Dimension x time slopes vs developmental rank
   - Task-split trajectory (MCQ vs free-response)

4. **`visualize_developmental_mapping.R`** — reads `modeling_mapping/` CSVs
   (from `5_model/developmental_scaling_irt.R`):
   - Profile-vector heatmap (headline)
   - Frontier trajectory (headline)
   - Theta trajectory (+ age-anchored)
   - Wright / item-person map
   - Difficulty vs age-band scatter with Spearman rho

5. **`visualize_accuracy_trajectory.R`** — reads `results/item_level.csv`
   directly (from `4_statistics/extract_item_level.py`):
   - Accuracy vs release date by model tier (overall + MCQ vs FR)
   - Accuracy vs release date by model family (overall + MCQ vs FR)
   - MCQ vs FR comparison faceted per family

## Prerequisites

R packages: `ggplot2`, `dplyr`, `tidyr`, `readr`, `patchwork`, `scales`
(all standard tidyverse + patchwork + scales).

## Quick start

```bash
# After running the upstream pipeline stages:
Rscript scripts/6_visualize/visualize_descriptives.R
Rscript scripts/6_visualize/visualize_glmm_trajectory.R
Rscript scripts/6_visualize/visualize_developmental_mapping.R
Rscript scripts/6_visualize/visualize_accuracy_trajectory.R
```

Or via Make:

```bash
make viz-descriptives
make viz-inference
make viz-mapping
make viz-accuracy
make visualize          # runs all of the above
```

Each script auto-detects the latest timestamped output directory under
`results/`, or you can point at a specific one with `--stats-dataset`,
`--stats-results`, `--inference-dir`, or `--mapping-dir`.
