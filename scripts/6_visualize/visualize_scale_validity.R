#!/usr/bin/env Rscript
# visualize_scale_validity.R — figures for Analysis 4 (is the developmental-age
# scale a USEFUL summary of a model?). Reads the CSVs from
# scripts/5_model/scale_validity_analysis.R and writes four figures:
#
#   cv_logloss.png            — held-out log-loss by prediction method, for both
#                               CV schemes; the parsimony + "beats metadata" story.
#   pred_vs_obs_by_dim.png    — observed vs dev-age-predicted accuracy on each
#                               held-out dimension (12 panels), with per-panel RMSE.
#   theta_mcq_vs_frq.png      — per-model developmental age from MCQ vs free
#                               response; format-transfer / measurement invariance.
#   pca_dimensionality.png    — PC1 loadings vs developmental rank + a scree /
#                               parallel-analysis inset (one dominant factor?).

suppressPackageStartupMessages({
  library(ggplot2); library(dplyr); library(tidyr); library(readr)
})
this_dir <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) {
    args <- commandArgs(trailingOnly = FALSE)
    f <- grep("--file=", args, value = TRUE)
    if (length(f)) dirname(sub("--file=", "", f)) else "scripts/6_visualize"
  })
source(file.path(this_dir, "_theme.R"))
proj_root <- normalizePath(file.path(this_dir, "..", ".."))

in_dir <- file.path(proj_root, "results", "modeling", "scale_validity", "latest")
if (!dir.exists(in_dir)) stop("Missing ", in_dir,
  "\nRun: Rscript scripts/5_model/scale_validity_analysis.R")
out_dir <- file.path(proj_root, "results", "figures", "scale_validity")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
rd <- function(f) read_csv(file.path(in_dir, f), show_col_types = FALSE)

cv       <- rd("cv_logloss.csv")
lodo_dim <- rd("lodo_dimension_predictions.csv")
theta    <- rd("theta_by_format.csv")
transfer <- rd("format_transfer.csv")
tcor     <- rd("format_transfer_theta_cor.csv")
pca_load <- rd("pca_loadings.csv")
pca_var  <- rd("pca_variance.csv")

# ── Figure 1: cross-validated log-loss by method ───────────────────────────
METHOD_LABELS <- c(
  devage = "Developmental age (1 param)", saturated = "Per-dimension (12 params)",
  overall = "Overall mean (1 param)", datesize = "Date + size (metadata)",
  family = "Family mean", grand = "Grand mean")
cvp <- cv %>% filter(subgroup == "all") %>%
  mutate(method_lab = METHOD_LABELS[method],
         scheme_lab = recode(scheme,
           `leave-one-dimension-out` = "Predict an UNSEEN dimension\n(leave-one-dimension-out)",
           `item hold-out (5-fold)`  = "Reconstruct the profile\n(5-fold item hold-out)"),
         is_devage = method == "devage")

p1 <- ggplot(cvp, aes(logloss, reorder(method_lab, -logloss))) +
  geom_col(aes(fill = is_devage), width = 0.68) +
  geom_text(aes(label = sprintf("%.3f", logloss)), hjust = -0.15, size = 3.1) +
  facet_wrap(~ scheme_lab, scales = "free_y") +
  scale_fill_manual(values = c(`TRUE` = "#2a9d8f", `FALSE` = "grey72"), guide = "none") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.18))) +
  labs(
    title = "One developmental-age number predicts as well as twelve — and beats metadata",
    subtitle = "Held-out log-loss (lower = better). The 1-parameter developmental-age model (teal) matches the overall-mean,\noutperforms the 12-parameter per-dimension model out-of-sample, and beats date + size.",
    x = "Held-out log-loss", y = NULL) +
  theme_devtom(base_size = 11) +
  theme(panel.grid.major.y = element_blank())
ggsave(file.path(out_dir, "cv_logloss.png"), p1, width = 11, height = 5, dpi = 200, bg = "white")

# ── Figure 2: observed vs predicted accuracy, per held-out dimension ───────
rmse_by_dim <- lodo_dim %>% group_by(tom_dimension) %>%
  summarise(rmse = sqrt(mean((observed - pred_devage)^2)), .groups = "drop")
ld <- lodo_dim %>%
  left_join(rmse_by_dim, by = "tom_dimension") %>%
  mutate(dimension = factor_dimension(tom_dimension),
         facet_lab = sprintf("%s\n(RMSE %.2f)", tom_dimension, rmse))
# order facets developmentally
facet_levels <- ld %>% distinct(dim_rank, facet_lab) %>% arrange(dim_rank) %>% pull(facet_lab)
ld$facet_lab <- factor(ld$facet_lab, levels = facet_levels)

p2 <- ggplot(ld, aes(observed, pred_devage)) +
  geom_abline(slope = 1, intercept = 0, color = "grey60", linetype = 2) +
  geom_point(aes(color = subgroup), size = 1.6, alpha = 0.8) +
  facet_wrap(~ facet_lab, ncol = 4) +
  scale_color_manual(values = c("discriminating (<0.95)" = "#e76f51",
                                "saturated (≥0.95)" = "#457b9d"), name = NULL) +
  coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
  scale_x_continuous(breaks = c(0, 0.5, 1)) + scale_y_continuous(breaks = c(0, 0.5, 1)) +
  labs(
    title = "Predicting each held-out concept from a single developmental age",
    subtitle = "Each point is one model on a dimension it was NOT trained on. Dashed line = perfect prediction.\nSaturated models sit in the top-right corner; the scale is tested on the discriminating (orange) models.",
    x = "Observed accuracy on held-out dimension",
    y = "Predicted (developmental-age model)") +
  theme_devtom(base_size = 10) +
  theme(legend.position = "bottom")
ggsave(file.path(out_dir, "pred_vs_obs_by_dim.png"), p2, width = 9, height = 8, dpi = 200, bg = "white")

# ── Figure 3: format transfer (theta MCQ vs FRQ) ───────────────────────────
th <- theta %>% mutate(family = factor_family(family),
                       headroom = ifelse(headroom, "headroom in both formats",
                                         "saturated (≥ 97% in a format)"))
p3 <- ggplot(th, aes(acc_mcq, acc_frq)) +
  geom_abline(slope = 1, intercept = 0, color = "grey60", linetype = 2) +
  geom_point(aes(color = family, size = params_b, shape = headroom), alpha = 0.85) +
  scale_color_manual(values = FAMILY_COLORS, name = "Family") +
  scale_shape_manual(values = c("headroom in both formats" = 16,
                                "saturated (≥ 97% in a format)" = 1), name = NULL) +
  scale_size_continuous(transform = "log10", name = "Params (B)", range = c(1.5, 7)) +
  coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
  labs(
    title = "Format changes a model's apparent competence",
    subtitle = sprintf("Per-model accuracy, MCQ vs free response (all 28 models).\nPearson r = %.2f overall, %.2f among the %d models with headroom in both formats.\nPoints off the dashed line are format-fragile.",
                       tcor$pearson[1], tcor$pearson_headroom[1], tcor$n_headroom[1]),
    x = "Accuracy (MCQ)", y = "Accuracy (free response)") +
  theme_devtom(base_size = 11)
ggsave(file.path(out_dir, "theta_mcq_vs_frq.png"), p3, width = 8.5, height = 6.5, dpi = 200, bg = "white")

# ── Figure 4: dimensionality (PC1 loadings + scree/parallel inset) ─────────
pl <- pca_load %>% mutate(dimension = factor_dimension(tom_dimension))
p4a <- ggplot(pl, aes(reorder(tom_dimension, dim_rank), PC1_loading)) +
  geom_col(fill = "#2a9d8f", width = 0.7) +
  coord_flip() +
  labs(subtitle = "PC1 loadings (developmental order): all dimensions load positively — a general factor",
       x = NULL, y = "PC1 loading") +
  theme_devtom(base_size = 10)

pv <- pca_var %>% mutate(kind = ifelse(retain, "retained", "not retained"))
p4b <- ggplot(pv, aes(PC)) +
  geom_col(aes(y = eigenvalue, fill = kind), width = 0.7) +
  geom_line(aes(y = parallel_95), color = "grey30") +
  geom_point(aes(y = parallel_95), color = "grey30", size = 1.5) +
  scale_fill_manual(values = c(retained = "#e76f51", `not retained` = "grey75"),
                    name = NULL) +
  scale_x_continuous(breaks = 1:12) +
  labs(subtitle = sprintf("Scree vs parallel analysis: %d factor retained (PC1 = %.0f%% var)",
                          sum(pca_var$retain), 100 * pca_var$pct_var[1]),
       x = "Principal component", y = "Eigenvalue") +
  theme_devtom(base_size = 10) +
  theme(legend.position = c(0.7, 0.8))

p4 <- tryCatch({
  library(patchwork)
  (p4a + p4b) + plot_annotation(
    title = "The 12 dimensions collapse to one dominant factor",
    subtitle = "A single strong general factor across all 12 dimensions is what makes one developmental-age scalar defensible.",
    theme = theme(plot.title = element_text(face = "bold", size = 14),
                  plot.subtitle = element_text(color = "grey40", size = 11)))
}, error = function(e) { cat("patchwork failed:", conditionMessage(e), "\n"); p4a })
ggsave(file.path(out_dir, "pca_dimensionality.png"), p4, width = 11, height = 5.5, dpi = 200, bg = "white")

cat("Wrote 4 figures to:", out_dir, "\n")
cat(list.files(out_dir, pattern = "\\.png$"), sep = "\n")
