#!/usr/bin/env Rscript
# visualize_glmm_trajectory.R — GLMM inference visualizations
#
# Reads modeling_inference/ CSVs (from scripts/5_model/glmm_trajectory.R),
# renders PNGs (300 dpi) to results/figures/inference/<timestamp>/:
#   a. Predicted-probability trajectory per tier (line + 95% ribbon)
#   b. Odds-ratio forest plot of fixed effects
#   c. Dimension x time slopes vs developmental rank
#   d. Task-split trajectory (MCQ vs free-response facets)
#
# Usage:
#   Rscript scripts/6_visualize/visualize_glmm_trajectory.R
#   Rscript scripts/6_visualize/visualize_glmm_trajectory.R \
#     --inference-dir results/modeling/inference/<ts>

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(readr)
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
inference_dir <- NULL
results_dir <- "results"

i <- 1
while (i <= length(args)) {
  if (args[i] == "--inference-dir" && i < length(args)) {
    inference_dir <- args[i + 1]; i <- i + 2
  } else if (args[i] == "--results-dir" && i < length(args)) {
    results_dir <- args[i + 1]; i <- i + 2
  } else {
    i <- i + 1
  }
}

if (is.null(inference_dir)) {
  search_dir <- file.path(results_dir, "modeling", "inference")
  if (dir.exists(search_dir)) {
    stamps <- sort(list.dirs(search_dir, recursive = FALSE, full.names = TRUE))
    if (length(stamps) > 0) inference_dir <- stamps[length(stamps)]
  }
}

if (is.null(inference_dir) || !dir.exists(inference_dir)) {
  stop("No modeling/inference directory found. Run: Rscript scripts/5_model/glmm_trajectory.R")
}

cat("Reading from:", inference_dir, "\n")

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path(results_dir, "figures", "inference", stamp)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

n_written <- 0
save_plot <- function(p, filename, width = 10, height = 7) {
  path <- file.path(out_dir, filename)
  ggsave(path, p, width = width, height = height, dpi = 300)
  cat(sprintf("Wrote %s\n", path))
  n_written <<- n_written + 1
}

# ---------------------------------------------------------------------------
# a. Predicted-probability trajectory per tier
# ---------------------------------------------------------------------------
pred_file <- file.path(inference_dir, "glmm_pred_trajectory.csv")
obs_file <- file.path(inference_dir, "glmm_observed_points.csv")

if (file.exists(pred_file) && file.exists(obs_file)) {
  pred <- read_csv(pred_file, show_col_types = FALSE)
  obs <- read_csv(obs_file, show_col_types = FALSE)

  pred$tier <- factor_tier(pred$tier)
  pred$family <- factor_family(pred$family)
  obs$tier <- factor_tier(obs$tier)
  obs$family <- factor_family(obs$family)
  obs$short_model <- short_model(obs$model)

  p <- ggplot() +
    geom_ribbon(data = pred, aes(x = date_years, ymin = pred_lo, ymax = pred_hi,
                                  fill = tier), alpha = 0.2) +
    geom_line(data = pred, aes(x = date_years, y = pred, color = tier),
              linewidth = 0.8) +
    geom_point(data = obs, aes(x = date_years, y = accuracy, color = tier),
               size = 2, alpha = 0.8) +
    geom_text(data = obs, aes(x = date_years, y = accuracy, label = short_model),
              size = 2, hjust = -0.1, vjust = -0.5, check_overlap = TRUE) +
    geom_hline(yintercept = 0.5, linetype = "dashed", color = "grey60") +
    scale_color_manual(values = TYPE_COLORS) +
    scale_fill_manual(values = TYPE_COLORS) +
    facet_wrap(~family, scales = "free_x") +
    ylim(0.4, 1.05) +
    labs(title = "GLMM predicted ToM accuracy trajectory",
         subtitle = "Lines = population-level predictions; ribbons = 95% CI; points = observed",
         x = "Release date (years since 2024-01-01)",
         y = "Predicted probability correct",
         color = "Tier", fill = "Tier") +
    theme_devtom() +
    theme(legend.position = "bottom")
  save_plot(p, "trajectory_by_tier.png", width = 14, height = 10)
}

# ---------------------------------------------------------------------------
# b. Odds-ratio forest plot
# ---------------------------------------------------------------------------
or_file <- file.path(inference_dir, "glmm_or_table.csv")
if (file.exists(or_file)) {
  or_df <- read_csv(or_file, show_col_types = FALSE) %>%
    filter(model_label == "M1_date_x_tier") %>%
    filter(!grepl("^\\(Intercept\\)", term))

  if (nrow(or_df) > 0) {
    or_df$label <- paste0(or_df$family, ": ", or_df$term)
    or_df <- or_df %>% arrange(family, estimate)
    or_df$label <- factor(or_df$label, levels = or_df$label)

    p <- ggplot(or_df, aes(x = estimate, y = label, color = family)) +
      geom_point(size = 2.5) +
      geom_errorbarh(aes(xmin = conf.low, xmax = conf.high), height = 0.3) +
      geom_vline(xintercept = 1, linetype = "dashed", color = "grey50") +
      scale_color_manual(values = FAMILY_COLORS) +
      scale_x_log10() +
      labs(title = "GLMM fixed-effect odds ratios",
           subtitle = "OR > 1 = higher accuracy; vertical dashed = OR=1 (no effect)",
           x = "Odds Ratio (log scale)", y = NULL, color = "Family") +
      theme_devtom()
    save_plot(p, "or_forest_plot.png", width = 12,
              height = max(5, nrow(or_df) * 0.4))
  }
}

# ---------------------------------------------------------------------------
# c. Dimension x time slopes vs developmental rank
# ---------------------------------------------------------------------------
dim_file <- file.path(inference_dir, "glmm_dim_time_slopes.csv")
if (file.exists(dim_file)) {
  dim_slopes <- read_csv(dim_file, show_col_types = FALSE)
  dim_slopes$tom_dimension <- factor_dimension(dim_slopes$tom_dimension)
  dim_slopes$family <- factor_family(dim_slopes$family)

  p <- ggplot(dim_slopes, aes(x = dim_rank, y = slope_or,
                                color = family)) +
    geom_point(size = 2.5) +
    geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.3) +
    geom_hline(yintercept = 1, linetype = "dashed", color = "grey50") +
    scale_color_manual(values = FAMILY_COLORS) +
    scale_x_continuous(
      breaks = sort(unique(dim_slopes$dim_rank)),
      labels = function(x) {
        labels <- dim_slopes %>%
          distinct(dim_rank, tom_dimension) %>%
          arrange(dim_rank)
        sapply(x, function(xi) {
          match <- labels$tom_dimension[labels$dim_rank == xi]
          if (length(match) > 0) match[1] else as.character(xi)
        })
      }
    ) +
    labs(title = "Per-dimension time slopes (OR/year) by developmental order",
         subtitle = "OR > 1 = improving over time for that dimension",
         x = "Dimension (developmental order, earliest first)",
         y = "OR per year (95% CI)",
         color = "Family") +
    theme_devtom() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7))
  save_plot(p, "dim_time_slopes.png", width = 14, height = 7)
}

# ---------------------------------------------------------------------------
# d. Task-split trajectory
# ---------------------------------------------------------------------------
task_file <- file.path(inference_dir, "glmm_pred_by_task.csv")
if (file.exists(task_file)) {
  task_pred <- read_csv(task_file, show_col_types = FALSE)
  task_pred$family <- factor_family(task_pred$family)

  p <- ggplot(task_pred, aes(x = date_years, y = pred, color = family)) +
    geom_line(linewidth = 0.8) +
    geom_hline(yintercept = 0.5, linetype = "dashed", color = "grey60") +
    scale_color_manual(values = FAMILY_COLORS) +
    facet_wrap(~task) +
    ylim(0.4, 1.05) +
    labs(title = "GLMM predicted trajectory: MCQ vs. free-response",
         x = "Release date (years since 2024-01-01)",
         y = "Predicted probability correct",
         color = "Family") +
    theme_devtom()
  save_plot(p, "trajectory_by_task.png", width = 12, height = 6)
}

cat(sprintf("\nWrote %d figures to %s/\n", n_written, out_dir))
