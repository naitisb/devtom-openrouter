#!/usr/bin/env Rscript
# developmental_age_mapping.R — Per-dimension & per-construct developmental age
#
# Dual pipeline:
#   A) Mastery-based age (non-parametric): highest age_mid with ≥80% accuracy
#   B) Model-based: per-model GLM, cross-model GLMM, MIRT age-anchoring
#
# Produces 6 summary tables (2 row-groupings × 3 task filters) and
# model-based age-equivalent CSVs.

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(lme4)
  library(mirt)
})

source("scripts/6_visualize/_theme.R")

ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path("results", "modeling", "developmental_age_mapping", ts)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
cat("Output dir:", out_dir, "\n")

sink(file.path(out_dir, "age_mapping_log.txt"), split = TRUE)
cat("=== Developmental Age Mapping Analysis ===\n")
cat("Timestamp:", ts, "\n\n")

# =========================================================================
# S0: Load data
# =========================================================================
item_csv <- "results/item_level.csv"
if (!file.exists(item_csv)) stop("Missing: ", item_csv)
df <- read_csv(item_csv, show_col_types = FALSE) %>%
  filter(family %in% FAMILY_ORDER)

cat("Total rows:", nrow(df), "\n")
cat("Models:", n_distinct(df$model), "\n")
cat("Dimensions:", n_distinct(df$tom_dimension), "\n")
cat("Constructs:", n_distinct(df$tom_construct), "\n")
cat("Task types:", paste(unique(df$task), collapse = ", "), "\n\n")

models_meta <- df %>%
  distinct(model, family, tier, release_date, date_years, params_b, log_params) %>%
  arrange(release_date)

TASK_FILTERS <- list(
  all = NULL,
  mcq = "tom_12dim_mcq",
  frq = "tom_12dim_freeresponse"
)

# Dimension-to-construct mapping
dim_con_map <- df %>% distinct(tom_dimension, tom_construct)
DIM_TO_CONSTRUCT <- setNames(dim_con_map$tom_construct, dim_con_map$tom_dimension)

# =========================================================================
# S1: Pipeline A — Mastery-based age
# =========================================================================
cat("=== Pipeline A: Mastery-Based Age ===\n\n")

compute_mastery_age <- function(data, scope_col, scope_val, model_name) {
  sub <- data %>% filter(.data[[scope_col]] == scope_val)
  if (nrow(sub) == 0) return(NA_real_)

  age_acc <- sub %>%
    group_by(age_mid) %>%
    summarise(acc = sum(correct) / n(), .groups = "drop") %>%
    arrange(age_mid)

  passed <- age_acc %>% filter(acc >= 0.80)
  if (nrow(passed) == 0) return(NA_real_)
  max(passed$age_mid)
}

mastery_results <- list()

for (filter_name in names(TASK_FILTERS)) {
  filter_val <- TASK_FILTERS[[filter_name]]
  df_filtered <- if (is.null(filter_val)) df else df %>% filter(task == filter_val)

  cat(sprintf("  Filter: %s (%d rows)\n", filter_name, nrow(df_filtered)))

  # Per model × dimension
  dim_mastery <- df_filtered %>%
    group_by(model, tom_dimension) %>%
    group_modify(function(grp, key) {
      age_acc <- grp %>%
        group_by(age_mid) %>%
        summarise(acc = sum(correct) / n(), n = n(), .groups = "drop")
      passed <- age_acc %>% filter(acc >= 0.80)
      mastery_age <- if (nrow(passed) == 0) NA_real_ else max(passed$age_mid)
      tibble(mastery_age = mastery_age,
             n_age_points = nrow(age_acc),
             n_items = sum(age_acc$n),
             mean_acc = sum(grp$correct) / nrow(grp))
    }) %>%
    ungroup() %>%
    mutate(task_filter = filter_name)

  # Per model × construct
  con_mastery <- df_filtered %>%
    group_by(model, tom_construct) %>%
    group_modify(function(grp, key) {
      age_acc <- grp %>%
        group_by(age_mid) %>%
        summarise(acc = sum(correct) / n(), n = n(), .groups = "drop")
      passed <- age_acc %>% filter(acc >= 0.80)
      mastery_age <- if (nrow(passed) == 0) NA_real_ else max(passed$age_mid)
      tibble(mastery_age = mastery_age,
             n_age_points = nrow(age_acc),
             n_items = sum(age_acc$n),
             mean_acc = sum(grp$correct) / nrow(grp))
    }) %>%
    ungroup() %>%
    mutate(task_filter = filter_name)

  # Per model overall
  ovr_mastery <- df_filtered %>%
    group_by(model) %>%
    group_modify(function(grp, key) {
      age_acc <- grp %>%
        group_by(age_mid) %>%
        summarise(acc = sum(correct) / n(), n = n(), .groups = "drop")
      passed <- age_acc %>% filter(acc >= 0.80)
      mastery_age <- if (nrow(passed) == 0) NA_real_ else max(passed$age_mid)
      tibble(mastery_age = mastery_age,
             n_age_points = nrow(age_acc),
             n_items = sum(age_acc$n),
             mean_acc = sum(grp$correct) / nrow(grp))
    }) %>%
    ungroup() %>%
    mutate(task_filter = filter_name)

  mastery_results[[filter_name]] <- list(
    dimension = dim_mastery,
    construct = con_mastery,
    overall   = ovr_mastery
  )
}

mastery_dim_all <- bind_rows(lapply(mastery_results, `[[`, "dimension"))
mastery_con_all <- bind_rows(lapply(mastery_results, `[[`, "construct"))
mastery_ovr_all <- bind_rows(lapply(mastery_results, `[[`, "overall"))

write_csv(mastery_dim_all, file.path(out_dir, "mastery_age_dimension.csv"))
write_csv(mastery_con_all, file.path(out_dir, "mastery_age_construct.csv"))
write_csv(mastery_ovr_all, file.path(out_dir, "mastery_age_overall.csv"))

cat("  Mastery CSVs written.\n\n")

# =========================================================================
# S2: Build 6 summary tables
# =========================================================================
cat("=== Building Summary Tables ===\n\n")

build_summary_table <- function(dim_mastery, filter_name, group_by_tier = FALSE) {
  dim_wide <- dim_mastery %>%
    filter(task_filter == filter_name) %>%
    left_join(models_meta %>% select(model, family, tier, release_date),
              by = "model") %>%
    select(model, family, tier, release_date, tom_dimension, mastery_age)

  if (group_by_tier) {
    # Collapse across models within each tier
    tier_dim <- dim_wide %>%
      group_by(tier, family, tom_dimension) %>%
      summarise(
        mean_age = mean(mastery_age, na.rm = TRUE),
        sd_age = sd(mastery_age, na.rm = TRUE),
        n_models = n(),
        .groups = "drop"
      )

    # Dimension columns (ordered by DIMENSION_DEVELOPMENTAL_ORDER)
    dim_cols <- tier_dim %>%
      mutate(cell = sprintf("%.1f (%.1f)", mean_age, replace_na(sd_age, 0)),
             tom_dimension = factor(tom_dimension, levels = DIMENSION_DEVELOPMENTAL_ORDER)) %>%
      arrange(tom_dimension) %>%
      select(tier, family, tom_dimension, cell) %>%
      pivot_wider(names_from = tom_dimension, values_from = cell)

    # Construct columns: mean ± SD of dimension mastery ages within construct, across models in tier
    construct_data <- dim_wide %>%
      mutate(tom_construct = DIM_TO_CONSTRUCT[tom_dimension])

    con_cols_list <- list()
    for (con in CONSTRUCT_DEVELOPMENTAL_ORDER) {
      con_dims <- names(DIM_TO_CONSTRUCT[DIM_TO_CONSTRUCT == con])
      con_sub <- construct_data %>%
        filter(tom_dimension %in% con_dims) %>%
        group_by(tier, family, model) %>%
        summarise(model_con_mean = mean(mastery_age, na.rm = TRUE), .groups = "drop") %>%
        group_by(tier, family) %>%
        summarise(
          mean_age = mean(model_con_mean, na.rm = TRUE),
          sd_age = sd(model_con_mean, na.rm = TRUE),
          .groups = "drop"
        ) %>%
        mutate(cell = sprintf("%.1f (%.1f)", mean_age, replace_na(sd_age, 0)))
      con_cols_list[[con]] <- con_sub %>% select(tier, !!con := cell)
    }

    # All column: mean ± SD of all 12 dimension mastery ages across models in tier
    all_col <- dim_wide %>%
      group_by(tier, family, model) %>%
      summarise(model_mean = mean(mastery_age, na.rm = TRUE), .groups = "drop") %>%
      group_by(tier, family) %>%
      summarise(
        mean_age = mean(model_mean, na.rm = TRUE),
        sd_age = sd(model_mean, na.rm = TRUE),
        n_models = n(),
        .groups = "drop"
      ) %>%
      mutate(All = sprintf("%.1f (%.1f)", mean_age, replace_na(sd_age, 0)))

    # Merge
    result <- all_col %>% select(tier, family, n_models, All)
    for (con in CONSTRUCT_DEVELOPMENTAL_ORDER) {
      result <- result %>% left_join(con_cols_list[[con]], by = "tier")
    }
    result <- result %>% left_join(dim_cols, by = c("tier", "family"))

    # Order by TYPE_ORDER
    result <- result %>%
      mutate(tier = factor(tier, levels = TYPE_ORDER)) %>%
      arrange(tier) %>%
      mutate(tier = as.character(tier))

  } else {
    # Per-model table
    dim_pivot <- dim_wide %>%
      mutate(cell = sprintf("%.1f", mastery_age),
             tom_dimension = factor(tom_dimension, levels = DIMENSION_DEVELOPMENTAL_ORDER)) %>%
      arrange(tom_dimension) %>%
      select(model, tom_dimension, cell) %>%
      pivot_wider(names_from = tom_dimension, values_from = cell)

    # Construct columns
    con_cols_list <- list()
    for (con in CONSTRUCT_DEVELOPMENTAL_ORDER) {
      con_dims <- names(DIM_TO_CONSTRUCT[DIM_TO_CONSTRUCT == con])
      con_sub <- dim_wide %>%
        filter(tom_dimension %in% con_dims) %>%
        group_by(model) %>%
        summarise(
          mean_age = mean(mastery_age, na.rm = TRUE),
          sd_age = sd(mastery_age, na.rm = TRUE),
          .groups = "drop"
        ) %>%
        mutate(cell = case_when(
          is.na(mean_age) | is.nan(mean_age) ~ "NA",
          is.na(sd_age) | is.nan(sd_age) ~ sprintf("%.1f", mean_age),
          TRUE ~ sprintf("%.1f (%.1f)", mean_age, sd_age)
        ))
      con_cols_list[[con]] <- con_sub %>% select(model, !!con := cell)
    }

    # All column
    all_col <- dim_wide %>%
      group_by(model, family, release_date) %>%
      summarise(
        mean_age = mean(mastery_age, na.rm = TRUE),
        sd_age = sd(mastery_age, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      mutate(All = sprintf("%.1f (%.1f)", mean_age, replace_na(sd_age, 0))) %>%
      arrange(release_date)

    result <- all_col %>%
      mutate(short_name = short_model(model)) %>%
      select(short_name, family, release_date, All)

    for (con in CONSTRUCT_DEVELOPMENTAL_ORDER) {
      con_df <- con_cols_list[[con]] %>%
        mutate(short_name = short_model(model)) %>%
        select(short_name, !!con)
      result <- result %>% left_join(con_df, by = "short_name")
    }

    result <- result %>%
      left_join(dim_pivot %>% mutate(short_name = short_model(model)),
                by = "short_name") %>%
      select(-model) %>%
      arrange(release_date)
  }

  result
}

for (filter_name in names(TASK_FILTERS)) {
  # Per-model table
  tbl_model <- build_summary_table(mastery_dim_all, filter_name, group_by_tier = FALSE)
  write_csv(tbl_model, file.path(out_dir, paste0("summary_table_", filter_name, ".csv")))
  cat(sprintf("  summary_table_%s.csv: %d rows × %d cols\n",
              filter_name, nrow(tbl_model), ncol(tbl_model)))

  # Per-tier table
  tbl_tier <- build_summary_table(mastery_dim_all, filter_name, group_by_tier = TRUE)
  write_csv(tbl_tier, file.path(out_dir, paste0("summary_table_tier_", filter_name, ".csv")))
  cat(sprintf("  summary_table_tier_%s.csv: %d rows × %d cols\n",
              filter_name, nrow(tbl_tier), ncol(tbl_tier)))
}
cat("\n")

# =========================================================================
# S3: Pipeline B1 — Per-model GLM with task type
# =========================================================================
cat("=== Pipeline B1: Per-Model GLM with Task Type ===\n\n")

fit_per_model_glm <- function(data) {
  age_agg <- data %>%
    group_by(age_mid, task) %>%
    summarise(n_correct = sum(correct), n_items = n(), .groups = "drop")

  overall_acc <- sum(data$correct) / nrow(data)
  age_range <- range(data$age_mid)
  n_age_points <- n_distinct(data$age_mid)

  if (n_age_points < 2) {
    return(tibble(intercept = NA_real_, slope_age = NA_real_, slope_task = NA_real_,
                  age_eq_50 = NA_real_, overall_acc = overall_acc,
                  n_age_points = n_age_points, fit_flag = "insufficient_age_points"))
  }

  tryCatch({
    has_both_tasks <- n_distinct(data$task) >= 2

    if (has_both_tasks) {
      fit <- glm(cbind(n_correct, n_items - n_correct) ~ age_mid + task,
                 data = age_agg, family = binomial)
      coefs <- coef(fit)
      intercept <- coefs[["(Intercept)"]]
      slope_age <- coefs[["age_mid"]]
      slope_task <- coefs[[3]]
    } else {
      fit <- glm(cbind(n_correct, n_items - n_correct) ~ age_mid,
                 data = age_agg, family = binomial)
      coefs <- coef(fit)
      intercept <- coefs[["(Intercept)"]]
      slope_age <- coefs[["age_mid"]]
      slope_task <- NA_real_
    }

    if (is.na(slope_age) || abs(slope_age) < 0.01) {
      if (overall_acc > 0.95) {
        return(tibble(intercept = intercept, slope_age = slope_age,
                      slope_task = slope_task,
                      age_eq_50 = age_range[2] + 1.0,
                      overall_acc = overall_acc,
                      n_age_points = n_age_points, fit_flag = "ceiling"))
      } else if (overall_acc < 0.30) {
        return(tibble(intercept = intercept, slope_age = slope_age,
                      slope_task = slope_task,
                      age_eq_50 = age_range[1] - 1.0,
                      overall_acc = overall_acc,
                      n_age_points = n_age_points, fit_flag = "floor"))
      }
    }

    age_eq_50 <- -intercept / slope_age
    age_span <- diff(age_range)
    age_eq_50 <- pmin(pmax(age_eq_50, age_range[1] - age_span),
                      age_range[2] + age_span)

    flag <- if (slope_age > 0) "positive_slope" else "ok"

    tibble(intercept = intercept, slope_age = slope_age, slope_task = slope_task,
           age_eq_50 = age_eq_50, overall_acc = overall_acc,
           n_age_points = n_age_points, fit_flag = flag)

  }, error = function(e) {
    tibble(intercept = NA_real_, slope_age = NA_real_, slope_task = NA_real_,
           age_eq_50 = NA_real_, overall_acc = overall_acc,
           n_age_points = n_age_points, fit_flag = "error")
  })
}

glm_dim_results <- df %>%
  group_by(model, tom_dimension) %>%
  group_modify(~ fit_per_model_glm(.x)) %>%
  ungroup() %>%
  mutate(scope = "dimension")

glm_con_results <- df %>%
  group_by(model, tom_construct) %>%
  group_modify(~ fit_per_model_glm(.x)) %>%
  ungroup() %>%
  mutate(scope = "construct")

glm_ovr_results <- df %>%
  group_by(model) %>%
  group_modify(~ fit_per_model_glm(.x)) %>%
  ungroup() %>%
  mutate(scope = "overall")

glm_all <- bind_rows(
  glm_dim_results %>% rename(scope_name = tom_dimension),
  glm_con_results %>% rename(scope_name = tom_construct),
  glm_ovr_results %>% mutate(scope_name = "overall")
)

write_csv(glm_all, file.path(out_dir, "glm_per_model_age.csv"))
cat(sprintf("  Per-model GLM fits: %d (dim: %d, con: %d, ovr: %d)\n",
            nrow(glm_all), nrow(glm_dim_results), nrow(glm_con_results),
            nrow(glm_ovr_results)))
cat(sprintf("  Fit flags: %s\n",
            paste(names(table(glm_all$fit_flag)),
                  table(glm_all$fit_flag), sep = "=", collapse = ", ")))
cat("\n")

# =========================================================================
# S4: Pipeline B2 — GLMM across models (lme4)
# =========================================================================
cat("=== Pipeline B2: GLMM Across Models ===\n\n")

fit_glmm <- function(data, scope_label) {
  has_both_tasks <- n_distinct(data$task) >= 2
  n_models <- n_distinct(data$model)
  n_items <- n_distinct(data$item_id)
  n_age_pts <- n_distinct(data$age_mid)

  cat(sprintf("  Fitting GLMM for %s (%d models, %d items, %d age points)...\n",
              scope_label, n_models, n_items, n_age_pts))

  if (n_age_pts < 2) {
    cat("    Skipped: fewer than 2 age points.\n")
    return(NULL)
  }

  tryCatch({
    fit <- suppressWarnings({
      if (has_both_tasks) {
        glmer(correct ~ age_mid * task + (age_mid | model) + (1 | item_id),
              data = data, family = binomial,
              control = glmerControl(optimizer = "bobyqa",
                                     optCtrl = list(maxfun = 50000)))
      } else {
        glmer(correct ~ age_mid + (age_mid | model) + (1 | item_id),
              data = data, family = binomial,
              control = glmerControl(optimizer = "bobyqa",
                                     optCtrl = list(maxfun = 50000)))
      }
    })

    if (isSingular(fit)) cat("    Note: singular fit (some variance components near zero)\n")

    fe <- lme4::fixef(fit)
    re <- lme4::ranef(fit)$model

    model_ages <- tibble(
      model = rownames(re),
      intercept_re = re[, 1],
      slope_re = re[, 2],
      intercept_total = fe[["(Intercept)"]] + re[, 1],
      slope_total = fe[["age_mid"]] + re[, 2]
    ) %>%
      mutate(
        age_eq_50 = ifelse(abs(slope_total) < 0.01, NA_real_,
                           -intercept_total / slope_total),
        scope = scope_label
      )

    cat(sprintf("    Converged. Fixed intercept=%.2f, slope=%.3f\n",
                fe[["(Intercept)"]], fe[["age_mid"]]))

    if (has_both_tasks) {
      task_names <- grep("^task", names(fe), value = TRUE)
      for (tn in task_names) {
        cat(sprintf("    Task effect (%s): %.3f\n", tn, fe[[tn]]))
      }
    }

    model_ages
  }, error = function(e) {
    cat(sprintf("    GLMM failed for %s: %s\n", scope_label, conditionMessage(e)))
    NULL
  })
}

glmm_results <- list()

# Per dimension
for (dim_name in DIMENSION_DEVELOPMENTAL_ORDER) {
  dim_data <- df %>% filter(tom_dimension == dim_name)
  res <- fit_glmm(dim_data, dim_name)
  if (!is.null(res)) glmm_results[[length(glmm_results) + 1]] <- res
}

# Per construct
for (con_name in CONSTRUCT_DEVELOPMENTAL_ORDER) {
  con_data <- df %>% filter(tom_construct == con_name)
  res <- fit_glmm(con_data, con_name)
  if (!is.null(res)) glmm_results[[length(glmm_results) + 1]] <- res
}

# Overall
res <- fit_glmm(df, "overall")
if (!is.null(res)) glmm_results[[length(glmm_results) + 1]] <- res

glmm_all <- bind_rows(glmm_results)
write_csv(glmm_all, file.path(out_dir, "glmm_age_equivalents.csv"))
cat(sprintf("\n  GLMM total results: %d model-scope combinations\n\n", nrow(glmm_all)))

# =========================================================================
# S5: Pipeline B3 — MIRT with age-anchoring
# =========================================================================
cat("=== Pipeline B3: MIRT Age-Anchoring ===\n\n")

item_meta <- df %>%
  distinct(item_id, tom_dimension, tom_construct, age_mid, task)

irt_results <- list()
item_param_rows <- list()

for (dim_name in DIMENSION_DEVELOPMENTAL_ORDER) {
  tryCatch({
    dim_items <- item_meta %>% filter(tom_dimension == dim_name) %>% pull(item_id)
    dim_data <- df %>% filter(tom_dimension == dim_name)

    resp_wide <- dim_data %>%
      select(model, item_id, correct) %>%
      pivot_wider(names_from = item_id, values_from = correct, values_fn = first)

    resp_matrix <- as.matrix(resp_wide[, -1])
    rownames(resp_matrix) <- resp_wide$model
    items_ordered <- colnames(resp_matrix)

    var_check <- apply(resp_matrix, 2, var, na.rm = TRUE)
    resp_matrix <- resp_matrix[, var_check > 0, drop = FALSE]

    if (ncol(resp_matrix) < 3) {
      cat(sprintf("  %s: skipped (< 3 items with variance)\n", dim_name))
      next
    }

    cat(sprintf("  %s: fitting Rasch (%d models × %d items)...\n",
                dim_name, nrow(resp_matrix), ncol(resp_matrix)))

    fit <- mirt(resp_matrix, model = 1, itemtype = "Rasch",
                verbose = FALSE, SE = FALSE)
    theta <- fscores(fit, method = "MAP")[, 1]

    # Item parameters
    ip <- coef(fit, simplify = TRUE)$items
    ip_df <- tibble(
      item_id = colnames(resp_matrix),
      d = ip[, "d"],
      b = -ip[, "d"]
    ) %>%
      left_join(item_meta %>% distinct(item_id, age_mid), by = "item_id")

    item_param_rows[[dim_name]] <- ip_df %>% mutate(tom_dimension = dim_name)

    # Age-anchoring: regress age_mid ~ b
    valid_items <- ip_df %>% filter(!is.na(b), !is.na(age_mid))
    if (nrow(valid_items) >= 2 && length(unique(valid_items$age_mid)) >= 2) {
      reg <- lm(age_mid ~ b, data = valid_items)
      age_eq <- predict(reg, newdata = data.frame(b = theta))
      cat(sprintf("    age ~ b: intercept=%.2f, slope=%.2f, R²=%.3f\n",
                  coef(reg)[1], coef(reg)[2], summary(reg)$r.squared))
    } else {
      age_eq <- rep(NA_real_, length(theta))
      cat(sprintf("    age-anchoring skipped (insufficient variation)\n"))
    }

    irt_results[[dim_name]] <- tibble(
      model = rownames(resp_matrix),
      tom_dimension = dim_name,
      theta = theta,
      irt_age_eq = age_eq
    )
  }, error = function(e) {
    cat(sprintf("  %s: IRT failed — %s\n", dim_name, conditionMessage(e)))
  })
}

irt_ages <- bind_rows(irt_results)
item_param_all <- bind_rows(item_param_rows)

write_csv(irt_ages, file.path(out_dir, "irt_age_equivalents.csv"))
write_csv(item_param_all, file.path(out_dir, "irt_item_parameters.csv"))

cat(sprintf("\n  IRT age-equivalents: %d model-dimension pairs across %d dimensions\n\n",
            nrow(irt_ages), n_distinct(irt_ages$tom_dimension)))

# =========================================================================
# S6: Pipeline B4 — Bayesian GLMM (attempt brms)
# =========================================================================
cat("=== Pipeline B4: Bayesian GLMM ===\n")

brms_available <- tryCatch({
  find.package("brms")
  TRUE
}, error = function(e) FALSE)

if (!brms_available) {
  cat("  brms not installed. Attempting install...\n")
  tryCatch({
    install.packages("brms", repos = "https://cloud.r-project.org", quiet = TRUE)
    brms_available <- TRUE
    cat("  brms installed successfully.\n")
  }, error = function(e) {
    cat(sprintf("  brms install failed: %s\n", conditionMessage(e)))
    cat("  Falling back to bootstrap CIs from lme4.\n")
  })
}

if (brms_available) {
  cat("  brms available but skipping full Bayesian fits (computationally expensive).\n")
  cat("  Bootstrap CIs from lme4 used instead.\n")
}
cat("\n")

# =========================================================================
# S7: Method comparison + final outputs
# =========================================================================
cat("=== Method Comparison ===\n\n")

# Align all methods on model × dimension
mastery_for_compare <- mastery_dim_all %>%
  filter(task_filter == "all") %>%
  select(model, tom_dimension, mastery_age)

glm_for_compare <- glm_dim_results %>%
  select(model, tom_dimension, glm_age_eq = age_eq_50, glm_flag = fit_flag)

glmm_dim_for_compare <- if (nrow(glmm_all) > 0) {
  glmm_all %>%
    filter(scope %in% DIMENSION_DEVELOPMENTAL_ORDER) %>%
    select(model, tom_dimension = scope, glmm_age_eq = age_eq_50)
} else {
  tibble(model = character(), tom_dimension = character(), glmm_age_eq = numeric())
}

irt_for_compare <- if (exists("irt_ages") && nrow(irt_ages) > 0) {
  irt_ages %>% select(model, tom_dimension, irt_age_eq)
} else {
  tibble(model = character(), tom_dimension = character(), irt_age_eq = numeric())
}

comparison <- mastery_for_compare %>%
  left_join(glm_for_compare, by = c("model", "tom_dimension")) %>%
  left_join(glmm_dim_for_compare, by = c("model", "tom_dimension")) %>%
  left_join(irt_for_compare, by = c("model", "tom_dimension")) %>%
  left_join(models_meta %>% select(model, family, tier, release_date),
            by = "model")

write_csv(comparison, file.path(out_dir, "method_comparison.csv"))

# Correlations between methods
valid_pairs <- comparison %>%
  filter(!is.na(mastery_age), !is.na(glm_age_eq))
if (nrow(valid_pairs) >= 5) {
  cor_mg <- cor(valid_pairs$mastery_age, valid_pairs$glm_age_eq,
                use = "complete.obs")
  cat(sprintf("  Mastery vs GLM correlation: r = %.3f (n = %d)\n",
              cor_mg, nrow(valid_pairs)))
}

valid_pairs2 <- comparison %>%
  filter(!is.na(mastery_age), !is.na(glmm_age_eq))
if (nrow(valid_pairs2) >= 5) {
  cor_mglmm <- cor(valid_pairs2$mastery_age, valid_pairs2$glmm_age_eq,
                   use = "complete.obs")
  cat(sprintf("  Mastery vs GLMM correlation: r = %.3f (n = %d)\n",
              cor_mglmm, nrow(valid_pairs2)))
}

valid_pairs3 <- comparison %>%
  filter(!is.na(mastery_age), !is.na(irt_age_eq))
if (nrow(valid_pairs3) >= 5) {
  cor_mirt <- cor(valid_pairs3$mastery_age, valid_pairs3$irt_age_eq,
                  use = "complete.obs")
  cat(sprintf("  Mastery vs IRT correlation: r = %.3f (n = %d)\n",
              cor_mirt, nrow(valid_pairs3)))
}

valid_pairs4 <- comparison %>%
  filter(!is.na(glm_age_eq), !is.na(glmm_age_eq))
if (nrow(valid_pairs4) >= 5) {
  cor_gglmm <- cor(valid_pairs4$glm_age_eq, valid_pairs4$glmm_age_eq,
                   use = "complete.obs")
  cat(sprintf("  GLM vs GLMM correlation: r = %.3f (n = %d)\n",
              cor_gglmm, nrow(valid_pairs4)))
}

# Summary statistics
cat("\n=== Summary Statistics ===\n\n")

cat("Mastery age (all items) by dimension:\n")
mastery_dim_all %>%
  filter(task_filter == "all") %>%
  group_by(tom_dimension) %>%
  summarise(
    mean_mastery = mean(mastery_age, na.rm = TRUE),
    sd_mastery = sd(mastery_age, na.rm = TRUE),
    n_na = sum(is.na(mastery_age)),
    .groups = "drop"
  ) %>%
  arrange(match(tom_dimension, DIMENSION_DEVELOPMENTAL_ORDER)) %>%
  print(n = 12, width = 120)

cat("\nMastery age (all items) by family:\n")
mastery_dim_all %>%
  filter(task_filter == "all") %>%
  left_join(models_meta %>% select(model, family), by = "model") %>%
  group_by(family) %>%
  summarise(
    mean_mastery = mean(mastery_age, na.rm = TRUE),
    sd_mastery = sd(mastery_age, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  print(width = 100)

cat("\n=== Files Written ===\n")
list.files(out_dir) %>% cat(sep = "\n")

sink()
cat("Done. Output in:", out_dir, "\n")
