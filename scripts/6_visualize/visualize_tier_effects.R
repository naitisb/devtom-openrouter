#!/usr/bin/env Rscript
# visualize_tier_effects.R — Visualize categorical tier effects from GLM, GLMM, IRT

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(patchwork)
})

source("scripts/6_visualize/_theme.R")

# Find latest tier effects directory
base_dir <- "results/modeling/tier_effects"
ts_dirs <- list.dirs(base_dir, recursive = FALSE, full.names = TRUE)
model_dir <- sort(ts_dirs, decreasing = TRUE)[1]
cat("Reading from:", model_dir, "\n")

# Output figures directory
fig_ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
fig_dir <- file.path("results/figures/tier_effects", fig_ts)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
cat("Figures dir:", fig_dir, "\n")

# =========================================================================
# Load data
# =========================================================================
glm_coefs <- read_csv(file.path(model_dir, "glm_tier_coefficients.csv"),
                      show_col_types = FALSE)
glm_lrt <- read_csv(file.path(model_dir, "glm_tier_lrt.csv"),
                    show_col_types = FALSE)
glm_preds <- read_csv(file.path(model_dir, "glm_tier_predictions.csv"),
                      show_col_types = FALSE)

glmm_coefs_file <- file.path(model_dir, "glmm_tier_coefficients.csv")
glmm_lrt_file <- file.path(model_dir, "glmm_tier_lrt.csv")
glmm_preds_file <- file.path(model_dir, "glmm_tier_predictions.csv")
has_glmm <- file.exists(glmm_coefs_file)

if (has_glmm) {
  glmm_coefs <- read_csv(glmm_coefs_file, show_col_types = FALSE)
  glmm_lrt <- read_csv(glmm_lrt_file, show_col_types = FALSE)
  glmm_preds <- read_csv(glmm_preds_file, show_col_types = FALSE)
}

irt_anova_file <- file.path(model_dir, "irt_tier_anova.csv")
irt_means_file <- file.path(model_dir, "irt_tier_means.csv")
irt_theta_file <- file.path(model_dir, "irt_theta_by_tier.csv")
has_irt <- file.exists(irt_anova_file)

if (has_irt) {
  irt_anova <- read_csv(irt_anova_file, show_col_types = FALSE)
  irt_means <- read_csv(irt_means_file, show_col_types = FALSE)
  irt_theta <- read_csv(irt_theta_file, show_col_types = FALSE)
}

# Tier factor ordering
tier_levels <- intersect(TYPE_ORDER, unique(glm_coefs$term %>%
  sub("^tier", "", .) %>% unique()))

# =========================================================================
# 1. LRT Significance Heatmap (GLM + GLMM + IRT side-by-side)
# =========================================================================
cat("1. LRT significance comparison...\n")

lrt_combined <- glm_lrt %>%
  filter(test == "tier_main") %>%
  transmute(tom_dimension, method = "GLM",
            neg_log10_p = -log10(pmax(p_value, 1e-50)))

if (has_glmm) {
  lrt_combined <- bind_rows(lrt_combined,
    glmm_lrt %>%
      filter(test == "tier_main") %>%
      transmute(tom_dimension, method = "GLMM",
                neg_log10_p = -log10(pmax(p_value, 1e-50)))
  )
}

if (has_irt) {
  lrt_combined <- bind_rows(lrt_combined,
    irt_anova %>%
      transmute(tom_dimension, method = "IRT",
                neg_log10_p = -log10(pmax(p_value, 1e-50)))
  )
}

lrt_combined <- lrt_combined %>%
  mutate(tom_dimension = factor(tom_dimension, levels = rev(DIMENSION_DEVELOPMENTAL_ORDER)),
         method = factor(method, levels = c("GLM", "GLMM", "IRT")))

p_lrt <- ggplot(lrt_combined, aes(x = method, y = tom_dimension, fill = neg_log10_p)) +
  geom_tile(color = "white", linewidth = 0.5) +
  geom_text(aes(label = sprintf("%.1f", neg_log10_p)), size = 3.5) +
  scale_fill_gradient2(low = "grey90", mid = "#3B82F6", high = "#1E2761",
                       midpoint = 10, name = expression(-log[10](p))) +
  geom_vline(xintercept = c(1.5, 2.5), color = "grey60", linewidth = 0.3) +
  labs(title = "Tier Effect Significance Across Methods",
       subtitle = expression("LRT/ANOVA"~-log[10](p)~"by dimension; dashed = p < .05 / .001 thresholds"),
       x = NULL, y = NULL) +
  theme_devtom(base_size = 12) +
  theme(panel.grid = element_blank(),
        axis.text.x = element_text(face = "bold"))

ggsave(file.path(fig_dir, "tier_lrt_significance.png"), p_lrt,
       width = 8, height = 7, dpi = 300, bg = "white")

# =========================================================================
# 2. GLM Tier Coefficients Forest Plot
# =========================================================================
cat("2. GLM tier coefficient forest plot...\n")

tier_coefs <- glm_coefs %>%
  filter(model_type == "main_effect",
         grepl("^tier", term)) %>%
  mutate(tier_name = sub("^tier", "", term),
         tom_dimension = factor(tom_dimension, levels = DIMENSION_DEVELOPMENTAL_ORDER)) %>%
  filter(tier_name %in% TYPE_ORDER) %>%
  mutate(tier_name = factor(tier_name, levels = TYPE_ORDER),
         sig = p.value < 0.05,
         family = case_when(
           grepl("^Claude", tier_name) ~ "Claude",
           grepl("^GPT", tier_name) ~ "GPT",
           grepl("^Llama", tier_name) ~ "Llama",
           grepl("^Qwen", tier_name) ~ "Qwen",
           TRUE ~ "Mistral"
         ))

p_forest <- ggplot(tier_coefs, aes(x = estimate, y = tier_name, color = family)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
  geom_pointrange(aes(xmin = estimate - 1.96 * std.error,
                      xmax = estimate + 1.96 * std.error,
                      alpha = sig),
                  size = 0.3) +
  scale_color_manual(values = FAMILY_COLORS) +
  scale_alpha_manual(values = c("TRUE" = 1.0, "FALSE" = 0.3), guide = "none") +
  facet_wrap(~ tom_dimension, scales = "free_x", ncol = 4) +
  labs(title = "GLM Tier Effects by Dimension",
       subtitle = "Coefficient (log-odds) relative to reference tier; 95% CI; faded = not significant",
       x = "Coefficient (log-odds)", y = NULL, color = "Family") +
  theme_devtom(base_size = 10) +
  theme(axis.text.y = element_text(size = 7),
        strip.text = element_text(size = 8))

ggsave(file.path(fig_dir, "glm_tier_forest.png"), p_forest,
       width = 16, height = 14, dpi = 300, bg = "white")

# =========================================================================
# 3. GLM Predicted Probability Curves by Tier
# =========================================================================
cat("3. GLM predicted curves by tier...\n")

glm_preds_plot <- glm_preds %>%
  mutate(
    tom_dimension = factor(tom_dimension, levels = DIMENSION_DEVELOPMENTAL_ORDER),
    tier = factor(tier, levels = intersect(TYPE_ORDER, unique(tier))),
    family = case_when(
      grepl("^Claude", tier) ~ "Claude",
      grepl("^GPT", tier) ~ "GPT",
      grepl("^Llama", tier) ~ "Llama",
      grepl("^Qwen", tier) ~ "Qwen",
      TRUE ~ "Mistral"
    )
  )

p_curves <- ggplot(glm_preds_plot, aes(x = age_mid, y = pred_prob,
                                        color = tier, group = tier)) +
  geom_line(alpha = 0.7, linewidth = 0.6) +
  geom_hline(yintercept = 0.5, linetype = "dashed", color = "grey60", linewidth = 0.3) +
  scale_color_manual(values = TYPE_COLORS, guide = guide_legend(ncol = 2)) +
  facet_wrap(~ tom_dimension, scales = "free_x", ncol = 4) +
  labs(title = "GLM Predicted Accuracy by Tier and Developmental Age",
       subtitle = "Each line = one tier; dashed = 50% accuracy threshold",
       x = "Developmental Age (years)", y = "Predicted P(correct)",
       color = "Tier") +
  theme_devtom(base_size = 10) +
  theme(legend.position = "bottom",
        legend.text = element_text(size = 7),
        strip.text = element_text(size = 8))

ggsave(file.path(fig_dir, "glm_tier_curves.png"), p_curves,
       width = 16, height = 14, dpi = 300, bg = "white")

# =========================================================================
# 4. GLM Tier Effect Size Heatmap (dimension × tier)
# =========================================================================
cat("4. GLM tier effect heatmap...\n")

tier_heatmap_data <- tier_coefs %>%
  select(tom_dimension, tier_name, estimate, family) %>%
  mutate(tom_dimension = factor(tom_dimension, levels = rev(DIMENSION_DEVELOPMENTAL_ORDER)),
         tier_name = factor(tier_name, levels = TYPE_ORDER))

p_heatmap <- ggplot(tier_heatmap_data,
                    aes(x = tier_name, y = tom_dimension, fill = estimate)) +
  geom_tile(color = "white", linewidth = 0.5) +
  geom_text(aes(label = sprintf("%.1f", estimate)), size = 2.5) +
  scale_fill_gradient2(low = "#2166AC", mid = "white", high = "#B2182B",
                       midpoint = 0, name = "Coef\n(log-odds)") +
  labs(title = "GLM Tier Effect Sizes by Dimension",
       subtitle = "Coefficient (log-odds) relative to reference tier; blue = below, red = above",
       x = NULL, y = NULL) +
  theme_devtom(base_size = 10) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
        panel.grid = element_blank())

ggsave(file.path(fig_dir, "glm_tier_heatmap.png"), p_heatmap,
       width = 14, height = 7, dpi = 300, bg = "white")

# =========================================================================
# 5. IRT Theta by Tier (violin + boxplot)
# =========================================================================
if (has_irt) {
  cat("5. IRT theta by tier...\n")

  irt_theta_plot <- irt_theta %>%
    mutate(
      tom_dimension = factor(tom_dimension, levels = DIMENSION_DEVELOPMENTAL_ORDER),
      tier = factor(tier, levels = intersect(TYPE_ORDER, unique(tier))),
      family = case_when(
        grepl("^Claude", tier) ~ "Claude",
        grepl("^GPT", tier) ~ "GPT",
        grepl("^Llama", tier) ~ "Llama",
        grepl("^Qwen", tier) ~ "Qwen",
        TRUE ~ "Mistral"
      )
    )

  p_irt_theta <- ggplot(irt_theta_plot,
                         aes(x = tier, y = theta, fill = family)) +
    geom_boxplot(outlier.shape = NA, alpha = 0.7, linewidth = 0.3) +
    geom_jitter(aes(color = family), width = 0.2, size = 0.8, alpha = 0.6) +
    scale_fill_manual(values = FAMILY_COLORS) +
    scale_color_manual(values = FAMILY_COLORS) +
    facet_wrap(~ tom_dimension, scales = "free_y", ncol = 4) +
    labs(title = "IRT Latent Ability (θ) by Tier and Dimension",
         subtitle = "Each point = one model; boxplot shows tier distribution",
         x = NULL, y = "Theta (θ)") +
    theme_devtom(base_size = 10) +
    theme(axis.text.x = element_text(angle = 60, hjust = 1, size = 6),
          strip.text = element_text(size = 8),
          legend.position = "bottom")

  ggsave(file.path(fig_dir, "irt_theta_by_tier.png"), p_irt_theta,
         width = 16, height = 16, dpi = 300, bg = "white")

  # IRT eta-squared by dimension
  cat("5b. IRT eta-squared by dimension...\n")

  irt_anova_plot <- irt_anova %>%
    mutate(tom_dimension = factor(tom_dimension, levels = rev(DIMENSION_DEVELOPMENTAL_ORDER)),
           sig = p_value < 0.05)

  p_eta <- ggplot(irt_anova_plot, aes(x = eta_squared, y = tom_dimension)) +
    geom_segment(aes(xend = 0, yend = tom_dimension), color = "grey70") +
    geom_point(aes(color = sig, size = -log10(p_value)), show.legend = TRUE) +
    scale_color_manual(values = c("TRUE" = "#7C3AED", "FALSE" = "grey70"),
                       labels = c("TRUE" = "p < .05", "FALSE" = "n.s."),
                       name = "Significance") +
    scale_size_continuous(range = c(2, 7), name = expression(-log[10](p))) +
    labs(title = "IRT: Tier Effect Size by Dimension",
         subtitle = expression("ANOVA"~η^2~"; larger = more variance explained by tier"),
         x = expression(η^2~"(proportion of θ variance explained by tier)"),
         y = NULL) +
    theme_devtom(base_size = 12)

  ggsave(file.path(fig_dir, "irt_eta_squared.png"), p_eta,
         width = 10, height = 7, dpi = 300, bg = "white")

  # IRT mean theta by tier (overall, averaged across dimensions)
  cat("5c. IRT mean theta across dimensions by tier...\n")

  irt_tier_overall <- irt_means %>%
    group_by(tier, family) %>%
    summarise(
      mean_theta = mean(mean_theta, na.rm = TRUE),
      mean_age = mean(mean_irt_age, na.rm = TRUE),
      n_dims = n(),
      .groups = "drop"
    ) %>%
    mutate(tier = factor(tier, levels = intersect(TYPE_ORDER, unique(tier))))

  p_irt_overall <- ggplot(irt_tier_overall, aes(x = tier, y = mean_theta, fill = family)) +
    geom_col(alpha = 0.85, width = 0.7) +
    geom_text(aes(label = sprintf("%.2f", mean_theta)),
              vjust = -0.3, size = 3) +
    scale_fill_manual(values = FAMILY_COLORS) +
    labs(title = "Mean IRT Ability (θ) by Tier",
         subtitle = "Averaged across all 12 dimensions",
         x = NULL, y = "Mean θ", fill = "Family") +
    theme_devtom(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  ggsave(file.path(fig_dir, "irt_mean_theta_by_tier.png"), p_irt_overall,
         width = 12, height = 6, dpi = 300, bg = "white")
}

# =========================================================================
# 6. GLMM Tier Coefficients Forest Plot
# =========================================================================
if (has_glmm) {
  cat("6. GLMM tier coefficient forest plot...\n")

  glmm_tier_coefs <- glmm_coefs %>%
    filter(grepl("^tier", term)) %>%
    mutate(tier_name = sub("^tier", "", term),
           tom_dimension = factor(tom_dimension, levels = DIMENSION_DEVELOPMENTAL_ORDER),
           sig = p.value < 0.05,
           family = case_when(
             grepl("^Claude", tier_name) ~ "Claude",
             grepl("^GPT", tier_name) ~ "GPT",
             grepl("^Llama", tier_name) ~ "Llama",
             grepl("^Qwen", tier_name) ~ "Qwen",
             TRUE ~ "Mistral"
           )) %>%
    filter(tier_name %in% TYPE_ORDER) %>%
    mutate(tier_name = factor(tier_name, levels = TYPE_ORDER))

  p_glmm_forest <- ggplot(glmm_tier_coefs,
                           aes(x = estimate, y = tier_name, color = family)) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
    geom_pointrange(aes(xmin = estimate - 1.96 * std.error,
                        xmax = estimate + 1.96 * std.error,
                        alpha = sig),
                    size = 0.3) +
    scale_color_manual(values = FAMILY_COLORS) +
    scale_alpha_manual(values = c("TRUE" = 1.0, "FALSE" = 0.3), guide = "none") +
    facet_wrap(~ tom_dimension, scales = "free_x", ncol = 4) +
    labs(title = "GLMM Tier Effects by Dimension",
         subtitle = "Fixed-effect coefficient (log-odds) relative to reference tier; 95% CI",
         x = "Coefficient (log-odds)", y = NULL, color = "Family") +
    theme_devtom(base_size = 10) +
    theme(axis.text.y = element_text(size = 7),
          strip.text = element_text(size = 8))

  ggsave(file.path(fig_dir, "glmm_tier_forest.png"), p_glmm_forest,
         width = 16, height = 14, dpi = 300, bg = "white")

  # GLMM predicted curves
  cat("6b. GLMM predicted curves by tier...\n")

  glmm_preds_plot <- glmm_preds %>%
    mutate(
      tom_dimension = factor(tom_dimension, levels = DIMENSION_DEVELOPMENTAL_ORDER),
      tier = factor(tier, levels = intersect(TYPE_ORDER, unique(tier)))
    )

  p_glmm_curves <- ggplot(glmm_preds_plot,
                           aes(x = age_mid, y = pred_prob, color = tier, group = tier)) +
    geom_line(alpha = 0.7, linewidth = 0.6) +
    geom_hline(yintercept = 0.5, linetype = "dashed", color = "grey60", linewidth = 0.3) +
    scale_color_manual(values = TYPE_COLORS, guide = guide_legend(ncol = 2)) +
    facet_wrap(~ tom_dimension, scales = "free_x", ncol = 4) +
    labs(title = "GLMM Predicted Accuracy by Tier and Developmental Age",
         subtitle = "Fixed-effects only (population-level); dashed = 50% threshold",
         x = "Developmental Age (years)", y = "Predicted P(correct)",
         color = "Tier") +
    theme_devtom(base_size = 10) +
    theme(legend.position = "bottom",
          legend.text = element_text(size = 7),
          strip.text = element_text(size = 8))

  ggsave(file.path(fig_dir, "glmm_tier_curves.png"), p_glmm_curves,
         width = 16, height = 14, dpi = 300, bg = "white")

  # GLMM tier heatmap
  cat("6c. GLMM tier effect heatmap...\n")

  glmm_heatmap_data <- glmm_tier_coefs %>%
    select(tom_dimension, tier_name, estimate) %>%
    mutate(tom_dimension = factor(tom_dimension, levels = rev(DIMENSION_DEVELOPMENTAL_ORDER)))

  p_glmm_heatmap <- ggplot(glmm_heatmap_data,
                            aes(x = tier_name, y = tom_dimension, fill = estimate)) +
    geom_tile(color = "white", linewidth = 0.5) +
    geom_text(aes(label = sprintf("%.1f", estimate)), size = 2.5) +
    scale_fill_gradient2(low = "#2166AC", mid = "white", high = "#B2182B",
                         midpoint = 0, name = "Coef\n(log-odds)") +
    labs(title = "GLMM Tier Effect Sizes by Dimension",
         subtitle = "Fixed-effect coefficient relative to reference; blue = below, red = above",
         x = NULL, y = NULL) +
    theme_devtom(base_size = 10) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
          panel.grid = element_blank())

  ggsave(file.path(fig_dir, "glmm_tier_heatmap.png"), p_glmm_heatmap,
         width = 14, height = 7, dpi = 300, bg = "white")
}

# =========================================================================
# 7. Combined Tier Effect Summary (all methods)
# =========================================================================
cat("7. Combined tier effect summary...\n")

# Effect size comparison: eta² for IRT, pseudo-R² improvement for GLM/GLMM
effect_summary <- glm_lrt %>%
  filter(test == "tier_main") %>%
  transmute(tom_dimension, method = "GLM",
            effect_size = deviance_diff / (deviance_diff + df_diff),
            p_value)

if (has_glmm) {
  effect_summary <- bind_rows(effect_summary,
    glmm_lrt %>%
      filter(test == "tier_main") %>%
      transmute(tom_dimension, method = "GLMM",
                effect_size = chisq / (chisq + 19),
                p_value)
  )
}

if (has_irt) {
  effect_summary <- bind_rows(effect_summary,
    irt_anova %>%
      transmute(tom_dimension, method = "IRT",
                effect_size = eta_squared,
                p_value)
  )
}

effect_summary <- effect_summary %>%
  mutate(tom_dimension = factor(tom_dimension, levels = DIMENSION_DEVELOPMENTAL_ORDER),
         method = factor(method, levels = c("GLM", "GLMM", "IRT")))

p_combined <- ggplot(effect_summary, aes(x = tom_dimension, y = effect_size,
                                          fill = method)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.6, alpha = 0.85) +
  scale_fill_manual(values = c(GLM = "#D97706", GLMM = "#0D9488", IRT = "#7C3AED")) +
  labs(title = "Tier Effect Size Across Methods and Dimensions",
       subtitle = expression("GLM/GLMM: deviance-based pseudo-"~R^2~"; IRT: ANOVA"~η^2),
       x = NULL, y = "Effect Size", fill = "Method") +
  theme_devtom(base_size = 12) +
  theme(axis.text.x = element_text(angle = 35, hjust = 1, size = 9))

ggsave(file.path(fig_dir, "tier_effect_size_comparison.png"), p_combined,
       width = 14, height = 6, dpi = 300, bg = "white")

cat("\nAll figures written to:", fig_dir, "\n")
cat("Files:\n")
list.files(fig_dir) %>% cat(sep = "\n")
