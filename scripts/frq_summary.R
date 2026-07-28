#!/usr/bin/env Rscript
# frq_summary.R — Complete free-response-only DevToM analysis + figures
#
# Filters to tom_12dim_freeresponse, runs descriptive stats, GLMM trajectory,
# IRT / developmental mapping, and size-scaling GLMM, then generates all
# figures. Outputs to results/frq_only/<timestamp>/.
#
# Usage:
#   Rscript scripts/frq_summary.R

suppressPackageStartupMessages({
  library(lme4)
  library(broom.mixed)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(tibble)
  library(ggplot2)
  library(ggrepel)
})
# mirt loaded later (after GLMM section) to avoid method dispatch conflicts

source("scripts/6_visualize/_theme.R")

DATE_EPOCH <- as.Date("2024-01-01")

scale_x_date_years <- function(step = 0.5) {
  brk <- seq(0, 2.5, by = step)
  lbl <- sapply(brk, function(dy) {
    yr <- 2024 + floor(dy)
    mo <- round((dy - floor(dy)) * 12) + 1
    if (mo > 12) { yr <- yr + 1; mo <- mo - 12 }
    if (step >= 1) format(as.Date(sprintf("%d-%02d-01", yr, mo)), "%Y")
    else           format(as.Date(sprintf("%d-%02d-01", yr, mo)), "%b\n%Y")
  })
  scale_x_continuous(breaks = brk, labels = lbl)
}

# ============================================================================
# 0. LOAD + FILTER
# ============================================================================
item_csv <- "results/item_level.csv"
if (!file.exists(item_csv)) stop("Missing: ", item_csv)

raw <- read_csv(item_csv, show_col_types = FALSE)

df <- raw %>%
  filter(task == "tom_12dim_freeresponse", !is.na(date_years)) %>%
  mutate(
    correct       = as.integer(correct),
    family        = factor(family, levels = FAMILY_ORDER),
    tier          = factor(tier),
    model         = factor(model),
    item_id       = factor(item_id),
    tom_dimension = factor(tom_dimension),
    dim_rank      = as.numeric(dim_rank),
    date_c        = date_years - mean(date_years)
  )

cat(sprintf("FR-only: %d rows, %d models, %d items, %d dimensions\n",
            nrow(df), nlevels(df$model), nlevels(df$item_id),
            nlevels(df$tom_dimension)))

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
base_dir <- file.path("results", "frq_only", stamp)
fig_dir  <- file.path(base_dir, "figures")
stat_dir <- file.path(base_dir, "stats")
mod_dir  <- file.path(base_dir, "modeling")
for (d in c(fig_dir, stat_dir, mod_dir)) dir.create(d, recursive = TRUE)

cat(sprintf("Output: %s/\n", base_dir))

# Save width/height presets
W <- 10; H <- 6   # standard landscape
WS <- 8; HS <- 6  # smaller
WW <- 14; HW <- 8 # wide

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
safe_glmer <- function(formula, data, label = "") {
  cat(sprintf("  Fitting %s...\n", label))
  tryCatch({
    fit <- glmer(formula, data = data, family = binomial,
                 control = glmerControl(optimizer = "bobyqa",
                                        optCtrl = list(maxfun = 1e5)))
    if (isSingular(fit)) cat(sprintf("  WARNING: singular fit (%s)\n", label))
    fit
  }, error = function(e) {
    cat(sprintf("  ERROR (%s): %s\n", label, conditionMessage(e)))
    NULL
  })
}

wilson_ci <- function(k, n, z = 1.96) {
  if (n == 0) return(c(p = NA, lo = NA, hi = NA))
  p <- k / n
  denom <- 1 + z^2 / n
  centre <- (p + z^2 / (2 * n)) / denom
  spread <- z * sqrt((p * (1 - p) + z^2 / (4 * n)) / n) / denom
  c(p = p, lo = max(0, centre - spread), hi = min(1, centre + spread))
}

save_plot <- function(p, name, w = W, h = H) {
  path <- file.path(fig_dir, name)
  ggsave(path, p, width = w, height = h, dpi = 300, bg = "white")
  cat(sprintf("  Wrote: %s\n", name))
}

# ============================================================================
# A. DESCRIPTIVE STATS
# ============================================================================
cat("\n=== A. Descriptive Statistics ===\n")

# --- Model accuracy ---
model_acc <- df %>%
  group_by(model, family, tier, date_years, release_date) %>%
  summarise(n = n(), n_correct = sum(correct), .groups = "drop") %>%
  rowwise() %>%
  mutate(w = list(wilson_ci(n_correct, n)),
         accuracy = w[["p"]], lo = w[["lo"]], hi = w[["hi"]]) %>%
  select(-w) %>%
  ungroup() %>%
  arrange(accuracy) %>%
  mutate(short = short_model(model))

write_csv(model_acc, file.path(stat_dir, "model_accuracy.csv"))

# --- Dimension difficulty ---
dim_diff <- df %>%
  group_by(tom_dimension) %>%
  summarise(accuracy = mean(correct), sd = sd(correct), n = n(),
            validated_age_band = first(validated_age_band),
            dim_rank = first(dim_rank), .groups = "drop") %>%
  arrange(accuracy)
write_csv(dim_diff, file.path(stat_dir, "dimension_difficulty.csv"))

# --- Construct difficulty ---
construct_diff <- df %>%
  group_by(tom_construct) %>%
  summarise(accuracy = mean(correct), sd = sd(correct), n = n(), .groups = "drop") %>%
  arrange(accuracy)
write_csv(construct_diff, file.path(stat_dir, "construct_difficulty.csv"))

# --- Family summary ---
family_summ <- df %>%
  group_by(family) %>%
  summarise(mean_acc = mean(correct), sd = sd(correct),
            n_models = n_distinct(model), n = n(), .groups = "drop") %>%
  arrange(desc(mean_acc))
write_csv(family_summ, file.path(stat_dir, "family_summary.csv"))

# --- CTT item stats ---
ctt_items <- df %>%
  group_by(item_id, tom_dimension, validated_age_band) %>%
  summarise(facility = mean(correct), n = n(), .groups = "drop") %>%
  mutate(discrimination = NA_real_)

# Point-biserial correlation as discrimination
total_scores <- df %>%
  group_by(model) %>%
  summarise(total = sum(correct), .groups = "drop")

for (i in seq_len(nrow(ctt_items))) {
  item <- ctt_items$item_id[i]
  item_data <- df %>% filter(item_id == item) %>%
    left_join(total_scores, by = "model")
  if (nrow(item_data) >= 3 && var(item_data$correct) > 0) {
    ctt_items$discrimination[i] <- cor(item_data$correct, item_data$total, use = "complete.obs")
  }
}
write_csv(ctt_items, file.path(stat_dir, "ctt_item_stats.csv"))

# --- Summary stats printout ---
best_model <- model_acc %>% slice_max(accuracy, n = 1)
worst_genuine <- model_acc %>% filter(accuracy > 0) %>% slice_min(accuracy, n = 1)
cat(sprintf("  Best: %s (%.1f%%) | Worst genuine: %s (%.1f%%)\n",
            best_model$short[1], best_model$accuracy[1] * 100,
            worst_genuine$short[1], worst_genuine$accuracy[1] * 100))
cat(sprintf("  Dimension range: %.1f%% – %.1f%%\n",
            min(dim_diff$accuracy) * 100, max(dim_diff$accuracy) * 100))

# ============================================================================
# A.FIGURES: Descriptive plots
# ============================================================================
cat("\n--- Descriptive figures ---\n")

# (1) Model accuracy caterpillar
model_acc_plot <- model_acc %>%
  mutate(short = factor(short, levels = short[order(accuracy)]))

p1 <- ggplot(model_acc_plot, aes(x = accuracy, y = short, color = family)) +
  geom_point(size = 2) +
  geom_errorbarh(aes(xmin = lo, xmax = hi), height = 0.3, linewidth = 0.4) +
  scale_color_manual(values = FAMILY_COLORS) +
  coord_cartesian(xlim = c(0, 1.05)) +
  labs(title = "Free Response: Model Accuracy (Wilson 95% CI)",
       x = "Accuracy", y = NULL, color = "Family") +
  theme_devtom() +
  theme(axis.text.y = element_text(size = 6))
save_plot(p1, "model_accuracy_caterpillar.png", w = 9, h = 12)

# (2) Dimension difficulty ranking — per-tier
model_dim_acc <- df %>%
  group_by(model, tier, tom_dimension) %>%
  summarise(accuracy = mean(correct), .groups = "drop") %>%
  mutate(tier = factor_tier(tier))

dim_order <- model_dim_acc %>%
  group_by(tom_dimension) %>%
  summarise(overall = mean(accuracy), .groups = "drop") %>%
  arrange(overall) %>% pull(tom_dimension)

model_dim_acc <- model_dim_acc %>%
  mutate(tom_dimension = factor(tom_dimension, levels = dim_order))

p2 <- ggplot(model_dim_acc, aes(x = accuracy, y = tom_dimension, color = tier)) +
  geom_point(alpha = 0.6, size = 1.8,
             position = position_jitter(height = 0.2, width = 0, seed = 42)) +
  stat_summary(fun = mean, geom = "point", shape = 18, size = 3.5, color = "black") +
  scale_color_manual(values = TYPE_COLORS) +
  coord_cartesian(xlim = c(0, 1.1)) +
  labs(title = "Free Response: Dimension Difficulty by Tier",
       subtitle = "Points = per-model accuracy; diamonds = overall mean",
       x = "Accuracy", y = NULL, color = "Tier") +
  theme_devtom() +
  theme(legend.text = element_text(size = 7))
save_plot(p2, "dimension_difficulty_ranking.png", w = 10, h = HS)

# (3) Construct difficulty ranking — per-tier
model_constr_acc <- df %>%
  group_by(model, tier, tom_construct) %>%
  summarise(accuracy = mean(correct), .groups = "drop") %>%
  mutate(tier = factor_tier(tier))

constr_order <- model_constr_acc %>%
  group_by(tom_construct) %>%
  summarise(overall = mean(accuracy), .groups = "drop") %>%
  arrange(overall) %>% pull(tom_construct)

model_constr_acc <- model_constr_acc %>%
  mutate(tom_construct = factor(tom_construct, levels = constr_order))

p3 <- ggplot(model_constr_acc, aes(x = accuracy, y = tom_construct, color = tier)) +
  geom_point(alpha = 0.6, size = 1.8,
             position = position_jitter(height = 0.2, width = 0, seed = 42)) +
  stat_summary(fun = mean, geom = "point", shape = 18, size = 3.5, color = "black") +
  scale_color_manual(values = TYPE_COLORS) +
  coord_cartesian(xlim = c(0, 1.1)) +
  labs(title = "Free Response: Construct Difficulty by Tier",
       subtitle = "Points = per-model accuracy; diamonds = overall mean",
       x = "Accuracy", y = NULL, color = "Tier") +
  theme_devtom() +
  theme(legend.text = element_text(size = 7))
save_plot(p3, "construct_difficulty_ranking.png", w = 10, h = 5)

# (4) CTT item map: facility vs discrimination
p4 <- ggplot(ctt_items %>% filter(!is.na(discrimination)),
             aes(x = facility, y = discrimination, color = tom_dimension)) +
  geom_point(alpha = 0.7, size = 2) +
  geom_hline(yintercept = 0.3, linetype = "dashed", color = "grey50") +
  labs(title = "Free Response: Item Facility vs. Discrimination",
       x = "Facility (proportion correct)", y = "Discrimination (rpb)",
       color = "Dimension") +
  theme_devtom() +
  theme(legend.text = element_text(size = 7))
save_plot(p4, "ctt_item_map.png")

# (5) Family accuracy comparison — per-tier
tier_family_acc <- df %>%
  group_by(model, family, tier) %>%
  summarise(accuracy = mean(correct), .groups = "drop") %>%
  mutate(family = factor(family, levels = FAMILY_ORDER),
         tier = factor_tier(tier))

p5 <- ggplot(tier_family_acc, aes(x = family, y = accuracy, color = tier)) +
  geom_point(size = 2.5, alpha = 0.7,
             position = position_jitter(width = 0.15, height = 0, seed = 42)) +
  stat_summary(fun = mean, geom = "crossbar", width = 0.5, linewidth = 0.4,
               color = "black", show.legend = FALSE) +
  scale_color_manual(values = TYPE_COLORS) +
  coord_cartesian(ylim = c(0, 1.1)) +
  labs(title = "Free Response: Accuracy by Family and Tier",
       subtitle = "Points = per-model accuracy; crossbar = family mean",
       x = NULL, y = "Accuracy", color = "Tier") +
  theme_devtom() +
  theme(legend.text = element_text(size = 7))
save_plot(p5, "family_accuracy_comparison.png", w = 10, h = HS)

# ============================================================================
# B. DIMENSION PROFILES
# ============================================================================
cat("\n=== B. Dimension Profile Figures ===\n")

# Model × dimension accuracy matrix
mod_dim <- df %>%
  group_by(model, family, tier, tom_dimension, date_years) %>%
  summarise(accuracy = mean(correct), .groups = "drop") %>%
  mutate(short = short_model(model),
         tom_dimension = factor_dimension(tom_dimension))

# (6) Overall dimension heatmap
model_order <- model_acc %>% arrange(accuracy) %>% pull(model)
heat_data <- mod_dim %>%
  mutate(model = factor(model, levels = model_order),
         short = short_model(as.character(model)))

p6 <- ggplot(heat_data, aes(x = tom_dimension, y = short, fill = accuracy)) +
  geom_tile() +
  scale_fill_gradient2(low = "#d73027", mid = "#ffffbf", high = "#1a9850",
                       midpoint = 0.5, limits = c(0, 1),
                       labels = scales::percent) +
  labs(title = "Free Response: Dimension × Model Accuracy",
       x = NULL, y = NULL, fill = "Accuracy") +
  theme_devtom() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
        axis.text.y = element_text(size = 5))
save_plot(p6, "dimension_heatmap.png", w = 12, h = 14)

# (7-11) Per-family dimension heatmaps
for (fam in levels(df$family)) {
  fam_data <- heat_data %>% filter(family == fam)
  if (nrow(fam_data) == 0) next
  fam_models <- model_acc %>% filter(family == fam) %>%
    arrange(accuracy) %>% pull(model)
  fam_data <- fam_data %>%
    mutate(model = factor(model, levels = fam_models),
           short = short_model(as.character(model)))

  pf <- ggplot(fam_data, aes(x = tom_dimension, y = short, fill = accuracy)) +
    geom_tile() +
    geom_text(aes(label = sprintf("%.0f", accuracy * 100)), size = 2.5) +
    scale_fill_gradient2(low = "#d73027", mid = "#ffffbf", high = "#1a9850",
                         midpoint = 0.5, limits = c(0, 1)) +
    labs(title = paste0("Free Response: ", fam, " Dimension Profile"),
         x = NULL, y = NULL, fill = "Accuracy") +
    theme_devtom() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 8))

  n_mod <- n_distinct(fam_data$model)
  save_plot(pf, sprintf("dimension_heatmap_%s.png", tolower(fam)),
            w = 11, h = max(4, n_mod * 0.5 + 2))
}

# (12) Construct heatmap
mod_constr <- df %>%
  group_by(model, family, tom_construct) %>%
  summarise(accuracy = mean(correct), .groups = "drop") %>%
  mutate(short = short_model(model),
         model = factor(model, levels = model_order),
         tom_construct = factor_construct(tom_construct))

p12 <- ggplot(mod_constr, aes(x = tom_construct, y = short, fill = accuracy)) +
  geom_tile() +
  scale_fill_gradient2(low = "#d73027", mid = "#ffffbf", high = "#1a9850",
                       midpoint = 0.5, limits = c(0, 1)) +
  labs(title = "Free Response: Construct × Model Accuracy",
       x = NULL, y = NULL, fill = "Accuracy") +
  theme_devtom() +
  theme(axis.text.x = element_text(angle = 30, hjust = 1, size = 8),
        axis.text.y = element_text(size = 5))
save_plot(p12, "construct_heatmap.png", w = 10, h = 14)

# ============================================================================
# C. ACCURACY TRAJECTORY
# ============================================================================
cat("\n=== C. Accuracy Trajectory Figures ===\n")

# (13) Overall accuracy by tier
p13 <- ggplot(model_acc, aes(x = date_years, y = accuracy, color = tier)) +
  geom_point(size = 2.5, alpha = 0.8) +
  geom_text_repel(aes(label = short), size = 2, max.overlaps = 15, show.legend = FALSE) +
  scale_color_manual(values = TYPE_COLORS) +
  geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey50", linewidth = 0.4) +
  coord_cartesian(ylim = c(0, 1.05)) +
  facet_wrap(~ family, nrow = 1, scales = "fixed") +
  scale_x_date_years(step = 1) +
  labs(title = "Free Response: Accuracy vs. Release Date by Tier",
       x = "Release Date", y = "Accuracy", color = "Tier") +
  theme_devtom() +
  theme(legend.text = element_text(size = 7),
        strip.text = element_text(size = 10))
save_plot(p13, "accuracy_by_tier_overall.png", w = WW, h = 6)

# (14-18) Per-family accuracy trends
for (fam in levels(df$family)) {
  fam_acc <- model_acc %>% filter(family == fam)
  if (nrow(fam_acc) < 2) next

  pf <- ggplot(fam_acc, aes(x = date_years, y = accuracy, color = tier)) +
    geom_point(size = 3) +
    geom_text_repel(aes(label = short), size = 2.5, max.overlaps = 20, show.legend = FALSE) +
    geom_smooth(method = "lm", se = TRUE, alpha = 0.15) +
    scale_color_manual(values = TYPE_COLORS) +
    geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey50", linewidth = 0.4) +
    coord_cartesian(ylim = c(0, 1.05)) +
    scale_x_date_years() +
    labs(title = paste0("Free Response: ", fam, " Accuracy Trajectory"),
         x = "Release Date", y = "Accuracy", color = "Tier") +
    theme_devtom()
  save_plot(pf, sprintf("accuracy_trend_%s.png", tolower(fam)))
}

# (19) Per-dimension regression grid (all families pooled)
dim_model <- df %>%
  group_by(model, family, tier, tom_dimension, date_years) %>%
  summarise(accuracy = mean(correct), .groups = "drop") %>%
  mutate(tom_dimension = factor_dimension(tom_dimension))

dim_model <- dim_model %>% mutate(tier = factor_tier(tier))

p19 <- ggplot(dim_model, aes(x = date_years, y = accuracy, color = tier)) +
  geom_point(alpha = 0.5, size = 1.5) +
  geom_smooth(method = "lm", se = TRUE, linewidth = 0.6, alpha = 0.15) +
  scale_color_manual(values = TYPE_COLORS) +
  geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey50", linewidth = 0.3) +
  coord_cartesian(ylim = c(0, 1.05)) +
  facet_wrap(~ tom_dimension, ncol = 4) +
  scale_x_date_years(step = 1) +
  labs(title = "Free Response: Per-Dimension Accuracy Trends",
       x = "Release Date", y = "Accuracy", color = "Tier") +
  theme_devtom(base_size = 9) +
  theme(strip.text = element_text(size = 7),
        axis.text.x = element_text(size = 6),
        legend.text = element_text(size = 6))
save_plot(p19, "dimension_regression_grid.png", w = 12, h = 9)

# ============================================================================
# D. GLMM TRAJECTORY
# ============================================================================
cat("\n=== D. GLMM Trajectory Modeling ===\n")

or_rows <- list()
pred_rows <- list()
obs_rows <- list()
dim_slope_rows <- list()

families <- levels(df$family)

# M1: date x tier per family
for (fam in families) {
  fam_df <- df %>% filter(family == fam)
  n_tiers <- n_distinct(fam_df$tier)
  n_dates <- n_distinct(fam_df$date_years)
  if (n_dates < 2) next

  if (n_tiers < 2) {
    formula <- correct ~ date_c + (1 | item_id)
  } else {
    formula <- correct ~ date_c * tier + (1 | item_id)
  }
  if (n_distinct(fam_df$model) >= 3) {
    if (n_tiers < 2) {
      formula <- correct ~ date_c + (1 | item_id) + (1 | model)
    } else {
      formula <- correct ~ date_c * tier + (1 | item_id) + (1 | model)
    }
  }

  fit <- safe_glmer(formula, fam_df, label = paste0("M1:", fam))
  if (is.null(fit)) next

  fe <- broom.mixed::tidy(fit, effects = "fixed", conf.int = TRUE, exponentiate = TRUE) %>%
    mutate(family = fam, model_label = "M1_date_x_tier")
  or_rows <- c(or_rows, list(fe))

  tiers_present <- unique(fam_df$tier)
  date_range <- seq(min(fam_df$date_c), max(fam_df$date_c), length.out = 50)
  grid <- expand.grid(date_c = date_range, tier = tiers_present, stringsAsFactors = FALSE) %>%
    mutate(tier = factor(tier, levels = levels(df$tier)))
  tryCatch({
    preds <- predict(fit, newdata = grid, type = "response", re.form = NA)
    grid$pred <- preds
    grid$family <- fam
    grid$date_years <- grid$date_c + mean(fam_df$date_years)
    pred_rows <- c(pred_rows, list(grid))
  }, error = function(e) NULL)

  obs <- fam_df %>%
    group_by(family, tier, model, date_years) %>%
    summarise(accuracy = mean(correct), n = n(), .groups = "drop")
  obs_rows <- c(obs_rows, list(obs))
}

# M2: date x dim_rank per family
for (fam in families) {
  fam_df <- df %>% filter(family == fam)
  if (n_distinct(fam_df$date_years) < 2) next

  formula <- correct ~ date_c * dim_rank + (1 | item_id)
  if (n_distinct(fam_df$model) >= 3) {
    formula <- correct ~ date_c * dim_rank + (1 | item_id) + (1 | model)
  }
  fit <- safe_glmer(formula, fam_df, label = paste0("M2:", fam))
  if (is.null(fit)) next

  fe <- broom.mixed::tidy(fit, effects = "fixed", conf.int = TRUE, exponentiate = TRUE) %>%
    mutate(family = fam, model_label = "M2_date_x_dimrank")
  or_rows <- c(or_rows, list(fe))

  dim_ranks <- sort(unique(fam_df$dim_rank))
  dim_labels <- fam_df %>% distinct(tom_dimension, dim_rank, validated_age_band) %>% arrange(dim_rank)
  coefs <- fixef(fit)
  vcov_mat <- vcov(fit)
  date_idx <- which(names(coefs) == "date_c")
  int_idx <- which(names(coefs) == "date_c:dim_rank")

  if (length(int_idx) == 1) {
    for (dr in dim_ranks) {
      slope <- coefs[date_idx] + coefs[int_idx] * dr
      se <- sqrt(vcov_mat[date_idx, date_idx] + dr^2 * vcov_mat[int_idx, int_idx] +
                   2 * dr * vcov_mat[date_idx, int_idx])
      dim_info <- dim_labels %>% filter(dim_rank == dr)
      dim_slope_rows <- c(dim_slope_rows, list(data.frame(
        family = fam, dim_rank = dr,
        tom_dimension = if (nrow(dim_info) > 0) dim_info$tom_dimension[1] else NA,
        validated_age_band = if (nrow(dim_info) > 0) dim_info$validated_age_band[1] else NA,
        slope_logodds = slope, slope_or = exp(slope), se = se,
        lo = exp(slope - 1.96 * se), hi = exp(slope + 1.96 * se),
        stringsAsFactors = FALSE
      )))
    }
  }
}

# M4: joint date x family
cat("  Fitting M4 (joint cross-family)...\n")
fit_m4 <- NULL
if (n_distinct(df$family) >= 2) {
  formula <- correct ~ date_c * family + (1 | item_id) + (1 | model)
  fit_m4 <- safe_glmer(formula, df, label = "M4:joint")
  if (!is.null(fit_m4)) {
    fe <- tidy(fit_m4, effects = "fixed", conf.int = TRUE, exponentiate = TRUE) %>%
      mutate(family = "ALL", model_label = "M4_date_x_family")
    or_rows <- c(or_rows, list(fe))
  }
  # LRT
  fit_null <- safe_glmer(correct ~ date_c + (1 | item_id), df, label = "M4:null")
  if (!is.null(fit_m4) && !is.null(fit_null)) {
    lrt <- anova(fit_null, fit_m4)
    lrt_df <- data.frame(
      comparison = "date_only vs date_x_family",
      chi2 = lrt$Chisq[2], p = lrt[["Pr(>Chisq)"]][2]
    )
    write_csv(lrt_df, file.path(mod_dir, "glmm_lrt.csv"))
    cat(sprintf("  M4 LRT: chi2=%.2f, p=%s\n", lrt_df$chi2, format.pval(lrt_df$p)))
  }
}

# Save GLMM outputs
if (length(or_rows) > 0) {
  or_table <- bind_rows(or_rows)
  write_csv(or_table, file.path(mod_dir, "glmm_or_table.csv"))
}
if (length(pred_rows) > 0) {
  pred_df <- bind_rows(pred_rows)
  write_csv(pred_df, file.path(mod_dir, "glmm_pred_trajectory.csv"))
}
if (length(obs_rows) > 0) {
  obs_df <- bind_rows(obs_rows)
  write_csv(obs_df, file.path(mod_dir, "glmm_observed_points.csv"))
}
if (length(dim_slope_rows) > 0) {
  dim_slopes <- bind_rows(dim_slope_rows)
  write_csv(dim_slopes, file.path(mod_dir, "glmm_dim_time_slopes.csv"))
}

# --- D.FIGURES: GLMM ---
cat("\n--- GLMM figures ---\n")

# (20) Trajectory by tier
if (length(pred_rows) > 0 && length(obs_rows) > 0) {
  pred_df <- bind_rows(pred_rows) %>% mutate(family = factor(family, levels = FAMILY_ORDER))
  obs_df <- bind_rows(obs_rows) %>% mutate(family = factor(family, levels = FAMILY_ORDER))

  p20 <- ggplot() +
    geom_line(data = pred_df, aes(x = date_years, y = pred, color = tier), linewidth = 0.7) +
    geom_point(data = obs_df, aes(x = date_years, y = accuracy, color = tier), size = 2) +
    scale_color_manual(values = TYPE_COLORS) +
    geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey50", linewidth = 0.4) +
    coord_cartesian(ylim = c(0, 1.05)) +
    facet_wrap(~ family, nrow = 1) +
    scale_x_date_years(step = 1) +
    labs(title = "Free Response: GLMM Predicted Trajectory by Tier",
         x = "Release Date", y = "P(correct)", color = "Tier") +
    theme_devtom() +
    theme(legend.text = element_text(size = 7))
  save_plot(p20, "glmm_trajectory_by_tier.png", w = WW, h = 6)
}

# (21) OR forest plot
if (length(or_rows) > 0) {
  or_table <- bind_rows(or_rows)
  m1_fe <- or_table %>%
    filter(model_label == "M1_date_x_tier", term != "(Intercept)") %>%
    mutate(label = paste0(family, ": ", term))

  if (nrow(m1_fe) > 0) {
    p21 <- ggplot(m1_fe, aes(x = estimate, y = reorder(label, estimate))) +
      geom_vline(xintercept = 1, linetype = "dashed", color = "grey50") +
      geom_point(size = 2.5) +
      geom_errorbarh(aes(xmin = conf.low, xmax = conf.high), height = 0.3) +
      scale_x_log10() +
      labs(title = "Free Response: GLMM Fixed-Effect Odds Ratios (M1)",
           x = "Odds Ratio (log scale)", y = NULL) +
      theme_devtom()
    save_plot(p21, "glmm_or_forest_plot.png", w = 10, h = max(4, nrow(m1_fe) * 0.4 + 2))
  }
}

# (22) Dimension time slopes
if (length(dim_slope_rows) > 0) {
  dim_slopes <- bind_rows(dim_slope_rows) %>%
    filter(!is.na(tom_dimension)) %>%
    mutate(tom_dimension = factor_dimension(tom_dimension))

  p22 <- ggplot(dim_slopes, aes(x = slope_or, y = tom_dimension, color = family)) +
    geom_vline(xintercept = 1, linetype = "dashed", color = "grey50") +
    geom_point(size = 2.5, position = position_dodge(0.5)) +
    geom_errorbarh(aes(xmin = lo, xmax = hi), height = 0.3,
                   position = position_dodge(0.5)) +
    scale_x_log10() +
    scale_color_manual(values = FAMILY_COLORS) +
    labs(title = "Free Response: Per-Dimension Time Slopes (OR/year)",
         subtitle = "Developmental order (easiest at top)",
         x = "OR per year (log scale)", y = NULL, color = "Family") +
    theme_devtom()
  save_plot(p22, "glmm_dim_time_slopes.png", w = 10, h = 7)
}

# ============================================================================
# E. IRT / DEVELOPMENTAL MAPPING
# ============================================================================
cat("\n=== E. IRT / Developmental Mapping ===\n")

suppressPackageStartupMessages(library(mirt))

# Build response matrix
resp_matrix <- df %>%
  select(model, item_id, correct) %>%
  pivot_wider(names_from = item_id, values_from = correct, values_fn = first) %>%
  column_to_rownames("model")

# Drop zero-variance items
item_vars <- apply(resp_matrix, 2, var, na.rm = TRUE)
zero_var <- names(item_vars[item_vars == 0 | is.na(item_vars)])
if (length(zero_var) > 0) {
  cat(sprintf("  Dropping %d zero-variance items\n", length(zero_var)))
  resp_matrix <- resp_matrix[, !names(resp_matrix) %in% zero_var]
}
cat(sprintf("  %d persons × %d items\n", nrow(resp_matrix), ncol(resp_matrix)))

# Rasch fit
cat("  Fitting Rasch (1PL)...\n")
rasch_fit <- tryCatch(
  mirt(as.matrix(resp_matrix), model = 1, itemtype = "Rasch", verbose = FALSE, SE = TRUE),
  error = function(e) { cat("  Rasch error:", conditionMessage(e), "\n"); NULL }
)

# 2PL fit
cat("  Fitting 2PL...\n")
twopl_fit <- tryCatch(
  mirt(as.matrix(resp_matrix), model = 1, itemtype = "2PL", verbose = FALSE, SE = TRUE),
  error = function(e) { cat("  2PL error:", conditionMessage(e), "\n"); NULL }
)

primary_fit <- if (!is.null(rasch_fit)) rasch_fit else twopl_fit

if (!is.null(primary_fit)) {
  # Theta extraction
  theta <- fscores(primary_fit, method = "EAP", full.scores.SE = TRUE)
  meta <- df %>% distinct(model, family, tier, date_years, release_date)
  theta_df <- data.frame(
    model = rownames(resp_matrix),
    theta = theta[, 1], theta_se = theta[, 2],
    stringsAsFactors = FALSE
  ) %>% left_join(meta, by = "model") %>%
    mutate(short = short_model(model))

  # Item parameters
  item_params <- coef(primary_fit, simplify = TRUE, IRTpars = TRUE)$items
  item_df <- data.frame(item_id = rownames(item_params), stringsAsFactors = FALSE)
  if ("a" %in% colnames(item_params)) item_df$a <- item_params[, "a"]
  if ("b" %in% colnames(item_params)) item_df$b <- item_params[, "b"]
  item_meta <- df %>% distinct(item_id, tom_dimension, validated_age_band, age_mid, dim_rank)
  item_df <- item_df %>% left_join(item_meta, by = "item_id")

  # Difficulty vs age correlation
  valid_items <- item_df %>% filter(!is.na(b), !is.na(age_mid))
  if (nrow(valid_items) >= 4) {
    sp <- cor.test(valid_items$b, valid_items$age_mid, method = "spearman")
    cat(sprintf("  IRT difficulty vs age: rho=%.3f, p=%.4f\n", sp$estimate, sp$p.value))
    write_csv(data.frame(spearman_rho = round(sp$estimate, 4), spearman_p = sp$p.value,
                          n = nrow(valid_items)),
              file.path(mod_dir, "irt_difficulty_vs_age.csv"))
  }

  # Age-anchored theta
  if (nrow(valid_items) >= 4) {
    age_reg <- lm(age_mid ~ b, data = valid_items)
    theta_df$age_anchored_theta <- predict(age_reg, newdata = data.frame(b = theta_df$theta))
    cat(sprintf("  Age anchoring: intercept=%.2f, slope=%.2f, R²=%.3f\n",
                coef(age_reg)[1], coef(age_reg)[2], summary(age_reg)$r.squared))
  }

  write_csv(theta_df, file.path(mod_dir, "irt_theta.csv"))
  write_csv(item_df, file.path(mod_dir, "irt_item_params.csv"))

  # Wright map data
  wright <- data.frame(
    type = c(rep("item", nrow(item_df)), rep("person", nrow(theta_df))),
    label = c(item_df$item_id, theta_df$model),
    value = c(item_df$b, theta_df$theta),
    stringsAsFactors = FALSE
  )
  write_csv(wright, file.path(mod_dir, "wright_map.csv"))

  # Profile vectors (pass/fail with Wilson LB > 0 for FR)
  profile <- df %>%
    group_by(model, family, tier, tom_dimension, validated_age_band, dim_rank, date_years) %>%
    summarise(n = n(), n_correct = sum(correct), .groups = "drop") %>%
    rowwise() %>%
    mutate(w = list(wilson_ci(n_correct, n)),
           accuracy = w[["p"]], wilson_lo = w[["lo"]]) %>%
    select(-w) %>%
    ungroup() %>%
    mutate(pass = as.integer(wilson_lo > 0.0))
  write_csv(profile, file.path(mod_dir, "profile_vectors.csv"))

  # Frontier age band
  age_band_order <- df %>%
    distinct(validated_age_band, age_lo, age_hi, age_mid) %>%
    filter(!is.na(age_mid)) %>% arrange(age_mid)

  frontier_rows <- list()
  for (mod in unique(profile$model)) {
    mod_prof <- profile %>% filter(model == mod)
    if (nrow(mod_prof) == 0) next
    mod_info <- mod_prof %>% slice(1)
    best_band <- NA
    bands <- age_band_order$validated_age_band
    for (b_idx in seq_along(bands)) {
      dims_below <- mod_prof %>% filter(validated_age_band %in% bands[1:b_idx])
      if (nrow(dims_below) > 0 && mean(dims_below$pass) >= 2/3) best_band <- bands[b_idx]
    }
    frontier_rows <- c(frontier_rows, list(data.frame(
      model = mod, family = as.character(mod_info$family), tier = as.character(mod_info$tier),
      frontier_band = best_band, date_years = mod_info$date_years,
      stringsAsFactors = FALSE
    )))
  }
  frontier_df <- bind_rows(frontier_rows) %>%
    left_join(age_band_order %>% select(validated_age_band, age_mid),
              by = c("frontier_band" = "validated_age_band")) %>%
    rename(frontier_age_mid = age_mid)
  write_csv(frontier_df, file.path(mod_dir, "frontier.csv"))

  # --- E.FIGURES: IRT ---
  cat("\n--- IRT figures ---\n")

  # (23) Wright map
  wright_items <- wright %>% filter(type == "item")
  wright_persons <- wright %>% filter(type == "person") %>%
    left_join(theta_df %>% select(model, family, short), by = c("label" = "model"))

  p23 <- ggplot() +
    geom_point(data = wright_items, aes(x = value, y = 0.5), shape = 4,
               color = "grey40", size = 2, alpha = 0.6) +
    geom_point(data = wright_persons, aes(x = value, y = 1.5, color = family), size = 2.5) +
    geom_text_repel(data = wright_persons, aes(x = value, y = 1.5, label = short),
                    size = 2, max.overlaps = 20) +
    scale_color_manual(values = FAMILY_COLORS) +
    scale_y_continuous(breaks = c(0.5, 1.5), labels = c("Items (b)", "Models (theta)")) +
    labs(title = "Free Response: Wright Map (Item-Person Map)",
         x = "Logit Scale", y = NULL, color = "Family") +
    theme_devtom() +
    theme(panel.grid.major.y = element_blank())
  save_plot(p23, "wright_map.png", w = 12, h = 5)

  # (24) Theta trajectory — per-tier
  theta_plot <- theta_df %>%
    mutate(family = factor(family, levels = FAMILY_ORDER),
           tier = factor_tier(tier))

  p24 <- ggplot(theta_plot, aes(x = date_years, y = theta, color = tier)) +
    geom_point(size = 2.5) +
    geom_text_repel(aes(label = short), size = 2, max.overlaps = 15, show.legend = FALSE) +
    geom_smooth(method = "lm", se = TRUE, alpha = 0.1, linewidth = 0.6) +
    scale_color_manual(values = TYPE_COLORS) +
    scale_x_date_years() +
    labs(title = "Free Response: IRT Theta vs. Release Date",
         x = "Release Date", y = "IRT Theta (EAP)", color = "Tier") +
    theme_devtom() +
    theme(legend.text = element_text(size = 7))
  save_plot(p24, "irt_theta_trajectory.png")

  # (25) Age-anchored theta trajectory — per-tier
  if ("age_anchored_theta" %in% names(theta_df)) {
    p25 <- ggplot(theta_plot, aes(x = date_years, y = age_anchored_theta, color = tier)) +
      geom_point(size = 2.5) +
      geom_text_repel(aes(label = short), size = 2, max.overlaps = 15, show.legend = FALSE) +
      geom_smooth(method = "lm", se = TRUE, alpha = 0.1, linewidth = 0.6) +
      scale_color_manual(values = TYPE_COLORS) +
      scale_x_date_years() +
      labs(title = "Free Response: Age-Equivalent Theta vs. Release Date",
           x = "Release Date", y = "Age-Equivalent (years)", color = "Tier") +
      theme_devtom() +
      theme(legend.text = element_text(size = 7))
    save_plot(p25, "irt_age_equivalent_trajectory.png")
  }

  # (26) Difficulty vs developmental age
  if (nrow(valid_items) >= 4) {
    p26 <- ggplot(valid_items, aes(x = age_mid, y = b)) +
      geom_point(aes(color = tom_dimension), size = 2.5, alpha = 0.7) +
      geom_smooth(method = "lm", se = TRUE, color = "black", linewidth = 0.6, alpha = 0.15) +
      labs(title = "Free Response: IRT Difficulty vs. Developmental Age",
           subtitle = sprintf("Spearman rho = %.3f, p = %.4f", sp$estimate, sp$p.value),
           x = "Target Developmental Age (years)", y = "IRT Difficulty (b)",
           color = "Dimension") +
      theme_devtom() +
      theme(legend.text = element_text(size = 7))
    save_plot(p26, "irt_difficulty_vs_age.png")
  }

  # (27) Profile heatmap (pass/fail)
  profile_plot <- profile %>%
    mutate(model = factor(model, levels = model_order),
           short = short_model(as.character(model)),
           tom_dimension = factor_dimension(tom_dimension))

  p27 <- ggplot(profile_plot, aes(x = tom_dimension, y = short, fill = factor(pass))) +
    geom_tile() +
    scale_fill_manual(values = c("0" = "#d73027", "1" = "#1a9850"),
                      labels = c("Fail", "Pass")) +
    labs(title = "Free Response: Developmental Pass/Fail Profile",
         subtitle = "Pass = Wilson LB > 0 (above chance for free response)",
         x = NULL, y = NULL, fill = NULL) +
    theme_devtom() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
          axis.text.y = element_text(size = 5))
  save_plot(p27, "profile_heatmap.png", w = 11, h = 14)

  # (28) Frontier trajectory — per-tier
  frontier_plot <- frontier_df %>%
    filter(!is.na(frontier_age_mid)) %>%
    mutate(family = factor(family, levels = FAMILY_ORDER),
           tier = factor_tier(tier),
           short = short_model(model))

  if (nrow(frontier_plot) > 0) {
    p28 <- ggplot(frontier_plot, aes(x = date_years, y = frontier_age_mid, color = tier)) +
      geom_point(size = 2.5) +
      geom_text_repel(aes(label = short), size = 2, max.overlaps = 15, show.legend = FALSE) +
      scale_color_manual(values = TYPE_COLORS) +
      scale_x_date_years() +
      labs(title = "Free Response: Frontier Developmental Age vs. Release Date",
           x = "Release Date", y = "Frontier Age Band (years)", color = "Tier") +
      theme_devtom() +
      theme(legend.text = element_text(size = 7))
    save_plot(p28, "frontier_trajectory.png")
  }
}

# ============================================================================
# F. SIZE SCALING GLMM
# ============================================================================
cat("\n=== F. Size Scaling GLMM ===\n")

ALL_FAMILIES <- c("Claude", "GPT", "Llama", "Qwen", "Mistral")

df_ss <- df %>%
  filter(family %in% ALL_FAMILIES, !is.na(log_params)) %>%
  mutate(
    family = factor(family, levels = ALL_FAMILIES),
    log_params_c = log_params - mean(log_params),
    date_c = date_years - mean(date_years)
  )

n_ss_models <- n_distinct(df_ss$model)
cat(sprintf("  Size scaling: %d rows, %d models\n", nrow(df_ss), n_ss_models))

ss_or_rows <- list()

# S1: size x date + family
fit_s1 <- safe_glmer(
  correct ~ log_params_c * date_c + family + (1 | item_id) + (1 | model),
  df_ss, label = "S1"
)
if (!is.null(fit_s1)) {
  fe <- tidy(fit_s1, effects = "fixed", conf.int = TRUE, exponentiate = TRUE) %>%
    mutate(model_label = "S1_size_x_date")
  ss_or_rows <- c(ss_or_rows, list(fe))
}

# S2: size x family
fit_s2 <- safe_glmer(
  correct ~ log_params_c * family + (1 | item_id) + (1 | model),
  df_ss, label = "S2"
)
if (!is.null(fit_s2)) {
  fe <- tidy(fit_s2, effects = "fixed", conf.int = TRUE, exponentiate = TRUE) %>%
    mutate(model_label = "S2_size_x_family")
  ss_or_rows <- c(ss_or_rows, list(fe))
}

# S3: date x family
fit_s3 <- safe_glmer(
  correct ~ date_c * family + (1 | item_id) + (1 | model),
  df_ss, label = "S3"
)
if (!is.null(fit_s3)) {
  fe <- tidy(fit_s3, effects = "fixed", conf.int = TRUE, exponentiate = TRUE) %>%
    mutate(model_label = "S3_date_x_family")
  ss_or_rows <- c(ss_or_rows, list(fe))
}

# Null + LRT
fit_ss_null <- safe_glmer(
  correct ~ 1 + (1 | item_id) + (1 | model),
  df_ss, label = "SS_null"
)

if (!is.null(fit_s1) && !is.null(fit_ss_null)) {
  lrt <- anova(fit_ss_null, fit_s1)
  ss_lrt <- data.frame(
    comparison = "null vs S1", chi2 = lrt$Chisq[2], p = lrt[["Pr(>Chisq)"]][2]
  )
  write_csv(ss_lrt, file.path(mod_dir, "size_scaling_lrt.csv"))
  cat(sprintf("  S1 vs null: chi2=%.2f, p=%s\n", ss_lrt$chi2, format.pval(ss_lrt$p)))
}

# Save OR table
if (length(ss_or_rows) > 0) {
  ss_or <- bind_rows(ss_or_rows)
  write_csv(ss_or, file.path(mod_dir, "size_scaling_or_table.csv"))

  # Print key ORs
  s1_fe <- ss_or %>% filter(model_label == "S1_size_x_date")
  for (i in seq_len(nrow(s1_fe))) {
    cat(sprintf("  S1 %s: OR=%.2f, p=%s\n",
                s1_fe$term[i], s1_fe$estimate[i], format.pval(s1_fe$p.value[i])))
  }
}

# Observed per-model
ss_obs <- df_ss %>%
  group_by(family, tier, model, date_years, params_b, log_params) %>%
  summarise(accuracy = mean(correct), n = n(), .groups = "drop")
write_csv(ss_obs, file.path(mod_dir, "size_scaling_observed.csv"))

# Prediction grids
mean_lp <- mean(df_ss$log_params)
mean_dy <- mean(df_ss$date_years)

if (!is.null(fit_s2)) {
  lp_range <- seq(min(df_ss$log_params), max(df_ss$log_params), length.out = 50)
  grid_size <- expand.grid(log_params_c = lp_range - mean_lp,
                            family = levels(df_ss$family), stringsAsFactors = FALSE) %>%
    mutate(family = factor(family, levels = ALL_FAMILIES))
  tryCatch({
    grid_size$pred <- predict(fit_s2, newdata = grid_size, type = "response", re.form = NA)
    grid_size$log_params <- grid_size$log_params_c + mean_lp
    grid_size$params_b <- 10^grid_size$log_params
    write_csv(grid_size, file.path(mod_dir, "size_scaling_pred_by_size.csv"))
  }, error = function(e) NULL)
}

if (!is.null(fit_s3)) {
  d_range <- seq(min(df_ss$date_years), max(df_ss$date_years), length.out = 50)
  grid_date <- expand.grid(date_c = d_range - mean_dy,
                             family = levels(df_ss$family), stringsAsFactors = FALSE) %>%
    mutate(family = factor(family, levels = ALL_FAMILIES))
  tryCatch({
    grid_date$pred <- predict(fit_s3, newdata = grid_date, type = "response", re.form = NA)
    grid_date$date_years <- grid_date$date_c + mean_dy
    write_csv(grid_date, file.path(mod_dir, "size_scaling_pred_by_date.csv"))
  }, error = function(e) NULL)
}

if (!is.null(fit_s1)) {
  lp_r <- seq(min(df_ss$log_params), max(df_ss$log_params), length.out = 30)
  d_r <- seq(min(df_ss$date_years), max(df_ss$date_years), length.out = 30)
  grid_2d <- expand.grid(log_params_c = lp_r - mean_lp, date_c = d_r - mean_dy,
                          family = levels(df_ss$family), stringsAsFactors = FALSE) %>%
    mutate(family = factor(family, levels = ALL_FAMILIES))
  tryCatch({
    grid_2d$pred <- predict(fit_s1, newdata = grid_2d, type = "response", re.form = NA)
    grid_2d$log_params <- grid_2d$log_params_c + mean_lp
    grid_2d$params_b <- 10^grid_2d$log_params
    grid_2d$date_years <- grid_2d$date_c + mean_dy
    write_csv(grid_2d, file.path(mod_dir, "size_scaling_pred_interaction.csv"))
  }, error = function(e) NULL)
}

# --- F.FIGURES: Size Scaling ---
cat("\n--- Size scaling figures ---\n")

param_breaks <- c(8, 20, 70, 200, 400, 1760)
log_breaks <- log10(param_breaks)
param_labels <- paste0(param_breaks, "B")

# (29) Size vs accuracy by family
if (file.exists(file.path(mod_dir, "size_scaling_pred_by_size.csv"))) {
  grid_size <- read_csv(file.path(mod_dir, "size_scaling_pred_by_size.csv"), show_col_types = FALSE) %>%
    mutate(family = factor(family, levels = ALL_FAMILIES))

  p29 <- ggplot() +
    geom_line(data = grid_size, aes(x = log_params, y = pred), color = "black", linewidth = 0.6) +
    geom_point(data = ss_obs, aes(x = log_params, y = accuracy, color = tier), size = 2.5) +
    scale_x_continuous(breaks = log_breaks, labels = param_labels) +
    scale_color_manual(values = TYPE_COLORS) +
    geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey50", linewidth = 0.4) +
    coord_cartesian(ylim = c(0, 1.05)) +
    facet_wrap(~ family, nrow = 1) +
    labs(title = "Free Response: Model Size vs. Accuracy (S2 prediction)",
         x = "Parameters (log scale)", y = "Accuracy", color = "Tier") +
    theme_devtom() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7))
  save_plot(p29, "size_vs_accuracy.png", w = WW, h = 6)
}

# (30) Date vs accuracy by family
if (file.exists(file.path(mod_dir, "size_scaling_pred_by_date.csv"))) {
  grid_date <- read_csv(file.path(mod_dir, "size_scaling_pred_by_date.csv"), show_col_types = FALSE) %>%
    mutate(family = factor(family, levels = ALL_FAMILIES))

  p30 <- ggplot() +
    geom_line(data = grid_date, aes(x = date_years, y = pred), color = "black", linewidth = 0.6) +
    geom_point(data = ss_obs, aes(x = date_years, y = accuracy, color = tier), size = 2.5) +
    scale_color_manual(values = TYPE_COLORS) +
    geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey50", linewidth = 0.4) +
    coord_cartesian(ylim = c(0, 1.05)) +
    facet_wrap(~ family, nrow = 1) +
    scale_x_date_years(step = 1) +
    labs(title = "Free Response: Release Date vs. Accuracy (S3 prediction)",
         x = "Release Date", y = "Accuracy", color = "Tier") +
    theme_devtom()
  save_plot(p30, "date_vs_accuracy.png", w = WW, h = 6)
}

# (31) Size-date interaction contour
if (file.exists(file.path(mod_dir, "size_scaling_pred_interaction.csv"))) {
  grid_2d <- read_csv(file.path(mod_dir, "size_scaling_pred_interaction.csv"), show_col_types = FALSE) %>%
    mutate(family = factor(family, levels = ALL_FAMILIES))

  p31 <- ggplot(grid_2d, aes(x = date_years, y = log_params)) +
    geom_tile(aes(fill = pred)) +
    geom_contour(aes(z = pred), color = "white", linewidth = 0.3) +
    geom_point(data = ss_obs, aes(x = date_years, y = log_params), size = 1.5) +
    scale_fill_viridis_c(option = "C", limits = c(0, 1), labels = scales::percent) +
    scale_y_continuous(breaks = log_breaks, labels = param_labels) +
    facet_wrap(~ family, nrow = 1) +
    scale_x_date_years(step = 1) +
    labs(title = "Free Response: Size × Date Interaction (S1 prediction)",
         x = "Release Date", y = "Parameters", fill = "P(correct)") +
    theme_devtom()
  save_plot(p31, "size_date_interaction_contour.png", w = WW, h = 5)
}

# (32) Size-binned trajectory
ss_obs_binned <- ss_obs %>%
  mutate(size_cat = case_when(
    params_b < 10  ~ "Small (<10B)",
    params_b < 50  ~ "Mid (10-50B)",
    params_b < 100 ~ "Large (50-100B)",
    TRUE           ~ "XL (100B+)"
  )) %>%
  mutate(size_cat = factor(size_cat, levels = c("Small (<10B)", "Mid (10-50B)",
                                                  "Large (50-100B)", "XL (100B+)")),
         family = factor(family, levels = ALL_FAMILIES))

p32 <- ggplot(ss_obs_binned, aes(x = date_years, y = accuracy, color = size_cat)) +
  geom_point(size = 2, alpha = 0.7) +
  geom_smooth(method = "lm", se = TRUE, linewidth = 0.6, alpha = 0.1) +
  geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey50", linewidth = 0.4) +
  coord_cartesian(ylim = c(0, 1.05)) +
  facet_wrap(~ family, nrow = 1) +
  scale_x_date_years(step = 1) +
  labs(title = "Free Response: Size-Binned Accuracy Trajectory",
       x = "Release Date", y = "Accuracy", color = "Size Category") +
  theme_devtom()
save_plot(p32, "size_binned_trajectory.png", w = WW, h = 6)

# (33) Size scaling OR forest
if (length(ss_or_rows) > 0) {
  s1_fe <- bind_rows(ss_or_rows) %>%
    filter(model_label == "S1_size_x_date", term != "(Intercept)")

  if (nrow(s1_fe) > 0) {
    p33 <- ggplot(s1_fe, aes(x = estimate, y = reorder(term, estimate))) +
      geom_vline(xintercept = 1, linetype = "dashed", color = "grey50") +
      geom_point(size = 3) +
      geom_errorbarh(aes(xmin = conf.low, xmax = conf.high), height = 0.3) +
      scale_x_log10() +
      labs(title = "Free Response: Size Scaling Fixed Effects (S1)",
           x = "Odds Ratio (log scale)", y = NULL) +
      theme_devtom()
    save_plot(p33, "size_scaling_forest_plot.png", w = 9, h = max(4, nrow(s1_fe) * 0.5 + 2))
  }
}

# (34) Age-binned vs size (faceted by family)
age_size_data <- df_ss %>%
  filter(!is.na(age_mid)) %>%
  mutate(age_bin = cut(age_mid, breaks = c(0, 4, 6, 8, 12),
                        labels = c("2-4 yr", "4-6 yr", "6-8 yr", "8-12 yr"))) %>%
  group_by(model, family, tier, age_bin, log_params, params_b) %>%
  summarise(accuracy = mean(correct), .groups = "drop") %>%
  mutate(family = factor(family, levels = ALL_FAMILIES))

p34 <- ggplot(age_size_data, aes(x = log_params, y = accuracy, color = tier)) +
  geom_point(size = 1.5, alpha = 0.7) +
  geom_smooth(aes(group = age_bin), method = "lm", se = TRUE,
              color = "black", linewidth = 0.5, alpha = 0.1) +
  scale_x_continuous(breaks = log_breaks, labels = param_labels) +
  geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey50", linewidth = 0.4) +
  coord_cartesian(ylim = c(0, 1.05)) +
  facet_grid(age_bin ~ family) +
  scale_color_manual(values = TYPE_COLORS) +
  labs(title = "Free Response: Accuracy by Age Band × Model Size",
       x = "Parameters", y = "Accuracy", color = "Tier") +
  theme_devtom(base_size = 9) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 6))
save_plot(p34, "age_binned_vs_size.png", w = WW, h = 10)

# (35) Age-binned vs date
age_date_data <- df_ss %>%
  filter(!is.na(age_mid)) %>%
  mutate(age_bin = cut(age_mid, breaks = c(0, 4, 6, 8, 12),
                        labels = c("2-4 yr", "4-6 yr", "6-8 yr", "8-12 yr"))) %>%
  group_by(model, family, tier, age_bin, date_years) %>%
  summarise(accuracy = mean(correct), .groups = "drop") %>%
  mutate(family = factor(family, levels = ALL_FAMILIES))

p35 <- ggplot(age_date_data, aes(x = date_years, y = accuracy, color = tier)) +
  geom_point(size = 1.5, alpha = 0.7) +
  geom_smooth(aes(group = age_bin), method = "lm", se = TRUE,
              color = "black", linewidth = 0.5, alpha = 0.1) +
  scale_color_manual(values = TYPE_COLORS) +
  geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey50", linewidth = 0.4) +
  coord_cartesian(ylim = c(0, 1.05)) +
  facet_grid(age_bin ~ family) +
  labs(title = "Free Response: Accuracy by Age Band × Release Date",
       x = "Release Date", y = "Accuracy", color = "Tier") +
  theme_devtom(base_size = 9)
save_plot(p35, "age_binned_vs_date.png", w = WW, h = 10)

# (36) Combined all-models age-binned vs size — per-tier
age_size_data <- age_size_data %>% mutate(tier = factor_tier(tier))

p36 <- ggplot(age_size_data, aes(x = log_params, y = accuracy, color = tier)) +
  geom_point(size = 1.5, alpha = 0.6) +
  geom_smooth(method = "lm", se = TRUE, linewidth = 0.6, alpha = 0.1) +
  scale_x_continuous(breaks = log_breaks, labels = param_labels) +
  scale_color_manual(values = TYPE_COLORS) +
  geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey50", linewidth = 0.4) +
  coord_cartesian(ylim = c(0, 1.05)) +
  facet_wrap(~ age_bin, nrow = 1) +
  labs(title = "Free Response: All Models — Accuracy by Age Band × Size",
       x = "Parameters", y = "Accuracy", color = "Tier") +
  theme_devtom() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
        legend.text = element_text(size = 6))
save_plot(p36, "age_binned_vs_size_combined.png", w = WW, h = 5)

# (37) All models combined size vs accuracy — per-tier
ss_obs <- ss_obs %>% mutate(tier = factor_tier(tier))

p37 <- ggplot(ss_obs, aes(x = log_params, y = accuracy, color = tier)) +
  geom_point(size = 3, alpha = 0.7) +
  geom_smooth(method = "lm", se = TRUE, linewidth = 0.7, alpha = 0.1) +
  geom_text_repel(aes(label = short_model(as.character(model))), size = 2, max.overlaps = 12, show.legend = FALSE) +
  scale_x_continuous(breaks = log_breaks, labels = param_labels) +
  scale_color_manual(values = TYPE_COLORS) +
  geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey50", linewidth = 0.4) +
  coord_cartesian(ylim = c(0, 1.05)) +
  labs(title = "Free Response: All Models — Size vs. Accuracy",
       x = "Parameters (log scale)", y = "Accuracy", color = "Tier") +
  theme_devtom() +
  theme(legend.text = element_text(size = 7))
save_plot(p37, "all_models_size_vs_accuracy.png", w = 11, h = 7)

# (38) Age-size heatmap
heat_age_size <- df_ss %>%
  filter(!is.na(age_mid)) %>%
  mutate(
    age_bin = cut(age_mid, breaks = c(0, 4, 6, 8, 12),
                  labels = c("2-4 yr", "4-6 yr", "6-8 yr", "8-12 yr")),
    size_bin = cut(params_b, breaks = c(0, 10, 50, 100, 2000),
                   labels = c("<10B", "10-50B", "50-100B", "100B+"))
  ) %>%
  group_by(age_bin, size_bin, family) %>%
  summarise(accuracy = mean(correct), n = n(), .groups = "drop") %>%
  mutate(family = factor(family, levels = ALL_FAMILIES))

p38 <- ggplot(heat_age_size, aes(x = size_bin, y = age_bin, fill = accuracy)) +
  geom_tile() +
  geom_text(aes(label = sprintf("%.0f%%", accuracy * 100)), size = 3) +
  scale_fill_gradient2(low = "#d73027", mid = "#ffffbf", high = "#1a9850",
                       midpoint = 0.5, limits = c(0, 1)) +
  facet_wrap(~ family, nrow = 1) +
  labs(title = "Free Response: Age Band × Size Bin Accuracy",
       x = "Model Size", y = "Developmental Age", fill = "Accuracy") +
  theme_devtom() +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))
save_plot(p38, "age_size_heatmap.png", w = WW, h = 5)

# ============================================================================
# SUMMARY
# ============================================================================
n_figs <- length(list.files(fig_dir, pattern = "\\.png$"))
cat(sprintf("\n=== DONE: %d figures written to %s/ ===\n", n_figs, fig_dir))
cat(sprintf("Stats: %s/\nModeling: %s/\n", stat_dir, mod_dir))

# Write summary stats for PPTX/poster creation
summary_stats <- list(
  n_models = nlevels(df$model),
  n_items = nlevels(df$item_id),
  n_rows = nrow(df),
  n_families = length(levels(df$family)),
  best_model = best_model$short[1],
  best_acc = round(best_model$accuracy[1] * 100, 1),
  worst_model = worst_genuine$short[1],
  worst_acc = round(worst_genuine$accuracy[1] * 100, 1),
  hardest_dim = dim_diff$tom_dimension[which.min(dim_diff$accuracy)],
  hardest_acc = round(min(dim_diff$accuracy) * 100, 1),
  easiest_dim = dim_diff$tom_dimension[which.max(dim_diff$accuracy)],
  easiest_acc = round(max(dim_diff$accuracy) * 100, 1),
  n_ss_models = n_ss_models,
  timestamp = stamp
)

sink(file.path(base_dir, "summary.txt"))
cat("=== DevToM FRQ Summary ===\n")
for (nm in names(summary_stats)) {
  cat(sprintf("%-20s: %s\n", nm, summary_stats[[nm]]))
}
cat("\n--- Family means (FR) ---\n")
print(family_summ)
cat("\n--- Dimension difficulty (FR) ---\n")
print(dim_diff %>% arrange(accuracy))
sink()

cat(sprintf("Summary: %s/summary.txt\n", base_dir))
