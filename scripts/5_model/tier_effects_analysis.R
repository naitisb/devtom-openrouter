#!/usr/bin/env Rscript
# tier_effects_analysis.R — Categorical tier effect in GLM, GLMM, and IRT
#
# Tests whether model tier (e.g., "Claude Opus", "Llama small") predicts
# ToM accuracy above and beyond developmental age and task format.
#
# Three approaches:
#   1. Pooled GLM: correct ~ age_mid * tier + task (per dimension)
#   2. GLMM:       correct ~ age_mid * tier + task + (1|model) + (1|item_id)
#   3. IRT:        ANOVA of theta ~ tier (post-hoc on Rasch thetas)
#
# Each approach includes LRT comparing models with/without tier.

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(lme4)
  library(mirt)
})

tidy_glm <- function(fit) {
  s <- summary(fit)$coefficients
  tibble(
    term = rownames(s),
    estimate = s[, "Estimate"],
    std.error = s[, "Std. Error"],
    statistic = s[, "z value"],
    p.value = s[, "Pr(>|z|)"]
  )
}

tidy_glmer <- function(fit) {
  s <- summary(fit)$coefficients
  tibble(
    term = rownames(s),
    estimate = s[, "Estimate"],
    std.error = s[, "Std. Error"],
    statistic = s[, "z value"],
    p.value = s[, "Pr(>|z|)"]
  )
}

source("scripts/6_visualize/_theme.R")

ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path("results", "modeling", "tier_effects", ts)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
cat("Output dir:", out_dir, "\n")

sink(file.path(out_dir, "tier_effects_log.txt"), split = TRUE)
cat("=== Tier Effects Analysis ===\n")
cat("Timestamp:", ts, "\n\n")

# =========================================================================
# Load data
# =========================================================================
df <- read_csv("results/item_level.csv", show_col_types = FALSE) %>%
  filter(family %in% FAMILY_ORDER) %>%
  mutate(tier = factor(tier, levels = intersect(TYPE_ORDER, unique(tier))))

cat("Total rows:", nrow(df), "\n")
cat("Models:", n_distinct(df$model), "\n")
cat("Tiers:", n_distinct(df$tier), "\n")
cat("Tier counts:\n")
df %>% distinct(model, tier) %>% count(tier) %>% print(n = 25)
cat("\n")

# =========================================================================
# 1. POOLED GLM WITH TIER (per dimension)
# =========================================================================
cat("=== 1. Pooled GLM with Tier ===\n\n")

glm_results <- list()
glm_lrt_results <- list()
glm_pred_results <- list()

for (dim_name in DIMENSION_DEVELOPMENTAL_ORDER) {
  dim_data <- df %>% filter(tom_dimension == dim_name)
  n_tiers <- n_distinct(dim_data$tier)
  has_both_tasks <- n_distinct(dim_data$task) >= 2

  cat(sprintf("  %s (%d obs, %d tiers, %d tasks)...\n",
              dim_name, nrow(dim_data), n_tiers, n_distinct(dim_data$task)))

  tryCatch({
    if (has_both_tasks) {
      fit_null  <- glm(correct ~ age_mid + task, data = dim_data, family = binomial)
      fit_tier  <- glm(correct ~ age_mid + tier + task, data = dim_data, family = binomial)
      fit_inter <- glm(correct ~ age_mid * tier + task, data = dim_data, family = binomial)
    } else {
      fit_null  <- glm(correct ~ age_mid, data = dim_data, family = binomial)
      fit_tier  <- glm(correct ~ age_mid + tier, data = dim_data, family = binomial)
      fit_inter <- glm(correct ~ age_mid * tier, data = dim_data, family = binomial)
    }

    lrt_main <- anova(fit_null, fit_tier, test = "Chisq")
    lrt_inter <- anova(fit_tier, fit_inter, test = "Chisq")

    glm_lrt_results[[dim_name]] <- tibble(
      tom_dimension = dim_name,
      test = c("tier_main", "tier_x_age"),
      df_diff = c(lrt_main$Df[2], lrt_inter$Df[2]),
      deviance_diff = c(lrt_main$Deviance[2], lrt_inter$Deviance[2]),
      p_value = c(lrt_main$`Pr(>Chi)`[2], lrt_inter$`Pr(>Chi)`[2])
    )

    coefs_main <- tidy_glm(fit_tier)
    coefs_main$tom_dimension <- dim_name
    coefs_main$model_type <- "main_effect"
    glm_results[[paste0(dim_name, "_main")]] <- coefs_main

    coefs_inter <- tidy_glm(fit_inter)
    coefs_inter$tom_dimension <- dim_name
    coefs_inter$model_type <- "interaction"
    glm_results[[paste0(dim_name, "_inter")]] <- coefs_inter

    # Predictions from main-effect model at each age point per tier
    pred_grid <- expand.grid(
      age_mid = seq(min(dim_data$age_mid), max(dim_data$age_mid), length.out = 50),
      tier = levels(dim_data$tier)[levels(dim_data$tier) %in% unique(dim_data$tier)],
      stringsAsFactors = FALSE
    )
    if (has_both_tasks) {
      ref_task <- levels(factor(dim_data$task))[1]
      pred_grid$task <- ref_task
    }
    pred_grid$tier <- factor(pred_grid$tier, levels = levels(dim_data$tier))
    pred_grid$pred_prob <- predict(fit_tier, newdata = pred_grid, type = "response")
    pred_grid$tom_dimension <- dim_name
    glm_pred_results[[dim_name]] <- pred_grid

    cat(sprintf("    Tier main effect LRT: Chi²=%.1f, df=%d, p=%.2e\n",
                lrt_main$Deviance[2], lrt_main$Df[2], lrt_main$`Pr(>Chi)`[2]))
    cat(sprintf("    Tier×age interaction LRT: Chi²=%.1f, df=%d, p=%.2e\n",
                lrt_inter$Deviance[2], lrt_inter$Df[2], lrt_inter$`Pr(>Chi)`[2]))
  }, error = function(e) {
    cat(sprintf("    GLM failed: %s\n", conditionMessage(e)))
  })
}

glm_coefs <- bind_rows(glm_results)
glm_lrt <- bind_rows(glm_lrt_results)
glm_preds <- bind_rows(glm_pred_results)

write_csv(glm_coefs, file.path(out_dir, "glm_tier_coefficients.csv"))
write_csv(glm_lrt, file.path(out_dir, "glm_tier_lrt.csv"))
write_csv(glm_preds, file.path(out_dir, "glm_tier_predictions.csv"))

cat(sprintf("\n  GLM: %d coefficient rows, %d LRT tests, %d prediction rows\n\n",
            nrow(glm_coefs), nrow(glm_lrt), nrow(glm_preds)))

# =========================================================================
# 2. GLMM WITH TIER (per dimension)
# =========================================================================
cat("=== 2. GLMM with Tier ===\n\n")

glmm_results <- list()
glmm_lrt_results <- list()
glmm_pred_results <- list()

for (dim_name in DIMENSION_DEVELOPMENTAL_ORDER) {
  dim_data <- df %>% filter(tom_dimension == dim_name)
  has_both_tasks <- n_distinct(dim_data$task) >= 2
  n_models <- n_distinct(dim_data$model)

  cat(sprintf("  %s (%d models)...\n", dim_name, n_models))

  tryCatch({
    ctrl <- glmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 100000))

    # Null model (no tier)
    fit_null <- suppressWarnings({
      if (has_both_tasks) {
        glmer(correct ~ age_mid + task + (1 | model) + (1 | item_id),
              data = dim_data, family = binomial, control = ctrl)
      } else {
        glmer(correct ~ age_mid + (1 | model) + (1 | item_id),
              data = dim_data, family = binomial, control = ctrl)
      }
    })

    # Tier main effect
    fit_tier <- suppressWarnings({
      if (has_both_tasks) {
        glmer(correct ~ age_mid + tier + task + (1 | model) + (1 | item_id),
              data = dim_data, family = binomial, control = ctrl)
      } else {
        glmer(correct ~ age_mid + tier + (1 | model) + (1 | item_id),
              data = dim_data, family = binomial, control = ctrl)
      }
    })

    # Tier × age interaction
    fit_inter <- suppressWarnings({
      if (has_both_tasks) {
        glmer(correct ~ age_mid * tier + task + (1 | model) + (1 | item_id),
              data = dim_data, family = binomial, control = ctrl)
      } else {
        glmer(correct ~ age_mid * tier + (1 | model) + (1 | item_id),
              data = dim_data, family = binomial, control = ctrl)
      }
    })

    lrt_main <- anova(fit_null, fit_tier)
    lrt_inter <- anova(fit_tier, fit_inter)

    if (isSingular(fit_tier)) cat("    Note: tier model is singular\n")

    lrt_main_df <- as.data.frame(lrt_main)
    lrt_inter_df <- as.data.frame(lrt_inter)
    chi_df_col <- grep("Chi Df|Df", names(lrt_main_df), value = TRUE)[1]
    chi_col <- grep("Chisq", names(lrt_main_df), value = TRUE)[1]
    p_col <- grep("Pr\\(", names(lrt_main_df), value = TRUE)[1]

    glmm_lrt_results[[dim_name]] <- tibble(
      tom_dimension = dim_name,
      test = c("tier_main", "tier_x_age"),
      chisq = c(lrt_main_df[2, chi_col], lrt_inter_df[2, chi_col]),
      df_diff = c(lrt_main_df[2, chi_df_col], lrt_inter_df[2, chi_df_col]),
      p_value = c(lrt_main_df[2, p_col], lrt_inter_df[2, p_col]),
      aic_null = c(AIC(fit_null), AIC(fit_tier)),
      aic_full = c(AIC(fit_tier), AIC(fit_inter))
    )

    fe <- tidy_glmer(fit_tier)
    fe$tom_dimension <- dim_name
    glmm_results[[dim_name]] <- fe

    # Predictions from tier main-effect model
    pred_grid <- expand.grid(
      age_mid = seq(min(dim_data$age_mid), max(dim_data$age_mid), length.out = 50),
      tier = levels(dim_data$tier)[levels(dim_data$tier) %in% unique(dim_data$tier)],
      stringsAsFactors = FALSE
    )
    if (has_both_tasks) {
      pred_grid$task <- levels(factor(dim_data$task))[1]
    }
    pred_grid$tier <- factor(pred_grid$tier, levels = levels(dim_data$tier))
    pred_grid$pred_prob <- predict(fit_tier, newdata = pred_grid, type = "response",
                                   re.form = NA)
    pred_grid$tom_dimension <- dim_name
    glmm_pred_results[[dim_name]] <- pred_grid

    cat(sprintf("    Tier main effect LRT: Chi²=%.1f, df=%d, p=%.2e\n",
                lrt_main$Chisq[2], lrt_main$`Chi Df`[2], lrt_main$`Pr(>Chisq)`[2]))
    cat(sprintf("    Tier×age interaction LRT: Chi²=%.1f, df=%d, p=%.2e\n",
                lrt_inter$Chisq[2], lrt_inter$`Chi Df`[2], lrt_inter$`Pr(>Chisq)`[2]))
  }, error = function(e) {
    cat(sprintf("    GLMM failed: %s\n", conditionMessage(e)))
  })
}

glmm_coefs <- bind_rows(glmm_results)
glmm_lrt <- bind_rows(glmm_lrt_results)
glmm_preds <- bind_rows(glmm_pred_results)

write_csv(glmm_coefs, file.path(out_dir, "glmm_tier_coefficients.csv"))
write_csv(glmm_lrt, file.path(out_dir, "glmm_tier_lrt.csv"))
write_csv(glmm_preds, file.path(out_dir, "glmm_tier_predictions.csv"))

cat(sprintf("\n  GLMM: %d coefficient rows, %d LRT tests, %d prediction rows\n\n",
            nrow(glmm_coefs), nrow(glmm_lrt), nrow(glmm_preds)))

# =========================================================================
# 3. IRT THETA ~ TIER (post-hoc ANOVA)
# =========================================================================
cat("=== 3. IRT Theta ~ Tier ===\n\n")

# Load existing IRT results
irt_dir <- list.dirs("results/modeling/developmental_age_mapping",
                     recursive = FALSE, full.names = TRUE)
irt_dir <- sort(irt_dir, decreasing = TRUE)[1]
irt_csv <- file.path(irt_dir, "irt_age_equivalents.csv")

if (file.exists(irt_csv)) {
  irt_ages <- read_csv(irt_csv, show_col_types = FALSE) %>%
    left_join(df %>% distinct(model, tier, family), by = "model") %>%
    filter(!is.na(tier)) %>%
    mutate(tier = factor(tier, levels = intersect(TYPE_ORDER, unique(tier))))

  cat("  IRT data:", nrow(irt_ages), "rows across",
      n_distinct(irt_ages$tom_dimension), "dimensions\n\n")

  irt_anova_results <- list()
  irt_means_results <- list()

  for (dim_name in unique(irt_ages$tom_dimension)) {
    dim_theta <- irt_ages %>% filter(tom_dimension == dim_name)
    n_tiers <- n_distinct(dim_theta$tier)

    if (n_tiers >= 2) {
      fit <- aov(theta ~ tier, data = dim_theta)
      f_tbl <- summary(fit)[[1]]
      eta_sq <- f_tbl["tier", "Sum Sq"] /
        sum(f_tbl[, "Sum Sq"])

      irt_anova_results[[dim_name]] <- tibble(
        tom_dimension = dim_name,
        f_stat = f_tbl["tier", "F value"],
        df1 = f_tbl["tier", "Df"],
        df2 = f_tbl["Residuals", "Df"],
        p_value = f_tbl["tier", "Pr(>F)"],
        eta_squared = eta_sq,
        n_tiers = n_tiers,
        n_models = nrow(dim_theta)
      )

      tier_means <- dim_theta %>%
        group_by(tier, family) %>%
        summarise(
          n = n(),
          mean_theta = mean(theta, na.rm = TRUE),
          sd_theta = sd(theta, na.rm = TRUE),
          mean_irt_age = mean(irt_age_eq, na.rm = TRUE),
          sd_irt_age = sd(irt_age_eq, na.rm = TRUE),
          .groups = "drop"
        ) %>%
        mutate(tom_dimension = dim_name)
      irt_means_results[[dim_name]] <- tier_means

      cat(sprintf("  %s: F(%d,%d)=%.2f, p=%.2e, η²=%.3f\n",
                  dim_name, f_tbl["tier", "Df"], f_tbl["Residuals", "Df"],
                  f_tbl["tier", "F value"], f_tbl["tier", "Pr(>F)"], eta_sq))
    }
  }

  irt_anova <- bind_rows(irt_anova_results)
  irt_means <- bind_rows(irt_means_results)

  write_csv(irt_anova, file.path(out_dir, "irt_tier_anova.csv"))
  write_csv(irt_means, file.path(out_dir, "irt_tier_means.csv"))
  write_csv(irt_ages, file.path(out_dir, "irt_theta_by_tier.csv"))

  cat(sprintf("\n  IRT ANOVA: %d dimensions tested\n", nrow(irt_anova)))
  cat(sprintf("  Significant (p < .05): %d / %d\n",
              sum(irt_anova$p_value < 0.05), nrow(irt_anova)))
  cat(sprintf("  Mean η²: %.3f\n\n", mean(irt_anova$eta_squared)))
} else {
  cat("  IRT CSV not found at:", irt_csv, "\n\n")
}

# =========================================================================
# Summary
# =========================================================================
cat("=== Summary of Tier Effects ===\n\n")

cat("GLM Tier Main Effects (LRT p-values by dimension):\n")
glm_lrt %>%
  filter(test == "tier_main") %>%
  mutate(sig = ifelse(p_value < .001, "***",
               ifelse(p_value < .01, "**",
               ifelse(p_value < .05, "*", "ns")))) %>%
  select(tom_dimension, deviance_diff, df_diff, p_value, sig) %>%
  print(n = 12)

cat("\nGLMM Tier Main Effects (LRT p-values by dimension):\n")
glmm_lrt %>%
  filter(test == "tier_main") %>%
  mutate(sig = ifelse(p_value < .001, "***",
               ifelse(p_value < .01, "**",
               ifelse(p_value < .05, "*", "ns")))) %>%
  select(tom_dimension, chisq, any_of("df_diff"), p_value, sig) %>%
  print(n = 12)

cat("\nIRT ANOVA (F-tests by dimension):\n")
irt_anova %>%
  mutate(sig = ifelse(p_value < .001, "***",
               ifelse(p_value < .01, "**",
               ifelse(p_value < .05, "*", "ns")))) %>%
  select(tom_dimension, f_stat, df1, df2, p_value, eta_squared, sig) %>%
  print(n = 12)

cat("\n=== Files Written ===\n")
list.files(out_dir) %>% cat(sep = "\n")

sink()
cat("Done. Output in:", out_dir, "\n")
