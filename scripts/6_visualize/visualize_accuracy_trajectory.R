#!/usr/bin/env Rscript
# visualize_accuracy_trajectory.R — Accuracy vs release date plots
#
# Reads results/item_level.csv directly and produces multiple views of
# overall model accuracy (y) vs release date (x):
#   a. By model type (tier), all tasks combined
#   b. By model type (tier), faceted MCQ vs FR
#   c. Collapsed by model family, all tasks combined
#   d. Collapsed by model family, faceted MCQ vs FR
#
# Usage:
#   Rscript scripts/6_visualize/visualize_accuracy_trajectory.R
#   Rscript scripts/6_visualize/visualize_accuracy_trajectory.R --item-csv results/item_level.csv

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(readr)
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

df <- read_csv(item_csv, show_col_types = FALSE) %>%
  filter(!is.na(date_years), !is.na(release_date))

cat(sprintf("Loaded %d rows with release dates: %d models\n",
            nrow(df), n_distinct(df$model)))

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path(results_dir, "figures", "accuracy_trajectory", stamp)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

n_written <- 0
save_plot <- function(p, filename, width = 12, height = 7) {
  path <- file.path(out_dir, filename)
  ggsave(path, p, width = width, height = height, dpi = 300)
  cat(sprintf("Wrote %s\n", path))
  n_written <<- n_written + 1
}

# ---------------------------------------------------------------------------
# Compute per-model accuracy summaries
# ---------------------------------------------------------------------------
task_labels <- c("tom_12dim_mcq" = "MCQ", "tom_12dim_freeresponse" = "Free Response")

# Per model × task
acc_by_task <- df %>%
  group_by(model, family, tier, date_years, release_date, task) %>%
  summarise(
    accuracy = mean(correct),
    n_items = n(),
    n_correct = sum(correct),
    .groups = "drop"
  ) %>%
  mutate(
    se = sqrt(accuracy * (1 - accuracy) / n_items),
    ci_lo = pmax(0, accuracy - 1.96 * se),
    ci_hi = pmin(1, accuracy + 1.96 * se),
    task_label = recode(task, !!!task_labels),
    short_model = short_model(model)
  )

# Per model (collapsed across tasks)
acc_overall <- df %>%
  group_by(model, family, tier, date_years, release_date) %>%
  summarise(
    accuracy = mean(correct),
    n_items = n(),
    n_correct = sum(correct),
    .groups = "drop"
  ) %>%
  mutate(
    se = sqrt(accuracy * (1 - accuracy) / n_items),
    ci_lo = pmax(0, accuracy - 1.96 * se),
    ci_hi = pmin(1, accuracy + 1.96 * se),
    short_model = short_model(model)
  )

# Factor tiers and families
acc_by_task$tier <- factor_tier(acc_by_task$tier)
acc_by_task$family <- factor_family(acc_by_task$family)
acc_overall$tier <- factor_tier(acc_overall$tier)
acc_overall$family <- factor_family(acc_overall$family)

# Date as actual Date for better x-axis formatting
acc_by_task$date <- as.Date(acc_by_task$release_date)
acc_overall$date <- as.Date(acc_overall$release_date)

# ---------------------------------------------------------------------------
# a. By model type (tier) — all tasks combined
# ---------------------------------------------------------------------------
p_tier_overall <- ggplot(acc_overall, aes(x = date, y = accuracy,
                                           color = tier, shape = tier)) +
  geom_point(size = 3) +
  geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 10, linewidth = 0.4) +
  geom_text(aes(label = short_model), size = 2.2, hjust = -0.1, vjust = -0.6,
            check_overlap = TRUE, show.legend = FALSE) +
  scale_color_manual(values = TYPE_COLORS) +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  scale_x_date(date_labels = "%b %Y") +
  labs(title = "Model accuracy vs release date (by tier)",
       subtitle = "MCQ + FR combined; error bars = 95% Wald CI",
       x = "Release date", y = "Overall accuracy",
       color = "Tier", shape = "Tier") +
  theme_devtom() +
  theme(legend.position = "bottom",
        legend.text = element_text(size = 8))
save_plot(p_tier_overall, "accuracy_by_tier_overall.png")

# ---------------------------------------------------------------------------
# b. By model type (tier) — faceted MCQ vs FR
# ---------------------------------------------------------------------------
p_tier_task <- ggplot(acc_by_task, aes(x = date, y = accuracy,
                                        color = tier, shape = tier)) +
  geom_point(size = 3) +
  geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 10, linewidth = 0.4) +
  geom_text(aes(label = short_model), size = 2.2, hjust = -0.1, vjust = -0.6,
            check_overlap = TRUE, show.legend = FALSE) +
  scale_color_manual(values = TYPE_COLORS) +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  scale_x_date(date_labels = "%b %Y") +
  facet_wrap(~task_label) +
  labs(title = "Model accuracy vs release date (by tier, MCQ vs FR)",
       subtitle = "Error bars = 95% Wald CI",
       x = "Release date", y = "Accuracy",
       color = "Tier", shape = "Tier") +
  theme_devtom() +
  theme(legend.position = "bottom",
        legend.text = element_text(size = 8))
save_plot(p_tier_task, "accuracy_by_tier_mcq_vs_fr.png", width = 16, height = 7)

# ---------------------------------------------------------------------------
# e. By tier, faceted by family — MCQ vs FR as shape/color
# ---------------------------------------------------------------------------
p_family_facet <- ggplot(acc_by_task, aes(x = date, y = accuracy,
                                            color = task_label, shape = task_label)) +
  geom_point(size = 3) +
  geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 10, linewidth = 0.4) +
  geom_line(aes(group = task_label), linewidth = 0.5, alpha = 0.4) +
  geom_text(aes(label = short_model), size = 2, hjust = -0.1, vjust = -0.6,
            check_overlap = TRUE, show.legend = FALSE) +
  scale_color_manual(values = c("MCQ" = "#2171b5", "Free Response" = "#cb181d")) +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  scale_x_date(date_labels = "%b %Y") +
  facet_wrap(~family, scales = "free_x") +
  labs(title = "MCQ vs Free Response accuracy trajectory (per family)",
       subtitle = "Lines connect models within each task type",
       x = "Release date", y = "Accuracy",
       color = "Task", shape = "Task") +
  theme_devtom() +
  theme(legend.position = "bottom")
save_plot(p_family_facet, "accuracy_mcq_fr_per_family.png", width = 14, height = 8)

# ---------------------------------------------------------------------------
# f. Within-tier version trajectory — does accuracy improve across releases?
# ---------------------------------------------------------------------------
# Only show tiers with >= 2 models (singletons can't show a trajectory)
tier_n <- acc_overall %>% count(tier) %>% filter(n >= 2)
if (nrow(tier_n) > 0) {
  traj <- acc_overall %>% filter(tier %in% tier_n$tier)
  traj$tier <- droplevels(traj$tier)

  # Within each tier, compute slope for annotation
  tier_slopes <- traj %>%
    group_by(tier) %>%
    filter(n() >= 2) %>%
    summarise(
      slope = if (n() >= 2) coef(lm(accuracy ~ date_years))[2] else NA_real_,
      n_models = n(),
      date_range = as.numeric(diff(range(date))),
      mid_date = mean(date),
      max_acc = max(accuracy),
      .groups = "drop"
    ) %>%
    mutate(direction = case_when(
      slope > 0.01 ~ "improving",
      slope < -0.01 ~ "declining",
      TRUE ~ "flat"
    ))

  # Main faceted plot
  p_within_tier <- ggplot(traj, aes(x = date, y = accuracy)) +
    geom_point(aes(color = tier), size = 3, show.legend = FALSE) +
    geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi, color = tier),
                  width = 10, linewidth = 0.4, show.legend = FALSE) +
    geom_line(aes(color = tier), linewidth = 0.6, alpha = 0.5, show.legend = FALSE) +
    geom_smooth(method = "lm", se = TRUE, linewidth = 0.8,
                color = "grey30", fill = "grey80", alpha = 0.3) +
    geom_text(aes(label = short_model), size = 2.2,
              hjust = -0.1, vjust = -0.8, check_overlap = TRUE) +
    scale_color_manual(values = TYPE_COLORS) +
    scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
    scale_x_date(date_labels = "%b\n%Y") +
    facet_wrap(~tier, scales = "free_x") +
    labs(title = "Within-tier version trajectory: does ToM accuracy improve?",
         subtitle = "Each panel = one model tier; grey band = linear trend ± SE",
         x = "Release date", y = "Overall accuracy") +
    theme_devtom() +
    theme(strip.text = element_text(size = 9))
  save_plot(p_within_tier, "accuracy_within_tier_trajectory.png",
            width = 16, height = 10)

  # Same but split MCQ vs FR
  traj_task <- acc_by_task %>% filter(tier %in% tier_n$tier)
  traj_task$tier <- droplevels(traj_task$tier)

  p_within_tier_task <- ggplot(traj_task, aes(x = date, y = accuracy,
                                               color = task_label,
                                               shape = task_label)) +
    geom_point(size = 2.5) +
    geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi),
                  width = 10, linewidth = 0.3) +
    geom_line(aes(group = task_label), linewidth = 0.5, alpha = 0.4) +
    geom_text(aes(label = short_model), size = 1.8,
              hjust = -0.1, vjust = -0.8, check_overlap = TRUE,
              show.legend = FALSE) +
    scale_color_manual(values = c("MCQ" = "#2171b5", "Free Response" = "#cb181d")) +
    scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
    scale_x_date(date_labels = "%b\n%Y") +
    facet_wrap(~tier, scales = "free_x") +
    labs(title = "Within-tier version trajectory: MCQ vs Free Response",
         subtitle = "Each panel = one model tier; lines connect successive releases",
         x = "Release date", y = "Accuracy",
         color = "Task", shape = "Task") +
    theme_devtom() +
    theme(legend.position = "bottom",
          strip.text = element_text(size = 9))
  save_plot(p_within_tier_task, "accuracy_within_tier_mcq_vs_fr.png",
            width = 16, height = 10)

  # Summary table: slope per tier
  cat("\nWithin-tier trajectory slopes (accuracy per year):\n")
  for (i in seq_len(nrow(tier_slopes))) {
    r <- tier_slopes[i, ]
    cat(sprintf("  %-20s  slope=%+.3f/yr  n=%d  (%s)\n",
                as.character(r$tier), r$slope, r$n_models, r$direction))
  }
} else {
  cat("No tiers with >= 2 models; skipping within-tier trajectory plot.\n")
}

cat(sprintf("\nWrote %d figures to %s/\n", n_written, out_dir))
