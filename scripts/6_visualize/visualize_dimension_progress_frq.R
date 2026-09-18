#!/usr/bin/env Rscript
# visualize_dimension_progress_frq.R — FRQ-only version of the tier-level
# developmental progression figure.
#
# Computes mastery-based age equivalents directly from item_level.csv
# (filtered to free-response only) so it doesn't depend on the full
# developmental_age_mapping.R pipeline.

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(ggtext)
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

# ── load item-level data, FRQ only ─────────────────────────────────────────
item_csv <- "results/item_level.csv"
if (!file.exists(item_csv)) stop("Missing: ", item_csv)
df <- read.csv(item_csv, stringsAsFactors = FALSE) %>%
  filter(task == "tom_12dim_freeresponse", family %in% FAMILY_ORDER)

cat("FRQ rows:", nrow(df), "  Models:", length(unique(df$model)), "\n")

# ── dimension order + age bands ────────────────────────────────────────────
DIM_ORDER <- c(
  "Diverse Desires",
  "Diverse Beliefs",
  "Knowledge Access / Ignorance",
  "Emotion Recognition",
  "First-Order False Belief",
  "Intention vs. Accident",
  "Hidden Emotion (Appearance vs. Reality)",
  "Second-Order False Belief",
  "White Lies / Prosocial Deception",
  "Sarcasm",
  "Irony",
  "Faux Pas Detection"
)

dim_bands <- tibble::tribble(
  ~tom_dimension,                             ~age_lo, ~age_hi, ~age_mid,
  "Diverse Desires",                           2,       3,       2.5,
  "Diverse Beliefs",                           3,       4,       3.5,
  "Knowledge Access / Ignorance",              3,       4,       3.5,
  "Emotion Recognition",                       3,       4,       3.5,
  "First-Order False Belief",                  4,       5,       4.5,
  "Intention vs. Accident",                    4,       5,       4.5,
  "Hidden Emotion (Appearance vs. Reality)",    4,       6,       5.0,
  "White Lies / Prosocial Deception",          5,       7,       6.0,
  "Second-Order False Belief",                 6,       7,       6.5,
  "Sarcasm",                                   6,       8,       7.0,
  "Irony",                                     6,       8,       7.0,
  "Faux Pas Detection",                        9,      11,      10.0
)

# ── compute per-model per-dimension accuracy ───────────────────────────────
model_dim <- df %>%
  group_by(model, family, tier, tom_dimension) %>%
  summarise(
    acc = mean(correct, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  left_join(dim_bands, by = "tom_dimension")

# ── mastery-based age: highest age_mid where accuracy >= 80% ───────────────
mastery <- model_dim %>%
  filter(acc >= 0.80) %>%
  group_by(model, family, tier) %>%
  summarise(mastery_age = max(age_mid, na.rm = TRUE), .groups = "drop")

# build full model x dimension grid with mastery age per dimension
model_dim_age <- model_dim %>%
  mutate(
    passed = acc >= 0.80,
    age_estimate = if_else(passed, age_mid, NA_real_)
  )

# for each model, the mastery age is the highest age_mid where it passed;
# assign that as the model's overall developmental age, then for plotting
# use per-dimension pass/fail mapped to age_mid
clamp <- function(x, lo = 2.5, hi = 11.0) pmin(pmax(x, lo, na.rm = TRUE), hi, na.rm = TRUE)

# per-dimension age estimate: if passed, use age_mid; if failed, use age_mid
# of the highest dimension passed (the model's frontier)
model_frontier <- model_dim %>%
  filter(acc >= 0.80) %>%
  group_by(model) %>%
  summarise(frontier_age = max(age_mid, na.rm = TRUE), .groups = "drop")

model_dim_plot <- model_dim %>%
  mutate(
    tom_dimension = factor(tom_dimension, levels = DIM_ORDER),
    age_estimate = clamp(if_else(acc >= 0.80, age_mid, age_mid * acc / 0.80))
  ) %>%
  filter(family %in% FAMILY_ORDER) %>%
  mutate(
    family = factor(family, levels = FAMILY_ORDER),
    tier   = factor(tier, levels = intersect(TYPE_ORDER, unique(tier)))
  )

# ── tier means ─────────────────────────────────────────────────────────────
tier_means <- model_dim_plot %>%
  group_by(family, tier, tom_dimension) %>%
  summarise(mean_age = mean(age_estimate, na.rm = TRUE), n = n(), .groups = "drop") %>%
  mutate(dim_num = as.numeric(tom_dimension))

tiers_present <- unique(as.character(tier_means$tier))
tc <- TYPE_COLORS[names(TYPE_COLORS) %in% tiers_present]

model_dim_plot <- model_dim_plot %>% mutate(dim_num = as.numeric(tom_dimension))

dim_bands_fam <- dim_bands %>%
  mutate(tom_dimension = factor(tom_dimension, levels = DIM_ORDER)) %>%
  tidyr::crossing(family = factor(FAMILY_ORDER, levels = FAMILY_ORDER)) %>%
  mutate(dim_num = as.numeric(tom_dimension))

# ── output directory ───────────────────────────────────────────────────────
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path("results", "figures", "developmental_age", ts)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ── plot ───────────────────────────────────────────────────────────────────
set.seed(42)
p_tier <- ggplot() +
  geom_rect(
    data = dim_bands_fam,
    aes(xmin = age_lo, xmax = age_hi,
        ymin = dim_num - 0.4, ymax = dim_num + 0.4),
    fill = "grey88", alpha = 0.45
  ) +
  geom_segment(
    data = dim_bands_fam,
    aes(x = age_mid, xend = age_mid,
        y = dim_num - 0.4, yend = dim_num + 0.4),
    linetype = "dashed", color = "grey40", linewidth = 0.5
  ) +
  geom_point(
    data = model_dim_plot %>%
      group_by(family, tier, tom_dimension, dim_num) %>%
      mutate(jit = dim_num + runif(n(), -0.18, 0.18)) %>%
      ungroup(),
    aes(x = age_estimate, y = jit, color = tier),
    size = 1.8, alpha = 0.35, shape = 16
  ) +
  geom_path(
    data = tier_means,
    aes(x = mean_age, y = dim_num, color = tier, group = tier),
    linewidth = 0.9, alpha = 0.8
  ) +
  geom_point(
    data = tier_means,
    aes(x = mean_age, y = dim_num, color = tier),
    size = 3, alpha = 0.9, shape = 16
  ) +
  facet_wrap(~ family, nrow = 1) +
  scale_color_manual(values = tc, name = "Tier") +
  scale_x_continuous(breaks = seq(2, 11, 3), limits = c(1.5, 11.5),
                     name = "Age equivalent (years)") +
  scale_y_continuous(
    breaks = seq_along(DIM_ORDER),
    labels = DIM_ORDER,
    name   = NULL,
    expand = expansion(add = 0.5)
  ) +
  labs(
    title    = "Within each model family, do LLMs master each ToM skill at the right stage in the same order as children? (FRQ only)",
    subtitle = paste0(
      "**Y-axis** = 12 Theory-of-Mind skills stacked in developmental order (bottom to top). ",
      "**X-axis** = Age equivalent (years) based on a human cognitive development.<br>",
      "**Grey bands** = target zone based on normal age window when children master that skill. ",
      "**Dashed vertical lines** = typical passing age at middle of target zone window.<br>",
      "**Faded dots** = individual LLMs ",
      "**Connected lines with big dots** = average for each size tier (based on company-defined capability levels) ",
      "within each model family, with line connecting each tier’s average across 12 skill dimensions to trace ",
      "estimated developmental profiles of models."
    ),
    caption  = NULL
  ) +
  theme_devtom(base_size = 10) +
  theme(
    panel.grid.major.y = element_blank(),
    legend.position    = "bottom",
    strip.text         = element_text(face = "bold", size = 11),
    plot.title         = element_markdown(face = "bold", size = 14),
    plot.subtitle      = element_textbox_simple(color = "grey30", size = 9,
                                                lineheight = 1.25,
                                                margin = margin(t = 4, b = 10))
  ) +
  guides(color = guide_legend(nrow = 3, override.aes = list(size = 3, alpha = 1)))

ggsave(file.path(out_dir, "dim_progress_tier_progression_frq.png"), p_tier,
       width = 18, height = 9, dpi = 300)
cat("Saved:", file.path(out_dir, "dim_progress_tier_progression_frq.png"), "\n")
