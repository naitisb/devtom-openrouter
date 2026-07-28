#!/usr/bin/env Rscript
# visualize_size_scaling.R — Size and release date scaling visualizations
#
# Reads size_scaling/ CSVs (from scripts/5_model/size_scaling_glmm.R) and
# item_level.csv, renders PNGs (300 dpi) to results/figures/size_scaling/<timestamp>/:
#   a. Size × accuracy (per family, collapsed by date)
#   b. Release date × accuracy (per family, collapsed by size)
#   c1. Predicted accuracy contour over (size, date) per family
#   c2. Accuracy trajectory by size bin per family
#
# Usage:
#   Rscript scripts/6_visualize/visualize_size_scaling.R
#   Rscript scripts/6_visualize/visualize_size_scaling.R \
#     --scaling-dir results/modeling/size_scaling/<ts>

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(readr)
  library(ggrepel)
  library(scales)
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
scaling_dir <- NULL
results_dir <- "results"

i <- 1
while (i <= length(args)) {
  if (args[i] == "--scaling-dir" && i < length(args)) {
    scaling_dir <- args[i + 1]; i <- i + 2
  } else if (args[i] == "--results-dir" && i < length(args)) {
    results_dir <- args[i + 1]; i <- i + 2
  } else {
    i <- i + 1
  }
}

if (is.null(scaling_dir)) {
  search_dir <- file.path(results_dir, "modeling", "size_scaling")
  if (dir.exists(search_dir)) {
    stamps <- sort(list.dirs(search_dir, recursive = FALSE, full.names = TRUE))
    if (length(stamps) > 0) scaling_dir <- stamps[length(stamps)]
  }
}

if (is.null(scaling_dir) || !dir.exists(scaling_dir)) {
  stop("No modeling/size_scaling directory found. Run: Rscript scripts/5_model/size_scaling_glmm.R")
}

cat("Reading from:", scaling_dir, "\n")

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path(results_dir, "figures", "size_scaling", stamp)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

n_written <- 0L
save_plot <- function(p, filename, width = 12, height = 7) {
  path <- file.path(out_dir, filename)
  ggsave(path, p, width = width, height = height, dpi = 300)
  cat("  Wrote:", path, "\n")
  n_written <<- n_written + 1L
}

# ---------------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------------
ALL_FAMILIES <- c("Claude", "GPT", "Llama", "Qwen", "Mistral")

obs_file <- file.path(scaling_dir, "size_scaling_observed.csv")
if (!file.exists(obs_file)) stop("Missing: ", obs_file)
obs <- read_csv(obs_file, show_col_types = FALSE) %>%
  mutate(
    family = factor(family, levels = ALL_FAMILIES),
    tier = factor_tier(tier),
    short_name = short_model(model)
  )

cat(sprintf("  %d observed models across %s\n", nrow(obs),
            paste(levels(obs$family), collapse = ", ")))

# ---------------------------------------------------------------------------
# (a) Size × Accuracy — per family, collapsed by date
# ---------------------------------------------------------------------------
cat("\n--- Plot (a): Size × Accuracy ---\n")

pred_size_file <- file.path(scaling_dir, "size_scaling_pred_by_size.csv")
has_pred_size <- file.exists(pred_size_file)

if (has_pred_size) {
  pred_size <- read_csv(pred_size_file, show_col_types = FALSE) %>%
    mutate(family = factor(family, levels = ALL_FAMILIES))
}

param_breaks <- c(8, 20, 70, 200, 400, 1760)
param_labels <- paste0(param_breaks, "B")

p_size <- ggplot(obs, aes(x = log_params, y = accuracy)) +
  geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey50", linewidth = 0.4)

if (has_pred_size) {
  p_size <- p_size +
    geom_ribbon(data = pred_size,
                aes(x = log_params, y = pred, ymin = pred_lo, ymax = pred_hi),
                alpha = 0.15, fill = "grey40", inherit.aes = FALSE) +
    geom_line(data = pred_size,
              aes(x = log_params, y = pred),
              color = "grey30", linewidth = 0.8, inherit.aes = FALSE)
}

tier_colors <- TYPE_COLORS[names(TYPE_COLORS) %in% levels(obs$tier)]

p_size <- p_size +
  geom_point(aes(color = tier), size = 3) +
  geom_text_repel(aes(label = short_name), size = 2.5, max.overlaps = 15,
                  segment.color = "grey70", segment.size = 0.3) +
  facet_wrap(~ family) +
  scale_x_continuous(
    breaks = log10(param_breaks),
    labels = param_labels,
    name = "Model size (parameters)"
  ) +
  scale_y_continuous(labels = percent_format(), name = "ToM accuracy") +
  scale_color_manual(values = tier_colors, name = "Tier") +
  coord_cartesian(ylim = c(0, 1.05)) +
  labs(
    title = "ToM accuracy vs model size (all families)",
    subtitle = "Controlling for release date; line = GLMM population prediction ± 95% CI"
  ) +
  theme_devtom() +
  theme(legend.position = "bottom")

save_plot(p_size, "size_vs_accuracy.png", width = 14, height = 7)

# ---------------------------------------------------------------------------
# (b) Release Date × Accuracy — per family, collapsed by size
# ---------------------------------------------------------------------------
cat("\n--- Plot (b): Date × Accuracy ---\n")

pred_date_file <- file.path(scaling_dir, "size_scaling_pred_by_date.csv")
has_pred_date <- file.exists(pred_date_file)

if (has_pred_date) {
  pred_date <- read_csv(pred_date_file, show_col_types = FALSE) %>%
    mutate(family = factor(family, levels = ALL_FAMILIES))
}

obs <- obs %>%
  mutate(release_dt = as.Date(release_date))

p_date <- ggplot(obs, aes(x = release_dt, y = accuracy)) +
  geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey50", linewidth = 0.4)

if (has_pred_date) {
  pred_date <- pred_date %>%
    mutate(release_dt = as.Date("2024-01-01") + date_years * 365.25)

  p_date <- p_date +
    geom_ribbon(data = pred_date,
                aes(x = release_dt, y = pred, ymin = pred_lo, ymax = pred_hi),
                alpha = 0.15, fill = "grey40", inherit.aes = FALSE) +
    geom_line(data = pred_date,
              aes(x = release_dt, y = pred),
              color = "grey30", linewidth = 0.8, inherit.aes = FALSE)
}

p_date <- p_date +
  geom_point(aes(color = tier), size = 3) +
  geom_text_repel(aes(label = short_name), size = 2.5, max.overlaps = 15,
                  segment.color = "grey70", segment.size = 0.3) +
  facet_wrap(~ family) +
  scale_x_date(date_labels = "%b %Y", name = "Release date") +
  scale_y_continuous(labels = percent_format(), name = "ToM accuracy") +
  scale_color_manual(values = tier_colors, name = "Tier") +
  coord_cartesian(ylim = c(0, 1.05)) +
  labs(
    title = "ToM accuracy vs release date (all families)",
    subtitle = "Controlling for model size; line = GLMM population prediction ± 95% CI"
  ) +
  theme_devtom() +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 30, hjust = 1))

save_plot(p_date, "date_vs_accuracy.png", width = 14, height = 7)

# ---------------------------------------------------------------------------
# (c1) Interaction contour — predicted accuracy over (size, date) per family
# ---------------------------------------------------------------------------
cat("\n--- Plot (c1): Size × Date interaction contour ---\n")

pred_int_file <- file.path(scaling_dir, "size_scaling_pred_interaction.csv")

if (file.exists(pred_int_file)) {
  pred_int <- read_csv(pred_int_file, show_col_types = FALSE) %>%
    mutate(
      family = factor(family, levels = ALL_FAMILIES),
      release_dt = as.Date("2024-01-01") + date_years * 365.25
    )

  p_contour <- ggplot(pred_int, aes(x = release_dt, y = log_params)) +
    geom_tile(aes(fill = pred)) +
    geom_contour(aes(z = pred), color = "white", alpha = 0.5, linewidth = 0.3) +
    geom_point(data = obs, aes(x = release_dt, y = log_params),
               color = "white", size = 2, shape = 16, inherit.aes = FALSE) +
    geom_text_repel(data = obs, aes(x = release_dt, y = log_params, label = short_name),
                    color = "white", size = 2, max.overlaps = 10,
                    segment.color = "white", segment.size = 0.2, inherit.aes = FALSE) +
    facet_wrap(~ family) +
    scale_fill_viridis_c(option = "magma", labels = percent_format(), name = "Predicted accuracy") +
    scale_x_date(date_labels = "%b %Y", name = "Release date") +
    scale_y_continuous(
      breaks = log10(param_breaks),
      labels = param_labels,
      name = "Model size (parameters)"
    ) +
    labs(
      title = "Predicted ToM accuracy: model size × release date",
      subtitle = "GLMM S1 population prediction; includes estimated params for Claude/GPT"
    ) +
    theme_devtom() +
    theme(legend.position = "right",
          axis.text.x = element_text(angle = 30, hjust = 1))

  save_plot(p_contour, "size_date_interaction_contour.png", width = 14, height = 8)
} else {
  cat("  Skipped: no interaction prediction grid found\n")
}

# ---------------------------------------------------------------------------
# (c2) Size-binned trajectory — accuracy vs date by size category
# ---------------------------------------------------------------------------
cat("\n--- Plot (c2): Size-binned trajectory ---\n")

obs <- obs %>%
  mutate(
    size_bin = case_when(
      params_b < 10  ~ "Small (<10B)",
      params_b < 50  ~ "Mid (10–50B)",
      TRUE           ~ "Large (>50B)"
    ),
    size_bin = factor(size_bin, levels = c("Small (<10B)", "Mid (10–50B)", "Large (>50B)"))
  )

size_bin_colors <- c(
  "Small (<10B)"  = "#9ecae1",
  "Mid (10–50B)"  = "#4292c6",
  "Large (>50B)"  = "#08306b"
)

p_binned <- ggplot(obs, aes(x = release_dt, y = accuracy, color = size_bin)) +
  geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey50", linewidth = 0.4) +
  geom_point(size = 3) +
  geom_smooth(method = "lm", se = TRUE, alpha = 0.15, linewidth = 0.8) +
  geom_text_repel(aes(label = short_name), size = 2.2, max.overlaps = 12,
                  segment.color = "grey70", segment.size = 0.3, show.legend = FALSE) +
  facet_wrap(~ family) +
  scale_x_date(date_labels = "%b %Y", name = "Release date") +
  scale_y_continuous(labels = percent_format(), name = "ToM accuracy") +
  scale_color_manual(values = size_bin_colors, name = "Size category") +
  coord_cartesian(ylim = c(0, 1.05)) +
  labs(
    title = "ToM accuracy trajectory by model size category",
    subtitle = "All families; lines = linear trend per size bin"
  ) +
  theme_devtom() +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 30, hjust = 1))

save_plot(p_binned, "size_binned_trajectory.png", width = 14, height = 7)

# ---------------------------------------------------------------------------
# (d) OR forest plot for S1 fixed effects
# ---------------------------------------------------------------------------
cat("\n--- Plot (d): S1 odds-ratio forest plot ---\n")

or_file <- file.path(scaling_dir, "size_scaling_or_table.csv")
if (file.exists(or_file)) {
  or_table <- read_csv(or_file, show_col_types = FALSE)
  or_s1 <- or_table %>%
    filter(model_label == "S1_size_x_date") %>%
    mutate(term = factor(term, levels = rev(term)))

  if (nrow(or_s1) > 0) {
    p_forest <- ggplot(or_s1, aes(x = estimate, y = term)) +
      geom_vline(xintercept = 1, linetype = "dashed", color = "grey50") +
      geom_errorbarh(aes(xmin = conf.low, xmax = conf.high),
                     height = 0.25, color = "grey40") +
      geom_point(size = 3, color = "#08519c") +
      scale_x_log10(name = "Odds ratio (95% CI)") +
      labs(
        y = NULL,
        title = "Size-scaling GLMM (S1) fixed effects",
        subtitle = "correct ~ log10(params) × release_date + family + (1|item) + (1|model)"
      ) +
      theme_devtom() +
      theme(panel.grid.major.y = element_blank())

    save_plot(p_forest, "size_scaling_forest_plot.png", width = 10, height = 5)
  }
}

# ---------------------------------------------------------------------------
# (e) Age-binned accuracy vs model size
# ---------------------------------------------------------------------------
cat("\n--- Plot (e): Age-binned accuracy vs model size ---\n")

item_csv <- file.path(results_dir, "item_level.csv")
if (file.exists(item_csv)) {
  items <- read_csv(item_csv, show_col_types = FALSE) %>%
    filter(family %in% ALL_FAMILIES, !is.na(log_params), !is.na(age_mid)) %>%
    mutate(
      family = factor(family, levels = ALL_FAMILIES),
      age_bin = cut(age_mid,
                    breaks = c(0, 4, 6, 8, 12),
                    labels = c("2–4 yr", "4–6 yr", "6–8 yr", "8–12 yr"),
                    include.lowest = TRUE)
    )

  age_by_size <- items %>%
    group_by(model, family, log_params, params_b, age_bin) %>%
    summarise(accuracy = mean(correct), n = n(), .groups = "drop") %>%
    mutate(short_name = short_model(model))

  age_bin_colors <- c(
    "2–4 yr"  = "#fee5d9",
    "4–6 yr"  = "#fcae91",
    "6–8 yr"  = "#fb6a4a",
    "8–12 yr" = "#cb181d"
  )

  p_age_size <- ggplot(age_by_size, aes(x = log_params, y = accuracy, color = age_bin)) +
    geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey50", linewidth = 0.4) +
    geom_point(size = 2.5, alpha = 0.8) +
    geom_smooth(method = "lm", se = FALSE, linewidth = 0.7) +
    facet_wrap(~ family) +
    scale_x_continuous(
      breaks = log10(param_breaks),
      labels = param_labels,
      name = "Model size (parameters)"
    ) +
    scale_y_continuous(labels = percent_format(), name = "ToM accuracy") +
    scale_color_manual(values = age_bin_colors, name = "Developmental age band") +
    coord_cartesian(ylim = c(0, 1.05)) +
    labs(
      title = "ToM accuracy by developmental age band vs model size",
      subtitle = "All families; lines = linear trend per age band"
    ) +
    theme_devtom() +
    theme(legend.position = "bottom")

  save_plot(p_age_size, "age_binned_vs_size.png", width = 14, height = 7)

  # ---------------------------------------------------------------------------
  # (f) Age-binned accuracy vs release date
  # ---------------------------------------------------------------------------
  cat("\n--- Plot (f): Age-binned accuracy vs release date ---\n")

  age_by_date <- items %>%
    group_by(model, family, date_years, release_date, age_bin) %>%
    summarise(accuracy = mean(correct), n = n(), .groups = "drop") %>%
    mutate(
      short_name = short_model(model),
      release_dt = as.Date(release_date)
    )

  p_age_date <- ggplot(age_by_date, aes(x = release_dt, y = accuracy, color = age_bin)) +
    geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey50", linewidth = 0.4) +
    geom_point(size = 2.5, alpha = 0.8) +
    geom_smooth(method = "lm", se = FALSE, linewidth = 0.7) +
    facet_wrap(~ family) +
    scale_x_date(date_labels = "%b %Y", name = "Release date") +
    scale_y_continuous(labels = percent_format(), name = "ToM accuracy") +
    scale_color_manual(values = age_bin_colors, name = "Developmental age band") +
    coord_cartesian(ylim = c(0, 1.05)) +
    labs(
      title = "ToM accuracy by developmental age band vs release date",
      subtitle = "All families; lines = linear trend per age band"
    ) +
    theme_devtom() +
    theme(legend.position = "bottom",
          axis.text.x = element_text(angle = 30, hjust = 1))

  save_plot(p_age_date, "age_binned_vs_date.png", width = 14, height = 7)

  # ---------------------------------------------------------------------------
  # (g) Age-binned heatmap — accuracy by age band × size bin, per family
  # ---------------------------------------------------------------------------
  cat("\n--- Plot (g): Age × size bin heatmap ---\n")

  items_binned <- items %>%
    mutate(
      size_bin = case_when(
        10^log_params < 10  ~ "Small\n(<10B)",
        10^log_params < 50  ~ "Mid\n(10–50B)",
        TRUE                ~ "Large\n(>50B)"
      ),
      size_bin = factor(size_bin, levels = c("Small\n(<10B)", "Mid\n(10–50B)", "Large\n(>50B)"))
    )

  heat_data <- items_binned %>%
    group_by(family, size_bin, age_bin) %>%
    summarise(accuracy = mean(correct), n_items = n(), .groups = "drop")

  p_heat <- ggplot(heat_data, aes(x = size_bin, y = age_bin, fill = accuracy)) +
    geom_tile(color = "white", linewidth = 0.5) +
    geom_text(aes(label = sprintf("%.0f%%\n(n=%d)", accuracy * 100, n_items)),
              size = 3, color = "white", fontface = "bold") +
    facet_wrap(~ family) +
    scale_fill_viridis_c(option = "magma", limits = c(0, 1),
                         labels = percent_format(), name = "Accuracy") +
    labs(
      x = "Model size category",
      y = "Developmental age band",
      title = "ToM accuracy: developmental age band × model size",
      subtitle = "All families; cell = mean accuracy (item count)"
    ) +
    theme_devtom() +
    theme(panel.grid = element_blank())

  save_plot(p_heat, "age_size_heatmap.png", width = 12, height = 6)

  # ---------------------------------------------------------------------------
  # (h) Combined all-models: age-binned accuracy vs model size (single scale)
  # ---------------------------------------------------------------------------
  cat("\n--- Plot (h): Combined all-models age-binned vs size ---\n")

  family_colors <- FAMILY_COLORS[names(FAMILY_COLORS) %in% ALL_FAMILIES]

  age_by_size_combined <- items %>%
    group_by(model, family, log_params, params_b, age_bin) %>%
    summarise(accuracy = mean(correct), n = n(), .groups = "drop") %>%
    mutate(short_name = short_model(model))

  global_x_range <- range(age_by_size_combined$log_params, na.rm = TRUE)

  p_combined <- ggplot(age_by_size_combined,
                        aes(x = log_params, y = accuracy, color = family)) +
    geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey50", linewidth = 0.4) +
    geom_point(size = 3, alpha = 0.8) +
    geom_smooth(method = "lm", se = TRUE, alpha = 0.10, linewidth = 0.8) +
    facet_wrap(~ age_bin, nrow = 1) +
    scale_x_continuous(
      breaks = log10(param_breaks),
      labels = param_labels,
      limits = global_x_range,
      name = "Model size (parameters)"
    ) +
    scale_y_continuous(labels = percent_format(), limits = c(0, 1.05), name = "ToM accuracy") +
    scale_color_manual(values = family_colors, name = "Family") +
    labs(
      title = "ToM accuracy by developmental age band vs model size (all models)",
      subtitle = "All families on a single x-scale; lines = linear trend ± 95% CI per family"
    ) +
    theme_devtom() +
    theme(legend.position = "bottom")

  save_plot(p_combined, "age_binned_vs_size_combined.png", width = 18, height = 7)

  # ---------------------------------------------------------------------------
  # (i) Combined all-models: accuracy vs model size colored by family
  # ---------------------------------------------------------------------------
  cat("\n--- Plot (i): Combined all-models accuracy vs size by family ---\n")

  model_by_size <- items %>%
    group_by(model, family, log_params, params_b) %>%
    summarise(accuracy = mean(correct), n = n(), .groups = "drop") %>%
    mutate(short_name = short_model(model))

  p_all_size <- ggplot(model_by_size,
                        aes(x = log_params, y = accuracy, color = family)) +
    geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey50", linewidth = 0.4) +
    geom_point(size = 3, alpha = 0.8) +
    geom_smooth(method = "lm", se = TRUE, alpha = 0.12, linewidth = 0.8) +
    geom_text_repel(aes(label = short_name), size = 2.3, max.overlaps = 20,
                    segment.color = "grey70", segment.size = 0.3, show.legend = FALSE) +
    scale_x_continuous(
      breaks = log10(param_breaks),
      labels = param_labels,
      limits = global_x_range,
      name = "Model size (parameters)"
    ) +
    scale_y_continuous(labels = percent_format(), limits = c(0, 1.05), name = "ToM accuracy") +
    scale_color_manual(values = family_colors, name = "Family") +
    labs(
      title = "ToM accuracy vs model size (all models, single scale)",
      subtitle = "All 5 families; lines = linear trend ± 95% CI per family"
    ) +
    theme_devtom() +
    theme(legend.position = "bottom")

  save_plot(p_all_size, "all_models_size_vs_accuracy.png", width = 14, height = 8)

} else {
  cat("  Skipped: item_level.csv not found\n")
}

cat(sprintf("\nWrote %d figures to %s/\n", n_written, out_dir))
