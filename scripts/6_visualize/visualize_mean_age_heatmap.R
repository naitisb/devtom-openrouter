#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

source("scripts/6_visualize/_theme.R")

base_dir <- "results/modeling/developmental_age_mapping"
ts_dirs <- list.dirs(base_dir, recursive = FALSE, full.names = TRUE)
model_dir <- sort(ts_dirs, decreasing = TRUE)[1]
cat("Reading from:", model_dir, "\n")

fig_dir <- file.path("results", "figures", "developmental_age",
                      basename(model_dir))
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

item_csv <- "results/item_level.csv"
df <- read_csv(item_csv, show_col_types = FALSE) %>%
  filter(family %in% FAMILY_ORDER)

models_meta <- df %>%
  distinct(model, family, tier, release_date) %>%
  mutate(release_date = as.Date(release_date),
         short_name = short_model(model))

DIM_TO_CONSTRUCT <- c(
  "Diverse Desires" = "Desire / intention inference",
  "Diverse Beliefs" = "Belief reasoning",
  "Knowledge Access / Ignorance" = "Knowledge access",
  "Emotion Recognition" = "Emotion recognition",
  "First-Order False Belief" = "Belief reasoning",
  "Intention vs. Accident" = "Desire / intention inference",
  "Hidden Emotion (Appearance vs. Reality)" = "Emotion recognition",
  "Second-Order False Belief" = "Belief reasoning",
  "White Lies / Prosocial Deception" = "Deception",
  "Sarcasm" = "Pragmatic understanding",
  "Faux Pas Detection" = "Pragmatic understanding",
  "Irony" = "Pragmatic understanding"
)

# Validated item age range
AGE_MIN <- 2.5
AGE_MAX <- 11.0
AGE_MID <- (AGE_MIN + AGE_MAX) / 2  # 6.75

clamp_age <- function(x) pmin(pmax(x, AGE_MIN), AGE_MAX)

# =========================================================================
# Load age estimates from all 4 methods at the dimension level
# Clamp each method's output to [2.5, 11] before averaging
# =========================================================================

# 1. Mastery (already within range by construction)
mastery <- read_csv(file.path(model_dir, "mastery_age_dimension.csv"),
                    show_col_types = FALSE) %>%
  filter(task_filter == "all") %>%
  mutate(mastery_age = as.numeric(mastery_age)) %>%
  select(model, tom_dimension, mastery_age)

# 2. GLM (positive-slope fits, then clamp to item range)
glm_ages <- read_csv(file.path(model_dir, "glm_per_model_age.csv"),
                     show_col_types = FALSE) %>%
  filter(scope == "dimension",
         fit_flag == "positive_slope",
         is.finite(age_eq_50),
         age_eq_50 > 0, age_eq_50 < 15) %>%
  mutate(glm_age = clamp_age(age_eq_50)) %>%
  select(model, tom_dimension = scope_name, glm_age)

# 3. GLMM (clamp extreme extrapolations to item range)
glmm_ages <- read_csv(file.path(model_dir, "glmm_age_equivalents.csv"),
                      show_col_types = FALSE) %>%
  filter(scope %in% DIMENSION_DEVELOPMENTAL_ORDER,
         is.finite(age_eq_50)) %>%
  mutate(glmm_age = clamp_age(age_eq_50)) %>%
  select(model, tom_dimension = scope, glmm_age)

# 4. IRT (clamp to item range)
irt_ages <- read_csv(file.path(model_dir, "irt_age_equivalents.csv"),
                     show_col_types = FALSE) %>%
  filter(is.finite(irt_age_eq)) %>%
  mutate(irt_age = clamp_age(irt_age_eq)) %>%
  select(model, tom_dimension, irt_age)

# =========================================================================
# Merge and compute mean age across available methods
# =========================================================================
combined <- mastery %>%
  full_join(glm_ages, by = c("model", "tom_dimension")) %>%
  full_join(glmm_ages, by = c("model", "tom_dimension")) %>%
  full_join(irt_ages, by = c("model", "tom_dimension")) %>%
  left_join(models_meta, by = "model") %>%
  filter(family %in% FAMILY_ORDER)

combined <- combined %>%
  rowwise() %>%
  mutate(
    mean_age = mean(c(mastery_age, glm_age, glmm_age, irt_age), na.rm = TRUE),
    n_methods = sum(!is.na(c(mastery_age, glm_age, glmm_age, irt_age)))
  ) %>%
  ungroup() %>%
  mutate(mean_age = ifelse(is.nan(mean_age), NA_real_, mean_age))

cat("Models:", n_distinct(combined$model), "\n")
cat("Model-dimension pairs:", nrow(combined), "\n")
cat("Mean methods per cell:", round(mean(combined$n_methods, na.rm = TRUE), 2), "\n")

# =========================================================================
# Compute target age per dimension = mean across all models
# =========================================================================
target_dim <- combined %>%
  filter(!is.na(mean_age)) %>%
  group_by(tom_dimension) %>%
  summarise(target_age = mean(mean_age, na.rm = TRUE), .groups = "drop")

cat("Target ages per dimension (mean across models):\n")
print(target_dim, n = 12)

# =========================================================================
# Heatmap: Model × Dimension — deviation from target
# =========================================================================
cat("Creating mean-age dimension heatmap (vs target)...\n")

heatmap_dim <- combined %>%
  filter(!is.na(mean_age)) %>%
  left_join(target_dim, by = "tom_dimension") %>%
  mutate(dev = mean_age - target_age) %>%
  group_by(model) %>%
  mutate(model_mean = mean(mean_age, na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(
    tom_dimension = factor_dimension(tom_dimension),
    family = factor_family(family),
    short_name = reorder(short_name, model_mean)
  )

max_dev <- max(abs(heatmap_dim$dev), na.rm = TRUE)

p_dim <- ggplot(heatmap_dim,
                aes(x = tom_dimension, y = short_name, fill = dev)) +
  geom_tile(color = "white", linewidth = 0.3) +
  geom_text(aes(label = sprintf("%.1f", mean_age)),
            size = 2.2, color = "black") +
  scale_fill_gradient2(low = "#2166ac", mid = "#f7f7f7", high = "#b2182b",
                       midpoint = 0,
                       limits = c(-max_dev, max_dev),
                       na.value = "grey80",
                       name = "vs\nTarget") +
  scale_x_discrete(position = "top") +
  labs(
    title = "Mean Developmental Age vs Target (All Methods)",
    subtitle = "Cell = mean age; color = deviation from per-dimension average across models (all items)",
    x = NULL, y = NULL
  ) +
  theme_devtom(base_size = 9) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 0, size = 7),
    axis.text.y = element_text(size = 6),
    legend.key.height = unit(1.5, "cm"),
    plot.margin = margin(5, 5, 5, 5)
  )

ggsave(file.path(fig_dir, "mean_age_heatmap_dimension.png"), p_dim,
       width = 14, height = 12, dpi = 200)

# =========================================================================
# Heatmap: Model × Construct — deviation from target
# =========================================================================
cat("Creating mean-age construct heatmap (vs target)...\n")

heatmap_con <- combined %>%
  filter(!is.na(mean_age)) %>%
  mutate(tom_construct = DIM_TO_CONSTRUCT[tom_dimension]) %>%
  group_by(model, tom_construct, family, short_name) %>%
  summarise(mean_age = mean(mean_age, na.rm = TRUE), .groups = "drop") %>%
  group_by(model) %>%
  mutate(model_mean = mean(mean_age, na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(
    tom_construct = factor_construct(tom_construct),
    family = factor_family(family),
    short_name = reorder(short_name, model_mean)
  )

target_con <- heatmap_con %>%
  group_by(tom_construct) %>%
  summarise(target_age = mean(mean_age, na.rm = TRUE), .groups = "drop")

heatmap_con <- heatmap_con %>%
  left_join(target_con, by = "tom_construct") %>%
  mutate(dev = mean_age - target_age)

max_dev_con <- max(abs(heatmap_con$dev), na.rm = TRUE)

p_con <- ggplot(heatmap_con,
                aes(x = tom_construct, y = short_name, fill = dev)) +
  geom_tile(color = "white", linewidth = 0.3) +
  geom_text(aes(label = sprintf("%.1f", mean_age)),
            size = 2.8, color = "black") +
  scale_fill_gradient2(low = "#2166ac", mid = "#f7f7f7", high = "#b2182b",
                       midpoint = 0,
                       limits = c(-max_dev_con, max_dev_con),
                       na.value = "grey80",
                       name = "vs\nTarget") +
  scale_x_discrete(position = "top") +
  labs(
    title = "Mean Developmental Age vs Target by Construct (All Methods)",
    subtitle = "Cell = mean age; color = deviation from per-construct average (all items)",
    x = NULL, y = NULL
  ) +
  theme_devtom(base_size = 10) +
  theme(
    axis.text.x = element_text(angle = 30, hjust = 0, size = 8),
    axis.text.y = element_text(size = 7),
    legend.key.height = unit(1.5, "cm")
  )

ggsave(file.path(fig_dir, "mean_age_heatmap_construct.png"), p_con,
       width = 10, height = 12, dpi = 200)

# =========================================================================
# Mastery heatmap — filtered to models with no missing dimensions
# =========================================================================
cat("Creating filtered mastery heatmap (no missing values)...\n")

mastery_full <- read_csv(file.path(model_dir, "mastery_age_dimension.csv"),
                         show_col_types = FALSE) %>%
  filter(task_filter == "all") %>%
  mutate(mastery_age = as.numeric(mastery_age)) %>%
  left_join(models_meta, by = "model") %>%
  filter(family %in% FAMILY_ORDER)

complete_models <- mastery_full %>%
  group_by(model) %>%
  summarise(n_valid = sum(!is.na(mastery_age)),
            n_dims = n(), .groups = "drop") %>%
  filter(n_valid == n_dims) %>%
  pull(model)

cat("  Models with complete mastery data:", length(complete_models),
    "out of", n_distinct(mastery_full$model), "\n")

# Compute mastery target per dimension (mean across complete models)
mastery_target_dim <- mastery_full %>%
  filter(model %in% complete_models, !is.na(mastery_age)) %>%
  group_by(tom_dimension) %>%
  summarise(target_age = mean(mastery_age, na.rm = TRUE), .groups = "drop")

mastery_filtered <- mastery_full %>%
  filter(model %in% complete_models) %>%
  left_join(mastery_target_dim, by = "tom_dimension") %>%
  mutate(dev = mastery_age - target_age) %>%
  group_by(model) %>%
  mutate(mean_mastery = mean(mastery_age, na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(
    tom_dimension = factor_dimension(tom_dimension),
    family = factor_family(family),
    short_name = reorder(short_name, mean_mastery)
  )

mastery_max_dev <- max(abs(mastery_filtered$dev), na.rm = TRUE)

p_mastery <- ggplot(mastery_filtered,
                    aes(x = tom_dimension, y = short_name, fill = dev)) +
  geom_tile(color = "white", linewidth = 0.3) +
  geom_text(aes(label = sprintf("%.1f", mastery_age)),
            size = 2.4, color = "black") +
  scale_fill_gradient2(low = "#2166ac", mid = "#f7f7f7", high = "#b2182b",
                       midpoint = 0,
                       limits = c(-mastery_max_dev, mastery_max_dev),
                       na.value = "grey80",
                       name = "vs\nTarget") +
  scale_x_discrete(position = "top") +
  labs(
    title = "Mastery Age vs Target (Complete Models Only)",
    subtitle = paste0("Cell = mastery age; color = deviation from per-dimension average — ",
                      length(complete_models), " models (all items)"),
    x = NULL, y = NULL
  ) +
  theme_devtom(base_size = 9) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 0, size = 7),
    axis.text.y = element_text(size = 6.5),
    legend.key.height = unit(1.5, "cm"),
    plot.margin = margin(5, 5, 5, 5)
  )

ggsave(file.path(fig_dir, "mastery_age_heatmap_complete.png"), p_mastery,
       width = 14, height = 10, dpi = 200)

# Construct-level mastery heatmap (filtered, vs target)
cat("Creating filtered mastery construct heatmap...\n")

mastery_con_full <- read_csv(file.path(model_dir, "mastery_age_construct.csv"),
                             show_col_types = FALSE) %>%
  filter(task_filter == "all") %>%
  mutate(mastery_age = as.numeric(mastery_age)) %>%
  left_join(models_meta, by = "model") %>%
  filter(family %in% FAMILY_ORDER,
         model %in% complete_models) %>%
  group_by(model) %>%
  mutate(mean_mastery = mean(mastery_age, na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(
    tom_construct = factor_construct(tom_construct),
    family = factor_family(family),
    short_name = reorder(short_name, mean_mastery)
  )

mastery_target_con <- mastery_con_full %>%
  filter(!is.na(mastery_age)) %>%
  group_by(tom_construct) %>%
  summarise(target_age = mean(mastery_age, na.rm = TRUE), .groups = "drop")

mastery_con_full <- mastery_con_full %>%
  left_join(mastery_target_con, by = "tom_construct") %>%
  mutate(dev = mastery_age - target_age)

mastery_max_dev_con <- max(abs(mastery_con_full$dev), na.rm = TRUE)

p_mastery_con <- ggplot(mastery_con_full,
                        aes(x = tom_construct, y = short_name, fill = dev)) +
  geom_tile(color = "white", linewidth = 0.3) +
  geom_text(aes(label = ifelse(is.na(mastery_age), "–",
                                sprintf("%.1f", mastery_age))),
            size = 2.8, color = "black") +
  scale_fill_gradient2(low = "#2166ac", mid = "#f7f7f7", high = "#b2182b",
                       midpoint = 0,
                       limits = c(-mastery_max_dev_con, mastery_max_dev_con),
                       na.value = "grey80",
                       name = "vs\nTarget") +
  scale_x_discrete(position = "top") +
  labs(
    title = "Mastery Age vs Target by Construct (Complete Models Only)",
    subtitle = paste0("Cell = mastery age; color = deviation from per-construct average — ",
                      length(complete_models), " models (all items)"),
    x = NULL, y = NULL
  ) +
  theme_devtom(base_size = 10) +
  theme(
    axis.text.x = element_text(angle = 30, hjust = 0, size = 8),
    axis.text.y = element_text(size = 7),
    legend.key.height = unit(1.5, "cm")
  )

ggsave(file.path(fig_dir, "mastery_age_heatmap_construct_complete.png"), p_mastery_con,
       width = 10, height = 10, dpi = 200)

cat("\n=== All heatmaps written ===\n")
list.files(fig_dir, pattern = "heatmap") %>% cat(sep = "\n")
cat("\nDone.\n")
