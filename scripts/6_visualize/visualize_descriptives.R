#!/usr/bin/env Rscript
# visualize_descriptives.R — Descriptive-statistics visualizations
#
# Reads stats_dataset/ and stats_results/ CSVs (from scripts/4_statistics/),
# renders PNGs to results/figures/descriptives/<timestamp>/.
#
# Usage:
#   Rscript scripts/6_visualize/visualize_descriptives.R
#   Rscript scripts/6_visualize/visualize_descriptives.R \
#     --stats-dataset results/<ts>/stats_dataset \
#     --stats-results results/<ts>/stats_results

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(patchwork)
})

# Source shared theme (handles both interactive and script invocation)
script_dir <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) "scripts/6_visualize"
)
source(file.path(script_dir, "_theme.R"))

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
stats_dataset_dir <- NULL
stats_results_dir <- NULL
results_dir <- "results"

i <- 1
while (i <= length(args)) {
  if (args[i] == "--stats-dataset" && i < length(args)) {
    stats_dataset_dir <- args[i + 1]; i <- i + 2
  } else if (args[i] == "--stats-results" && i < length(args)) {
    stats_results_dir <- args[i + 1]; i <- i + 2
  } else if (args[i] == "--results-dir" && i < length(args)) {
    results_dir <- args[i + 1]; i <- i + 2
  } else {
    i <- i + 1
  }
}

# Auto-detect latest timestamped run under results/<subdir>/
find_latest <- function(parent, subdir) {
  search_dir <- file.path(parent, subdir)
  if (!dir.exists(search_dir)) return(NULL)
  stamps <- sort(list.dirs(search_dir, recursive = FALSE, full.names = TRUE))
  if (length(stamps) == 0) return(NULL)
  stamps[length(stamps)]
}

if (is.null(stats_dataset_dir)) {
  stats_dataset_dir <- find_latest(results_dir, file.path("stats", "dataset"))
}
if (is.null(stats_results_dir)) {
  stats_results_dir <- find_latest(results_dir, file.path("stats", "results"))
}

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path(results_dir, "figures", "descriptives", stamp)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

n_written <- 0
save_plot <- function(p, filename, width = 10, height = 7) {
  path <- file.path(out_dir, filename)
  ggsave(path, p, width = width, height = height, dpi = 300)
  cat(sprintf("Wrote %s\n", path))
  n_written <<- n_written + 1
}

# ---------------------------------------------------------------------------
# Dataset composition + coverage
# ---------------------------------------------------------------------------
if (!is.null(stats_dataset_dir) && dir.exists(stats_dataset_dir)) {
  cat("Reading dataset stats from:", stats_dataset_dir, "\n")

  comp_file <- file.path(stats_dataset_dir, "composition_by_dimension.csv")
  if (file.exists(comp_file)) {
    comp <- read_csv(comp_file, show_col_types = FALSE)
    comp$tom_dimension <- factor_dimension(comp$tom_dimension)

    p <- ggplot(comp, aes(x = tom_dimension, y = count, fill = task_type)) +
      geom_col(position = "dodge") +
      coord_flip() +
      labs(title = "Item composition by ToM dimension",
           x = NULL, y = "Number of items", fill = "Task type") +
      theme_devtom()
    save_plot(p, "composition_by_dimension.png", width = 10, height = 7)
  }

  cov_file <- file.path(stats_dataset_dir, "coverage_dimension_x_age_band.csv")
  if (file.exists(cov_file)) {
    cov <- read_csv(cov_file, show_col_types = FALSE)
    cov_long <- cov %>%
      pivot_longer(-tom_dimension, names_to = "age_band", values_to = "count")
    cov_long$tom_dimension <- factor_dimension(cov_long$tom_dimension)

    # Expand age bands into individual years ("3-5 yrs" -> 3, 4, 5)
    cov_long$age_lo <- as.integer(sub("^(\\d+).*", "\\1", cov_long$age_band))
    cov_long$age_hi <- as.integer(sub("^\\d+-(\\d+).*", "\\1", cov_long$age_band))
    cov_expanded <- cov_long %>%
      rowwise() %>%
      mutate(age_year = list(seq(age_lo, age_hi))) %>%
      unnest(age_year) %>%
      ungroup() %>%
      group_by(tom_dimension, age_year) %>%
      summarise(count = sum(count), .groups = "drop") %>%
      mutate(age_label = paste0(age_year, " yrs"),
             count_label = as.character(as.integer(count)))
    cov_agg <- cov_expanded
    cov_agg$age_label <- factor(cov_agg$age_label,
                                 levels = paste0(sort(unique(cov_agg$age_year)), " yrs"))

    p <- ggplot(cov_agg, aes(x = age_label, y = tom_dimension, fill = count)) +
      geom_tile(color = "white") +
      geom_text(aes(label = count_label), size = 3) +
      scale_fill_gradient(low = "white", high = "#2166ac") +
      labs(title = "Coverage: dimension x target age",
           x = "Target age", y = NULL, fill = "Items") +
      theme_devtom() +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))
    save_plot(p, "coverage_dimension_age_band.png", width = 10, height = 7)
  }

  balance_file <- file.path(stats_dataset_dir, "label_balance_mcq.csv")
  if (file.exists(balance_file)) {
    balance <- read_csv(balance_file, show_col_types = FALSE)
    bal_long <- balance %>%
      pivot_longer(-tom_dimension, names_to = "target", values_to = "count")
    bal_long$tom_dimension <- factor_dimension(bal_long$tom_dimension)

    p <- ggplot(bal_long, aes(x = tom_dimension, y = count, fill = target)) +
      geom_col(position = "dodge") +
      coord_flip() +
      labs(title = "MCQ target label balance by dimension",
           x = NULL, y = "Count", fill = "Target") +
      theme_devtom()
    save_plot(p, "label_balance_mcq.png", width = 10, height = 7)
  }
} else {
  cat("No stats_dataset directory found -- skipping dataset viz.\n")
  cat("Run: python scripts/4_statistics/profile_dataset.py\n")
}

# ---------------------------------------------------------------------------
# Results descriptives
# ---------------------------------------------------------------------------
if (!is.null(stats_results_dir) && dir.exists(stats_results_dir)) {
  cat("\nReading results stats from:", stats_results_dir, "\n")

  # CTT item map
  ctt_file <- file.path(stats_results_dir, "ctt_item_stats.csv")
  if (file.exists(ctt_file)) {
    ctt <- read_csv(ctt_file, show_col_types = FALSE)
    ctt$tom_dimension <- factor_dimension(ctt$tom_dimension)

    p <- ggplot(ctt, aes(x = facility, y = discrimination,
                          color = tom_dimension)) +
      geom_point(alpha = 0.7, size = 2) +
      geom_hline(yintercept = 0.3, linetype = "dashed", color = "grey50") +
      geom_vline(xintercept = c(0.2, 0.8), linetype = "dashed", color = "grey50") +
      annotate("rect", xmin = 0.2, xmax = 0.8, ymin = 0.3, ymax = Inf,
               alpha = 0.05, fill = "green") +
      labs(title = "CTT item map: facility vs. point-biserial discrimination",
           subtitle = "Green zone: acceptable facility (0.2-0.8) and discrimination (>0.3)",
           x = "Facility (proportion correct)", y = "Point-biserial discrimination",
           color = "Dimension") +
      facet_wrap(~task) +
      theme_devtom() +
      theme(legend.position = "bottom",
            legend.text = element_text(size = 7))
    save_plot(p, "ctt_item_map.png", width = 14, height = 8)
  }

  # KR-20 reliability bars
  kr_file <- file.path(stats_results_dir, "reliability_kr20.csv")
  if (file.exists(kr_file)) {
    kr <- read_csv(kr_file, show_col_types = FALSE) %>%
      filter(!is.na(kr20))

    p <- ggplot(kr, aes(x = reorder(scope, kr20), y = kr20, fill = task)) +
      geom_col(position = "dodge") +
      geom_hline(yintercept = 0.7, linetype = "dashed", color = "red") +
      coord_flip() +
      labs(title = "Internal consistency (KR-20)",
           subtitle = "Dashed line: alpha >= 0.7 guideline",
           x = NULL, y = "KR-20", fill = "Task") +
      theme_devtom()
    save_plot(p, "reliability_kr20.png", width = 10, height = max(5, nrow(kr) * 0.4))
  }

  # Per-model accuracy caterpillar (Wilson CI)
  acc_file <- file.path(stats_results_dir, "model_accuracy.csv")
  if (file.exists(acc_file)) {
    acc <- read_csv(acc_file, show_col_types = FALSE)
    acc$short_model <- short_model(acc$model)
    acc$family <- factor_family(acc$family)

    # Join release dates from item_level.csv for chronological ordering
    item_csv <- "results/item_level.csv"
    if (file.exists(item_csv)) {
      dates <- read_csv(item_csv, show_col_types = FALSE) %>%
        distinct(model, release_date, date_years)
      acc <- acc %>% left_join(dates, by = "model")
    } else {
      acc$release_date <- NA
      acc$date_years <- NA
    }
    # Order: by family, then by release date (models without dates sort last)
    acc <- acc %>% arrange(family, !is.na(date_years), date_years, model)
    acc$short_model <- factor(acc$short_model, levels = acc$short_model)

    p <- ggplot(acc, aes(x = accuracy, y = short_model, color = family)) +
      geom_point(size = 2) +
      geom_errorbarh(aes(xmin = wilson_lo, xmax = wilson_hi), height = 0.3) +
      geom_vline(xintercept = 0.5, linetype = "dashed", color = "grey50") +
      scale_color_manual(values = FAMILY_COLORS) +
      labs(title = "Per-model overall accuracy (Wilson 95% CI)",
           x = "Accuracy", y = NULL, color = "Family") +
      theme_devtom()
    save_plot(p, "model_accuracy_caterpillar.png", width = 10,
              height = max(5, nrow(acc) * 0.35))
  }

  # Dimension difficulty ranking
  dim_file <- file.path(stats_results_dir, "dimension_difficulty.csv")
  if (file.exists(dim_file)) {
    dim_diff <- read_csv(dim_file, show_col_types = FALSE) %>%
      arrange(mean_accuracy)
    dim_diff$tom_dimension <- factor(dim_diff$tom_dimension,
                                      levels = dim_diff$tom_dimension)

    p <- ggplot(dim_diff, aes(x = mean_accuracy, y = tom_dimension)) +
      geom_col(aes(fill = mean_accuracy)) +
      geom_errorbarh(aes(xmin = mean_accuracy - std, xmax = mean_accuracy + std),
                     height = 0.3) +
      geom_vline(xintercept = 0.5, linetype = "dashed", color = "grey50") +
      scale_fill_gradient2(low = "#d73027", mid = "#fee08b", high = "#1a9850",
                            midpoint = 0.7, guide = "none") +
      labs(title = "Dimension difficulty ranking (hardest at top)",
           subtitle = "Error bars = SD across models",
           x = "Mean accuracy", y = NULL) +
      theme_devtom()
    save_plot(p, "dimension_difficulty_ranking.png", width = 10, height = 7)
  }
} else {
  cat("No stats_results directory found -- skipping results viz.\n")
  cat("Run: python scripts/4_statistics/profile_results.py\n")
}

cat(sprintf("\nWrote %d figures to %s/\n", n_written, out_dir))
