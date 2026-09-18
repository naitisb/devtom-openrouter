#!/usr/bin/env Rscript
# visualize_guttman_sequence.R — figures for Analysis 1 (developmental sequence
# organizes model performance). Reads the CSVs emitted by
# scripts/5_model/guttman_sequence_analysis.R and writes four figures:
#
#   guttman_scalogram.png        — models (chronological) x dimensions (developmental
#                                  order); filled = mastered; Guttman errors (cells
#                                  that break the cumulative pattern) outlined red.
#   permutation_null.png         — null distribution of reproducibility (CR) under
#                                  10k random dimension orders, with the developmental
#                                  and rival orders marked; faceted by dataset.
#   item_difficulty_vs_age.png   — 184 items, difficulty (logit) vs validated
#                                  developmental age, colored by dimension, OLS fit.
#   coherence_vs_date_size.png   — per-model developmental coherence vs release date
#                                  and vs model size, to visualize Strand C.

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(readr)
})

this_dir <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) {
    args <- commandArgs(trailingOnly = FALSE)
    f <- grep("--file=", args, value = TRUE)
    if (length(f)) dirname(sub("--file=", "", f)) else "scripts/6_visualize"
  }
)
source(file.path(this_dir, "_theme.R"))
proj_root <- normalizePath(file.path(this_dir, "..", ".."))

in_dir  <- file.path(proj_root, "results", "modeling", "guttman_sequence", "latest")
if (!dir.exists(in_dir)) stop("Missing ", in_dir,
  "\nRun: Rscript scripts/5_model/guttman_sequence_analysis.R")
out_dir <- file.path(proj_root, "results", "figures", "guttman_sequence")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

rd <- function(f) read_csv(file.path(in_dir, f), show_col_types = FALSE)
mastery <- rd("mastery_matrix_long.csv")
perm    <- rd("permutation_results.csv")
null_dr <- rd("permutation_null_draws.csv")
itemdf  <- rd("item_difficulty_vs_age.csv")
coh     <- rd("per_model_coherence.csv")
scal    <- rd("scalability_coefficients.csv")

DATASET_LABELS <- c(pooled = "Pooled (MCQ + FRQ)", mcq = "MCQ", frq = "Free response")

# ── Figure 1: Guttman scalogram (pooled) ───────────────────────────────────
# Mark the Guttman-error cells: within each model row (dims in developmental
# order), the ideal cumulative pattern passes the first s = #mastered dimensions;
# any cell that deviates from that prefix is a scale error.
scg <- mastery %>%
  filter(dataset == "pooled") %>%
  arrange(date_years, dim_rank) %>%
  group_by(model) %>%
  mutate(s = sum(mastered),
         ideal = as.integer(rank(dim_rank, ties.method = "first") <= s),
         is_error = mastered != ideal) %>%
  ungroup() %>%
  mutate(dimension = factor_dimension(dimension),
         model_lab = factor(short_model(model),
                            levels = short_model(unique(model[order(date_years)]))),
         status = ifelse(mastered == 1, "Mastered (≥ 80%)", "Not mastered"))

cr_pooled <- scal$CR[scal$dataset == "pooled"]
h_pooled  <- scal$loevinger_H[scal$dataset == "pooled"]
p_pooled  <- perm$p_value[perm$dataset == "pooled" & perm$order == "developmental"]

p1 <- ggplot(scg, aes(dimension, model_lab)) +
  geom_tile(aes(fill = status), color = "grey85", linewidth = 0.3) +
  geom_tile(data = filter(scg, is_error), fill = NA,
            color = "#d1495b", linewidth = 0.9) +
  scale_fill_manual(values = c("Mastered (≥ 80%)" = "#2a9d8f",
                               "Not mastered" = "grey92"), name = NULL) +
  labs(
    title = "Developmental scalogram: mastery follows the acquisition sequence",
    subtitle = sprintf(
      "Models oldest → newest (bottom → top) × 12 ToM dimensions in developmental order (left → right).\nRed outline = Guttman error.  CR = %.3f  ·  Loevinger H = %.2f (strong scale)  ·  permutation p = %.3f",
      cr_pooled, h_pooled, p_pooled),
    x = NULL, y = NULL) +
  theme_devtom(base_size = 10) +
  theme(axis.text.x = element_text(angle = 40, hjust = 1, size = 8),
        axis.text.y = element_text(size = 7),
        legend.position = "bottom",
        panel.grid = element_blank())
ggsave(file.path(out_dir, "guttman_scalogram.png"), p1,
       width = 9, height = 8.5, dpi = 200, bg = "white")

# ── Figure 2: permutation null distribution ────────────────────────────────
DS_LEVELS <- c("Pooled (MCQ + FRQ)", "MCQ", "Free response")
ord_lines <- perm %>%
  mutate(order = recode(order,
    developmental = "Developmental", construct_grouped = "Construct-grouped",
    empirical_best = "Empirical best", reverse = "Reverse"),
    dataset_lab = factor(DATASET_LABELS[dataset], levels = DS_LEVELS))
null_lab <- null_dr %>%
  mutate(dataset_lab = factor(DATASET_LABELS[dataset], levels = DS_LEVELS))

ORDER_COLS <- c(Developmental = "#e76f51", `Construct-grouped` = "#457b9d",
                `Empirical best` = "#2a9d8f", Reverse = "grey55")

p2 <- ggplot(null_lab, aes(perm_cr)) +
  geom_histogram(bins = 40, fill = "grey80", color = "white", linewidth = 0.15) +
  geom_vline(data = ord_lines, aes(xintercept = CR, color = order),
             linewidth = 0.9) +
  facet_wrap(~ dataset_lab, ncol = 1, scales = "free_y") +
  scale_color_manual(values = ORDER_COLS, name = "Column order") +
  labs(
    title = "The developmental order reproduces the data better than chance",
    subtitle = "Reproducibility (CR) under 10,000 random orderings of the 12 dimensions (grey),\nwith the developmental order and three named rivals marked.",
    x = "Coefficient of reproducibility (CR)", y = "Random orderings") +
  theme_devtom(base_size = 11) +
  theme(legend.position = "bottom")
ggsave(file.path(out_dir, "permutation_null.png"), p2,
       width = 8, height = 8, dpi = 200, bg = "white")

# ── Figure 3: item difficulty vs developmental age ─────────────────────────
id <- itemdf %>%
  filter(task == "tom_12dim_mcq" | task == "tom_12dim_freeresponse") %>%
  mutate(dimension = factor_dimension(tom_dimension))
slope_pooled <- coef(lm(difficulty_logit ~ age_mid, data = itemdf))["age_mid"]
sp_pooled <- scal$kendall_tau_dev_vs_empirical[scal$dataset == "pooled"]  # (context only)

p3 <- ggplot(id, aes(age_mid, difficulty_logit)) +
  geom_jitter(aes(color = dimension), width = 0.12, height = 0, alpha = 0.7,
              size = 1.8) +
  geom_smooth(method = "lm", se = TRUE, color = "grey20", linewidth = 0.8) +
  scale_color_viridis_d(option = "turbo", name = "Dimension\n(developmental order)") +
  labs(
    title = "Later-acquired concepts are harder for models",
    subtitle = sprintf("Each point is one item (n = %d). Difficulty = logit(1 − pass rate) across %d models.\nOLS slope = %.3f logits per developmental year.",
                       nrow(itemdf), n_distinct(coh$model), slope_pooled),
    x = "Validated developmental age of item (years, age_mid)",
    y = "Item difficulty (logit, higher = harder)") +
  theme_devtom(base_size = 11) +
  theme(legend.text = element_text(size = 7), legend.key.size = unit(0.4, "cm"))
ggsave(file.path(out_dir, "item_difficulty_vs_age.png"), p3,
       width = 9, height = 6, dpi = 200, bg = "white")

# NOTE: the per-model developmental-coherence figures (Strand C) now live in
# scripts/6_visualize/visualize_coherence_continuous.R, which uses the continuous
# residualized measure. This script covers Strands A & B only.

cat("Wrote 3 figures to:", out_dir, "\n")
cat(list.files(out_dir, pattern = "\\.png$"), sep = "\n")
