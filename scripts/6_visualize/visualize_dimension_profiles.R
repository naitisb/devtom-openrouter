#!/usr/bin/env Rscript
# visualize_dimension_profiles.R — Dimension-level profile visualizations
#
# Reads results/item_level.csv and produces:
#   - Dimension x model heatmaps (overall, by task, by family, by construct)
#   - Dimension difficulty rankings (overall, by task, by family)
#   - Per-dimension regression grids (accuracy vs date, per family)
#   - Construct-level heatmaps and rankings
#   - Overall accuracy trend with per-tier regression bands + significance
#
# Usage:
#   Rscript scripts/6_visualize/visualize_dimension_profiles.R
#   Rscript scripts/6_visualize/visualize_dimension_profiles.R --item-csv results/item_level.csv

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(scales)
  library(patchwork)
})

script_dir <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) "scripts/6_visualize"
)
source(file.path(script_dir, "_theme.R"))

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
item_csv <- "results/item_level.csv"
results_dir <- "results"

i <- 1
while (i <= length(args)) {
  if (args[i] == "--item-csv" && i < length(args)) {
    item_csv <- args[i + 1]; i <- i + 2
  } else if (args[i] == "--results-dir" && i < length(args)) {
    results_dir <- args[i + 1]; i <- i + 2
  } else {
    i <- i + 1
  }
}

if (!file.exists(item_csv)) {
  stop("Item-level CSV not found: ", item_csv,
       "\nRun: python scripts/4_statistics/extract_item_level.py")
}

df <- read_csv(item_csv, show_col_types = FALSE)
cat(sprintf("Loaded %d rows: %d models, %d dimensions\n",
            nrow(df), n_distinct(df$model), n_distinct(df$tom_dimension)))

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path(results_dir, "figures", "dimension_profiles", stamp)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

n_written <- 0
save_plot <- function(p, filename, width = 10, height = 7) {
  path <- file.path(out_dir, filename)
  ggsave(path, p, width = width, height = height, dpi = 300)
  cat(sprintf("Wrote %s\n", path))
  n_written <<- n_written + 1
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
task_labels <- c("tom_12dim_mcq" = "MCQ", "tom_12dim_freeresponse" = "Free Response")

# Order models by family then ascending release date
order_models <- function(d) {
  model_info <- d %>%
    distinct(model, family, release_date, date_years) %>%
    mutate(
      family = factor(family, levels = intersect(FAMILY_ORDER, unique(family))),
      date_years = as.numeric(date_years)
    ) %>%
    arrange(family, !is.na(date_years), date_years, model)
  model_info$short <- short_model(model_info$model)
  model_info
}

# Compute per-model x dimension accuracy pivot
make_dim_pivot <- function(d, task_filter = NULL) {
  sub <- d
  if (!is.null(task_filter)) sub <- sub %>% filter(task == task_filter)
  sub %>%
    group_by(model, tom_dimension) %>%
    summarise(accuracy = mean(correct), .groups = "drop")
}

# Compute per-model x construct accuracy pivot
make_construct_pivot <- function(d, task_filter = NULL) {
  sub <- d
  if (!is.null(task_filter)) sub <- sub %>% filter(task == task_filter)
  sub %>%
    filter(!is.na(tom_construct)) %>%
    group_by(model, tom_construct) %>%
    summarise(accuracy = mean(correct), .groups = "drop")
}

# Significance stars
sig_stars <- function(p) {
  ifelse(p < 0.001, "***", ifelse(p < 0.01, "**", ifelse(p < 0.05, "*", "ns")))
}

# ===========================================================================
# A. DIMENSION x MODEL HEATMAPS
# ===========================================================================
cat("\n--- Dimension x Model Heatmaps ---\n")

plot_dim_heatmap <- function(d, task_filter = NULL, family_filter = NULL,
                              suffix = "", title_extra = "") {
  sub <- d
  if (!is.null(task_filter)) sub <- sub %>% filter(task == task_filter)
  if (!is.null(family_filter)) sub <- sub %>% filter(family == family_filter)
  if (nrow(sub) == 0) return(invisible(NULL))

  piv <- make_dim_pivot(sub)
  model_ord <- order_models(sub)

  piv <- piv %>%
    mutate(
      short_model = short_model(model),
      short_model = factor(short_model, levels = rev(model_ord$short)),
      tom_dimension = factor(tom_dimension,
                             levels = DIMENSION_DEVELOPMENTAL_ORDER)
    ) %>%
    filter(!is.na(tom_dimension))

  # Family color strip via model -> family mapping
  model_fam <- model_ord %>% select(short, family) %>% rename(short_model = short)
  piv <- piv %>% left_join(model_fam, by = "short_model")

  n_models <- n_distinct(piv$short_model)
  n_dims <- n_distinct(piv$tom_dimension)

  task_label <- if (!is.null(task_filter)) task_labels[task_filter] else "Combined"
  fam_label <- if (!is.null(family_filter)) family_filter else "All families"
  title <- paste0("Accuracy by ToM dimension (", fam_label, ", ", task_label, ")")
  if (nchar(title_extra) > 0) title <- paste0(title, "\n", title_extra)

  p <- ggplot(piv, aes(x = tom_dimension, y = short_model, fill = accuracy)) +
    geom_tile(color = "white", linewidth = 0.3) +
    geom_text(aes(label = sprintf("%.2f", accuracy)), size = 2.2) +
    scale_fill_gradient2(low = "#d73027", mid = "#fee08b", high = "#1a9850",
                         midpoint = 0.7, limits = c(0, 1),
                         name = "Accuracy") +
    labs(title = title,
         x = "ToM dimension (developmental order)",
         y = NULL) +
    theme_devtom() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
          axis.text.y = element_text(size = 7),
          plot.title = element_text(size = 10))

  fname <- paste0("dimension_heatmap", suffix, ".png")
  save_plot(p, fname, width = max(10, n_dims * 0.9 + 3),
            height = max(5, n_models * 0.35 + 2))
}

# Overall heatmap (both tasks)
plot_dim_heatmap(df, suffix = "", title_extra = "Models ordered by release date within family")
# Per task
plot_dim_heatmap(df, task_filter = "tom_12dim_mcq", suffix = "_mcq")
plot_dim_heatmap(df, task_filter = "tom_12dim_freeresponse", suffix = "_freeresponse")
# Per family
for (fam in intersect(FAMILY_ORDER, unique(df$family))) {
  plot_dim_heatmap(df, family_filter = fam,
                   suffix = paste0("_", tolower(fam)))
}

# ===========================================================================
# B. CONSTRUCT x MODEL HEATMAPS
# ===========================================================================
cat("\n--- Construct x Model Heatmaps ---\n")

plot_construct_heatmap <- function(d, task_filter = NULL, family_filter = NULL,
                                    suffix = "") {
  sub <- d
  if (!is.null(task_filter)) sub <- sub %>% filter(task == task_filter)
  if (!is.null(family_filter)) sub <- sub %>% filter(family == family_filter)
  if (nrow(sub) == 0) return(invisible(NULL))

  piv <- make_construct_pivot(sub)
  model_ord <- order_models(sub)

  piv <- piv %>%
    mutate(
      short_model = short_model(model),
      short_model = factor(short_model, levels = rev(model_ord$short)),
      tom_construct = factor(tom_construct,
                             levels = CONSTRUCT_DEVELOPMENTAL_ORDER)
    ) %>%
    filter(!is.na(tom_construct))

  n_models <- n_distinct(piv$short_model)
  task_label <- if (!is.null(task_filter)) task_labels[task_filter] else "Combined"
  fam_label <- if (!is.null(family_filter)) family_filter else "All families"

  p <- ggplot(piv, aes(x = tom_construct, y = short_model, fill = accuracy)) +
    geom_tile(color = "white", linewidth = 0.3) +
    geom_text(aes(label = sprintf("%.2f", accuracy)), size = 2.8) +
    scale_fill_gradient2(low = "#d73027", mid = "#fee08b", high = "#1a9850",
                         midpoint = 0.7, limits = c(0, 1),
                         name = "Accuracy") +
    labs(title = paste0("Accuracy by construct (", fam_label, ", ", task_label, ")"),
         x = "Developmental construct (developmental order)",
         y = NULL) +
    theme_devtom() +
    theme(axis.text.x = element_text(angle = 30, hjust = 1, size = 8),
          axis.text.y = element_text(size = 7))

  save_plot(p, paste0("construct_heatmap", suffix, ".png"),
            width = 9, height = max(5, n_models * 0.35 + 2))
}

plot_construct_heatmap(df, suffix = "")
plot_construct_heatmap(df, task_filter = "tom_12dim_mcq", suffix = "_mcq")
plot_construct_heatmap(df, task_filter = "tom_12dim_freeresponse", suffix = "_freeresponse")
for (fam in intersect(FAMILY_ORDER, unique(df$family))) {
  plot_construct_heatmap(df, family_filter = fam,
                         suffix = paste0("_", tolower(fam)))
}

# ===========================================================================
# C. DIMENSION DIFFICULTY RANKINGS
# ===========================================================================
cat("\n--- Dimension Difficulty Rankings ---\n")

plot_difficulty_ranking <- function(d, task_filter = NULL, family_filter = NULL,
                                     suffix = "", use_construct = FALSE) {
  sub <- d
  if (!is.null(task_filter)) sub <- sub %>% filter(task == task_filter)
  if (!is.null(family_filter)) sub <- sub %>% filter(family == family_filter)
  if (nrow(sub) == 0) return(invisible(NULL))

  group_col <- if (use_construct) "tom_construct" else "tom_dimension"

  # Per-model accuracy for tier overlay
  model_stats <- sub %>%
    group_by(model, tier, .data[[group_col]]) %>%
    summarise(acc = mean(correct), .groups = "drop") %>%
    mutate(tier = factor_tier(tier))

  # Overall order by mean
  dim_order <- model_stats %>%
    group_by(.data[[group_col]]) %>%
    summarise(overall = mean(acc), .groups = "drop") %>%
    arrange(overall) %>%
    pull(.data[[group_col]])

  model_stats[[group_col]] <- factor(model_stats[[group_col]], levels = dim_order)

  task_label <- if (!is.null(task_filter)) task_labels[task_filter] else "Combined"
  fam_label <- if (!is.null(family_filter)) family_filter else "All families"
  level <- if (use_construct) "construct" else "dimension"

  p <- ggplot(model_stats, aes(x = acc, y = .data[[group_col]], color = tier)) +
    geom_point(alpha = 0.6, size = 1.5,
               position = position_jitter(height = 0.2, width = 0, seed = 42)) +
    stat_summary(fun = mean, geom = "point", shape = 18, size = 3.5,
                 color = "black", show.legend = FALSE) +
    geom_vline(xintercept = 0.5, linetype = "dashed", color = "grey50") +
    scale_color_manual(values = TYPE_COLORS) +
    scale_x_continuous(limits = c(0, 1.05), labels = percent_format()) +
    labs(title = paste0("ToM ", level, " difficulty by tier (", fam_label, ", ", task_label, ")"),
         subtitle = "Points = per-model accuracy; diamonds = overall mean",
         x = "Accuracy", y = NULL, color = "Tier") +
    theme_devtom() +
    theme(legend.text = element_text(size = 7))

  n_items <- length(dim_order)
  prefix <- if (use_construct) "construct" else "dimension"
  save_plot(p, paste0(prefix, "_difficulty_ranking", suffix, ".png"),
            width = 10, height = max(4, n_items * 0.45 + 2))
}

# Overall
plot_difficulty_ranking(df, suffix = "")
# Per task
plot_difficulty_ranking(df, task_filter = "tom_12dim_mcq", suffix = "_mcq")
plot_difficulty_ranking(df, task_filter = "tom_12dim_freeresponse", suffix = "_freeresponse")
# Per family
for (fam in intersect(FAMILY_ORDER, unique(df$family))) {
  plot_difficulty_ranking(df, family_filter = fam,
                          suffix = paste0("_", tolower(fam)))
}
# Per family, side-by-side MCQ vs FR
for (fam in intersect(FAMILY_ORDER, unique(df$family))) {
  p_mcq <- NULL; p_fr <- NULL
  sub_fam <- df %>% filter(family == fam)

  for (task_name in c("tom_12dim_mcq", "tom_12dim_freeresponse")) {
    sub <- sub_fam %>% filter(task == task_name)
    if (nrow(sub) == 0) next

    stats <- sub %>%
      group_by(model, tom_dimension) %>%
      summarise(acc = mean(correct), .groups = "drop") %>%
      group_by(tom_dimension) %>%
      summarise(mean_acc = mean(acc), sd_acc = sd(acc), .groups = "drop") %>%
      arrange(mean_acc)
    stats$tom_dimension <- factor(stats$tom_dimension, levels = stats$tom_dimension)

    pp <- ggplot(stats, aes(x = mean_acc, y = tom_dimension)) +
      geom_col(aes(fill = mean_acc), width = 0.7) +
      geom_errorbarh(aes(xmin = pmax(0, mean_acc - sd_acc),
                         xmax = pmin(1, mean_acc + sd_acc)),
                     height = 0.3, linewidth = 0.4) +
      geom_vline(xintercept = 0.5, linetype = "dashed", color = "grey50") +
      scale_fill_gradient2(low = "#d73027", mid = "#fee08b", high = "#1a9850",
                           midpoint = 0.7, guide = "none") +
      scale_x_continuous(limits = c(0, 1.05), labels = percent_format()) +
      labs(title = task_labels[task_name], x = "Mean accuracy", y = NULL) +
      theme_devtom()

    if (task_name == "tom_12dim_mcq") p_mcq <- pp else p_fr <- pp
  }

  if (!is.null(p_mcq) && !is.null(p_fr)) {
    combined <- p_mcq + p_fr +
      plot_annotation(title = paste0(fam, ": dimension difficulty ranking, MCQ vs Free Response"),
                      subtitle = "Hardest at top; error bars = SD across models")
    save_plot(combined, paste0("dimension_difficulty_ranking_", tolower(fam), "_by_task.png"),
              width = 16, height = 8)
  }
}

# Construct-level rankings
plot_difficulty_ranking(df, suffix = "", use_construct = TRUE)
plot_difficulty_ranking(df, task_filter = "tom_12dim_mcq", suffix = "_mcq", use_construct = TRUE)
plot_difficulty_ranking(df, task_filter = "tom_12dim_freeresponse", suffix = "_freeresponse", use_construct = TRUE)
for (fam in intersect(FAMILY_ORDER, unique(df$family))) {
  plot_difficulty_ranking(df, family_filter = fam,
                          suffix = paste0("_", tolower(fam)), use_construct = TRUE)
}

# ===========================================================================
# D. OVERALL ACCURACY TREND WITH REGRESSION BANDS + SIGNIFICANCE
# ===========================================================================
cat("\n--- Overall Accuracy Trends with Regression ---\n")

# Per-model overall accuracy
acc_overall <- df %>%
  filter(!is.na(date_years), !is.na(release_date)) %>%
  group_by(model, family, tier, date_years, release_date) %>%
  summarise(accuracy = mean(correct), n_items = n(), .groups = "drop") %>%
  mutate(
    se = sqrt(accuracy * (1 - accuracy) / n_items),
    ci_lo = pmax(0, accuracy - 1.96 * se),
    ci_hi = pmin(1, accuracy + 1.96 * se),
    short_model = short_model(model),
    date = as.Date(release_date),
    tier = factor_tier(tier),
    family = factor_family(family)
  )

# Per-task accuracy
acc_by_task <- df %>%
  filter(!is.na(date_years), !is.na(release_date)) %>%
  group_by(model, family, tier, date_years, release_date, task) %>%
  summarise(accuracy = mean(correct), n_items = n(), .groups = "drop") %>%
  mutate(
    se = sqrt(accuracy * (1 - accuracy) / n_items),
    ci_lo = pmax(0, accuracy - 1.96 * se),
    ci_hi = pmin(1, accuracy + 1.96 * se),
    short_model = short_model(model),
    date = as.Date(release_date),
    task_label = recode(task, !!!task_labels),
    tier = factor_tier(tier),
    family = factor_family(family)
  )

# Compute per-tier regression stats for annotation
compute_tier_regressions <- function(acc_df) {
  acc_df %>%
    filter(!is.na(date_years), !is.na(accuracy)) %>%
    mutate(date_years = as.numeric(date_years)) %>%
    group_by(tier) %>%
    filter(sum(!is.na(date_years)) >= 3, n_distinct(date_years) >= 2) %>%
    summarise(
      slope = tryCatch(coef(lm(accuracy ~ date_years))[2], error = function(e) NA_real_),
      p_value = tryCatch(summary(lm(accuracy ~ date_years))$coefficients[2, 4], error = function(e) NA_real_),
      n_models = n(),
      .groups = "drop"
    ) %>%
    filter(!is.na(slope)) %>%
    mutate(stars = sig_stars(p_value),
           label = sprintf("%s: %s (p=%.3f)", tier, stars, p_value))
}

# a. By tier, overall, with regression bands
tier_reg <- compute_tier_regressions(acc_overall)

p_trend_tier <- ggplot(acc_overall, aes(x = date, y = accuracy, color = tier)) +
  geom_point(size = 2.5, alpha = 0.8) +
  geom_smooth(method = "lm", se = TRUE, linewidth = 0.8,
              linetype = "dashed", alpha = 0.15) +
  geom_text(aes(label = short_model), size = 1.8, hjust = -0.1, vjust = -0.6,
            check_overlap = TRUE, show.legend = FALSE) +
  scale_color_manual(values = TYPE_COLORS) +
  scale_y_continuous(limits = c(0, 1), labels = percent_format()) +
  scale_x_date(date_labels = "%b %Y") +
  labs(title = "Overall accuracy by release date, per model tier",
       subtitle = paste0("Dashed lines = linear trend ± 95% CI per tier\n",
                         paste(tier_reg$label, collapse = "  |  ")),
       x = "Release date", y = "Overall accuracy", color = "Tier") +
  theme_devtom() +
  theme(legend.position = "bottom",
        legend.text = element_text(size = 7),
        plot.subtitle = element_text(size = 7))
save_plot(p_trend_tier, "accuracy_trend_by_tier_regression.png", width = 14, height = 8)

# c. By tier, MCQ vs FR side-by-side
p_trend_task <- ggplot(acc_by_task, aes(x = date, y = accuracy, color = tier)) +
  geom_point(size = 2, alpha = 0.8) +
  geom_smooth(method = "lm", se = TRUE, linewidth = 0.7,
              linetype = "dashed", alpha = 0.15) +
  geom_text(aes(label = short_model), size = 1.5, hjust = -0.1, vjust = -0.6,
            check_overlap = TRUE, show.legend = FALSE) +
  scale_color_manual(values = TYPE_COLORS) +
  scale_y_continuous(limits = c(0, 1), labels = percent_format()) +
  scale_x_date(date_labels = "%b %Y") +
  facet_wrap(~task_label) +
  labs(title = "Overall accuracy by release date, per tier — MCQ vs Free Response",
       subtitle = "Dashed lines = linear trend ± 95% CI per tier",
       x = "Release date", y = "Accuracy", color = "Tier") +
  theme_devtom() +
  theme(legend.position = "bottom",
        legend.text = element_text(size = 7))
save_plot(p_trend_task, "accuracy_trend_by_task_regression.png", width = 18, height = 8)

# d. Per family, by tier
for (fam in intersect(FAMILY_ORDER, unique(acc_overall$family))) {
  fam_acc <- acc_overall %>% filter(family == fam, !is.na(date_years))
  if (nrow(fam_acc) < 2) next

  fam_tier_reg <- compute_tier_regressions(fam_acc)
  subtitle <- if (nrow(fam_tier_reg) > 0) {
    paste(fam_tier_reg$label, collapse = "  |  ")
  } else {
    "Insufficient data for per-tier regression"
  }

  p <- ggplot(fam_acc, aes(x = date, y = accuracy, color = tier)) +
    geom_point(size = 3, alpha = 0.8) +
    geom_smooth(method = "lm", se = TRUE, linewidth = 0.8,
                linetype = "dashed", alpha = 0.15) +
    geom_line(aes(group = tier), linewidth = 0.4, alpha = 0.3) +
    geom_text(aes(label = short_model), size = 2.2, hjust = -0.1, vjust = -0.6,
              check_overlap = TRUE, show.legend = FALSE) +
    scale_color_manual(values = TYPE_COLORS) +
    scale_y_continuous(limits = c(0, 1), labels = percent_format()) +
    scale_x_date(date_labels = "%b %Y") +
    labs(title = paste0(fam, ": accuracy by release date, per tier"),
         subtitle = subtitle,
         x = "Release date", y = "Overall accuracy", color = "Tier") +
    theme_devtom() +
    theme(legend.position = "bottom",
          plot.subtitle = element_text(size = 8))
  save_plot(p, paste0("accuracy_trend_", tolower(fam), ".png"), width = 10, height = 7)
}

# e. Per family, by tier, MCQ vs FR
for (fam in intersect(FAMILY_ORDER, unique(acc_by_task$family))) {
  fam_task <- acc_by_task %>% filter(family == fam, !is.na(date_years))
  if (nrow(fam_task) < 2) next

  p <- ggplot(fam_task, aes(x = date, y = accuracy, color = tier, shape = task_label)) +
    geom_point(size = 3, alpha = 0.8) +
    geom_line(aes(group = interaction(tier, task_label)),
              linewidth = 0.4, alpha = 0.3) +
    geom_text(aes(label = short_model), size = 1.8, hjust = -0.1, vjust = -0.6,
              check_overlap = TRUE, show.legend = FALSE) +
    scale_color_manual(values = TYPE_COLORS) +
    scale_y_continuous(limits = c(0, 1), labels = percent_format()) +
    scale_x_date(date_labels = "%b %Y") +
    facet_wrap(~task_label) +
    labs(title = paste0(fam, ": accuracy by release date, MCQ vs Free Response"),
         x = "Release date", y = "Accuracy", color = "Tier") +
    guides(shape = "none") +
    theme_devtom() +
    theme(legend.position = "bottom")
  save_plot(p, paste0("accuracy_trend_", tolower(fam), "_by_task.png"),
            width = 14, height = 7)
}

# ===========================================================================
# E. PER-DIMENSION REGRESSION GRIDS (3x4, one panel per dimension)
# ===========================================================================
cat("\n--- Per-Dimension Regression Grids ---\n")

plot_dim_regression_grid <- function(d, family_filter = NULL,
                                      task_filter = "tom_12dim_freeresponse") {
  sub <- d %>%
    filter(task == task_filter, !is.na(date_years), !is.na(release_date))
  if (!is.null(family_filter)) sub <- sub %>% filter(family == family_filter)
  if (nrow(sub) == 0) return(invisible(NULL))

  dim_acc <- sub %>%
    group_by(model, tier, date_years, release_date, tom_dimension) %>%
    summarise(accuracy = mean(correct), .groups = "drop") %>%
    mutate(date = as.Date(release_date),
           tier = factor_tier(tier))

  dims <- intersect(DIMENSION_DEVELOPMENTAL_ORDER, unique(dim_acc$tom_dimension))
  if (length(dims) == 0) return(invisible(NULL))
  dim_acc <- dim_acc %>% filter(tom_dimension %in% dims)
  dim_acc$tom_dimension <- factor(dim_acc$tom_dimension, levels = dims)

  p <- ggplot(dim_acc, aes(x = date, y = accuracy, color = tier)) +
    geom_point(size = 1.5, alpha = 0.7) +
    geom_smooth(method = "lm", se = TRUE, linewidth = 0.7,
                linetype = "dashed", alpha = 0.15) +
    scale_color_manual(values = TYPE_COLORS) +
    geom_hline(yintercept = 0.5, color = "grey50", linetype = "dashed", linewidth = 0.3)

  task_label <- task_labels[task_filter]
  scope_label <- if (is.null(family_filter)) "all families" else family_filter

  p <- p +
    facet_wrap(~tom_dimension, ncol = 4) +
    scale_y_continuous(limits = c(0, 1), labels = percent_format()) +
    scale_x_date(date_labels = "%b\n%Y") +
    labs(title = paste0(scope_label, ": per-dimension accuracy trend (", task_label, ", per tier)"),
         subtitle = "Dimensions in developmental order; one regression line per tier",
         x = "Release date", y = "Accuracy", color = "Tier") +
    theme_devtom() +
    theme(strip.text = element_text(size = 7),
          axis.text = element_text(size = 6),
          legend.position = "bottom",
          legend.text = element_text(size = 6))

  task_slug <- gsub("tom_12dim_", "", task_filter)
  family_slug <- if (is.null(family_filter)) "all" else tolower(family_filter)
  save_plot(p, paste0("dimension_regression_", family_slug, "_", task_slug, ".png"),
            width = 16, height = 10)
}

# All-families-pooled per-dimension grids (per tier)
for (task in c("tom_12dim_freeresponse", "tom_12dim_mcq")) {
  if (!task %in% unique(df$task)) next
  plot_dim_regression_grid(df, family_filter = NULL, task_filter = task)
}

# Per-family per-dimension grids (per tier)
for (fam in intersect(FAMILY_ORDER, unique(df$family))) {
  for (task in c("tom_12dim_freeresponse", "tom_12dim_mcq")) {
    if (!task %in% df$task[df$family == fam]) next
    plot_dim_regression_grid(df, family_filter = fam, task_filter = task)
  }
}

# ===========================================================================
# F. PER-CONSTRUCT REGRESSION GRIDS (2x3, one panel per construct)
# ===========================================================================
cat("\n--- Per-Construct Regression Grids ---\n")

plot_construct_regression_grid <- function(d, family_filter = NULL,
                                            task_filter = "tom_12dim_freeresponse") {
  sub <- d %>%
    filter(task == task_filter, !is.na(date_years), !is.na(release_date),
           !is.na(tom_construct))
  if (!is.null(family_filter)) sub <- sub %>% filter(family == family_filter)
  if (nrow(sub) == 0) return(invisible(NULL))

  con_acc <- sub %>%
    group_by(model, tier, date_years, release_date, tom_construct) %>%
    summarise(accuracy = mean(correct), .groups = "drop") %>%
    mutate(date = as.Date(release_date),
           tier = factor_tier(tier))

  constructs <- intersect(CONSTRUCT_DEVELOPMENTAL_ORDER, unique(con_acc$tom_construct))
  if (length(constructs) == 0) return(invisible(NULL))
  con_acc <- con_acc %>% filter(tom_construct %in% constructs)
  con_acc$tom_construct <- factor(con_acc$tom_construct, levels = constructs)

  task_label <- task_labels[task_filter]
  scope_label <- if (is.null(family_filter)) "all families" else family_filter

  p <- ggplot(con_acc, aes(x = date, y = accuracy, color = tier)) +
    geom_point(size = 1.5, alpha = 0.7) +
    geom_smooth(method = "lm", se = TRUE, linewidth = 0.7,
                linetype = "dashed", alpha = 0.15) +
    scale_color_manual(values = TYPE_COLORS) +
    geom_hline(yintercept = 0.5, color = "grey50", linetype = "dashed", linewidth = 0.3) +
    facet_wrap(~tom_construct, ncol = 3) +
    scale_y_continuous(limits = c(0, 1), labels = percent_format()) +
    scale_x_date(date_labels = "%b\n%Y") +
    labs(title = paste0(scope_label, ": per-construct accuracy trend (", task_label, ", per tier)"),
         subtitle = "Constructs in developmental order; one regression line per tier",
         x = "Release date", y = "Accuracy", color = "Tier") +
    theme_devtom() +
    theme(strip.text = element_text(size = 8),
          axis.text = element_text(size = 6),
          legend.position = "bottom",
          legend.text = element_text(size = 6))

  task_slug <- gsub("tom_12dim_", "", task_filter)
  family_slug <- if (is.null(family_filter)) "all" else tolower(family_filter)
  save_plot(p, paste0("construct_regression_", family_slug, "_", task_slug, ".png"),
            width = 14, height = 8)
}

# All-families-pooled
for (task in c("tom_12dim_freeresponse", "tom_12dim_mcq")) {
  if (!task %in% unique(df$task)) next
  plot_construct_regression_grid(df, family_filter = NULL, task_filter = task)
}

# Per-family
for (fam in intersect(FAMILY_ORDER, unique(df$family))) {
  for (task in c("tom_12dim_freeresponse", "tom_12dim_mcq")) {
    if (!task %in% df$task[df$family == fam]) next
    plot_construct_regression_grid(df, family_filter = fam, task_filter = task)
  }
}

cat(sprintf("\nWrote %d figures to %s/\n", n_written, out_dir))
