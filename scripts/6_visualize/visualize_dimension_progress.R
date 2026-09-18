#!/usr/bin/env Rscript
# visualize_dimension_progress.R — strip charts showing each model's
# position within each dimension's validated developmental age range

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

# ── locate latest method_comparison.csv ──────────────────────────────────
base_dir <- file.path("results", "modeling", "developmental_age_mapping")
ts_dirs  <- sort(list.dirs(base_dir, recursive = FALSE), decreasing = TRUE)
ts_dir   <- ts_dirs[1]
cat("Using:", ts_dir, "\n")

mc <- read.csv(file.path(ts_dir, "method_comparison.csv"),
               stringsAsFactors = FALSE)

# ── dimension order (Irony before Faux Pas) ──────────────────────────────
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

# ── dimension age bands (validated developmental norms) ──────────────────
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

# ── clamp helper ─────────────────────────────────────────────────────────
clamp <- function(x, lo = 2.5, hi = 11.0) pmin(pmax(x, lo, na.rm = TRUE), hi, na.rm = TRUE)

mc <- mc %>%
  mutate(
    mastery_age = clamp(mastery_age),
    glm_age_eq  = clamp(glm_age_eq),
    glmm_age_eq = clamp(glmm_age_eq),
    irt_age_eq  = clamp(irt_age_eq)
  )

# ── pivot to long ────────────────────────────────────────────────────────
mc_long <- mc %>%
  pivot_longer(
    cols      = c(mastery_age, glm_age_eq, glmm_age_eq, irt_age_eq),
    names_to  = "method",
    values_to = "age_estimate"
  ) %>%
  mutate(method = recode(method,
    mastery_age = "Mastery",
    glm_age_eq  = "GLM",
    glmm_age_eq = "GLMM",
    irt_age_eq  = "IRT"
  )) %>%
  mutate(method = factor(method, levels = c("Mastery", "GLM", "GLMM", "IRT")))

mc_long <- mc_long %>%
  left_join(dim_bands, by = "tom_dimension") %>%
  mutate(tom_dimension = factor(tom_dimension, levels = DIM_ORDER))

# keep only families in FAMILY_ORDER for clean colors
mc_long <- mc_long %>%
  filter(family %in% FAMILY_ORDER) %>%
  mutate(family = factor_family(family))

# bands also need factor levels for y-axis
dim_bands <- dim_bands %>%
  mutate(tom_dimension = factor(tom_dimension, levels = DIM_ORDER))

# ── output directory ─────────────────────────────────────────────────────
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path("results", "figures", "developmental_age", ts)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ── build one strip chart ────────────────────────────────────────────────
make_strip <- function(data, title, subtitle = NULL) {
  set.seed(42)
  ggplot(data, aes(x = age_estimate, y = tom_dimension)) +
    geom_rect(
      data = dim_bands,
      aes(xmin = age_lo, xmax = age_hi,
          ymin = as.numeric(tom_dimension) - 0.4,
          ymax = as.numeric(tom_dimension) + 0.4),
      inherit.aes = FALSE,
      fill = "grey85", alpha = 0.5
    ) +
    geom_segment(
      data = dim_bands,
      aes(x = age_mid, xend = age_mid,
          y = as.numeric(tom_dimension) - 0.4,
          yend = as.numeric(tom_dimension) + 0.4),
      inherit.aes = FALSE,
      linetype = "dashed", color = "grey30", linewidth = 0.6
    ) +
    geom_jitter(
      aes(color = family),
      height = 0.25, width = 0,
      size = 2.5, alpha = 0.7
    ) +
    scale_color_manual(values = FAMILY_COLORS, name = "Family") +
    scale_x_continuous(
      breaks = 2:11,
      limits = c(1.5, 11.5),
      name   = "Age equivalent (years)"
    ) +
    scale_y_discrete(name = NULL) +
    labs(
      title    = title,
      subtitle = subtitle,
      caption  = "Grey band = validated developmental window; dashed line = passing age (age_mid)"
    ) +
    theme_devtom(base_size = 11) +
    theme(
      panel.grid.major.y = element_blank(),
      legend.position     = "bottom"
    )
}

# ── per-method plots ─────────────────────────────────────────────────────
method_labels <- c(
  Mastery = "Mastery Age (≥80% threshold)",
  GLM     = "Per-Model GLM Age Equivalent",
  GLMM    = "Cross-Model GLMM Age Equivalent",
  IRT     = "IRT Age Equivalent"
)

for (m in names(method_labels)) {
  d <- mc_long %>% filter(method == m, !is.na(age_estimate))
  p <- make_strip(d,
    title    = paste0("Model Progress by Dimension — ", method_labels[m]),
    subtitle = "Where does each LLM fall within each dimension's developmental age range?"
  )
  fname <- paste0("dim_progress_", tolower(m), ".png")
  ggsave(file.path(out_dir, fname), p, width = 12, height = 8, dpi = 300)
  cat("Saved:", fname, "\n")
}

# ── all-methods faceted ──────────────────────────────────────────────────
d_all <- mc_long %>% filter(!is.na(age_estimate))
set.seed(42)
p_all <- ggplot(d_all, aes(x = age_estimate, y = tom_dimension)) +
  geom_rect(
    data = dim_bands %>% crossing(method = factor(c("Mastery","GLM","GLMM","IRT"),
                                                  levels = c("Mastery","GLM","GLMM","IRT"))),
    aes(xmin = age_lo, xmax = age_hi,
        ymin = as.numeric(tom_dimension) - 0.4,
        ymax = as.numeric(tom_dimension) + 0.4),
    inherit.aes = FALSE,
    fill = "grey85", alpha = 0.5
  ) +
  geom_segment(
    data = dim_bands %>% crossing(method = factor(c("Mastery","GLM","GLMM","IRT"),
                                                  levels = c("Mastery","GLM","GLMM","IRT"))),
    aes(x = age_mid, xend = age_mid,
        y = as.numeric(tom_dimension) - 0.4,
        yend = as.numeric(tom_dimension) + 0.4),
    inherit.aes = FALSE,
    linetype = "dashed", color = "grey30", linewidth = 0.6
  ) +
  geom_jitter(
    aes(color = family),
    height = 0.25, width = 0,
    size = 1.8, alpha = 0.6
  ) +
  facet_wrap(~ method, nrow = 2) +
  scale_color_manual(values = FAMILY_COLORS, name = "Family") +
  scale_x_continuous(breaks = seq(2, 11, 2), limits = c(1.5, 11.5),
                     name = "Age equivalent (years)") +
  scale_y_discrete(name = NULL) +
  labs(
    title    = "Model Progress by Dimension — All Methods",
    subtitle = "Each panel shows one age-equivalent estimation method",
    caption  = "Grey band = validated developmental window; dashed line = passing age"
  ) +
  theme_devtom(base_size = 10) +
  theme(
    panel.grid.major.y = element_blank(),
    legend.position     = "bottom",
    strip.text          = element_text(face = "bold", size = 11)
  )
ggsave(file.path(out_dir, "dim_progress_all_methods.png"), p_all,
       width = 14, height = 10, dpi = 300)
cat("Saved: dim_progress_all_methods.png\n")

# ── tier progression by family (mastery method) ──────────────────────────
d_mastery <- mc_long %>% filter(method == "Mastery", !is.na(age_estimate))

# tier means per dimension
tier_means <- d_mastery %>%
  group_by(family, tier, tom_dimension) %>%
  summarise(
    mean_age = mean(age_estimate, na.rm = TRUE),
    n        = n(),
    .groups  = "drop"
  ) %>%
  mutate(dim_num = as.numeric(tom_dimension))

# keep only tiers that appear in the data
tiers_present <- unique(tier_means$tier)
tc <- TYPE_COLORS[names(TYPE_COLORS) %in% tiers_present]

# convert everything to numeric y for consistent scale
d_mastery <- d_mastery %>%
  mutate(dim_num = as.numeric(tom_dimension))

dim_bands_fam <- dim_bands %>%
  crossing(family = factor(FAMILY_ORDER, levels = FAMILY_ORDER)) %>%
  mutate(dim_num = as.numeric(tom_dimension))

set.seed(42)
p_tier <- ggplot() +
  # age bands
  geom_rect(
    data = dim_bands_fam,
    aes(xmin = age_lo, xmax = age_hi,
        ymin = dim_num - 0.4, ymax = dim_num + 0.4),
    fill = "grey88", alpha = 0.45
  ) +
  # passing-age dashed lines
  geom_segment(
    data = dim_bands_fam,
    aes(x = age_mid, xend = age_mid,
        y = dim_num - 0.4, yend = dim_num + 0.4),
    linetype = "dashed", color = "grey40", linewidth = 0.5
  ) +
  # individual model points (background)
  geom_point(
    data = d_mastery %>%
      group_by(family, tier, tom_dimension, dim_num) %>%
      mutate(jit = dim_num + runif(n(), -0.18, 0.18)) %>%
      ungroup(),
    aes(x = age_estimate, y = jit, color = tier),
    size = 1.8, alpha = 0.35, shape = 16
  ) +
  # tier mean trajectory lines
  geom_path(
    data = tier_means,
    aes(x = mean_age, y = dim_num, color = tier, group = tier),
    linewidth = 0.9, alpha = 0.8
  ) +
  # tier mean points
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
    breaks = seq_along(DIMENSION_DEVELOPMENTAL_ORDER),
    labels = DIM_ORDER,
    name   = NULL,
    expand = expansion(add = 0.5)
  ) +
  labs(
    title    = "Within each model family, do LLMs master each ToM skill at the right stage in the same order as children?",
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
    legend.position     = "bottom",
    strip.text          = element_text(face = "bold", size = 11),
    plot.title          = element_markdown(face = "bold", size = 14),
    plot.subtitle       = element_textbox_simple(color = "grey30", size = 9,
                                                  lineheight = 1.25,
                                                  margin = margin(t = 4, b = 10))
  ) +
  guides(color = guide_legend(nrow = 3, override.aes = list(size = 3, alpha = 1)))
ggsave(file.path(out_dir, "dim_progress_tier_progression.png"), p_tier,
       width = 18, height = 9, dpi = 300)
cat("Saved: dim_progress_tier_progression.png\n")

cat("\nAll plots saved to:", out_dir, "\n")
