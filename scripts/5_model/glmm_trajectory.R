#!/usr/bin/env Rscript
# glmm_trajectory.R — Binomial GLMM trajectory analysis (primary inference)
#
# Fits item-level logistic mixed models to test whether ToM accuracy improves
# release-over-release within each model family/tier. Reads
# results/item_level.csv (from extract_item_level.py); emits tidy CSV artifacts
# to results/modeling/inference/<timestamp>/ (consumed by 6_visualize).
#
# Usage:
#   Rscript scripts/5_model/glmm_trajectory.R
#   Rscript scripts/5_model/glmm_trajectory.R --item-csv results/item_level.csv

suppressPackageStartupMessages({
  library(lme4)
  library(broom.mixed)
  library(dplyr)
  library(tidyr)
  library(readr)
})

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

# ---------------------------------------------------------------------------
# Load & prep
# ---------------------------------------------------------------------------
df <- read_csv(item_csv, show_col_types = FALSE) %>%
  filter(!is.na(date_years)) %>%
  mutate(
    correct  = as.integer(correct),
    family   = factor(family),
    tier     = factor(tier),
    task     = factor(task),
    model    = factor(model),
    item_id  = factor(item_id),
    tom_dimension = factor(tom_dimension),
    dim_rank = as.numeric(dim_rank),
    date_c   = date_years - mean(date_years)
  )

cat(sprintf("Loaded %d rows: %d models, %d items, %d dimensions, families: %s\n",
            nrow(df), nlevels(df$model), nlevels(df$item_id),
            nlevels(df$tom_dimension),
            paste(levels(df$family), collapse = ", ")))

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path(results_dir, "modeling", "inference", stamp)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

log_file <- file.path(out_dir, "glmm_log.txt")
log_con <- file(log_file, open = "wt")
log_msg <- function(...) {
  msg <- paste0(...)
  cat(msg, "\n")
  writeLines(msg, log_con)
}

# ---------------------------------------------------------------------------
# Helper: safe glmer with convergence handling
# ---------------------------------------------------------------------------
safe_glmer <- function(formula, data, label = "") {
  log_msg("Fitting: ", label, " (", deparse(formula), ")")
  n_obs <- nrow(data)
  log_msg("  n = ", n_obs)

  tryCatch({
    fit <- glmer(formula, data = data, family = binomial,
                 control = glmerControl(optimizer = "bobyqa",
                                        optCtrl = list(maxfun = 1e5)))
    if (isSingular(fit)) {
      log_msg("  WARNING: singular fit for ", label)
    }
    msgs <- fit@optinfo$conv$lme4$messages
    if (length(msgs) > 0) {
      for (m in msgs) log_msg("  CONVERGENCE: ", m)
    }
    log_msg("  AIC = ", round(AIC(fit), 1))
    fit
  }, error = function(e) {
    log_msg("  ERROR fitting ", label, ": ", conditionMessage(e))
    NULL
  })
}

# ---------------------------------------------------------------------------
# Ceiling/separation check
# ---------------------------------------------------------------------------
check_ceiling <- function(data, groupvar = "tom_dimension") {
  rates <- data %>%
    group_by(across(all_of(groupvar))) %>%
    summarise(mean_acc = mean(correct), .groups = "drop")
  ceiling_groups <- rates %>% filter(mean_acc >= 1.0)
  floor_groups <- rates %>% filter(mean_acc <= 0.0)
  if (nrow(ceiling_groups) > 0) {
    log_msg("  Ceiling (100% correct): ",
            paste(ceiling_groups[[groupvar]], collapse = ", "))
  }
  if (nrow(floor_groups) > 0) {
    log_msg("  Floor (0% correct): ",
            paste(floor_groups[[groupvar]], collapse = ", "))
  }
  list(ceiling = ceiling_groups, floor = floor_groups)
}

# ---------------------------------------------------------------------------
# Model 1: correct ~ date_c * tier + (1|item_id) — per family
# ---------------------------------------------------------------------------
log_msg("\n=== Model 1: date × tier (per family) ===")
or_rows <- list()
pred_rows <- list()
obs_rows <- list()

families <- levels(df$family)
for (fam in families) {
  fam_df <- df %>% filter(family == fam)
  n_tiers <- n_distinct(fam_df$tier)
  n_dates <- n_distinct(fam_df$date_years)

  if (n_dates < 2) {
    log_msg("Skipping ", fam, ": only ", n_dates, " release date(s)")
    next
  }

  # Check if tier has enough levels
  if (n_tiers < 2) {
    formula <- correct ~ date_c + (1 | item_id)
  } else {
    formula <- correct ~ date_c * tier + (1 | item_id)
  }

  # Try adding (1|model) if enough models
  if (n_distinct(fam_df$model) >= 3) {
    if (n_tiers < 2) {
      formula <- correct ~ date_c + (1 | item_id) + (1 | model)
    } else {
      formula <- correct ~ date_c * tier + (1 | item_id) + (1 | model)
    }
  }

  check_ceiling(fam_df)
  fit <- safe_glmer(formula, fam_df, label = paste0("M1:", fam))
  if (is.null(fit)) next

  # Tidy fixed effects as odds ratios
  fe <- tidy(fit, effects = "fixed", conf.int = TRUE, exponentiate = TRUE) %>%
    mutate(family = fam, model_label = "M1_date_x_tier")
  or_rows <- c(or_rows, list(fe))

  # Prediction grid
  tiers_present <- unique(fam_df$tier)
  date_range <- seq(min(fam_df$date_c), max(fam_df$date_c), length.out = 50)
  grid <- expand.grid(date_c = date_range, tier = tiers_present,
                      stringsAsFactors = FALSE) %>%
    mutate(tier = factor(tier, levels = levels(df$tier)))
  # Population-level predictions (re.form = NA)
  tryCatch({
    preds <- predict(fit, newdata = grid, type = "response", re.form = NA)
    grid$pred <- preds
    grid$family <- fam
    # Approximate CI via SE
    preds_link <- predict(fit, newdata = grid, type = "link", re.form = NA, se.fit = TRUE)
    if (!is.null(attr(preds_link, "se.fit"))) {
      se <- attr(preds_link, "se.fit")
    } else {
      se <- rep(NA, length(preds_link))
    }
    grid$pred_lo <- plogis(preds_link - 1.96 * se)
    grid$pred_hi <- plogis(preds_link + 1.96 * se)
    # Convert date_c back to date_years
    grid$date_years <- grid$date_c + mean(fam_df$date_years)
    pred_rows <- c(pred_rows, list(grid))
  }, error = function(e) {
    log_msg("  Prediction failed for ", fam, ": ", conditionMessage(e))
  })

  # Observed points
  obs <- fam_df %>%
    group_by(family, tier, model, date_years, release_date) %>%
    summarise(accuracy = mean(correct), n = n(), .groups = "drop")
  obs_rows <- c(obs_rows, list(obs))
}

# ---------------------------------------------------------------------------
# Model 2: correct ~ date_c * dim_rank + (1|item_id) + (1|model) — per family
# ---------------------------------------------------------------------------
log_msg("\n=== Model 2: date × dim_rank (per family) ===")
dim_slope_rows <- list()

for (fam in families) {
  fam_df <- df %>% filter(family == fam)
  if (n_distinct(fam_df$date_years) < 2) next

  formula <- correct ~ date_c * dim_rank + (1 | item_id)
  if (n_distinct(fam_df$model) >= 3) {
    formula <- correct ~ date_c * dim_rank + (1 | item_id) + (1 | model)
  }

  fit <- safe_glmer(formula, fam_df, label = paste0("M2:", fam))
  if (is.null(fit)) next

  fe <- tidy(fit, effects = "fixed", conf.int = TRUE, exponentiate = TRUE) %>%
    mutate(family = fam, model_label = "M2_date_x_dimrank")
  or_rows <- c(or_rows, list(fe))

  # Per-dimension time slopes via emtrends if ggeffects available, else manual
  dim_ranks <- sort(unique(fam_df$dim_rank))
  dim_labels <- fam_df %>%
    distinct(tom_dimension, dim_rank, validated_age_band) %>%
    arrange(dim_rank)

  tryCatch({
    # Extract interaction coefficient
    coefs <- fixef(fit)
    vcov_mat <- vcov(fit)

    # For each dim_rank, slope = beta_date + beta_interaction * dim_rank
    date_idx <- which(names(coefs) == "date_c")
    int_idx <- which(names(coefs) == "date_c:dim_rank")

    if (length(int_idx) == 1) {
      for (dr in dim_ranks) {
        slope <- coefs[date_idx] + coefs[int_idx] * dr
        se <- sqrt(vcov_mat[date_idx, date_idx] +
                     dr^2 * vcov_mat[int_idx, int_idx] +
                     2 * dr * vcov_mat[date_idx, int_idx])
        dim_info <- dim_labels %>% filter(dim_rank == dr)
        dim_slope_rows <- c(dim_slope_rows, list(data.frame(
          family = fam,
          dim_rank = dr,
          tom_dimension = if (nrow(dim_info) > 0) dim_info$tom_dimension[1] else NA,
          validated_age_band = if (nrow(dim_info) > 0) dim_info$validated_age_band[1] else NA,
          slope_logodds = slope,
          slope_or = exp(slope),
          se = se,
          lo = exp(slope - 1.96 * se),
          hi = exp(slope + 1.96 * se),
          stringsAsFactors = FALSE
        )))
      }
    }
  }, error = function(e) {
    log_msg("  Dim slope extraction failed for ", fam, ": ", conditionMessage(e))
  })
}

# ---------------------------------------------------------------------------
# Model 3: correct ~ date_c * task + (1|item_id) — per family (format robustness)
# ---------------------------------------------------------------------------
log_msg("\n=== Model 3: date × task (per family) ===")
pred_task_rows <- list()

for (fam in families) {
  fam_df <- df %>% filter(family == fam)
  if (n_distinct(fam_df$date_years) < 2) next
  if (n_distinct(fam_df$task) < 2) {
    log_msg("Skipping M3:", fam, " — only one task")
    next
  }

  formula <- correct ~ date_c * task + (1 | item_id)
  fit <- safe_glmer(formula, fam_df, label = paste0("M3:", fam))
  if (is.null(fit)) next

  fe <- tidy(fit, effects = "fixed", conf.int = TRUE, exponentiate = TRUE) %>%
    mutate(family = fam, model_label = "M3_date_x_task")
  or_rows <- c(or_rows, list(fe))

  # Prediction grid by task
  tasks_present <- unique(fam_df$task)
  date_range <- seq(min(fam_df$date_c), max(fam_df$date_c), length.out = 50)
  grid <- expand.grid(date_c = date_range, task = tasks_present,
                      stringsAsFactors = FALSE) %>%
    mutate(task = factor(task, levels = levels(df$task)))
  tryCatch({
    preds <- predict(fit, newdata = grid, type = "response", re.form = NA)
    grid$pred <- preds
    grid$family <- fam
    grid$date_years <- grid$date_c + mean(fam_df$date_years)
    pred_task_rows <- c(pred_task_rows, list(grid))
  }, error = function(e) {
    log_msg("  Task prediction failed for ", fam, ": ", conditionMessage(e))
  })
}

# ---------------------------------------------------------------------------
# Model 4 (joint): correct ~ date_c * family + (1|item_id) — cross-family
# ---------------------------------------------------------------------------
log_msg("\n=== Model 4: date × family (joint, cross-family) ===")
if (n_distinct(df$family) >= 2 && n_distinct(df$date_years) >= 2) {
  formula <- correct ~ date_c * family + (1 | item_id)
  if (n_distinct(df$model) >= 3) {
    formula <- correct ~ date_c * family + (1 | item_id) + (1 | model)
  }
  fit_joint <- safe_glmer(formula, df, label = "M4:joint")
  if (!is.null(fit_joint)) {
    fe <- tidy(fit_joint, effects = "fixed", conf.int = TRUE, exponentiate = TRUE) %>%
      mutate(family = "ALL", model_label = "M4_date_x_family")
    or_rows <- c(or_rows, list(fe))
  }

  # LRT: compare date*family vs date-only
  fit_null <- safe_glmer(correct ~ date_c + (1 | item_id), df, label = "M4:null")
  if (!is.null(fit_joint) && !is.null(fit_null)) {
    lrt <- anova(fit_null, fit_joint)
    lrt_df <- data.frame(
      comparison = "date_only vs date_x_family",
      df = lrt$Df[2] - lrt$Df[1],
      chi2 = lrt$Chisq[2],
      p = lrt[["Pr(>Chisq)"]][2]
    )
    write_csv(lrt_df, file.path(out_dir, "glmm_lrt.csv"))
    log_msg("LRT (date vs date×family): chi2=", round(lrt_df$chi2, 2),
            " df=", lrt_df$df, " p=", format.pval(lrt_df$p))
  }
}

# ---------------------------------------------------------------------------
# Write outputs
# ---------------------------------------------------------------------------
if (length(or_rows) > 0) {
  or_table <- bind_rows(or_rows)
  write_csv(or_table, file.path(out_dir, "glmm_or_table.csv"))
  log_msg("\nWrote glmm_or_table.csv: ", nrow(or_table), " rows")
}

if (length(pred_rows) > 0) {
  pred_df <- bind_rows(pred_rows)
  write_csv(pred_df, file.path(out_dir, "glmm_pred_trajectory.csv"))
  log_msg("Wrote glmm_pred_trajectory.csv: ", nrow(pred_df), " rows")
}

if (length(obs_rows) > 0) {
  obs_df <- bind_rows(obs_rows)
  write_csv(obs_df, file.path(out_dir, "glmm_observed_points.csv"))
  log_msg("Wrote glmm_observed_points.csv: ", nrow(obs_df), " rows")
}

if (length(dim_slope_rows) > 0) {
  dim_slopes <- bind_rows(dim_slope_rows)
  write_csv(dim_slopes, file.path(out_dir, "glmm_dim_time_slopes.csv"))
  log_msg("Wrote glmm_dim_time_slopes.csv: ", nrow(dim_slopes), " rows")
}

if (length(pred_task_rows) > 0) {
  pred_task <- bind_rows(pred_task_rows)
  write_csv(pred_task, file.path(out_dir, "glmm_pred_by_task.csv"))
  log_msg("Wrote glmm_pred_by_task.csv: ", nrow(pred_task), " rows")
}

# Contamination caveat
log_msg("\nCAVEAT: These trajectory estimates do not model potential contamination.")
log_msg("The item bank is unpublished, mitigating training-set leakage (see ANALYSIS_PLAN.md")
log_msg("Threat 7), but the caveat should accompany any interpretation of time slopes.")

close(log_con)
cat(sprintf("\nAll outputs written to %s/\n", out_dir))
