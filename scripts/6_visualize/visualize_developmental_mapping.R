#!/usr/bin/env Rscript
# visualize_developmental_mapping.R — Developmental mapping visualizations
#
# Reads modeling_mapping/ CSVs (from scripts/5_model/developmental_scaling_irt.R),
# renders PNGs to results/figures/mapping/<timestamp>/:
#   a. Profile-vector heatmap (models x dimensions)
#   b. Frontier trajectory (frontier age band vs release date per tier)
#   c. Theta trajectory (latent theta vs release date per tier)
#   d. Wright / item-person map
#   e. Difficulty vs age-band scatter with Spearman rho
#
# Usage:
#   Rscript scripts/6_visualize/visualize_developmental_mapping.R
#   Rscript scripts/6_visualize/visualize_developmental_mapping.R \
#     --mapping-dir results/<ts>/modeling_mapping

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
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
mapping_dir <- NULL
results_dir <- "results"

i <- 1
while (i <= length(args)) {
  if (args[i] == "--mapping-dir" && i < length(args)) {
    mapping_dir <- args[i + 1]; i <- i + 2
  } else if (args[i] == "--results-dir" && i < length(args)) {
    results_dir <- args[i + 1]; i <- i + 2
  } else {
    i <- i + 1
  }
}

if (is.null(mapping_dir)) {
  search_dir <- file.path(results_dir, "modeling", "mapping")
  if (dir.exists(search_dir)) {
    stamps <- sort(list.dirs(search_dir, recursive = FALSE, full.names = TRUE))
    if (length(stamps) > 0) mapping_dir <- stamps[length(stamps)]
  }
}

if (is.null(mapping_dir) || !dir.exists(mapping_dir)) {
  stop("No modeling/mapping directory found. Run: Rscript scripts/5_model/developmental_scaling_irt.R")
}

cat("Reading from:", mapping_dir, "\n")

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path(results_dir, "figures", "mapping", stamp)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

n_written <- 0
save_plot <- function(p, filename, width = 10, height = 7) {
  path <- file.path(out_dir, filename)
  ggsave(path, p, width = width, height = height, dpi = 300)
  cat(sprintf("Wrote %s\n", path))
  n_written <<- n_written + 1
}

# ---------------------------------------------------------------------------
# a. Profile-vector heatmap
# ---------------------------------------------------------------------------
profile_file <- file.path(mapping_dir, "profile_vectors.csv")
if (file.exists(profile_file)) {
  prof <- read_csv(profile_file, show_col_types = FALSE)
  prof$tom_dimension <- factor_dimension(prof$tom_dimension)
  prof$short_model <- short_model(prof$model)
  prof$family <- factor_family(prof$family)

  # Order models: oldest to newest within family
  model_order <- prof %>%
    distinct(short_model, family, date_years) %>%
    arrange(family, date_years) %>%
    pull(short_model)
  prof$short_model <- factor(prof$short_model, levels = model_order)

  # Separate heatmaps per task
  for (tsk in unique(prof$task)) {
    tsk_data <- prof %>% filter(task == tsk)
    tsk_label <- sub("tom_12dim_", "", tsk)

    p <- ggplot(tsk_data, aes(x = tom_dimension, y = short_model,
                               fill = accuracy)) +
      geom_tile(color = "white", linewidth = 0.3) +
      geom_text(aes(label = sprintf("%.2f", accuracy)), size = 2.2) +
      geom_point(data = tsk_data %>% filter(pass == 1),
                 aes(x = tom_dimension, y = short_model),
                 shape = 4, size = 1.5, color = "black", stroke = 0.5) +
      scale_fill_gradient2(low = "#d73027", mid = "#fee08b", high = "#1a9850",
                            midpoint = 0.7, limits = c(0, 1)) +
      facet_grid(family ~ ., scales = "free_y", space = "free_y") +
      labs(title = paste0("Profile-vector heatmap (", tsk_label, ")"),
           subtitle = "X = passes Wilson LB > chance; dimensions in developmental order",
           x = NULL, y = NULL, fill = "Accuracy") +
      theme_devtom() +
      theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
            strip.text.y = element_text(angle = 0))
    save_plot(p, paste0("profile_heatmap_", tsk_label, ".png"),
              width = 14, height = max(6, length(model_order) * 0.4))
  }
}

# ---------------------------------------------------------------------------
# b. Frontier trajectory
# ---------------------------------------------------------------------------
frontier_file <- file.path(mapping_dir, "frontier_trajectory.csv")
if (file.exists(frontier_file)) {
  frontier <- read_csv(frontier_file, show_col_types = FALSE) %>%
    filter(!is.na(frontier_age_mid))
  frontier$tier <- factor_tier(frontier$tier)
  frontier$family <- factor_family(frontier$family)
  frontier$short_model <- short_model(frontier$model)

  p <- ggplot(frontier, aes(x = date_years, y = frontier_age_mid,
                              color = tier)) +
    geom_step(linewidth = 0.8, alpha = 0.6) +
    geom_point(size = 2.5) +
    geom_text(aes(label = short_model), size = 2, hjust = -0.1,
              vjust = -0.5, check_overlap = TRUE) +
    scale_color_manual(values = TYPE_COLORS) +
    facet_wrap(~task) +
    labs(title = "Developmental frontier trajectory",
         subtitle = "Highest age band with >= 2/3 dimensions passed, per model",
         x = "Release date (years since 2024-01-01)",
         y = "Frontier age (midpoint of band)",
         color = "Tier") +
    theme_devtom() +
    theme(legend.position = "bottom")
  save_plot(p, "frontier_trajectory.png", width = 14, height = 7)
}

# ---------------------------------------------------------------------------
# c. Theta trajectory
# ---------------------------------------------------------------------------
theta_file <- file.path(mapping_dir, "irt_theta.csv")
if (file.exists(theta_file)) {
  theta <- read_csv(theta_file, show_col_types = FALSE) %>%
    filter(!is.na(date_years))
  theta$tier <- factor_tier(theta$tier)
  theta$family <- factor_family(theta$family)
  theta$short_model <- short_model(theta$model)

  # Primary theta plot
  p1 <- ggplot(theta, aes(x = date_years, y = theta, color = tier)) +
    geom_point(size = 2.5) +
    geom_errorbar(aes(ymin = theta - 1.96 * theta_se,
                      ymax = theta + 1.96 * theta_se), width = 0.05) +
    geom_text(aes(label = short_model), size = 2, hjust = -0.1,
              vjust = -0.5, check_overlap = TRUE) +
    scale_color_manual(values = TYPE_COLORS) +
    facet_wrap(~task) +
    labs(title = "IRT latent ability (theta) trajectory",
         subtitle = "Higher theta = greater ToM ability; error bars = 95% CI",
         x = "Release date (years since 2024-01-01)",
         y = "Theta (EAP)", color = "Tier") +
    theme_devtom() +
    theme(legend.position = "bottom")
  save_plot(p1, "theta_trajectory.png", width = 14, height = 7)

  # Age-anchored theta (if available)
  if ("age_anchored_theta" %in% names(theta) &&
      any(!is.na(theta$age_anchored_theta))) {
    theta_anchored <- theta %>%
      filter(!is.na(age_anchored_theta), !is.na(date_years)) %>%
      group_by(tier, task) %>%
      filter(n() >= 3, n_distinct(date_years) >= 2) %>%
      ungroup()

    p2 <- ggplot(theta %>% filter(!is.na(age_anchored_theta)),
                 aes(x = date_years, y = age_anchored_theta, color = tier)) +
      geom_smooth(data = theta_anchored,
                  aes(fill = tier), method = "lm",
                  se = TRUE, linewidth = 0.9, linetype = "dashed",
                  alpha = 0.08) +
      geom_point(size = 2.5) +
      geom_text(aes(label = short_model), size = 2, hjust = -0.1,
                vjust = -0.5, check_overlap = TRUE) +
      scale_color_manual(values = TYPE_COLORS) +
      scale_fill_manual(values = TYPE_COLORS, guide = "none") +
      facet_wrap(~task) +
      labs(title = "Age-equivalent trajectory by model tier",
           subtitle = "OLS regression ± 95% CI per tier (tiers with ≥ 3 models); equivalent child age via item-difficulty mapping",
           x = "Release date (years since 2024-01-01)",
           y = "Age-equivalent (years)", color = "Tier") +
      theme_devtom() +
      theme(legend.position = "bottom")
    save_plot(p2, "theta_age_anchored_trajectory.png", width = 14, height = 7)
  }
}

# ---------------------------------------------------------------------------
# d. Wright / item-person map
# ---------------------------------------------------------------------------
wright_file <- file.path(mapping_dir, "wright_map.csv")
if (file.exists(wright_file)) {
  wright <- read_csv(wright_file, show_col_types = FALSE)

  for (tsk in unique(wright$task)) {
    tsk_data <- wright %>% filter(task == tsk)
    tsk_label <- sub("tom_12dim_", "", tsk)

    items <- tsk_data %>% filter(type == "item")
    persons <- tsk_data %>% filter(type == "person")

    # Join dimension info for items
    item_params_file <- file.path(mapping_dir, "irt_item_params.csv")
    if (file.exists(item_params_file)) {
      item_info <- read_csv(item_params_file, show_col_types = FALSE) %>%
        filter(task == tsk) %>%
        select(item_id, tom_dimension)
      items <- items %>%
        left_join(item_info, by = c("label" = "item_id"))
      items$tom_dimension <- factor_dimension(items$tom_dimension)
    }

    p <- ggplot() +
      # Items on the left
      geom_point(data = items, aes(x = -0.3, y = value, color = tom_dimension),
                 size = 2, alpha = 0.7) +
      geom_text(data = items, aes(x = -0.5, y = value, label = label),
                size = 1.8, hjust = 1, check_overlap = TRUE) +
      # Persons on the right
      geom_point(data = persons, aes(x = 0.3, y = value),
                 size = 2, shape = 17, color = "grey30") +
      geom_text(data = persons, aes(x = 0.5, y = value,
                                      label = short_model(label)),
                size = 1.8, hjust = 0, check_overlap = TRUE) +
      geom_hline(yintercept = 0, linetype = "dotted", color = "grey60") +
      annotate("text", x = -0.3, y = max(c(items$value, persons$value)) + 0.3,
               label = "Items", fontface = "bold", size = 3.5) +
      annotate("text", x = 0.3, y = max(c(items$value, persons$value)) + 0.3,
               label = "Models", fontface = "bold", size = 3.5) +
      xlim(-1.5, 1.5) +
      labs(title = paste0("Wright map (", tsk_label, ")"),
           subtitle = "Item difficulty (left) vs. model ability (right) on the logit scale",
           y = "Logits (difficulty / ability)", x = NULL,
           color = "Dimension") +
      theme_devtom() +
      theme(axis.text.x = element_blank(),
            axis.ticks.x = element_blank(),
            panel.grid.major.x = element_blank(),
            legend.position = "bottom",
            legend.text = element_text(size = 7))
    save_plot(p, paste0("wright_map_", tsk_label, ".png"), width = 10, height = 10)
  }
}

# ---------------------------------------------------------------------------
# e. Difficulty vs age-band scatter
# ---------------------------------------------------------------------------
diff_age_file <- file.path(mapping_dir, "irt_difficulty_vs_age.csv")
item_params_file <- file.path(mapping_dir, "irt_item_params.csv")

if (file.exists(item_params_file)) {
  item_params <- read_csv(item_params_file, show_col_types = FALSE) %>%
    filter(!is.na(b), !is.na(age_mid))

  if (nrow(item_params) > 0) {
    item_params$tom_dimension <- factor_dimension(item_params$tom_dimension)

    # Read Spearman results for annotation
    rho_label <- ""
    if (file.exists(diff_age_file)) {
      diff_age <- read_csv(diff_age_file, show_col_types = FALSE)
      rho_label <- paste0("rho = ", round(diff_age$spearman_rho[1], 3),
                          ", p = ", format.pval(diff_age$spearman_p[1], digits = 3))
    }

    p <- ggplot(item_params, aes(x = age_mid, y = b, color = tom_dimension)) +
      geom_point(size = 2.5, alpha = 0.7) +
      geom_smooth(method = "lm", se = TRUE, color = "grey30",
                  linetype = "dashed", linewidth = 0.7) +
      facet_wrap(~task) +
      annotate("text", x = Inf, y = Inf, label = rho_label,
               hjust = 1.1, vjust = 1.5, size = 3.5, fontface = "italic") +
      labs(title = "Item difficulty (IRT b) vs. target developmental age",
           subtitle = "H1: items targeting older children should be harder (positive slope)",
           x = "Target age (midpoint of validated age band)",
           y = "IRT difficulty (b parameter)",
           color = "Dimension") +
      theme_devtom() +
      theme(legend.position = "bottom",
            legend.text = element_text(size = 7))
    save_plot(p, "difficulty_vs_age.png", width = 12, height = 7)
  }
}

cat(sprintf("\nWrote %d figures to %s/\n", n_written, out_dir))
