#!/usr/bin/env Rscript
# visualize_developmental_horizon.R — METR-style developmental horizon charts
#
# Produces:
#   A. Headline trend chart: release date vs developmental age horizon
#   B. Per-model logistic fit grids (accuracy vs developmental age)
#   C. Family-faceted trend chart
#   D. Dimension mastery heatmap

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(ggrepel)
  library(scales)
  library(patchwork)
})

source("scripts/6_visualize/_theme.R")

# ---------------------------------------------------------------------------
# 0. Locate latest output
# ---------------------------------------------------------------------------
horizon_dir <- "results/modeling/developmental_horizon"
latest <- rev(sort(list.dirs(horizon_dir, recursive = FALSE)))[1]
cat("Reading from:", latest, "\n")

ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
fig_dir <- file.path("results", "figures", "developmental_horizon", ts)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

horizons   <- read_csv(file.path(latest, "developmental_horizons.csv"), show_col_types = FALSE)
pred_curves <- read_csv(file.path(latest, "horizon_predicted_curves.csv"), show_col_types = FALSE)
dim_acc    <- read_csv(file.path(latest, "dimension_accuracy_by_model.csv"), show_col_types = FALSE)

# Prep
horizons <- horizons %>%
  filter(overall_acc > 0) %>%
  mutate(
    family = factor_family(family),
    release_date = as.Date(release_date),
    short = short_model(model),
    mastery_label = case_when(
      n_dims_above_80 == 12 ~ paste0(short, " *"),
      TRUE ~ short
    )
  )

dim_acc <- dim_acc %>%
  mutate(
    family = factor_family(family),
    tom_dimension = factor_dimension(tom_dimension)
  )

pred_curves <- pred_curves %>%
  mutate(family = factor_family(family))

scale_x_date_years <- function(step = 0.5) {
  brk <- seq(-0.5, 3, by = step)
  lbl <- sapply(brk, function(dy) {
    yr <- 2024 + floor(dy)
    mo <- round((dy - floor(dy)) * 12) + 1
    if (mo <= 0) { yr <- yr - 1; mo <- mo + 12 }
    if (mo > 12) { yr <- yr + 1; mo <- mo - 12 }
    if (step >= 1) format(as.Date(sprintf("%d-%02d-01", yr, mo)), "%Y")
    else format(as.Date(sprintf("%d-%02d-01", yr, mo)), "%b\n%Y")
  })
  scale_x_continuous(breaks = brk, labels = lbl, expand = expansion(mult = 0.05))
}

# ---------------------------------------------------------------------------
# A. HEADLINE CHART — Release date vs developmental age horizon
# ---------------------------------------------------------------------------
cat("Plotting A: headline trend...\n")

# Use n_dims_above_80 for y-axis (0-12, more granular than mastery_80)
headline_data <- horizons %>%
  filter(!is.na(date_years))

p_headline <- ggplot(headline_data,
       aes(x = date_years, y = n_dims_above_80)) +
  geom_hline(yintercept = 12, linetype = "dashed", color = "grey60", linewidth = 0.4) +
  annotate("text", x = -0.3, y = 12.3, label = "All 12 dimensions mastered",
           hjust = 0, size = 2.8, color = "grey50") +
  geom_point(aes(color = family), size = 2.5, alpha = 0.8) +
  geom_text_repel(aes(label = short, color = family),
                  size = 2.2, max.overlaps = 25, segment.size = 0.25,
                  segment.color = "grey70", seed = 42, force = 2,
                  box.padding = 0.3) +
  geom_smooth(method = "lm", se = TRUE, color = "grey30",
              linewidth = 0.6, alpha = 0.15, linetype = "solid") +
  scale_color_manual(values = FAMILY_COLORS) +
  scale_x_date_years(step = 0.5) +
  scale_y_continuous(
    breaks = seq(0, 12, by = 2),
    limits = c(-0.5, 13.5),
    labels = function(x) ifelse(x == 12, "12 (all)", as.character(x))
  ) +
  labs(
    title = "Developmental ToM dimensions mastered\nby different LLMs over time",
    subtitle = "Number of ToM dimensions (out of 12) where model achieves >= 80% accuracy",
    x = "LLM release date",
    y = "Dimensions mastered (>= 80% accuracy)",
    color = "Family"
  ) +
  theme_devtom(base_size = 10) +
  theme(
    legend.position = "bottom",
    legend.title = element_blank(),
    plot.title = element_text(size = 14),
    plot.subtitle = element_text(size = 9, color = "grey40")
  )

ggsave(file.path(fig_dir, "headline_dims_mastered.png"), p_headline,
       width = 10, height = 7.5, dpi = 300, bg = "white")

# Version with mastery_80 (developmental age) on y-axis
p_headline_age <- ggplot(headline_data,
       aes(x = date_years, y = mastery_80)) +
  geom_hline(yintercept = 10, linetype = "dashed", color = "grey60", linewidth = 0.4) +
  annotate("text", x = -0.3, y = 10.5,
           label = "Measurements above 10 yr are at ceiling\nwith our current test suite",
           hjust = 0, size = 2.6, color = "grey50", lineheight = 0.9) +
  geom_point(aes(color = family), size = 2.5, alpha = 0.8) +
  geom_text_repel(aes(label = short, color = family),
                  size = 2.2, max.overlaps = 25, segment.size = 0.25,
                  segment.color = "grey70", seed = 42, force = 2,
                  box.padding = 0.3) +
  scale_color_manual(values = FAMILY_COLORS) +
  scale_x_date_years(step = 0.5) +
  scale_y_continuous(
    breaks = c(0, 2.5, 3.5, 5, 7, 10),
    labels = c("0", "2-3 yr", "3-4 yr", "5 yr", "7 yr", "9-11 yr"),
    limits = c(-0.5, 12)
  ) +
  labs(
    title = "Developmental age horizon of\ndifferent LLMs over time",
    subtitle = "Highest developmental age band where model achieves >= 80% accuracy on any dimension",
    x = "LLM release date",
    y = "Developmental age horizon",
    color = "Family"
  ) +
  theme_devtom(base_size = 10) +
  theme(
    legend.position = "bottom",
    legend.title = element_blank(),
    plot.title = element_text(size = 14),
    plot.subtitle = element_text(size = 9, color = "grey40")
  )

ggsave(file.path(fig_dir, "headline_age_horizon.png"), p_headline_age,
       width = 10, height = 7.5, dpi = 300, bg = "white")

# ---------------------------------------------------------------------------
# B. PER-MODEL LOGISTIC FIT — accuracy vs developmental age (METR detail view)
# ---------------------------------------------------------------------------
cat("Plotting B: per-model logistic fits...\n")

# Select representative models (spanning the performance range)
model_order <- horizons %>%
  arrange(n_dims_above_80, overall_acc) %>%
  pull(model)

# Plot in batches of 9
batch_size <- 9
n_batches <- ceiling(length(model_order) / batch_size)

for (b in seq_len(n_batches)) {
  idx <- ((b - 1) * batch_size + 1) : min(b * batch_size, length(model_order))
  batch_models <- model_order[idx]

  batch_dim <- dim_acc %>%
    filter(model %in% batch_models) %>%
    mutate(
      short = short_model(model),
      short = factor(short, levels = short_model(batch_models))
    )

  batch_curves <- pred_curves %>%
    filter(model %in% batch_models) %>%
    mutate(
      short = short_model(model),
      short = factor(short, levels = short_model(batch_models))
    )

  batch_horizons <- horizons %>%
    filter(model %in% batch_models) %>%
    mutate(short = factor(short, levels = short_model(batch_models)))

  p <- ggplot() +
    # Logistic fit curve
    geom_line(data = batch_curves,
              aes(x = dim_age, y = pred_prob),
              color = "grey30", linewidth = 0.6) +
    # Observed dimension accuracies
    geom_point(data = batch_dim,
               aes(x = dim_age, y = accuracy, size = n_items,
                   color = accuracy),
               alpha = 0.8) +
    # 80% threshold line
    geom_hline(yintercept = 0.80, linetype = "dashed",
               color = "#a50f15", linewidth = 0.3, alpha = 0.5) +
    # 50% threshold line
    geom_hline(yintercept = 0.50, linetype = "dotted",
               color = "grey50", linewidth = 0.3) +
    # Facet subtitle with overall accuracy
    geom_text(data = batch_horizons,
              aes(x = 2, y = 0.05,
                  label = sprintf("%.0f%% overall | %d/12 dims >= 80%%",
                                  overall_acc * 100, n_dims_above_80)),
              hjust = 0, size = 2.2, color = "grey40") +
    facet_wrap(~ short, ncol = 3, scales = "fixed") +
    scale_x_continuous(
      breaks = c(3, 5, 7, 10),
      labels = c("3yr", "5yr", "7yr", "10yr"),
      limits = c(1.5, 12)
    ) +
    scale_y_continuous(
      breaks = seq(0, 1, by = 0.25),
      labels = percent,
      limits = c(0, 1.05)
    ) +
    scale_color_gradient2(
      low = "#d73027", mid = "#fee08b", high = "#1a9850",
      midpoint = 0.5, limits = c(0, 1),
      guide = guide_colorbar(barwidth = 8, barheight = 0.4,
                              title.position = "top")
    ) +
    scale_size_continuous(range = c(1.5, 5), guide = "none") +
    labs(
      title = sprintf("Per-model accuracy vs. developmental age (page %d/%d)", b, n_batches),
      subtitle = "Each point = one ToM dimension. Curve = binomial logistic fit. Red dashed = 80% threshold.",
      x = "Developmental age",
      y = "Accuracy",
      color = "Accuracy"
    ) +
    theme_devtom(base_size = 10) +
    theme(
      legend.position = "bottom",
      strip.text = element_text(size = 9, face = "bold"),
      panel.grid.major.x = element_line(color = "grey90", linewidth = 0.3)
    )

  ggsave(file.path(fig_dir, sprintf("per_model_logistic_%02d.png", b)), p,
         width = 11, height = 9, dpi = 300, bg = "white")
}

# ---------------------------------------------------------------------------
# C. FAMILY-FACETED TREND — one panel per family
# ---------------------------------------------------------------------------
cat("Plotting C: family-faceted trend...\n")

p_family <- ggplot(headline_data,
       aes(x = date_years, y = n_dims_above_80)) +
  geom_hline(yintercept = 12, linetype = "dashed", color = "grey70", linewidth = 0.3) +
  geom_point(aes(color = family), size = 2, alpha = 0.8) +
  geom_text_repel(aes(label = short, color = family),
                  size = 2, max.overlaps = 15, segment.size = 0.2,
                  segment.color = "grey70", seed = 42) +
  geom_smooth(method = "lm", se = TRUE, color = "grey30",
              linewidth = 0.5, alpha = 0.15) +
  facet_wrap(~ family, ncol = 3) +
  scale_color_manual(values = FAMILY_COLORS, guide = "none") +
  scale_x_date_years(step = 1) +
  scale_y_continuous(breaks = seq(0, 12, by = 3), limits = c(-0.5, 13.5)) +
  labs(
    title = "ToM dimensions mastered over time, by family",
    subtitle = "Number of dimensions with >= 80% accuracy",
    x = "Release date", y = "Dimensions mastered"
  ) +
  theme_devtom(base_size = 10) +
  theme(strip.text = element_text(size = 11, face = "bold"))

ggsave(file.path(fig_dir, "family_trend.png"), p_family,
       width = 12, height = 7, dpi = 300, bg = "white")

# ---------------------------------------------------------------------------
# D. DIMENSION MASTERY HEATMAP
# ---------------------------------------------------------------------------
cat("Plotting D: dimension mastery heatmap...\n")

heatmap_data <- dim_acc %>%
  mutate(
    short = short_model(model),
    tom_dimension = factor_dimension(tom_dimension)
  ) %>%
  left_join(horizons %>% select(model, n_dims_above_80, overall_acc), by = "model") %>%
  mutate(
    date_yrs = as.numeric(as.Date(release_date) - as.Date("2024-01-01")) / 365.25,
    short = reorder(short, date_yrs)
  )

p_heatmap <- ggplot(heatmap_data, aes(x = tom_dimension, y = short, fill = accuracy)) +
  geom_tile(color = "white", linewidth = 0.3) +
  geom_text(aes(label = sprintf("%.0f", accuracy * 100)),
            size = 2, color = ifelse(heatmap_data$accuracy > 0.6, "white", "black")) +
  scale_fill_gradient2(
    low = "#d73027", mid = "#fee08b", high = "#1a9850",
    midpoint = 0.5, limits = c(0, 1),
    labels = percent
  ) +
  scale_x_discrete(labels = function(x) {
    sub(" / Prosocial Deception", "", sub(" \\(Appearance vs. Reality\\)", "",
      sub(" / Ignorance", "", x)))
  }) +
  labs(
    title = "Accuracy by model and ToM dimension",
    subtitle = "Dimensions ordered by developmental acquisition age (left = earliest). Models ordered by release date.",
    x = NULL, y = NULL, fill = "Accuracy"
  ) +
  theme_devtom(base_size = 9) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
    axis.text.y = element_text(size = 6.5),
    legend.position = "right",
    panel.grid = element_blank()
  )

ggsave(file.path(fig_dir, "dimension_mastery_heatmap.png"), p_heatmap,
       width = 13, height = 11, dpi = 300, bg = "white")

# ---------------------------------------------------------------------------
# E. COMBINED HEADLINE (METR-style, publication quality)
# ---------------------------------------------------------------------------
cat("Plotting E: METR-style combined headline...\n")

# Add jitter to mastery_80 to reduce overplotting
set.seed(42)
headline_data <- headline_data %>%
  mutate(
    mastery_jitter = mastery_80 + runif(n(), -0.3, 0.3),
    is_frontier = n_dims_above_80 == 12,
    label_show = case_when(
      # Always label frontier models and floor models
      is_frontier ~ short,
      mastery_80 <= 3.5 ~ short,
      # Label a few mid-range models
      overall_acc < 0.6 ~ short,
      TRUE ~ NA_character_
    )
  )

# Annotated exemplar tasks at each age level
age_annotations <- tibble(
  y = c(2.5, 3.5, 4.5, 7.0, 10.0),
  label = c("Diverse Desires", "Diverse Beliefs", "False Belief",
            "Sarcasm / Irony", "Faux Pas")
)

p_metr <- ggplot(headline_data,
       aes(x = date_years, y = mastery_80)) +
  # Ceiling zone
  annotate("rect", xmin = -Inf, xmax = Inf, ymin = 10.5, ymax = 12,
           fill = "grey95", alpha = 0.5) +
  annotate("text", x = 2.7, y = 11.3,
           label = "Beyond measurement\nwith current test suite",
           size = 2.5, color = "grey50", hjust = 1, lineheight = 0.9) +
  # Age band reference lines
  geom_hline(yintercept = c(2.5, 3.5, 4.5, 7, 10),
             linetype = "dotted", color = "grey85", linewidth = 0.3) +
  # Points
  geom_point(aes(color = family, shape = is_frontier), size = 2.5, alpha = 0.85) +
  scale_shape_manual(values = c("FALSE" = 16, "TRUE" = 17), guide = "none") +
  # Labels for selected models
  geom_text_repel(
    aes(label = label_show, color = family),
    size = 2.1, max.overlaps = 30, segment.size = 0.2,
    segment.color = "grey70", seed = 42, force = 3,
    box.padding = 0.35, na.rm = TRUE
  ) +
  scale_color_manual(values = FAMILY_COLORS) +
  scale_x_date_years(step = 0.5) +
  scale_y_continuous(
    breaks = c(0, 2.5, 3.5, 4.5, 7, 10),
    labels = c("0", "2-3 yr", "3-4 yr", "4-5 yr", "6-8 yr", "9-11 yr"),
    limits = c(-0.5, 12),
    sec.axis = sec_axis(
      ~ .,
      breaks = c(2.5, 3.5, 4.5, 7, 10),
      labels = c("Desires", "Beliefs", "False Belief", "Sarcasm", "Faux Pas")
    )
  ) +
  labs(
    title = "Developmental age of ToM tasks that\ndifferent LLMs can master 80% of the time",
    x = "LLM release date",
    y = "Developmental age (human acquisition)",
    color = NULL
  ) +
  theme_devtom(base_size = 10) +
  theme(
    legend.position = "bottom",
    legend.title = element_blank(),
    plot.title = element_text(size = 14, face = "bold"),
    axis.text.y.right = element_text(color = "grey50", size = 8),
    axis.title.y.right = element_blank(),
    panel.grid.major.y = element_blank()
  )

ggsave(file.path(fig_dir, "metr_style_headline.png"), p_metr,
       width = 10, height = 7, dpi = 300, bg = "white")

# ---------------------------------------------------------------------------
# F. SINGLE-MODEL DETAIL (METR per-model equivalent)
# ---------------------------------------------------------------------------
cat("Plotting F: per-model detail for select models...\n")

select_models <- c(
  "openai-api/local/meta-llama/llama-2-7b-chat",
  "openai-api/local/mistralai/mistral-7b-instruct",
  "openrouter/meta-llama/llama-3-8b-instruct",
  "openai/o1",
  "openrouter/meta-llama/llama-3.3-70b-instruct",
  "anthropic/claude-sonnet-5"
)
select_models <- intersect(select_models, horizons$model)

for (mdl in select_models) {
  mdl_dim <- dim_acc %>% filter(model == mdl)
  mdl_curve <- pred_curves %>% filter(model == mdl)
  mdl_info <- horizons %>% filter(model == mdl)
  mdl_short <- short_model(mdl)

  p_detail <- ggplot() +
    geom_hline(yintercept = 0.80, linetype = "dashed", color = "#a50f15",
               linewidth = 0.4, alpha = 0.5) +
    geom_hline(yintercept = 0.50, linetype = "dotted", color = "grey50",
               linewidth = 0.3) +
    geom_line(data = mdl_curve, aes(x = dim_age, y = pred_prob),
              color = "grey30", linewidth = 0.8) +
    geom_ribbon(data = mdl_curve,
                aes(x = dim_age, ymin = pmax(pred_prob - 0.1, 0),
                    ymax = pmin(pred_prob + 0.1, 1)),
                fill = "grey30", alpha = 0.08) +
    geom_point(data = mdl_dim,
               aes(x = dim_age, y = accuracy, color = accuracy, size = n_items),
               alpha = 0.85) +
    geom_text_repel(data = mdl_dim,
                    aes(x = dim_age, y = accuracy,
                        label = sub(" / .*| \\(.*", "", tom_dimension)),
                    size = 2.3, max.overlaps = 20, seed = 42,
                    segment.size = 0.2, segment.color = "grey70") +
    scale_color_gradient2(
      low = "#d73027", mid = "#fee08b", high = "#1a9850",
      midpoint = 0.5, limits = c(0, 1), guide = "none"
    ) +
    scale_size_continuous(range = c(2, 6), guide = "none") +
    scale_x_continuous(
      breaks = c(2.5, 3.5, 5, 7, 10),
      labels = c("2-3yr", "3-4yr", "5yr", "7yr", "9-11yr"),
      limits = c(1.5, 12)
    ) +
    scale_y_continuous(breaks = seq(0, 1, 0.25), labels = percent,
                       limits = c(0, 1.05)) +
    labs(
      title = mdl_short,
      subtitle = sprintf("Overall: %.1f%% | %d/12 dimensions >= 80%%",
                          mdl_info$overall_acc * 100, mdl_info$n_dims_above_80),
      x = "Developmental age (human acquisition)",
      y = "Accuracy"
    ) +
    theme_devtom(base_size = 11) +
    theme(
      plot.title = element_text(size = 16, face = "bold"),
      plot.subtitle = element_text(size = 10, color = "grey40"),
      panel.grid.major.x = element_line(color = "grey90", linewidth = 0.3)
    )

  fname <- gsub("[^a-zA-Z0-9_-]", "_", mdl_short)
  ggsave(file.path(fig_dir, sprintf("detail_%s.png", fname)), p_detail,
         width = 8, height = 6, dpi = 300, bg = "white")
}

# ---------------------------------------------------------------------------
# G. FACETED BY MODEL SIZE — developmental age horizon vs release date
# ---------------------------------------------------------------------------
cat("Plotting G: faceted by model size...\n")

# Get params_b per model from item_level.csv
item_df <- read_csv("results/item_level.csv", show_col_types = FALSE)
params_lookup <- item_df %>%
  select(model, params_b) %>%
  distinct()

headline_size <- headline_data %>%
  left_join(params_lookup, by = "model") %>%
  filter(!is.na(params_b)) %>%
  mutate(
    size_cat = case_when(
      params_b < 10  ~ "Small (< 10B)",
      params_b < 50  ~ "Mid (10-50B)",
      params_b < 150 ~ "Large (50-150B)",
      TRUE           ~ "Frontier (> 150B)"
    ),
    size_cat = factor(size_cat, levels = c("Small (< 10B)", "Mid (10-50B)",
                                            "Large (50-150B)", "Frontier (> 150B)"))
  )

p_size <- ggplot(headline_size,
       aes(x = date_years, y = mastery_80)) +
  geom_hline(yintercept = 10, linetype = "dashed", color = "grey60", linewidth = 0.3) +
  annotate("rect", xmin = -Inf, xmax = Inf, ymin = 10.5, ymax = 12,
           fill = "grey95", alpha = 0.5) +
  annotate("text", x = 2.5, y = 11.3,
           label = "Beyond measurement", size = 2.3, color = "grey50", hjust = 1) +
  geom_point(aes(color = family), size = 2.5, alpha = 0.8) +
  geom_text_repel(aes(label = short, color = family),
                  size = 2, max.overlaps = 15, segment.size = 0.2,
                  segment.color = "grey70", seed = 42) +
  geom_smooth(method = "lm", se = TRUE, color = "grey30",
              linewidth = 0.5, alpha = 0.15) +
  facet_wrap(~ size_cat, ncol = 2) +
  scale_color_manual(values = FAMILY_COLORS) +
  scale_x_date_years(step = 1) +
  scale_y_continuous(
    breaks = c(0, 2.5, 3.5, 5, 7, 10),
    labels = c("0", "2-3yr", "3-4yr", "5yr", "7yr", "9-11yr"),
    limits = c(-0.5, 12)
  ) +
  labs(
    title = "Developmental age horizon by model size",
    subtitle = "Highest developmental age band with >= 80% accuracy on any ToM dimension. Faceted by parameter count.",
    x = "LLM release date",
    y = "Developmental age horizon",
    color = "Family"
  ) +
  theme_devtom(base_size = 10) +
  theme(
    legend.position = "bottom",
    legend.title = element_blank(),
    strip.text = element_text(size = 11, face = "bold"),
    plot.subtitle = element_text(size = 9, color = "grey40")
  )

ggsave(file.path(fig_dir, "facet_by_size.png"), p_size,
       width = 12, height = 9, dpi = 300, bg = "white")

# ---------------------------------------------------------------------------
# H. FACETED BY MODEL FAMILY — developmental age horizon vs release date
# ---------------------------------------------------------------------------
cat("Plotting H: faceted by family (age horizon)...\n")

headline_family <- headline_data %>%
  left_join(params_lookup, by = "model")

p_family_age <- ggplot(headline_family,
       aes(x = date_years, y = mastery_80)) +
  geom_hline(yintercept = 10, linetype = "dashed", color = "grey60", linewidth = 0.3) +
  annotate("rect", xmin = -Inf, xmax = Inf, ymin = 10.5, ymax = 12,
           fill = "grey95", alpha = 0.5) +
  geom_point(aes(color = family, size = params_b), alpha = 0.8) +
  geom_text_repel(aes(label = short, color = family),
                  size = 2, max.overlaps = 15, segment.size = 0.2,
                  segment.color = "grey70", seed = 42) +
  geom_smooth(method = "lm", se = TRUE, color = "grey30",
              linewidth = 0.5, alpha = 0.15) +
  facet_wrap(~ family, ncol = 3) +
  scale_color_manual(values = FAMILY_COLORS, guide = "none") +
  scale_size_continuous(range = c(1.5, 5), name = "Params (B)") +
  scale_x_date_years(step = 1) +
  scale_y_continuous(
    breaks = c(0, 2.5, 3.5, 5, 7, 10),
    labels = c("0", "2-3yr", "3-4yr", "5yr", "7yr", "9-11yr"),
    limits = c(-0.5, 12)
  ) +
  labs(
    title = "Developmental age horizon over time, by model family",
    subtitle = "Highest developmental age band with >= 80% accuracy. Point size proportional to parameter count.",
    x = "Release date",
    y = "Developmental age horizon"
  ) +
  theme_devtom(base_size = 10) +
  theme(
    strip.text = element_text(size = 11, face = "bold"),
    plot.subtitle = element_text(size = 9, color = "grey40")
  )

ggsave(file.path(fig_dir, "facet_by_family_age.png"), p_family_age,
       width = 12, height = 7, dpi = 300, bg = "white")

# ---------------------------------------------------------------------------
cat(sprintf("\nDone. %d figures saved to: %s\n",
            length(list.files(fig_dir, pattern = "\\.png$")), fig_dir))
