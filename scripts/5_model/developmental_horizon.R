#!/usr/bin/env Rscript
# developmental_horizon.R — METR-style "developmental age horizon" analysis
#
# Adapts METR's time-horizon methodology to ToM:
#   - METR: logistic(success ~ log(human_task_duration)) → time horizon
#   - DevToM: logistic(success ~ developmental_age) → developmental age horizon
#
# Uses dimension-level binomial GLM (aggregated items per dimension)
# for more stable fits than item-level, plus a complementary
# "milestone mastery" metric.

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(purrr)
})

source("scripts/6_visualize/_theme.R")

ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path("results", "modeling", "developmental_horizon", ts)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
cat("Output dir:", out_dir, "\n")

sink(file.path(out_dir, "horizon_log.txt"), split = TRUE)
cat("=== Developmental Age Horizon Analysis ===\n")
cat("Timestamp:", ts, "\n\n")

# ---------------------------------------------------------------------------
# 1. Load data
# ---------------------------------------------------------------------------
item_csv <- "results/item_level.csv"
if (!file.exists(item_csv)) stop("Missing: ", item_csv)
df <- read_csv(item_csv, show_col_types = FALSE) %>%
  filter(family %in% FAMILY_ORDER)

cat("Total rows:", nrow(df), "\n")
cat("Models:", n_distinct(df$model), "\n\n")

# Canonical dimension ages (midpoint of acquisition age band)
DIM_AGES <- tibble(
  tom_dimension = DIMENSION_DEVELOPMENTAL_ORDER,
  dim_age = c(2.5, 3.5, 3.5, 3.5, 4.5, 4.5, 5.0, 6.5, 6.0, 7.0, 10.0, 7.0),
  dim_rank = 0:11
)

# ---------------------------------------------------------------------------
# 2. Aggregate to dimension level per model
# ---------------------------------------------------------------------------
dim_acc <- df %>%
  group_by(model, family, tier, release_date, tom_dimension) %>%
  summarise(
    n_items   = n(),
    n_correct = sum(correct),
    accuracy  = mean(correct),
    .groups   = "drop"
  ) %>%
  left_join(DIM_AGES, by = "tom_dimension") %>%
  mutate(
    release_date = as.Date(release_date),
    date_years   = as.numeric(release_date - as.Date("2024-01-01")) / 365.25
  )

# Also aggregate by task type
dim_acc_by_task <- df %>%
  group_by(model, family, tier, release_date, tom_dimension, task) %>%
  summarise(
    n_items   = n(),
    n_correct = sum(correct),
    accuracy  = mean(correct),
    .groups   = "drop"
  ) %>%
  left_join(DIM_AGES, by = "tom_dimension") %>%
  mutate(
    release_date = as.Date(release_date),
    task_type    = case_when(
      task == "tom_12dim_mcq" ~ "mcq",
      task == "tom_12dim_freeresponse" ~ "freeresponse",
      TRUE ~ task
    )
  )

# ---------------------------------------------------------------------------
# 3. Fit binomial GLM per model (dimension-level)
# ---------------------------------------------------------------------------
fit_horizon_binomial <- function(data, thresholds = c(0.50, 0.80)) {
  tryCatch({
    # Exclude models with 0% overall (parsing failures)
    if (sum(data$n_correct) == 0) {
      return(tibble(
        intercept = NA_real_, slope = NA_real_,
        horizon_50 = NA_real_, horizon_80 = NA_real_,
        overall_acc = 0, n_dims = nrow(data),
        slope_pvalue = NA_real_, fit_type = "failure"
      ))
    }

    fit <- glm(
      cbind(n_correct, n_items - n_correct) ~ dim_age,
      data = data, family = binomial(link = "logit")
    )
    coefs <- coef(fit)
    intercept <- coefs[["(Intercept)"]]
    slope     <- coefs[["dim_age"]]
    pval      <- summary(fit)$coefficients["dim_age", "Pr(>|z|)"]

    horizon_at <- function(thresh) {
      if (is.na(slope) || slope == 0) return(NA_real_)
      -(intercept + log(thresh / (1 - thresh))) / slope
    }

    tibble(
      intercept    = intercept,
      slope        = slope,
      horizon_50   = horizon_at(0.50),
      horizon_80   = horizon_at(0.80),
      overall_acc  = sum(data$n_correct) / sum(data$n_items),
      n_dims       = nrow(data),
      slope_pvalue = pval,
      fit_type     = if_else(slope < 0, "negative_slope", "positive_slope")
    )
  }, error = function(e) {
    tibble(
      intercept = NA_real_, slope = NA_real_,
      horizon_50 = NA_real_, horizon_80 = NA_real_,
      overall_acc = sum(data$n_correct) / sum(data$n_items),
      n_dims = nrow(data),
      slope_pvalue = NA_real_, fit_type = "error"
    )
  })
}

horizons <- dim_acc %>%
  group_by(model, family, tier, release_date, date_years) %>%
  group_modify(~ fit_horizon_binomial(.x)) %>%
  ungroup()

# ---------------------------------------------------------------------------
# 4. Milestone mastery metric (complementary)
# ---------------------------------------------------------------------------
# For each threshold, find the highest-age dimension the model "passes"
mastery_fn <- function(acc_vec, age_vec, threshold) {
  idx <- which(acc_vec >= threshold)
  if (length(idx) == 0) return(0)
  max(age_vec[idx])
}

mastery <- dim_acc %>%
  group_by(model, family, tier, release_date, date_years) %>%
  summarise(
    mastery_80 = mastery_fn(accuracy, dim_age, 0.80),
    mastery_90 = mastery_fn(accuracy, dim_age, 0.90),
    mastery_50 = mastery_fn(accuracy, dim_age, 0.50),
    n_dims_above_80 = sum(accuracy >= 0.80),
    n_dims_above_90 = sum(accuracy >= 0.90),
    overall_acc = sum(n_correct) / sum(n_items),
    .groups = "drop"
  )

# Merge
horizons <- horizons %>%
  left_join(
    mastery %>% select(model, mastery_80, mastery_90, mastery_50,
                       n_dims_above_80, n_dims_above_90),
    by = "model"
  ) %>%
  mutate(
    # Categorize each model
    category = case_when(
      overall_acc == 0 ~ "failure",
      overall_acc < 0.30 ~ "below_floor",
      fit_type == "negative_slope" & horizon_50 >= 0 & horizon_50 <= 13 ~ "in_range",
      overall_acc >= 0.80 ~ "ceiling",
      TRUE ~ "mid_range"
    ),
    # Primary display metric: use mastery_80 for the headline chart
    # (more robust than logistic horizon for this data)
    display_horizon = mastery_80,
    beyond_range = n_dims_above_80 == 12
  )

# ---------------------------------------------------------------------------
# 5. Generate predicted curves for per-model plots
# ---------------------------------------------------------------------------
age_grid <- seq(1.5, 13, by = 0.1)

pred_curves <- horizons %>%
  filter(!is.na(intercept), !is.na(slope)) %>%
  rowwise() %>%
  do({
    row <- .
    tibble(
      model     = row$model,
      family    = row$family,
      tier      = row$tier,
      dim_age   = age_grid,
      pred_prob = plogis(row$intercept + row$slope * age_grid)
    )
  }) %>%
  ungroup()

# ---------------------------------------------------------------------------
# 6. Summary
# ---------------------------------------------------------------------------
cat("=== Category Breakdown ===\n")
horizons %>% count(category) %>% print()

cat("\n=== Horizon Summary (Mastery at 80%) ===\n")
h <- horizons %>% filter(overall_acc > 0) %>% arrange(display_horizon)
cat(sprintf("Models with valid data: %d\n", nrow(h)))
cat(sprintf("Models passing ALL 12 dims at 80%%: %d\n", sum(h$beyond_range)))
cat(sprintf("Range of mastery_80: %.1f - %.1f years\n",
            min(h$display_horizon), max(h$display_horizon)))

cat("\nAll models (sorted by developmental age horizon):\n")
h %>%
  mutate(short = short_model(model)) %>%
  select(short, family, release_date, overall_acc, mastery_80,
         n_dims_above_80, horizon_50) %>%
  arrange(mastery_80, overall_acc) %>%
  print(n = 60, width = 140)

# Date vs horizon correlation
cat("\n=== Date-Horizon Correlation ===\n")
valid <- h %>% filter(!is.na(date_years))
if (nrow(valid) >= 5) {
  cor_r <- cor.test(valid$date_years, valid$mastery_80)
  cat(sprintf("Pearson r(mastery_80 ~ date): %.3f, p = %.4g\n",
              cor_r$estimate, cor_r$p.value))
  cor_n80 <- cor.test(valid$date_years, valid$n_dims_above_80)
  cat(sprintf("Pearson r(n_dims_80 ~ date): %.3f, p = %.4g\n",
              cor_n80$estimate, cor_n80$p.value))
}

# ---------------------------------------------------------------------------
# 7. Save
# ---------------------------------------------------------------------------
write_csv(horizons, file.path(out_dir, "developmental_horizons.csv"))
write_csv(pred_curves, file.path(out_dir, "horizon_predicted_curves.csv"))
write_csv(dim_acc, file.path(out_dir, "dimension_accuracy_by_model.csv"))
write_csv(dim_acc_by_task, file.path(out_dir, "dimension_accuracy_by_model_task.csv"))

cat("\n=== Files written ===\n")
list.files(out_dir) %>% cat(sep = "\n")

sink()
cat("Done. Output in:", out_dir, "\n")
