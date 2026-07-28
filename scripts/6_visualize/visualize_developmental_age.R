#!/usr/bin/env Rscript
# visualize_developmental_age.R — Figures for developmental age mapping analysis

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(purrr)
})

source("scripts/6_visualize/_theme.R")

# Find latest modeling output
base_dir <- "results/modeling/developmental_age_mapping"
ts_dirs <- list.dirs(base_dir, recursive = FALSE, full.names = TRUE)
if (length(ts_dirs) == 0) stop("No modeling output found in ", base_dir)
model_dir <- sort(ts_dirs, decreasing = TRUE)[1]
cat("Reading from:", model_dir, "\n")

ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
fig_dir <- file.path("results", "figures", "developmental_age", ts)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
cat("Output dir:", fig_dir, "\n\n")

# Load data
mastery_dim <- read_csv(file.path(model_dir, "mastery_age_dimension.csv"),
                        show_col_types = FALSE)
mastery_con <- read_csv(file.path(model_dir, "mastery_age_construct.csv"),
                        show_col_types = FALSE)
comparison <- read_csv(file.path(model_dir, "method_comparison.csv"),
                       show_col_types = FALSE)

item_csv <- "results/item_level.csv"
df <- read_csv(item_csv, show_col_types = FALSE) %>%
  filter(family %in% FAMILY_ORDER)

models_meta <- df %>%
  distinct(model, family, tier, release_date) %>%
  mutate(release_date = as.Date(release_date),
         short_name = short_model(model))

# GLM per-model ages (if available)
glm_file <- file.path(model_dir, "glm_per_model_age.csv")
has_glm <- file.exists(glm_file)
if (has_glm) {
  glm_ages <- read_csv(glm_file, show_col_types = FALSE)
}

# GLMM ages (if available)
glmm_file <- file.path(model_dir, "glmm_age_equivalents.csv")
has_glmm <- file.exists(glmm_file)
if (has_glmm) {
  glmm_ages <- read_csv(glmm_file, show_col_types = FALSE)
}

# IRT ages (if available)
irt_file <- file.path(model_dir, "irt_age_equivalents.csv")
has_irt <- file.exists(irt_file) && file.info(irt_file)$size > 50

# =========================================================================
# Fig A: Mastery age heatmap (models × 12 dimensions)
# =========================================================================
cat("Fig A: Mastery age heatmap...\n")

heatmap_data <- mastery_dim %>%
  filter(task_filter == "all") %>%
  left_join(models_meta, by = "model") %>%
  group_by(model) %>%
  mutate(mean_mastery = mean(mastery_age, na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(
    tom_dimension = factor_dimension(tom_dimension),
    short_name = reorder(short_name, mean_mastery)
  )

p_heatmap <- ggplot(heatmap_data,
                     aes(x = tom_dimension, y = short_name, fill = mastery_age)) +
  geom_tile(color = "white", linewidth = 0.3) +
  geom_text(aes(label = ifelse(is.na(mastery_age), "–",
                                sprintf("%.1f", mastery_age))),
            size = 2.2, color = "black") +
  scale_fill_gradient2(low = "#2166ac", mid = "#f7f7f7", high = "#b2182b",
                       midpoint = 6, na.value = "grey80",
                       name = "Mastery\nAge") +
  scale_x_discrete(position = "top") +
  labs(title = "Developmental Mastery Age by Model and Dimension",
       subtitle = "Highest validated age with ≥80% accuracy",
       x = NULL, y = NULL) +
  theme_devtom(base_size = 9) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 0, size = 7),
    axis.text.y = element_text(size = 6),
    legend.key.height = unit(1.5, "cm"),
    plot.margin = margin(5, 5, 5, 5)
  )

ggsave(file.path(fig_dir, "mastery_age_heatmap.png"), p_heatmap,
       width = 14, height = 12, dpi = 200)

# =========================================================================
# Fig B: Construct mastery heatmap
# =========================================================================
cat("Fig B: Construct mastery heatmap...\n")

con_heatmap_data <- mastery_con %>%
  filter(task_filter == "all") %>%
  left_join(models_meta, by = "model") %>%
  group_by(model) %>%
  mutate(mean_mastery = mean(mastery_age, na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(
    tom_construct = factor_construct(tom_construct),
    short_name = reorder(short_name, mean_mastery)
  )

p_con_heatmap <- ggplot(con_heatmap_data,
                         aes(x = tom_construct, y = short_name, fill = mastery_age)) +
  geom_tile(color = "white", linewidth = 0.3) +
  geom_text(aes(label = ifelse(is.na(mastery_age), "–",
                                sprintf("%.1f", mastery_age))),
            size = 2.8) +
  scale_fill_gradient2(low = "#2166ac", mid = "#f7f7f7", high = "#b2182b",
                       midpoint = 6, na.value = "grey80",
                       name = "Mastery\nAge") +
  scale_x_discrete(position = "top") +
  labs(title = "Developmental Mastery Age by Model and Construct",
       x = NULL, y = NULL) +
  theme_devtom(base_size = 10) +
  theme(
    axis.text.x = element_text(angle = 30, hjust = 0, size = 8),
    axis.text.y = element_text(size = 7),
    legend.key.height = unit(1.5, "cm")
  )

ggsave(file.path(fig_dir, "construct_mastery_heatmap.png"), p_con_heatmap,
       width = 10, height = 12, dpi = 200)

# =========================================================================
# Fig C: Per-model dimension accuracy profiles (6 models per page)
# =========================================================================
cat("Fig C: Per-model dimension accuracy profiles...\n")

acc_by_age_dim <- df %>%
  group_by(model, tom_dimension, age_mid) %>%
  summarise(accuracy = mean(correct), n = n(), .groups = "drop") %>%
  left_join(models_meta %>% select(model, short_name, family), by = "model")

model_list <- models_meta %>%
  arrange(release_date) %>%
  pull(model) %>%
  unique()

models_per_page <- 6
n_pages <- ceiling(length(model_list) / models_per_page)

for (page in seq_len(n_pages)) {
  start_idx <- (page - 1) * models_per_page + 1
  end_idx <- min(page * models_per_page, length(model_list))
  page_models <- model_list[start_idx:end_idx]

  page_data <- acc_by_age_dim %>%
    filter(model %in% page_models) %>%
    mutate(tom_dimension = factor_dimension(tom_dimension))

  p_detail <- ggplot(page_data, aes(x = age_mid, y = accuracy)) +
    geom_hline(yintercept = 0.80, linetype = "dashed", color = "grey50", alpha = 0.7) +
    geom_point(aes(size = n), alpha = 0.7) +
    geom_line(alpha = 0.5) +
    facet_grid(short_name ~ tom_dimension, scales = "free_x") +
    scale_y_continuous(limits = c(0, 1), labels = scales::percent) +
    scale_size_continuous(range = c(1, 3), guide = "none") +
    labs(title = sprintf("Within-Dimension Accuracy vs. Developmental Age (Page %d/%d)",
                         page, n_pages),
         x = "Item Developmental Age (years)", y = "Accuracy") +
    theme_devtom(base_size = 8) +
    theme(
      strip.text.x = element_text(size = 5.5, angle = 45, hjust = 0),
      strip.text.y = element_text(size = 6),
      panel.spacing = unit(0.15, "lines")
    )

  ggsave(file.path(fig_dir, sprintf("per_model_dim_fit_%02d.png", page)),
         p_detail, width = 16, height = max(4, length(page_models) * 1.8), dpi = 200)
}

# =========================================================================
# Fig D: Family age profiles
# =========================================================================
cat("Fig D: Family age profiles...\n")

family_profiles <- mastery_dim %>%
  filter(task_filter == "all") %>%
  left_join(models_meta %>% select(model, family), by = "model") %>%
  group_by(family, tom_dimension) %>%
  summarise(
    mean_age = mean(mastery_age, na.rm = TRUE),
    se_age = sd(mastery_age, na.rm = TRUE) / sqrt(sum(!is.na(mastery_age))),
    .groups = "drop"
  ) %>%
  mutate(
    tom_dimension = factor_dimension(tom_dimension),
    family = factor_family(family)
  )

p_family <- ggplot(family_profiles,
                    aes(x = tom_dimension, y = mean_age, fill = family)) +
  geom_col(position = position_dodge(0.8), width = 0.7) +
  geom_errorbar(aes(ymin = mean_age - se_age, ymax = mean_age + se_age),
                position = position_dodge(0.8), width = 0.2) +
  scale_fill_manual(values = FAMILY_COLORS, name = "Family") +
  labs(title = "Mean Mastery Age by Model Family and Dimension",
       x = NULL, y = "Mean Mastery Age (years)") +
  theme_devtom() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 8))

ggsave(file.path(fig_dir, "family_age_profiles.png"), p_family,
       width = 14, height = 7, dpi = 200)

# =========================================================================
# Fig E: MCQ vs FRQ comparison
# =========================================================================
cat("Fig E: MCQ vs FRQ comparison...\n")

mcq_ages <- mastery_dim %>%
  filter(task_filter == "mcq") %>%
  select(model, tom_dimension, mcq_age = mastery_age)

frq_ages <- mastery_dim %>%
  filter(task_filter == "frq") %>%
  select(model, tom_dimension, frq_age = mastery_age)

task_compare <- mcq_ages %>%
  inner_join(frq_ages, by = c("model", "tom_dimension")) %>%
  left_join(models_meta %>% select(model, family), by = "model") %>%
  mutate(tom_dimension = factor_dimension(tom_dimension))

p_task <- ggplot(task_compare, aes(x = mcq_age, y = frq_age, color = family)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey50") +
  geom_point(alpha = 0.6, size = 1.5) +
  facet_wrap(~ tom_dimension, ncol = 4) +
  scale_color_manual(values = FAMILY_COLORS, name = "Family") +
  labs(title = "MCQ vs. FRQ Mastery Ages by Dimension",
       subtitle = "Points above diagonal: higher mastery on FRQ than MCQ",
       x = "MCQ Mastery Age (years)", y = "FRQ Mastery Age (years)") +
  theme_devtom(base_size = 9) +
  theme(strip.text = element_text(size = 7))

ggsave(file.path(fig_dir, "mcq_vs_frq_comparison.png"), p_task,
       width = 14, height = 10, dpi = 200)

# =========================================================================
# Fig F: Method comparison scatter
# =========================================================================
cat("Fig F: Method comparison...\n")

if (nrow(comparison) > 0 && any(!is.na(comparison$glm_age_eq))) {
  comp_long <- comparison %>%
    filter(!is.na(mastery_age)) %>%
    select(model, tom_dimension, family, mastery_age, glm_age_eq, glmm_age_eq) %>%
    pivot_longer(c(glm_age_eq, glmm_age_eq),
                 names_to = "method", values_to = "model_age") %>%
    filter(!is.na(model_age)) %>%
    mutate(method = case_when(
      method == "glm_age_eq" ~ "Per-model GLM",
      method == "glmm_age_eq" ~ "Cross-model GLMM"
    ))

  if (nrow(comp_long) > 0) {
    p_compare <- ggplot(comp_long,
                         aes(x = mastery_age, y = model_age, color = family)) +
      geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey50") +
      geom_point(alpha = 0.4, size = 1) +
      facet_wrap(~ method) +
      scale_color_manual(values = FAMILY_COLORS) +
      labs(title = "Convergent Validity: Mastery-Based vs. Model-Based Age Estimates",
           x = "Mastery Age (years)", y = "Model-Based Age Estimate (years)") +
      theme_devtom()

    ggsave(file.path(fig_dir, "method_comparison_scatter.png"), p_compare,
           width = 12, height = 6, dpi = 200)
  }
}

# =========================================================================
# Fig G: GLMM task type effect
# =========================================================================
cat("Fig G: GLMM task type effect...\n")

if (has_glmm && nrow(glmm_ages) > 0) {
  # Compare dimension-level GLMM ages between scopes
  glmm_dim <- glmm_ages %>%
    filter(scope %in% DIMENSION_DEVELOPMENTAL_ORDER) %>%
    left_join(models_meta %>% select(model, family), by = "model") %>%
    mutate(scope = factor_dimension(scope))

  if (nrow(glmm_dim) > 0) {
    p_glmm_box <- ggplot(glmm_dim, aes(x = scope, y = age_eq_50, fill = scope)) +
      geom_boxplot(alpha = 0.7, outlier.size = 1) +
      scale_fill_viridis_d(guide = "none") +
      labs(title = "GLMM Age-Equivalent Distribution by Dimension",
           subtitle = "Cross-model GLMM with task type covariate",
           x = NULL, y = "Age Equivalent (50% threshold)") +
      theme_devtom() +
      theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 8))

    ggsave(file.path(fig_dir, "glmm_age_by_dimension.png"), p_glmm_box,
           width = 12, height = 7, dpi = 200)
  }
}

cat("\n=== Figures written ===\n")
list.files(fig_dir) %>% cat(sep = "\n")
cat("\nDone. Output in:", fig_dir, "\n")
