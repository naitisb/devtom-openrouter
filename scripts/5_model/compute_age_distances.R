#!/usr/bin/env Rscript
# compute_age_distances.R — Model-wise distance between estimated and target age
#
# For each model × scope (dimension / construct / overall) × method:
#   distance = estimated_age - target_age
#
# Target age = mean item age_mid within that scope.
# Methods: Mastery, GLM, GLMM, IRT (+ cross-method mean).

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
})

source("scripts/6_visualize/_theme.R")

base_dir <- "results/modeling/developmental_age_mapping"
ts_dirs  <- list.dirs(base_dir, recursive = FALSE, full.names = TRUE)
model_dir <- sort(ts_dirs, decreasing = TRUE)[1]
cat("Reading from:", model_dir, "\n")

item_csv <- "results/item_level.csv"
df <- read_csv(item_csv, show_col_types = FALSE) %>%
  filter(family %in% FAMILY_ORDER)

models_meta <- df %>%
  distinct(model, family, tier, release_date) %>%
  mutate(release_date = as.Date(release_date))

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

# =========================================================================
# Target ages (mean item age_mid per scope)
# =========================================================================
target_dim <- df %>%
  group_by(tom_dimension) %>%
  summarise(target_age = mean(age_mid, na.rm = TRUE), .groups = "drop")

target_con <- df %>%
  mutate(tom_construct = DIM_TO_CONSTRUCT[tom_dimension]) %>%
  group_by(tom_construct) %>%
  summarise(target_age = mean(age_mid, na.rm = TRUE), .groups = "drop")

target_ovr <- mean(df$age_mid, na.rm = TRUE)

cat("Target ages computed.\n")
cat("  Overall:", round(target_ovr, 2), "\n")

# =========================================================================
# 1. MASTERY
# =========================================================================
mastery_dim <- read_csv(file.path(model_dir, "mastery_age_dimension.csv"),
                        show_col_types = FALSE) %>%
  filter(task_filter == "all") %>%
  mutate(estimated_age = as.numeric(mastery_age)) %>%
  filter(!is.na(estimated_age)) %>%
  left_join(target_dim, by = "tom_dimension") %>%
  transmute(model, scope = tom_dimension, scope_type = "dimension",
            method = "mastery", estimated_age, target_age,
            distance = estimated_age - target_age,
            abs_distance = abs(distance),
            ratio = estimated_age / target_age)

mastery_con <- read_csv(file.path(model_dir, "mastery_age_construct.csv"),
                        show_col_types = FALSE) %>%
  filter(task_filter == "all") %>%
  mutate(estimated_age = as.numeric(mastery_age)) %>%
  filter(!is.na(estimated_age)) %>%
  left_join(target_con, by = "tom_construct") %>%
  transmute(model, scope = tom_construct, scope_type = "construct",
            method = "mastery", estimated_age, target_age,
            distance = estimated_age - target_age,
            abs_distance = abs(distance),
            ratio = estimated_age / target_age)

mastery_ovr <- read_csv(file.path(model_dir, "mastery_age_overall.csv"),
                        show_col_types = FALSE) %>%
  filter(task_filter == "all") %>%
  mutate(estimated_age = as.numeric(mastery_age)) %>%
  filter(!is.na(estimated_age)) %>%
  transmute(model, scope = "overall", scope_type = "overall",
            method = "mastery", estimated_age, target_age = target_ovr,
            distance = estimated_age - target_age,
            abs_distance = abs(distance),
            ratio = estimated_age / target_age)

cat("Mastery:", nrow(mastery_dim), "dim,", nrow(mastery_con), "con,",
    nrow(mastery_ovr), "ovr\n")

# =========================================================================
# 2. GLM
# =========================================================================
glm_raw <- read_csv(file.path(model_dir, "glm_per_model_age.csv"),
                     show_col_types = FALSE) %>%
  filter(fit_flag == "positive_slope",
         is.finite(age_eq_50),
         age_eq_50 > 0, age_eq_50 < 15) %>%
  mutate(estimated_age = pmin(pmax(age_eq_50, 2.5), 11.0))

glm_dim <- glm_raw %>%
  filter(scope == "dimension") %>%
  rename(tom_dimension = scope_name) %>%
  left_join(target_dim, by = "tom_dimension") %>%
  transmute(model, scope = tom_dimension, scope_type = "dimension",
            method = "glm", estimated_age, target_age,
            distance = estimated_age - target_age,
            abs_distance = abs(distance),
            ratio = estimated_age / target_age)

glm_con <- glm_raw %>%
  filter(scope == "construct") %>%
  rename(tom_construct = scope_name) %>%
  left_join(target_con, by = "tom_construct") %>%
  transmute(model, scope = tom_construct, scope_type = "construct",
            method = "glm", estimated_age, target_age,
            distance = estimated_age - target_age,
            abs_distance = abs(distance),
            ratio = estimated_age / target_age)

glm_ovr <- glm_raw %>%
  filter(scope == "overall") %>%
  transmute(model, scope = "overall", scope_type = "overall",
            method = "glm", estimated_age, target_age = target_ovr,
            distance = estimated_age - target_age,
            abs_distance = abs(distance),
            ratio = estimated_age / target_age)

cat("GLM:", nrow(glm_dim), "dim,", nrow(glm_con), "con,",
    nrow(glm_ovr), "ovr\n")

# =========================================================================
# 3. GLMM
# =========================================================================
glmm_raw <- read_csv(file.path(model_dir, "glmm_age_equivalents.csv"),
                      show_col_types = FALSE) %>%
  filter(is.finite(age_eq_50)) %>%
  mutate(estimated_age = pmin(pmax(age_eq_50, 2.5), 11.0))

glmm_dim <- glmm_raw %>%
  filter(scope %in% DIMENSION_DEVELOPMENTAL_ORDER) %>%
  rename(tom_dimension = scope) %>%
  left_join(target_dim, by = "tom_dimension") %>%
  transmute(model, scope = tom_dimension, scope_type = "dimension",
            method = "glmm", estimated_age, target_age,
            distance = estimated_age - target_age,
            abs_distance = abs(distance),
            ratio = estimated_age / target_age)

glmm_con <- glmm_raw %>%
  filter(scope %in% CONSTRUCT_DEVELOPMENTAL_ORDER) %>%
  rename(tom_construct = scope) %>%
  left_join(target_con, by = "tom_construct") %>%
  transmute(model, scope = tom_construct, scope_type = "construct",
            method = "glmm", estimated_age, target_age,
            distance = estimated_age - target_age,
            abs_distance = abs(distance),
            ratio = estimated_age / target_age)

glmm_ovr <- glmm_raw %>%
  filter(scope == "overall") %>%
  transmute(model, scope = "overall", scope_type = "overall",
            method = "glmm", estimated_age, target_age = target_ovr,
            distance = estimated_age - target_age,
            abs_distance = abs(distance),
            ratio = estimated_age / target_age)

cat("GLMM:", nrow(glmm_dim), "dim,", nrow(glmm_con), "con,",
    nrow(glmm_ovr), "ovr\n")

# =========================================================================
# 4. IRT
# =========================================================================
irt_raw <- read_csv(file.path(model_dir, "irt_age_equivalents.csv"),
                    show_col_types = FALSE) %>%
  filter(is.finite(irt_age_eq)) %>%
  mutate(estimated_age = pmin(pmax(irt_age_eq, 2.5), 11.0))

irt_dim <- irt_raw %>%
  left_join(target_dim, by = "tom_dimension") %>%
  transmute(model, scope = tom_dimension, scope_type = "dimension",
            method = "irt", estimated_age, target_age,
            distance = estimated_age - target_age,
            abs_distance = abs(distance),
            ratio = estimated_age / target_age)

irt_con <- irt_raw %>%
  mutate(tom_construct = DIM_TO_CONSTRUCT[tom_dimension]) %>%
  group_by(model, tom_construct) %>%
  summarise(estimated_age = mean(estimated_age, na.rm = TRUE), .groups = "drop") %>%
  left_join(target_con, by = "tom_construct") %>%
  transmute(model, scope = tom_construct, scope_type = "construct",
            method = "irt", estimated_age, target_age,
            distance = estimated_age - target_age,
            abs_distance = abs(distance),
            ratio = estimated_age / target_age)

irt_ovr <- irt_raw %>%
  group_by(model) %>%
  summarise(estimated_age = mean(estimated_age, na.rm = TRUE), .groups = "drop") %>%
  transmute(model, scope = "overall", scope_type = "overall",
            method = "irt", estimated_age, target_age = target_ovr,
            distance = estimated_age - target_age,
            abs_distance = abs(distance),
            ratio = estimated_age / target_age)

cat("IRT:", nrow(irt_dim), "dim,", nrow(irt_con), "con,",
    nrow(irt_ovr), "ovr\n")

# =========================================================================
# Combine all methods into a single long table
# =========================================================================
all_distances <- bind_rows(
  mastery_dim, mastery_con, mastery_ovr,
  glm_dim, glm_con, glm_ovr,
  glmm_dim, glmm_con, glmm_ovr,
  irt_dim, irt_con, irt_ovr
) %>%
  left_join(models_meta, by = "model") %>%
  arrange(model, scope_type, scope, method)

cat("\nTotal rows:", nrow(all_distances), "\n")
cat("Models:", n_distinct(all_distances$model), "\n")
cat("Methods:", paste(unique(all_distances$method), collapse = ", "), "\n")

# =========================================================================
# Cross-method mean distance per model × scope
# =========================================================================
mean_distances <- all_distances %>%
  group_by(model, scope, scope_type, family, tier, release_date, target_age) %>%
  summarise(
    n_methods      = n(),
    mean_est_age   = mean(estimated_age, na.rm = TRUE),
    mean_distance  = mean(distance, na.rm = TRUE),
    mean_abs_dist  = mean(abs_distance, na.rm = TRUE),
    sd_distance    = sd(distance, na.rm = TRUE),
    min_distance   = min(distance, na.rm = TRUE),
    max_distance   = max(distance, na.rm = TRUE),
    mean_ratio     = mean(ratio, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(scope_type, scope, mean_distance)

# =========================================================================
# Summary statistics
# =========================================================================
cat("\n=== Distance Summary by Method ===\n")
all_distances %>%
  group_by(method, scope_type) %>%
  summarise(
    n = n(),
    mean_dist     = round(mean(distance, na.rm = TRUE), 2),
    median_dist   = round(median(distance, na.rm = TRUE), 2),
    mean_abs_dist = round(mean(abs_distance, na.rm = TRUE), 2),
    sd_dist       = round(sd(distance, na.rm = TRUE), 2),
    .groups = "drop"
  ) %>%
  print(n = 30)

cat("\n=== Distance Summary by Dimension (cross-method mean) ===\n")
mean_distances %>%
  filter(scope_type == "dimension") %>%
  group_by(scope) %>%
  summarise(
    n_models      = n(),
    mean_dist     = round(mean(mean_distance, na.rm = TRUE), 2),
    median_dist   = round(median(mean_distance, na.rm = TRUE), 2),
    mean_abs_dist = round(mean(mean_abs_dist, na.rm = TRUE), 2),
    sd_dist       = round(sd(mean_distance, na.rm = TRUE), 2),
    .groups = "drop"
  ) %>%
  arrange(mean_dist) %>%
  print(n = 12)

cat("\n=== Distance Summary by Construct (cross-method mean) ===\n")
mean_distances %>%
  filter(scope_type == "construct") %>%
  group_by(scope) %>%
  summarise(
    n_models      = n(),
    mean_dist     = round(mean(mean_distance, na.rm = TRUE), 2),
    median_dist   = round(median(mean_distance, na.rm = TRUE), 2),
    mean_abs_dist = round(mean(mean_abs_dist, na.rm = TRUE), 2),
    sd_dist       = round(sd(mean_distance, na.rm = TRUE), 2),
    .groups = "drop"
  ) %>%
  arrange(mean_dist) %>%
  print(n = 6)

# =========================================================================
# Write outputs
# =========================================================================
out_dir <- model_dir

write_csv(all_distances,
          file.path(out_dir, "age_distances_by_method.csv"))
cat("\nWrote:", file.path(out_dir, "age_distances_by_method.csv"), "\n")

write_csv(mean_distances,
          file.path(out_dir, "age_distances_cross_method.csv"))
cat("Wrote:", file.path(out_dir, "age_distances_cross_method.csv"), "\n")

# Wide format: one row per model × scope, columns per method
wide_distances <- all_distances %>%
  select(model, scope, scope_type, method, distance) %>%
  pivot_wider(names_from = method, values_from = distance,
              names_prefix = "dist_") %>%
  left_join(
    all_distances %>%
      select(model, scope, scope_type, method, estimated_age) %>%
      pivot_wider(names_from = method, values_from = estimated_age,
                  names_prefix = "age_"),
    by = c("model", "scope", "scope_type")
  ) %>%
  left_join(
    all_distances %>% distinct(model, scope, target_age),
    by = c("model", "scope")
  ) %>%
  left_join(models_meta, by = "model") %>%
  arrange(scope_type, scope, model)

write_csv(wide_distances,
          file.path(out_dir, "age_distances_wide.csv"))
cat("Wrote:", file.path(out_dir, "age_distances_wide.csv"), "\n")

cat("\nDone.\n")
