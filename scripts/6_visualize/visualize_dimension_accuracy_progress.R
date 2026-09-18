#!/usr/bin/env Rscript
# visualize_dimension_accuracy_progress.R — strip charts showing each model's
# percent correct within each dimension (same layout as dim_progress_tier_progression
# but with accuracy on x-axis instead of age equivalent)

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
})

this_dir <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) {
    args <- commandArgs(trailingOnly = FALSE)
    f <- grep("--file=", args, value = TRUE)
    if (length(f)) dirname(sub("--file=", "", f))
    else "scripts/6_visualize"
  }
)
source(file.path(this_dir, "_theme.R"))

# ── locate item_level.csv ──────────────────────────────────────────────────
item_csv <- "results/item_level.csv"
if (!file.exists(item_csv)) stop("Missing: ", item_csv,
  "\nRun: python scripts/4_statistics/extract_item_level.py")
df <- read.csv(item_csv, stringsAsFactors = FALSE)

# keep only active families, FRQ only
df <- df %>%
  filter(family %in% FAMILY_ORDER, task == "tom_12dim_freeresponse") %>%
  mutate(
    family        = factor_family(family),
    tier          = factor_tier(tier),
    tom_dimension = factor(tom_dimension, levels = DIMENSION_DEVELOPMENTAL_ORDER)
  )

# ── compute per-model per-dimension accuracy ───────────────────────────────
model_dim_acc <- df %>%
  group_by(model, family, tier, tom_dimension) %>%
  summarise(
    n_items = n(),
    n_correct = sum(correct, na.rm = TRUE),
    pct_correct = 100 * n_correct / n_items,
    .groups = "drop"
  )

# ── tier means per dimension ───────────────────────────────────────────────
tier_means <- model_dim_acc %>%
  group_by(family, tier, tom_dimension) %>%
  summarise(
    mean_pct = mean(pct_correct, na.rm = TRUE),
    n = n(),
    .groups = "drop"
  ) %>%
  mutate(dim_num = as.numeric(tom_dimension))

# keep only tiers present
tiers_present <- unique(as.character(tier_means$tier))
tc <- TYPE_COLORS[names(TYPE_COLORS) %in% tiers_present]

# numeric y for model points
model_dim_acc <- model_dim_acc %>%
  mutate(dim_num = as.numeric(tom_dimension))

# ── output directory ───────────────────────────────────────────────────────
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path("results", "figures", "dimension_profiles", ts)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ── tier progression plot (all tasks pooled) ───────────────────────────────
set.seed(42)
p_tier <- ggplot() +
  geom_point(
    data = model_dim_acc %>%
      group_by(family, tier, tom_dimension, dim_num) %>%
      mutate(jit = dim_num + runif(n(), -0.18, 0.18)) %>%
      ungroup(),
    aes(x = pct_correct, y = jit, color = tier),
    size = 1.8, alpha = 0.35, shape = 16
  ) +
  geom_path(
    data = tier_means,
    aes(x = mean_pct, y = dim_num, color = tier, group = tier),
    linewidth = 0.9, alpha = 0.8
  ) +
  geom_point(
    data = tier_means,
    aes(x = mean_pct, y = dim_num, color = tier),
    size = 3, alpha = 0.9, shape = 16
  ) +
  facet_wrap(~ family, nrow = 1) +
  scale_color_manual(values = tc, name = "Tier") +
  scale_x_continuous(
    breaks = seq(0, 100, 25),
    limits = c(0, 105),
    name = "Accuracy (%)"
  ) +
  scale_y_continuous(
    breaks = seq_along(DIMENSION_DEVELOPMENTAL_ORDER),
    labels = DIMENSION_DEVELOPMENTAL_ORDER,
    name = NULL,
    expand = expansion(add = 0.5)
  ) +
  labs(
    title    = "Tier-Level Accuracy by Dimension (Free-Response Only)",
    subtitle = "Lines connect tier means across dimensions; faded dots = individual models"
  ) +
  theme_devtom(base_size = 10) +
  theme(
    panel.grid.major.y = element_blank(),
    legend.position    = "bottom",
    strip.text         = element_text(face = "bold", size = 11)
  ) +
  guides(color = guide_legend(nrow = 3, override.aes = list(size = 3, alpha = 1)))

ggsave(file.path(out_dir, "dim_accuracy_tier_progression.png"), p_tier,
       width = 18, height = 9, dpi = 300)
cat("Saved: dim_accuracy_tier_progression.png\n")

# ── by-family jitter plot (all models, colored by family) ──────────────────
set.seed(42)
p_family <- ggplot(model_dim_acc, aes(x = pct_correct, y = tom_dimension)) +
  geom_jitter(
    aes(color = family),
    height = 0.25, width = 0,
    size = 2.5, alpha = 0.7
  ) +
  scale_color_manual(values = FAMILY_COLORS, name = "Family") +
  scale_x_continuous(
    breaks = seq(0, 100, 25),
    limits = c(0, 105),
    name = "Accuracy (%)"
  ) +
  scale_y_discrete(name = NULL) +
  labs(
    title    = "Model Accuracy by Dimension (Free-Response Only)",
    subtitle = "Each dot = one model's accuracy on that dimension"
  ) +
  theme_devtom(base_size = 11) +
  theme(
    panel.grid.major.y = element_blank(),
    legend.position    = "bottom"
  )

ggsave(file.path(out_dir, "dim_accuracy_by_family.png"), p_family,
       width = 12, height = 8, dpi = 300)
cat("Saved: dim_accuracy_by_family.png\n")

cat("\nAll plots saved to:", out_dir, "\n")
