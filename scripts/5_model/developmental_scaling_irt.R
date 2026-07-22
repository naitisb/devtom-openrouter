#!/usr/bin/env Rscript
# developmental_scaling_irt.R — Developmental scaling + IRT mapping (primary mapping)
#
# Places each model on a per-dimension profile vector and a developmental age
# band, then tracks that placement across releases. Three parts:
#   A. Scaling/frontier: per-dimension pass/fail + frontier age band + Guttman CR
#   B. IRT (mirt): Rasch + 2PL, θ extraction, age-anchoring, DIF by family
#   C. Trajectory: frontier + θ vs release date, trend stats
#
# Reads results/item_level.csv; emits CSVs to results/modeling/mapping/<timestamp>/.
#
# Usage:
#   Rscript scripts/5_model/developmental_scaling_irt.R
#   Rscript scripts/5_model/developmental_scaling_irt.R --item-csv results/item_level.csv

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(tibble)
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
# Load
# ---------------------------------------------------------------------------
df <- read_csv(item_csv, show_col_types = FALSE) %>%
  filter(!is.na(date_years)) %>%
  mutate(correct = as.integer(correct))

cat(sprintf("Loaded %d rows: %d models, %d items\n",
            nrow(df), n_distinct(df$model), n_distinct(df$item_id)))

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path(results_dir, "modeling", "mapping", stamp)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# Wilson CI helper
# ---------------------------------------------------------------------------
wilson_ci <- function(k, n, z = 1.96) {
  if (n == 0) return(c(p = NA, lo = NA, hi = NA))
  p <- k / n
  denom <- 1 + z^2 / n
  centre <- (p + z^2 / (2 * n)) / denom
  spread <- z * sqrt((p * (1 - p) + z^2 / (4 * n)) / n) / denom
  c(p = p, lo = max(0, centre - spread), hi = min(1, centre + spread))
}

# ---------------------------------------------------------------------------
# Part A: Scaling / frontier
# ---------------------------------------------------------------------------
cat("\n=== Part A: Developmental scaling / frontier ===\n")

# Profile vectors: per model × dimension accuracy + Wilson CI
profile_rows <- df %>%
  group_by(model, family, tier, task, tom_dimension, validated_age_band,
           dim_rank, date_years, release_date) %>%
  summarise(n = n(), n_correct = sum(correct), .groups = "drop") %>%
  rowwise() %>%
  mutate(
    w = list(wilson_ci(n_correct, n)),
    accuracy = w[["p"]],
    wilson_lo = w[["lo"]],
    wilson_hi = w[["hi"]]
  ) %>%
  select(-w) %>%
  ungroup()

# Pass/fail: Wilson LB > chance (0.5 for MCQ; 0.0 for free-response as conservative)
profile_rows <- profile_rows %>%
  mutate(
    chance = ifelse(task == "tom_12dim_mcq", 0.5, 0.0),
    pass = as.integer(wilson_lo > chance)
  )

write_csv(profile_rows, file.path(out_dir, "profile_vectors.csv"))
cat(sprintf("Wrote profile_vectors.csv: %d rows\n", nrow(profile_rows)))

# Frontier: highest age band with ≥⅔ of dims (band ≤ b) passed
# Parse age bands into numeric for ordering
age_band_order <- df %>%
  distinct(validated_age_band, age_lo, age_hi, age_mid) %>%
  filter(!is.na(age_mid)) %>%
  arrange(age_mid)

frontier_rows <- list()

for (mod in unique(profile_rows$model)) {
  for (tsk in unique(profile_rows$task)) {
    mod_task <- profile_rows %>% filter(model == mod, task == tsk)
    if (nrow(mod_task) == 0) next

    mod_info <- mod_task %>% slice(1)

    # For each age band (ascending), count dims at or below that band that pass
    best_band <- NA
    guttman_errors <- 0
    total_pairs <- 0

    bands <- age_band_order$validated_age_band
    for (b_idx in seq_along(bands)) {
      band <- bands[b_idx]
      dims_at_or_below <- mod_task %>%
        filter(validated_age_band %in% bands[1:b_idx])
      if (nrow(dims_at_or_below) == 0) next

      pass_rate <- mean(dims_at_or_below$pass)
      if (pass_rate >= 2/3) {
        best_band <- band
      }

      # Guttman errors: harder item passed but easier item failed
      for (j in seq_len(nrow(dims_at_or_below))) {
        for (k in seq_len(nrow(dims_at_or_below))) {
          if (j >= k) next
          total_pairs <- total_pairs + 1
          if (dims_at_or_below$dim_rank[j] < dims_at_or_below$dim_rank[k]) {
            if (dims_at_or_below$pass[j] == 0 && dims_at_or_below$pass[k] == 1) {
              guttman_errors <- guttman_errors + 1
            }
          } else {
            if (dims_at_or_below$pass[j] == 1 && dims_at_or_below$pass[k] == 0) {
              guttman_errors <- guttman_errors + 1
            }
          }
        }
      }
    }

    guttman_cr <- if (total_pairs > 0) 1 - guttman_errors / total_pairs else NA
    scalability <- if (total_pairs > 0) {
      max_errors <- total_pairs / 2
      if (max_errors > 0) 1 - guttman_errors / max_errors else 1
    } else NA

    frontier_rows <- c(frontier_rows, list(data.frame(
      model = mod, family = mod_info$family, tier = mod_info$tier,
      task = tsk, frontier_band = best_band,
      guttman_cr = round(guttman_cr, 4),
      scalability = round(scalability, 4),
      date_years = mod_info$date_years,
      release_date = mod_info$release_date,
      stringsAsFactors = FALSE
    )))
  }
}

frontier_df <- bind_rows(frontier_rows)
write_csv(frontier_df, file.path(out_dir, "frontier.csv"))
cat(sprintf("Wrote frontier.csv: %d rows\n", nrow(frontier_df)))

# ---------------------------------------------------------------------------
# Part B: IRT (mirt)
# ---------------------------------------------------------------------------
cat("\n=== Part B: IRT ===\n")

has_mirt <- requireNamespace("mirt", quietly = TRUE)
if (!has_mirt) {
  cat("WARNING: mirt not installed — skipping IRT analysis.\n")
  cat("Install with: install.packages('mirt')\n")
} else {
  library(mirt)

  irt_theta_rows <- list()
  irt_item_rows <- list()
  wright_rows <- list()
  diff_vs_age_rows <- list()
  dif_rows <- list()

  for (tsk in unique(df$task)) {
    cat(sprintf("\nIRT for task: %s\n", tsk))
    task_df <- df %>% filter(task == tsk)

    # Build person × item matrix (models as persons)
    resp_matrix <- task_df %>%
      select(model, item_id, correct) %>%
      pivot_wider(names_from = item_id, values_from = correct,
                  values_fn = first) %>%
      column_to_rownames("model")

    # Drop items with zero variance
    item_vars <- apply(resp_matrix, 2, var, na.rm = TRUE)
    zero_var <- names(item_vars[item_vars == 0 | is.na(item_vars)])
    if (length(zero_var) > 0) {
      cat(sprintf("  Dropping %d zero-variance items\n", length(zero_var)))
      resp_matrix <- resp_matrix[, !names(resp_matrix) %in% zero_var]
    }

    n_persons <- nrow(resp_matrix)
    n_items <- ncol(resp_matrix)
    cat(sprintf("  %d persons × %d items\n", n_persons, n_items))

    if (n_persons < 3 || n_items < 3) {
      cat("  Skipping: too few persons or items\n")
      next
    }

    # --- Rasch (1PL) primary ---
    cat("  Fitting Rasch (1PL)...\n")
    rasch_fit <- tryCatch({
      mirt(as.matrix(resp_matrix), model = 1, itemtype = "Rasch",
           verbose = FALSE, SE = TRUE)
    }, error = function(e) {
      cat("  ERROR in Rasch fit: ", conditionMessage(e), "\n")
      NULL
    })

    # --- 2PL sensitivity ---
    cat("  Fitting 2PL...\n")
    twopl_fit <- tryCatch({
      mirt(as.matrix(resp_matrix), model = 1, itemtype = "2PL",
           verbose = FALSE, SE = TRUE)
    }, error = function(e) {
      cat("  ERROR in 2PL fit: ", conditionMessage(e), "\n")
      NULL
    })

    # Use Rasch as primary, 2PL for sensitivity
    primary_fit <- if (!is.null(rasch_fit)) rasch_fit else twopl_fit
    if (is.null(primary_fit)) next

    # Extract θ (factor scores)
    theta <- fscores(primary_fit, method = "EAP", full.scores.SE = TRUE)
    theta_df <- data.frame(
      model = rownames(resp_matrix),
      task = tsk,
      theta = theta[, 1],
      theta_se = theta[, 2],
      stringsAsFactors = FALSE
    )
    # Join model metadata
    meta <- task_df %>% distinct(model, family, tier, date_years, release_date)
    theta_df <- theta_df %>% left_join(meta, by = "model")
    irt_theta_rows <- c(irt_theta_rows, list(theta_df))

    # Extract item parameters
    item_params <- coef(primary_fit, simplify = TRUE, IRTpars = TRUE)$items
    item_df <- data.frame(
      item_id = rownames(item_params),
      task = tsk,
      stringsAsFactors = FALSE
    )
    if ("a" %in% colnames(item_params)) item_df$a <- item_params[, "a"]
    if ("b" %in% colnames(item_params)) item_df$b <- item_params[, "b"]
    if ("g" %in% colnames(item_params)) item_df$g <- item_params[, "g"]

    # Join item metadata (dimension, age band)
    item_meta <- task_df %>%
      distinct(item_id, tom_dimension, validated_age_band, age_mid, dim_rank)
    item_df <- item_df %>% left_join(item_meta, by = "item_id")
    irt_item_rows <- c(irt_item_rows, list(item_df))

    # Wright map data
    wright <- data.frame(
      type = c(rep("item", nrow(item_df)), rep("person", nrow(theta_df))),
      label = c(item_df$item_id, theta_df$model),
      value = c(item_df$b, theta_df$theta),
      task = tsk,
      stringsAsFactors = FALSE
    )
    wright_rows <- c(wright_rows, list(wright))

    # Difficulty vs age-mid (H1 ordering check)
    if ("b" %in% names(item_df) && any(!is.na(item_df$age_mid))) {
      valid <- item_df %>% filter(!is.na(b), !is.na(age_mid))
      if (nrow(valid) >= 4) {
        sp <- cor.test(valid$b, valid$age_mid, method = "spearman")
        diff_age <- data.frame(
          task = tsk,
          spearman_rho = round(sp$estimate, 4),
          spearman_p = sp$p.value,
          n = nrow(valid),
          stringsAsFactors = FALSE
        )
        diff_vs_age_rows <- c(diff_vs_age_rows, list(diff_age))
        cat(sprintf("  Difficulty vs age: rho=%.3f, p=%.4f (n=%d)\n",
                    sp$estimate, sp$p.value, nrow(valid)))
      }
    }

    # Age-anchored θ: regress item b on age_mid, then transform θ
    if ("b" %in% names(item_df) && any(!is.na(item_df$age_mid))) {
      valid <- item_df %>% filter(!is.na(b), !is.na(age_mid))
      if (nrow(valid) >= 4) {
        age_reg <- lm(age_mid ~ b, data = valid)
        theta_df$age_anchored_theta <- predict(age_reg,
                                                newdata = data.frame(b = theta_df$theta))
        # Update the stored theta rows
        irt_theta_rows[[length(irt_theta_rows)]] <- theta_df
        cat(sprintf("  Age anchoring: intercept=%.2f, slope=%.2f (R²=%.3f)\n",
                    coef(age_reg)[1], coef(age_reg)[2], summary(age_reg)$r.squared))
      }
    }

    # DIF by family (if enough families with enough models)
    family_counts <- task_df %>%
      distinct(model, family) %>%
      count(family) %>%
      filter(n >= 2)

    if (nrow(family_counts) >= 2) {
      cat("  DIF analysis by family...\n")
      tryCatch({
        group_var <- task_df %>%
          distinct(model, family) %>%
          arrange(match(model, rownames(resp_matrix)))
        # Only include families with >=2 models
        keep_fams <- family_counts$family
        keep_models <- group_var %>% filter(family %in% keep_fams) %>% pull(model)
        group_resp <- resp_matrix[rownames(resp_matrix) %in% keep_models, ]
        group_labels <- group_var %>%
          filter(model %in% keep_models) %>%
          pull(family)

        if (length(unique(group_labels)) >= 2 && nrow(group_resp) >= 4) {
          mg_fit <- multipleGroup(as.matrix(group_resp), model = 1,
                                  group = group_labels, itemtype = "Rasch",
                                  verbose = FALSE, SE = FALSE)
          dif_result <- DIF(mg_fit, which.par = "d", scheme = "drop")
          dif_df <- data.frame(
            item_id = rownames(dif_result),
            task = tsk,
            chi2 = dif_result$X2,
            df = dif_result$df,
            p = dif_result$p,
            flagged = dif_result$p < 0.05,
            stringsAsFactors = FALSE
          )
          dif_rows <- c(dif_rows, list(dif_df))
          n_flagged <- sum(dif_df$flagged, na.rm = TRUE)
          cat(sprintf("  DIF: %d/%d items flagged (p<.05)\n",
                      n_flagged, nrow(dif_df)))
        }
      }, error = function(e) {
        cat("  DIF analysis failed: ", conditionMessage(e), "\n")
      })
    }

    cat(sprintf("  CAVEAT: %d persons — Rasch is primary; SEs will be large.\n",
                n_persons))
  }

  # Write IRT outputs
  if (length(irt_theta_rows) > 0) {
    theta_all <- bind_rows(irt_theta_rows)
    write_csv(theta_all, file.path(out_dir, "irt_theta.csv"))
    cat(sprintf("\nWrote irt_theta.csv: %d rows\n", nrow(theta_all)))
  }
  if (length(irt_item_rows) > 0) {
    items_all <- bind_rows(irt_item_rows)
    write_csv(items_all, file.path(out_dir, "irt_item_params.csv"))
    cat(sprintf("Wrote irt_item_params.csv: %d rows\n", nrow(items_all)))
  }
  if (length(wright_rows) > 0) {
    wright_all <- bind_rows(wright_rows)
    write_csv(wright_all, file.path(out_dir, "wright_map.csv"))
    cat(sprintf("Wrote wright_map.csv: %d rows\n", nrow(wright_all)))
  }
  if (length(diff_vs_age_rows) > 0) {
    diff_age_all <- bind_rows(diff_vs_age_rows)
    write_csv(diff_age_all, file.path(out_dir, "irt_difficulty_vs_age.csv"))
    cat(sprintf("Wrote irt_difficulty_vs_age.csv: %d rows\n", nrow(diff_age_all)))
  }
  if (length(dif_rows) > 0) {
    dif_all <- bind_rows(dif_rows)
    write_csv(dif_all, file.path(out_dir, "irt_dif.csv"))
    cat(sprintf("Wrote irt_dif.csv: %d rows\n", nrow(dif_all)))
  }
}

# ---------------------------------------------------------------------------
# Part C: Trajectory (frontier + θ vs release date)
# ---------------------------------------------------------------------------
cat("\n=== Part C: Trajectory ===\n")

# Frontier trajectory: per tier, frontier band vs release date
if (nrow(frontier_df) > 0) {
  # Encode frontier band as numeric (age_lo of the band)
  frontier_traj <- frontier_df %>%
    left_join(age_band_order %>% select(validated_age_band, age_lo, age_mid),
              by = c("frontier_band" = "validated_age_band")) %>%
    rename(frontier_age_lo = age_lo, frontier_age_mid = age_mid) %>%
    filter(!is.na(date_years))

  # Spearman trend per tier
  trend_rows <- list()
  for (tr in unique(frontier_traj$tier)) {
    tier_data <- frontier_traj %>%
      filter(tier == tr, !is.na(frontier_age_mid))
    if (nrow(tier_data) >= 3 && length(unique(tier_data$date_years)) >= 2) {
      sp <- cor.test(tier_data$date_years, tier_data$frontier_age_mid,
                     method = "spearman")
      trend_rows <- c(trend_rows, list(data.frame(
        tier = tr,
        family = tier_data$family[1],
        spearman_rho = round(sp$estimate, 4),
        spearman_p = sp$p.value,
        n = nrow(tier_data),
        stringsAsFactors = FALSE
      )))
    }
  }
  frontier_traj_out <- frontier_traj
  if (length(trend_rows) > 0) {
    trends <- bind_rows(trend_rows)
    frontier_traj_out <- frontier_traj_out %>%
      left_join(trends %>% select(tier, spearman_rho, spearman_p),
                by = "tier")
  }
  write_csv(frontier_traj_out, file.path(out_dir, "frontier_trajectory.csv"))
  cat(sprintf("Wrote frontier_trajectory.csv: %d rows\n", nrow(frontier_traj_out)))
}

# θ trajectory: per tier, θ vs release date (if IRT ran)
if (has_mirt && length(irt_theta_rows) > 0) {
  theta_all <- bind_rows(irt_theta_rows)
  theta_traj <- theta_all %>% filter(!is.na(date_years))

  # Spearman per tier
  theta_trend_rows <- list()
  for (tr in unique(theta_traj$tier)) {
    tier_data <- theta_traj %>% filter(tier == tr)
    if (nrow(tier_data) >= 3 && length(unique(tier_data$date_years)) >= 2) {
      sp <- cor.test(tier_data$date_years, tier_data$theta, method = "spearman")
      theta_trend_rows <- c(theta_trend_rows, list(data.frame(
        tier = tr,
        family = tier_data$family[1],
        metric = "theta",
        spearman_rho = round(sp$estimate, 4),
        spearman_p = sp$p.value,
        n = nrow(tier_data),
        stringsAsFactors = FALSE
      )))
    }
  }
  if (length(theta_trend_rows) > 0) {
    theta_trends <- bind_rows(theta_trend_rows)
    cat("\nθ trajectory trends:\n")
    print(theta_trends)
  }
}

cat(sprintf("\nAll outputs written to %s/\n", out_dir))
