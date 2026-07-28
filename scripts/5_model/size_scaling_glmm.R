#!/usr/bin/env Rscript
# size_scaling_glmm.R — Binomial GLMM for model size and release date scaling
#
# Fits item-level logistic mixed models to test whether ToM accuracy scales
# with model size (log10 params) and release date, across all 5 families.
# Claude and GPT use estimated parameter counts (see roster.py PARAMS_B).
#
# Usage:
#   Rscript scripts/5_model/size_scaling_glmm.R
#   Rscript scripts/5_model/size_scaling_glmm.R --item-csv results/item_level.csv

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
# Load & prep — all families with known/estimated parameter counts
# ---------------------------------------------------------------------------
ALL_FAMILIES <- c("Claude", "GPT", "Llama", "Qwen", "Mistral")

df <- read_csv(item_csv, show_col_types = FALSE) %>%
  filter(family %in% ALL_FAMILIES, !is.na(log_params), !is.na(date_years)) %>%
  mutate(
    correct       = as.integer(correct),
    family        = factor(family, levels = ALL_FAMILIES),
    tier          = factor(tier),
    model         = factor(model),
    item_id       = factor(item_id),
    log_params_c  = log_params - mean(log_params),
    date_c        = date_years - mean(date_years)
  )

cat(sprintf("Loaded %d rows (open-weight only): %d models, %d items, families: %s\n",
            nrow(df), nlevels(df$model), nlevels(df$item_id),
            paste(levels(df$family), collapse = ", ")))
cat(sprintf("  log_params range: %.2f – %.2f (%.1fB – %.1fB)\n",
            min(df$log_params), max(df$log_params),
            10^min(df$log_params), 10^max(df$log_params)))
cat(sprintf("  date_years range: %.2f – %.2f\n",
            min(df$date_years), max(df$date_years)))

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path(results_dir, "modeling", "size_scaling", stamp)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

log_file <- file.path(out_dir, "size_scaling_log.txt")
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
  log_msg("  n = ", nrow(data), ", models = ", n_distinct(data$model))

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
# Model S1: correct ~ log_params_c * date_c + family + (1|item_id) + (1|model)
# ---------------------------------------------------------------------------
log_msg("\n=== Model S1: size × date + family (main model) ===")
fit_s1 <- safe_glmer(
  correct ~ log_params_c * date_c + family + (1 | item_id) + (1 | model),
  df, label = "S1"
)

or_rows <- list()
if (!is.null(fit_s1)) {
  fe <- tidy(fit_s1, effects = "fixed", conf.int = TRUE, exponentiate = TRUE) %>%
    mutate(model_label = "S1_size_x_date")
  or_rows <- c(or_rows, list(fe))
}

# ---------------------------------------------------------------------------
# Model S2: correct ~ log_params_c * family + (1|item_id) + (1|model)
# ---------------------------------------------------------------------------
log_msg("\n=== Model S2: size × family (size effect per family) ===")
fit_s2 <- safe_glmer(
  correct ~ log_params_c * family + (1 | item_id) + (1 | model),
  df, label = "S2"
)

if (!is.null(fit_s2)) {
  fe <- tidy(fit_s2, effects = "fixed", conf.int = TRUE, exponentiate = TRUE) %>%
    mutate(model_label = "S2_size_x_family")
  or_rows <- c(or_rows, list(fe))
}

# ---------------------------------------------------------------------------
# Model S3: correct ~ date_c * family + (1|item_id) + (1|model)
# ---------------------------------------------------------------------------
log_msg("\n=== Model S3: date × family (open-weight subset) ===")
fit_s3 <- safe_glmer(
  correct ~ date_c * family + (1 | item_id) + (1 | model),
  df, label = "S3"
)

if (!is.null(fit_s3)) {
  fe <- tidy(fit_s3, effects = "fixed", conf.int = TRUE, exponentiate = TRUE) %>%
    mutate(model_label = "S3_date_x_family")
  or_rows <- c(or_rows, list(fe))
}

# ---------------------------------------------------------------------------
# Model S4: correct ~ log_params_c * date_c * family + (1|item_id) + (1|model)
# ---------------------------------------------------------------------------
log_msg("\n=== Model S4: three-way interaction (may not converge) ===")
fit_s4 <- safe_glmer(
  correct ~ log_params_c * date_c * family + (1 | item_id) + (1 | model),
  df, label = "S4"
)

if (!is.null(fit_s4)) {
  fe <- tidy(fit_s4, effects = "fixed", conf.int = TRUE, exponentiate = TRUE) %>%
    mutate(model_label = "S4_three_way")
  or_rows <- c(or_rows, list(fe))
}

# ---------------------------------------------------------------------------
# Likelihood ratio tests
# ---------------------------------------------------------------------------
log_msg("\n=== Likelihood ratio tests ===")
lrt_rows <- list()

fit_null <- safe_glmer(
  correct ~ 1 + (1 | item_id) + (1 | model),
  df, label = "null"
)

if (!is.null(fit_s1) && !is.null(fit_null)) {
  lrt <- anova(fit_null, fit_s1)
  lrt_rows <- c(lrt_rows, list(data.frame(
    comparison = "null vs S1 (size*date+family)",
    df = lrt$Df[2] - lrt$Df[1],
    chi2 = lrt$Chisq[2],
    p = lrt[["Pr(>Chisq)"]][2]
  )))
  log_msg("null vs S1: chi2=", round(lrt$Chisq[2], 2),
          " df=", lrt$Df[2] - lrt$Df[1],
          " p=", format.pval(lrt[["Pr(>Chisq)"]][2]))
}

if (!is.null(fit_s1) && !is.null(fit_s2)) {
  lrt <- anova(fit_s2, fit_s1)
  lrt_rows <- c(lrt_rows, list(data.frame(
    comparison = "S2 (size only) vs S1 (size+date)",
    df = abs(lrt$Df[2] - lrt$Df[1]),
    chi2 = lrt$Chisq[2],
    p = lrt[["Pr(>Chisq)"]][2]
  )))
  log_msg("S2 vs S1: chi2=", round(lrt$Chisq[2], 2),
          " p=", format.pval(lrt[["Pr(>Chisq)"]][2]))
}

if (!is.null(fit_s1) && !is.null(fit_s3)) {
  lrt <- anova(fit_s3, fit_s1)
  lrt_rows <- c(lrt_rows, list(data.frame(
    comparison = "S3 (date only) vs S1 (size+date)",
    df = abs(lrt$Df[2] - lrt$Df[1]),
    chi2 = lrt$Chisq[2],
    p = lrt[["Pr(>Chisq)"]][2]
  )))
  log_msg("S3 vs S1: chi2=", round(lrt$Chisq[2], 2),
          " p=", format.pval(lrt[["Pr(>Chisq)"]][2]))
}

# ---------------------------------------------------------------------------
# Prediction grids
# ---------------------------------------------------------------------------
log_msg("\n=== Generating prediction grids ===")

mean_log_params <- mean(df$log_params)
mean_date_years <- mean(df$date_years)

# (a) Predictions over size, at mean date, per family
if (!is.null(fit_s2)) {
  log_params_range <- seq(min(df$log_params), max(df$log_params), length.out = 50)
  grid_size <- expand.grid(
    log_params_c = log_params_range - mean_log_params,
    family = levels(df$family),
    stringsAsFactors = FALSE
  ) %>% mutate(family = factor(family, levels = ALL_FAMILIES))

  tryCatch({
    grid_size$pred <- predict(fit_s2, newdata = grid_size, type = "response", re.form = NA)
    preds_link <- predict(fit_s2, newdata = grid_size, type = "link", re.form = NA)
    mm <- model.matrix(~ log_params_c * family, data = grid_size)
    V <- vcov(fit_s2)
    V_fe <- as.matrix(V[rownames(V) %in% colnames(mm), colnames(V) %in% colnames(mm)])
    se <- sqrt(pmax(0, rowSums((mm %*% V_fe) * mm)))
    grid_size$pred_lo <- plogis(preds_link - 1.96 * se)
    grid_size$pred_hi <- plogis(preds_link + 1.96 * se)
    grid_size$log_params <- grid_size$log_params_c + mean_log_params
    grid_size$params_b <- 10^grid_size$log_params
    write_csv(grid_size, file.path(out_dir, "size_scaling_pred_by_size.csv"))
    log_msg("Wrote size_scaling_pred_by_size.csv: ", nrow(grid_size), " rows")
  }, error = function(e) {
    log_msg("  Size prediction grid failed: ", conditionMessage(e))
  })
}

# (b) Predictions over date, at mean size, per family
if (!is.null(fit_s3)) {
  date_range <- seq(min(df$date_years), max(df$date_years), length.out = 50)
  grid_date <- expand.grid(
    date_c = date_range - mean_date_years,
    family = levels(df$family),
    stringsAsFactors = FALSE
  ) %>% mutate(family = factor(family, levels = ALL_FAMILIES))

  tryCatch({
    grid_date$pred <- predict(fit_s3, newdata = grid_date, type = "response", re.form = NA)
    preds_link <- predict(fit_s3, newdata = grid_date, type = "link", re.form = NA)
    mm <- model.matrix(~ date_c * family, data = grid_date)
    V <- vcov(fit_s3)
    V_fe <- as.matrix(V[rownames(V) %in% colnames(mm), colnames(V) %in% colnames(mm)])
    se <- sqrt(pmax(0, rowSums((mm %*% V_fe) * mm)))
    grid_date$pred_lo <- plogis(preds_link - 1.96 * se)
    grid_date$pred_hi <- plogis(preds_link + 1.96 * se)
    grid_date$date_years <- grid_date$date_c + mean_date_years
    write_csv(grid_date, file.path(out_dir, "size_scaling_pred_by_date.csv"))
    log_msg("Wrote size_scaling_pred_by_date.csv: ", nrow(grid_date), " rows")
  }, error = function(e) {
    log_msg("  Date prediction grid failed: ", conditionMessage(e))
  })
}

# (c) 2D prediction grid over (size, date) per family
if (!is.null(fit_s1)) {
  log_params_range <- seq(min(df$log_params), max(df$log_params), length.out = 30)
  date_range <- seq(min(df$date_years), max(df$date_years), length.out = 30)
  grid_2d <- expand.grid(
    log_params_c = log_params_range - mean_log_params,
    date_c = date_range - mean_date_years,
    family = levels(df$family),
    stringsAsFactors = FALSE
  ) %>% mutate(family = factor(family, levels = ALL_FAMILIES))

  tryCatch({
    grid_2d$pred <- predict(fit_s1, newdata = grid_2d, type = "response", re.form = NA)
    grid_2d$log_params <- grid_2d$log_params_c + mean_log_params
    grid_2d$params_b <- 10^grid_2d$log_params
    grid_2d$date_years <- grid_2d$date_c + mean_date_years
    write_csv(grid_2d, file.path(out_dir, "size_scaling_pred_interaction.csv"))
    log_msg("Wrote size_scaling_pred_interaction.csv: ", nrow(grid_2d), " rows")
  }, error = function(e) {
    log_msg("  2D prediction grid failed: ", conditionMessage(e))
  })
}

# ---------------------------------------------------------------------------
# Observed per-model summaries
# ---------------------------------------------------------------------------
obs <- df %>%
  group_by(family, tier, model, date_years, release_date, params_b, log_params) %>%
  summarise(accuracy = mean(correct), n = n(), .groups = "drop")
write_csv(obs, file.path(out_dir, "size_scaling_observed.csv"))
log_msg("Wrote size_scaling_observed.csv: ", nrow(obs), " rows")

# ---------------------------------------------------------------------------
# Write outputs
# ---------------------------------------------------------------------------
if (length(or_rows) > 0) {
  or_table <- bind_rows(or_rows)
  write_csv(or_table, file.path(out_dir, "size_scaling_or_table.csv"))
  log_msg("\nWrote size_scaling_or_table.csv: ", nrow(or_table), " rows")
}

if (length(lrt_rows) > 0) {
  lrt_df <- bind_rows(lrt_rows)
  write_csv(lrt_df, file.path(out_dir, "size_scaling_lrt.csv"))
  log_msg("Wrote size_scaling_lrt.csv: ", nrow(lrt_df), " rows")
}

# Variance components for all fitted models
vc_rows <- list()
for (nm in c("S1", "S2", "S3", "S4")) {
  fit <- get(paste0("fit_s", gsub("S", "", nm)), inherits = FALSE)
  if (is.null(fit)) next
  vc <- as.data.frame(VarCorr(fit))
  vc$model_label <- nm
  vc_rows <- c(vc_rows, list(vc))
}
if (length(vc_rows) > 0) {
  vc_df <- bind_rows(vc_rows)
  write_csv(vc_df, file.path(out_dir, "size_scaling_variance_components.csv"))
  log_msg("Wrote size_scaling_variance_components.csv")
}

# ---------------------------------------------------------------------------
# Caveats
# ---------------------------------------------------------------------------
log_msg("\nCAVEATS:")
log_msg("1. MoE models (e.g. Llama-4-Scout 109B, Qwen3-235b, GPT-4 1760B) use TOTAL params,")
log_msg("   not active params. The (1|model) random intercept absorbs some of this mismatch.")
log_msg("2. Size and release date are moderately correlated within families")
log_msg("   (newer generations tend to come in more size variants).")
log_msg("3. Claude and GPT use ESTIMATED parameter counts (widely cited, not official).")
log_msg("   Claude: Haiku ~20B, Sonnet ~70B, Opus ~175B, Fable ~70B.")
log_msg("   GPT: 3.5-turbo ~20B, 4 ~1760B MoE, 4o ~200B, 4o-mini ~8B, o-series ~70-200B.")

close(log_con)
cat(sprintf("\nAll outputs written to %s/\n", out_dir))
