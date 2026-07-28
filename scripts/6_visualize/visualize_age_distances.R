#!/usr/bin/env Rscript
# visualize_age_distances.R — Plots for model-wise age distances

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

source("scripts/6_visualize/_theme.R")

base_dir <- "results/modeling/developmental_age_mapping"
ts_dirs  <- list.dirs(base_dir, recursive = FALSE, full.names = TRUE)
model_dir <- sort(ts_dirs, decreasing = TRUE)[1]
cat("Reading from:", model_dir, "\n")

fig_dir <- file.path("results", "figures", "developmental_age",
                      basename(model_dir))
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

by_method <- read_csv(file.path(model_dir, "age_distances_by_method.csv"),
                      show_col_types = FALSE) %>%
  mutate(release_date = as.Date(release_date),
         short_name = short_model(model),
         family = factor_family(family))

cross_method <- read_csv(file.path(model_dir, "age_distances_cross_method.csv"),
                         show_col_types = FALSE) %>%
  mutate(release_date = as.Date(release_date),
         family = factor_family(family))

METHOD_COLORS <- c(mastery = "#3B82F6", glm = "#D97706",
                   glmm = "#0D9488", irt = "#7C3AED")
METHOD_LABELS <- c(mastery = "Mastery", glm = "GLM",
                   glmm = "GLMM", irt = "IRT")

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
# 1. Violin + jitter: distance distribution by method × scope_type
# =========================================================================
cat("1. Distance distributions by method...\n")

dist_dim <- by_method %>% filter(scope_type == "dimension")

p1 <- ggplot(dist_dim, aes(x = method, y = distance, fill = method)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50",
             linewidth = 0.5) +
  geom_violin(alpha = 0.4, width = 0.8, color = NA) +
  geom_jitter(aes(color = method), width = 0.15, size = 0.8, alpha = 0.4) +
  geom_boxplot(width = 0.15, outlier.shape = NA, alpha = 0.6, color = "grey30") +
  scale_fill_manual(values = METHOD_COLORS) +
  scale_color_manual(values = METHOD_COLORS) +
  scale_x_discrete(labels = METHOD_LABELS) +
  labs(
    title = "Distance Distribution by Method (Dimension-Level)",
    subtitle = "Distance = estimated age − target age; dashed = 0 (perfect match)",
    x = NULL, y = "Distance (years)"
  ) +
  theme_devtom(base_size = 11) +
  theme(legend.position = "none")

ggsave(file.path(fig_dir, "dist_violin_by_method.png"), p1,
       width = 10, height = 6, dpi = 200)

# =========================================================================
# 2. Dot plot: mean distance by dimension, faceted by method
# =========================================================================
cat("2. Mean distance by dimension per method...\n")

dim_summary <- dist_dim %>%
  group_by(scope, method) %>%
  summarise(
    mean_dist = mean(distance, na.rm = TRUE),
    se_dist   = sd(distance, na.rm = TRUE) / sqrt(n()),
    .groups = "drop"
  ) %>%
  mutate(scope = factor(scope, levels = DIMENSION_DEVELOPMENTAL_ORDER))

p2 <- ggplot(dim_summary, aes(x = mean_dist, y = scope, color = method)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey50",
             linewidth = 0.5) +
  geom_errorbarh(aes(xmin = mean_dist - se_dist, xmax = mean_dist + se_dist),
                 height = 0.3, linewidth = 0.4, alpha = 0.6) +
  geom_point(size = 3) +
  scale_color_manual(values = METHOD_COLORS, labels = METHOD_LABELS,
                     name = "Method") +
  labs(
    title = "Mean Distance from Target Age by Dimension",
    subtitle = "Error bars = ±1 SE across models; dashed = 0 (matches target)",
    x = "Mean Distance (years)", y = NULL
  ) +
  theme_devtom(base_size = 11) +
  theme(legend.position = "top")

ggsave(file.path(fig_dir, "dist_dotplot_dimension.png"), p2,
       width = 12, height = 7, dpi = 200)

# =========================================================================
# 3. Same for constructs
# =========================================================================
cat("3. Mean distance by construct per method...\n")

dist_con <- by_method %>% filter(scope_type == "construct")

con_summary <- dist_con %>%
  group_by(scope, method) %>%
  summarise(
    mean_dist = mean(distance, na.rm = TRUE),
    se_dist   = sd(distance, na.rm = TRUE) / sqrt(n()),
    .groups = "drop"
  ) %>%
  mutate(scope = factor(scope, levels = CONSTRUCT_DEVELOPMENTAL_ORDER))

p3 <- ggplot(con_summary, aes(x = mean_dist, y = scope, color = method)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey50",
             linewidth = 0.5) +
  geom_errorbarh(aes(xmin = mean_dist - se_dist, xmax = mean_dist + se_dist),
                 height = 0.3, linewidth = 0.4, alpha = 0.6) +
  geom_point(size = 3.5) +
  scale_color_manual(values = METHOD_COLORS, labels = METHOD_LABELS,
                     name = "Method") +
  labs(
    title = "Mean Distance from Target Age by Construct",
    subtitle = "Error bars = ±1 SE across models; dashed = 0 (matches target)",
    x = "Mean Distance (years)", y = NULL
  ) +
  theme_devtom(base_size = 11) +
  theme(legend.position = "top")

ggsave(file.path(fig_dir, "dist_dotplot_construct.png"), p3,
       width = 11, height = 5, dpi = 200)

# =========================================================================
# 4. Heatmap: cross-method mean distance, model × dimension
# =========================================================================
cat("4. Heatmap: mean distance by model × dimension...\n")

heat_dim <- cross_method %>%
  filter(scope_type == "dimension") %>%
  mutate(scope = factor(scope, levels = DIMENSION_DEVELOPMENTAL_ORDER))

model_order <- heat_dim %>%
  group_by(model) %>%
  summarise(overall_dist = mean(mean_distance, na.rm = TRUE),
            .groups = "drop") %>%
  arrange(overall_dist) %>%
  pull(model)

heat_dim <- heat_dim %>%
  left_join(
    heat_dim %>% distinct(model) %>%
      mutate(short_name = short_model(model)),
    by = "model"
  ) %>%
  mutate(short_name = factor(short_name,
                              levels = short_model(model_order)))

max_abs <- max(abs(heat_dim$mean_distance), na.rm = TRUE)

p4 <- ggplot(heat_dim, aes(x = scope, y = short_name, fill = mean_distance)) +
  geom_tile(color = "white", linewidth = 0.3) +
  geom_text(aes(label = sprintf("%+.1f", mean_distance)),
            size = 2.2, color = "black") +
  scale_fill_gradient2(low = "#2166AC", mid = "white", high = "#B2182B",
                       midpoint = 0, limits = c(-max_abs, max_abs),
                       name = "Distance\n(years)") +
  labs(
    title = "Cross-Method Mean Distance from Target Age",
    subtitle = "Model × Dimension (blue = below target, red = above target)",
    x = NULL, y = NULL
  ) +
  theme_devtom(base_size = 9) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
    axis.text.y = element_text(size = 6),
    panel.grid = element_blank()
  )

ggsave(file.path(fig_dir, "dist_heatmap_dimension.png"), p4,
       width = 14, height = 12, dpi = 200)

# =========================================================================
# 5. Heatmap: cross-method mean distance, model × construct
# =========================================================================
cat("5. Heatmap: mean distance by model × construct...\n")

heat_con <- cross_method %>%
  filter(scope_type == "construct") %>%
  mutate(scope = factor(scope, levels = CONSTRUCT_DEVELOPMENTAL_ORDER))

model_order_con <- heat_con %>%
  group_by(model) %>%
  summarise(overall_dist = mean(mean_distance, na.rm = TRUE),
            .groups = "drop") %>%
  arrange(overall_dist) %>%
  pull(model)

heat_con <- heat_con %>%
  left_join(
    heat_con %>% distinct(model) %>%
      mutate(short_name = short_model(model)),
    by = "model"
  ) %>%
  mutate(short_name = factor(short_name,
                              levels = short_model(model_order_con)))

max_abs_con <- max(abs(heat_con$mean_distance), na.rm = TRUE)

p5 <- ggplot(heat_con, aes(x = scope, y = short_name, fill = mean_distance)) +
  geom_tile(color = "white", linewidth = 0.3) +
  geom_text(aes(label = sprintf("%+.1f", mean_distance)),
            size = 2.8, color = "black") +
  scale_fill_gradient2(low = "#2166AC", mid = "white", high = "#B2182B",
                       midpoint = 0, limits = c(-max_abs_con, max_abs_con),
                       name = "Distance\n(years)") +
  labs(
    title = "Cross-Method Mean Distance from Target Age",
    subtitle = "Model × Construct (blue = below target, red = above target)",
    x = NULL, y = NULL
  ) +
  theme_devtom(base_size = 10) +
  theme(
    axis.text.x = element_text(angle = 30, hjust = 1, size = 9),
    axis.text.y = element_text(size = 7),
    panel.grid = element_blank()
  )

ggsave(file.path(fig_dir, "dist_heatmap_construct.png"), p5,
       width = 10, height = 12, dpi = 200)

# =========================================================================
# 6. Mean absolute distance per model, ranked (lollipop)
# =========================================================================
cat("6. Model-level mean absolute distance ranking...\n")

model_rank <- cross_method %>%
  filter(scope_type == "dimension") %>%
  group_by(model, family, tier) %>%
  summarise(
    mean_abs_dist = mean(mean_abs_dist, na.rm = TRUE),
    mean_dist     = mean(mean_distance, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(short_name = short_model(model)) %>%
  arrange(mean_abs_dist) %>%
  mutate(short_name = factor(short_name, levels = short_name))

p6 <- ggplot(model_rank, aes(x = mean_abs_dist, y = short_name, color = family)) +
  geom_segment(aes(x = 0, xend = mean_abs_dist, yend = short_name),
               linewidth = 0.5, alpha = 0.6) +
  geom_point(size = 3) +
  scale_color_manual(values = FAMILY_COLORS, name = "Family") +
  labs(
    title = "Mean Absolute Distance from Target Age (Cross-Method)",
    subtitle = "Averaged across 12 dimensions and 4 methods; lower = closer to target",
    x = "Mean |Distance| (years)", y = NULL
  ) +
  theme_devtom(base_size = 10) +
  theme(legend.position = "top")

ggsave(file.path(fig_dir, "dist_lollipop_model.png"), p6,
       width = 10, height = 12, dpi = 200)

# =========================================================================
# 7. Distance vs release date (scatter + LOESS per method)
# =========================================================================
cat("7. Distance trends over time...\n")

dist_ovr <- by_method %>%
  filter(scope_type == "dimension") %>%
  group_by(model, method, family, tier, release_date) %>%
  summarise(mean_dist = mean(distance, na.rm = TRUE),
            mean_abs_dist = mean(abs_distance, na.rm = TRUE),
            .groups = "drop")

p7 <- ggplot(dist_ovr, aes(x = release_date, y = mean_abs_dist,
                             color = method)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50",
             linewidth = 0.5) +
  geom_point(alpha = 0.5, size = 2) +
  geom_smooth(method = "loess", se = TRUE, linewidth = 0.8, alpha = 0.15) +
  scale_color_manual(values = METHOD_COLORS, labels = METHOD_LABELS,
                     name = "Method") +
  scale_x_date(date_labels = "%b %Y", date_breaks = "6 months") +
  labs(
    title = "Mean |Distance| from Target Age Over Time",
    subtitle = "Per-model mean across 12 dimensions; LOESS per method",
    x = "Release Date",
    y = "Mean |Distance| (years)"
  ) +
  theme_devtom(base_size = 11) +
  theme(
    axis.text.x = element_text(angle = 30, hjust = 1),
    legend.position = "top"
  )

ggsave(file.path(fig_dir, "dist_abs_over_time.png"), p7,
       width = 12, height = 6, dpi = 200)

# Signed distance over time
p7b <- ggplot(dist_ovr, aes(x = release_date, y = mean_dist,
                              color = method)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50",
             linewidth = 0.5) +
  geom_point(alpha = 0.5, size = 2) +
  geom_smooth(method = "loess", se = TRUE, linewidth = 0.8, alpha = 0.15) +
  scale_color_manual(values = METHOD_COLORS, labels = METHOD_LABELS,
                     name = "Method") +
  scale_x_date(date_labels = "%b %Y", date_breaks = "6 months") +
  labs(
    title = "Mean Signed Distance from Target Age Over Time",
    subtitle = "Per-model mean across 12 dimensions; positive = model exceeds target",
    x = "Release Date",
    y = "Mean Distance (years)"
  ) +
  theme_devtom(base_size = 11) +
  theme(
    axis.text.x = element_text(angle = 30, hjust = 1),
    legend.position = "top"
  )

ggsave(file.path(fig_dir, "dist_signed_over_time.png"), p7b,
       width = 12, height = 6, dpi = 200)

# =========================================================================
# 8. Per-dimension distance heatmap, one panel per method
# =========================================================================
cat("8. Per-method distance heatmaps (faceted)...\n")

heat_by_method <- by_method %>%
  filter(scope_type == "dimension") %>%
  mutate(scope = factor(scope, levels = DIMENSION_DEVELOPMENTAL_ORDER),
         method = factor(method, levels = c("mastery", "glm", "glmm", "irt"),
                         labels = c("Mastery", "GLM", "GLMM", "IRT")),
         short_name = short_model(model))

model_ord_all <- heat_by_method %>%
  group_by(model) %>%
  summarise(m = mean(distance, na.rm = TRUE), .groups = "drop") %>%
  arrange(m) %>%
  pull(model)

heat_by_method <- heat_by_method %>%
  mutate(short_name = factor(short_name,
                              levels = short_model(model_ord_all)))

max_abs_m <- max(abs(heat_by_method$distance), na.rm = TRUE)

p8 <- ggplot(heat_by_method,
             aes(x = scope, y = short_name, fill = distance)) +
  geom_tile(color = "white", linewidth = 0.2) +
  facet_wrap(~ method, nrow = 1) +
  scale_fill_gradient2(low = "#2166AC", mid = "white", high = "#B2182B",
                       midpoint = 0, limits = c(-max_abs_m, max_abs_m),
                       name = "Dist (yrs)") +
  labs(
    title = "Distance from Target Age — All Methods",
    subtitle = "Blue = below target, red = above target; each panel = one method",
    x = NULL, y = NULL
  ) +
  theme_devtom(base_size = 8) +
  theme(
    axis.text.x = element_text(angle = 60, hjust = 1, size = 5),
    axis.text.y = element_text(size = 5),
    strip.text = element_text(face = "bold", size = 10),
    panel.grid = element_blank()
  )

ggsave(file.path(fig_dir, "dist_heatmap_by_method.png"), p8,
       width = 22, height = 12, dpi = 200)

# =========================================================================
# 9. Method agreement: distance spread per model × dimension
# =========================================================================
cat("9. Method agreement (SD across methods)...\n")

agreement <- cross_method %>%
  filter(scope_type == "dimension", n_methods >= 2) %>%
  mutate(scope = factor(scope, levels = DIMENSION_DEVELOPMENTAL_ORDER))

agree_dim <- agreement %>%
  group_by(scope) %>%
  summarise(
    mean_sd = mean(sd_distance, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(mean_sd) %>%
  mutate(scope = factor(scope, levels = scope))

p9 <- ggplot(agree_dim, aes(x = mean_sd, y = scope)) +
  geom_segment(aes(x = 0, xend = mean_sd, yend = scope),
               linewidth = 0.8, color = "grey60") +
  geom_point(size = 4, color = "#7C3AED") +
  labs(
    title = "Method Disagreement by Dimension",
    subtitle = "Mean SD of distance across methods; higher = methods disagree more",
    x = "Mean SD of Distance Across Methods (years)", y = NULL
  ) +
  theme_devtom(base_size = 11)

ggsave(file.path(fig_dir, "dist_method_agreement.png"), p9,
       width = 10, height = 6, dpi = 200)

# =========================================================================
# 10. Faceted by family: signed distance per dimension
# =========================================================================
cat("10. Family-faceted distance by dimension...\n")

fam_dim <- cross_method %>%
  filter(scope_type == "dimension") %>%
  mutate(scope = factor(scope, levels = DIMENSION_DEVELOPMENTAL_ORDER))

p10 <- ggplot(fam_dim, aes(x = scope, y = mean_distance, color = family)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50",
             linewidth = 0.5) +
  geom_jitter(width = 0.2, alpha = 0.5, size = 1.5) +
  geom_boxplot(aes(group = scope), width = 0.6, outlier.shape = NA,
               alpha = 0.15, color = "grey30") +
  facet_wrap(~ family, nrow = 1) +
  scale_color_manual(values = FAMILY_COLORS) +
  labs(
    title = "Cross-Method Mean Distance by Dimension — Faceted by Family",
    subtitle = "Each point = one model; dashed = 0 (matches target)",
    x = NULL,
    y = "Mean Distance (years)"
  ) +
  theme_devtom(base_size = 9) +
  theme(
    axis.text.x = element_text(angle = 60, hjust = 1, size = 6),
    strip.text = element_text(face = "bold", size = 11),
    legend.position = "none"
  )

ggsave(file.path(fig_dir, "dist_family_facet_dimension.png"), p10,
       width = 22, height = 7, dpi = 200)

# =========================================================================
cat("\n=== Distance figures ===\n")
list.files(fig_dir, pattern = "^dist_") %>% sort() %>% cat(sep = "\n")
cat("\nDone.\n")
