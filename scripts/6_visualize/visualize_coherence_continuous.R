#!/usr/bin/env Rscript
# visualize_coherence_continuous.R — figures for the CONTINUOUS developmental
# coherence measure (Analysis 1, Strand C), reading the CSVs written by
# scripts/5_model/guttman_sequence_analysis.R.
#
# Measure: for each split point k = 1..11 in the developmental ordering,
#   DC(k) = mean(accuracy of dims at/before k) − mean(accuracy of dims after k)
#         = earlier − later,
# averaged over k. POSITIVE = better on the earlier/easier dimensions than the
# later/harder ones = the child-like, developmentally-coherent direction; ~0 =
# flat; NEGATIVE = better on the harder later concepts (inverted). Because ceiling
# compression ties this raw measure to overall accuracy, we also use the version
# RESIDUALIZED on mean accuracy (regression residual, not a normalization).
#
# Six figures:
#   coherence_gradient_profile.png       — the construct: accuracy across the 12
#                                          dimensions (dev order), by model size.
#   coherence_residualization.png        — raw coherence vs mean accuracy + OLS
#                                          line; the residual is the vertical gap.
#   coherence_resid_vs_date_size.png     — residualized coherence vs date & size
#                                          (competence partialled out).
#   coherence_raw_vs_date_size.png       — raw coherence vs date & size (no
#                                          level-removal), for comparison.
#   coherence_normalized_vs_date_size.png— coherence on accuracy divided by the
#                                          model's mean (multiplicative level-removal).
#   coherence_split_point_profile.png    — DC(k) for every split point k.

suppressPackageStartupMessages({
  library(ggplot2); library(dplyr); library(tidyr); library(readr)
})
this_dir <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) {
  a <- commandArgs(trailingOnly = FALSE); f <- grep("--file=", a, value = TRUE)
  if (length(f)) dirname(sub("--file=", "", f)) else "scripts/6_visualize" })
source(file.path(this_dir, "_theme.R"))
proj_root <- normalizePath(file.path(this_dir, "..", ".."))

in_dir <- file.path(proj_root, "results", "modeling", "guttman_sequence", "latest")
if (!dir.exists(in_dir)) stop("Missing ", in_dir,
  "\nRun: Rscript scripts/5_model/guttman_sequence_analysis.R")
out_dir <- file.path(proj_root, "results", "figures", "coherence_continuous")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
rd <- function(f) read_csv(file.path(in_dir, f), show_col_types = FALSE)

coh     <- rd("per_model_coherence.csv")
acc_dim <- rd("per_dimension_accuracy.csv")
dk      <- rd("coherence_by_split_point.csv")

# size bins (shared across figures)
size_bin <- function(p) cut(p, breaks = c(0, 10, 70, Inf),
  labels = c("small (≤10B)", "mid (10–70B)", "large (>70B)"))
SIZE_COLS <- c("small (≤10B)" = "#e76f51", "mid (10–70B)" = "#e9c46a",
               "large (>70B)" = "#2a9d8f")
coh$size_bin     <- size_bin(coh$params_b)
acc_dim$size_bin <- size_bin(acc_dim$params_b)
dk <- dk %>% left_join(coh %>% select(model, params_b, size_bin), by = "model")

# ── Figure 1: the construct — accuracy gradient across dimensions ──────────
gd <- acc_dim %>% mutate(dimension = factor_dimension(tom_dimension))
bin_means <- gd %>% group_by(size_bin, dim_rank, tom_dimension) %>%
  summarise(accuracy = mean(accuracy), .groups = "drop") %>%
  mutate(dimension = factor_dimension(tom_dimension))
p1 <- ggplot(gd, aes(dimension, accuracy, group = model)) +
  geom_line(aes(color = size_bin), alpha = 0.25, linewidth = 0.4) +
  geom_line(data = bin_means, aes(group = size_bin, color = size_bin), linewidth = 1.4) +
  scale_color_manual(values = SIZE_COLS, name = "Model size") +
  scale_y_continuous(limits = c(0, 1)) +
  labs(
    title = "What the measure captures: does accuracy fall across the developmental sequence?",
    subtitle = "Per-model accuracy on the 12 ToM dimensions in developmental order (thin = models, thick = size-bin means).\nA downward slope (good early, worse late) is the child-like pattern → positive coherence. Flat (ceiling) → ~0.",
    x = NULL, y = "Accuracy") +
  theme_devtom(base_size = 10) +
  theme(axis.text.x = element_text(angle = 40, hjust = 1, size = 8),
        legend.position = "bottom")
ggsave(file.path(out_dir, "coherence_gradient_profile.png"), p1,
       width = 10, height = 6.5, dpi = 200, bg = "white")

# ── Figure 2: residualization — coherence vs mean accuracy ─────────────────
cm <- coh %>% mutate(family = factor_family(family))
fit <- lm(coherence ~ mean_acc, data = cm)
r_lin <- suppressWarnings(cor(cm$coherence, cm$mean_acc))
p2 <- ggplot(cm, aes(mean_acc, coherence)) +
  geom_hline(yintercept = 0, color = "grey80", linetype = 3) +
  geom_smooth(method = "lm", se = TRUE, color = "grey30", linewidth = 0.7) +
  geom_segment(aes(xend = mean_acc, yend = predict(fit)), color = "grey70",
               linewidth = 0.3) +                       # the residual = this gap
  geom_point(aes(color = family, size = params_b), alpha = 0.85) +
  scale_color_manual(values = FAMILY_COLORS, name = "Family") +
  scale_size_continuous(transform = "log10", name = "Params (B)", range = c(1.5, 7)) +
  labs(
    title = "Why we residualize: raw coherence rides on overall accuracy",
    subtitle = sprintf("Ceiling compression flattens strong models' profiles, so raw coherence falls as accuracy rises (r = %.2f).\nThe RESIDUAL (grey vertical gap to the line) is the profile shape not explained by competence — the clean DV.",
                       r_lin),
    x = "Overall mean accuracy", y = "Developmental coherence (earlier − later)") +
  theme_devtom(base_size = 11)
ggsave(file.path(out_dir, "coherence_residualization.png"), p2,
       width = 9, height = 6, dpi = 200, bg = "white")

# ── Figure 3: the clean result — residualized coherence vs date & size ─────
cd <- coh %>% mutate(family = factor_family(family),
                     release = as.Date("2024-01-01") + date_years * 365.25)
sp_date <- suppressWarnings(cor(cd$date_years, cd$coherence_resid, method = "spearman"))
sp_size <- suppressWarnings(cor(log10(cd$params_b), cd$coherence_resid,
                                method = "spearman", use = "complete.obs"))
bl <- theme_devtom(base_size = 11) + theme(legend.position = "bottom")
p3a <- ggplot(cd, aes(release, coherence_resid)) +
  geom_hline(yintercept = 0, color = "grey80", linetype = 3) +
  geom_smooth(method = "lm", se = TRUE, color = "grey40", linewidth = 0.7) +
  geom_point(aes(color = family, size = params_b), alpha = 0.85) +
  scale_color_manual(values = FAMILY_COLORS, name = "Family") +
  scale_size_continuous(transform = "log10", name = "Params (B)", range = c(1.5, 7)) +
  labs(subtitle = "vs release date", x = "Release date",
       y = "Developmental Coherence (residualized)") + bl
p3b <- ggplot(cd, aes(params_b, coherence_resid)) +
  geom_hline(yintercept = 0, color = "grey80", linetype = 3) +
  geom_smooth(method = "lm", se = TRUE, color = "grey40", linewidth = 0.7) +
  geom_point(aes(color = family), size = 2.6, alpha = 0.85) +
  scale_color_manual(values = FAMILY_COLORS, name = "Family", guide = "none") +
  scale_x_log10() +
  labs(subtitle = "vs model size", x = "Parameters (billions, log scale)", y = NULL) + bl
p3 <- tryCatch({
  library(patchwork)
  (p3a + p3b) + plot_layout(guides = "collect") +
    plot_annotation(
      title = "Residualized Developmental Coherence",
      subtitle = sprintf("Developmental Coherence (residualized) computed using each model's residual value from fitting an ordinary least\nsquares line across all models.\nSpearman ρ: date = %.2f, size = %.2f",
                         sp_date, sp_size),
      theme = theme(plot.title = element_text(face = "bold", size = 14),
                    plot.subtitle = element_text(color = "grey40", size = 11),
                    legend.position = "bottom"))
}, error = function(e) p3a)
ggsave(file.path(out_dir, "coherence_resid_vs_date_size.png"), p3,
       width = 11, height = 5.5, dpi = 200, bg = "white")

# ── Figure 3b: RAW coherence vs date & size (no residualization) ───────────
# Same plot as Figure 3 but with the raw continuous measure, for comparison.
# The raw measure still rides on overall accuracy, so this shows the (stronger)
# apparent relationship BEFORE competence is partialled out.
sp_date_raw <- suppressWarnings(cor(cd$date_years, cd$coherence, method = "spearman"))
sp_size_raw <- suppressWarnings(cor(log10(cd$params_b), cd$coherence,
                                    method = "spearman", use = "complete.obs"))
p3ra <- ggplot(cd, aes(release, coherence)) +
  geom_hline(yintercept = 0, color = "grey80", linetype = 3) +
  geom_smooth(method = "lm", se = TRUE, color = "grey40", linewidth = 0.7) +
  geom_point(aes(color = family, size = params_b), alpha = 0.85) +
  scale_color_manual(values = FAMILY_COLORS, name = "Family") +
  scale_size_continuous(transform = "log10", name = "Params (B)", range = c(1.5, 7)) +
  labs(subtitle = "vs release date", x = "Release date",
       y = "Developmental coherence (raw)") + bl
p3rb <- ggplot(cd, aes(params_b, coherence)) +
  geom_hline(yintercept = 0, color = "grey80", linetype = 3) +
  geom_smooth(method = "lm", se = TRUE, color = "grey40", linewidth = 0.7) +
  geom_point(aes(color = family), size = 2.6, alpha = 0.85) +
  scale_color_manual(values = FAMILY_COLORS, name = "Family", guide = "none") +
  scale_x_log10() +
  labs(subtitle = "vs model size", x = "Parameters (billions, log scale)", y = NULL) + bl
p3raw <- tryCatch({
  library(patchwork)
  (p3ra + p3rb) + plot_layout(guides = "collect") +
    plot_annotation(
      title = "Raw Developmental Coherence",
      subtitle = sprintf("Developmental Coherence (raw) computed using mean accuracy for each model on each dimension.\nSpearman ρ: date = %.2f, size = %.2f",
                         sp_date_raw, sp_size_raw),
      theme = theme(plot.title = element_text(face = "bold", size = 14),
                    plot.subtitle = element_text(color = "grey40", size = 11),
                    legend.position = "bottom"))
}, error = function(e) p3ra)
ggsave(file.path(out_dir, "coherence_raw_vs_date_size.png"), p3raw,
       width = 11, height = 5.5, dpi = 200, bg = "white")

# ── Figure 3c: NORMALIZED coherence vs date & size ─────────────────────────
# Alternative to residualizing: normalize each dimension's accuracy by the model's
# OVERALL mean accuracy (a multiplicative level-removal), then recompute the
# coherence measure on the normalized profile and plot vs date & size.
coh_norm <- acc_dim %>%
  mutate(acc_norm = accuracy / mean_acc) %>%
  arrange(model, dim_rank) %>%
  group_by(model) %>%
  summarise(coherence_norm = {
    a <- acc_norm[order(dim_rank)]; Kk <- length(a)
    mean(vapply(1:(Kk - 1), function(k) mean(a[1:k]) - mean(a[(k + 1):Kk]), numeric(1)))
  }, .groups = "drop") %>%
  left_join(cd %>% select(model, family, date_years, release, params_b), by = "model")

sp_date_n <- suppressWarnings(cor(coh_norm$date_years, coh_norm$coherence_norm, method = "spearman"))
sp_size_n <- suppressWarnings(cor(log10(coh_norm$params_b), coh_norm$coherence_norm,
                                  method = "spearman", use = "complete.obs"))
p3na <- ggplot(coh_norm, aes(release, coherence_norm)) +
  geom_hline(yintercept = 0, color = "grey80", linetype = 3) +
  geom_smooth(method = "lm", se = TRUE, color = "grey40", linewidth = 0.7) +
  geom_point(aes(color = family, size = params_b), alpha = 0.85) +
  scale_color_manual(values = FAMILY_COLORS, name = "Family") +
  scale_size_continuous(transform = "log10", name = "Params (B)", range = c(1.5, 7)) +
  labs(subtitle = "vs release date", x = "Release date",
       y = "Developmental coherence (normalized)") + bl
p3nb <- ggplot(coh_norm, aes(params_b, coherence_norm)) +
  geom_hline(yintercept = 0, color = "grey80", linetype = 3) +
  geom_smooth(method = "lm", se = TRUE, color = "grey40", linewidth = 0.7) +
  geom_point(aes(color = family), size = 2.6, alpha = 0.85) +
  scale_color_manual(values = FAMILY_COLORS, name = "Family", guide = "none") +
  scale_x_log10() +
  labs(subtitle = "vs model size", x = "Parameters (billions, log scale)", y = NULL) + bl
p3norm <- tryCatch({
  library(patchwork)
  (p3na + p3nb) + plot_layout(guides = "collect") +
    plot_annotation(
      title = "Normalized developmental coherence vs release date and size",
      subtitle = sprintf("Each dimension's accuracy divided by the model's overall mean accuracy (multiplicative level-removal),\nthen re-scored. Spearman ρ: date = %.2f, size = %.2f. Dividing amplifies weak models, so the gradient stands out more.",
                         sp_date_n, sp_size_n),
      theme = theme(plot.title = element_text(face = "bold", size = 14),
                    plot.subtitle = element_text(color = "grey40", size = 11),
                    legend.position = "bottom"))
}, error = function(e) p3na)
ggsave(file.path(out_dir, "coherence_normalized_vs_date_size.png"), p3norm,
       width = 11, height = 5.5, dpi = 200, bg = "white")

# ── Figure 3d: WITHIN-FAMILY residualized coherence vs date & size ─────────
# Residualize by fitting a SEPARATE OLS line (coherence ~ mean_acc) within each
# model family, and use each model's residual from its own family's line. This
# removes family-level level effects too. CAVEAT: Claude and GPT have almost no
# accuracy spread (near ceiling), so their within-family slope is ill-determined,
# and Mistral has only n = 3 models; treat those families' residuals with care.
cdf <- coh %>% mutate(family = factor_family(family),
                      release = as.Date("2024-01-01") + date_years * 365.25) %>%
  group_by(family) %>%
  mutate(coherence_resid_fam = if (n() >= 3 && sd(mean_acc) > 0)
           residuals(lm(coherence ~ mean_acc)) else coherence - mean(coherence)) %>%
  ungroup()
cat("Within-family OLS (coherence ~ mean_acc):\n")
cdf %>% group_by(family) %>%
  summarise(n = n(), slope = coef(lm(coherence ~ mean_acc))[2], .groups = "drop") %>%
  as.data.frame() %>% print(digits = 3)

sp_date_f <- suppressWarnings(cor(cdf$date_years, cdf$coherence_resid_fam, method = "spearman"))
sp_size_f <- suppressWarnings(cor(log10(cdf$params_b), cdf$coherence_resid_fam,
                                  method = "spearman", use = "complete.obs"))
p3fa <- ggplot(cdf, aes(release, coherence_resid_fam)) +
  geom_hline(yintercept = 0, color = "grey80", linetype = 3) +
  geom_smooth(method = "lm", se = TRUE, color = "grey40", linewidth = 0.7) +
  geom_point(aes(color = family, size = params_b), alpha = 0.85) +
  scale_color_manual(values = FAMILY_COLORS, name = "Family") +
  scale_size_continuous(transform = "log10", name = "Params (B)", range = c(1.5, 7)) +
  labs(subtitle = "vs release date", x = "Release date",
       y = "Developmental Coherence (within-family residual)") + bl
p3fb <- ggplot(cdf, aes(params_b, coherence_resid_fam)) +
  geom_hline(yintercept = 0, color = "grey80", linetype = 3) +
  geom_smooth(method = "lm", se = TRUE, color = "grey40", linewidth = 0.7) +
  geom_point(aes(color = family), size = 2.6, alpha = 0.85) +
  scale_color_manual(values = FAMILY_COLORS, name = "Family", guide = "none") +
  scale_x_log10() +
  labs(subtitle = "vs model size", x = "Parameters (billions, log scale)", y = NULL) + bl
p3fam <- tryCatch({
  library(patchwork)
  (p3fa + p3fb) + plot_layout(guides = "collect") +
    plot_annotation(
      title = "Within-family Residualized Developmental Coherence",
      subtitle = sprintf("Developmental Coherence residualized against a SEPARATE OLS line fit within each family. Spearman ρ: date = %.2f, size = %.2f.\nCaveat: Claude and GPT are near ceiling (no accuracy spread) and Mistral has n = 3, so their within-family fits are unstable.",
                         sp_date_f, sp_size_f),
      theme = theme(plot.title = element_text(face = "bold", size = 14),
                    plot.subtitle = element_text(color = "grey40", size = 10),
                    legend.position = "bottom"))
}, error = function(e) p3fa)
ggsave(file.path(out_dir, "coherence_resid_family_vs_date_size.png"), p3fam,
       width = 11, height = 5.5, dpi = 200, bg = "white")

# ── Figure 3e: WITHIN-SIZE-BIN residualized coherence vs date & size ───────
# Residualize by fitting a SEPARATE OLS line (coherence ~ mean_acc) within each
# size bin (small ≤10B, mid 10–70B, large >70B), and use each model's residual
# from its own bin's line. Small/mid bins have real accuracy spread; the large
# bin is near ceiling, so its within-bin slope is less stable.
cds <- coh %>% mutate(family = factor_family(family),
                      release = as.Date("2024-01-01") + date_years * 365.25) %>%
  group_by(size_bin) %>%
  mutate(coherence_resid_bin = if (n() >= 3 && sd(mean_acc) > 0)
           residuals(lm(coherence ~ mean_acc)) else coherence - mean(coherence)) %>%
  ungroup()
cat("Within-size-bin OLS (coherence ~ mean_acc):\n")
cds %>% group_by(size_bin) %>%
  summarise(n = n(), acc_range = round(diff(range(mean_acc)), 2),
            slope = coef(lm(coherence ~ mean_acc))[2], .groups = "drop") %>%
  as.data.frame() %>% print(digits = 3)

sp_date_s <- suppressWarnings(cor(cds$date_years, cds$coherence_resid_bin, method = "spearman"))
sp_size_s <- suppressWarnings(cor(log10(cds$params_b), cds$coherence_resid_bin,
                                  method = "spearman", use = "complete.obs"))
p3sa <- ggplot(cds, aes(release, coherence_resid_bin)) +
  geom_hline(yintercept = 0, color = "grey80", linetype = 3) +
  geom_smooth(method = "lm", se = TRUE, color = "grey40", linewidth = 0.7) +
  geom_point(aes(color = size_bin, size = params_b), alpha = 0.85) +
  scale_color_manual(values = SIZE_COLS, name = "Model size") +
  scale_size_continuous(transform = "log10", name = "Params (B)", range = c(1.5, 7)) +
  labs(subtitle = "vs release date", x = "Release date",
       y = "Developmental Coherence (within-size-bin residual)") + bl
p3sb <- ggplot(cds, aes(params_b, coherence_resid_bin)) +
  geom_hline(yintercept = 0, color = "grey80", linetype = 3) +
  geom_smooth(method = "lm", se = TRUE, color = "grey40", linewidth = 0.7) +
  geom_point(aes(color = size_bin), size = 2.6, alpha = 0.85) +
  scale_color_manual(values = SIZE_COLS, name = "Model size", guide = "none") +
  scale_x_log10() +
  labs(subtitle = "vs model size", x = "Parameters (billions, log scale)", y = NULL) + bl
p3siz <- tryCatch({
  library(patchwork)
  (p3sa + p3sb) + plot_layout(guides = "collect") +
    plot_annotation(
      title = "Within-size-bin Residualized Developmental Coherence",
      subtitle = sprintf("Developmental Coherence residualized against a SEPARATE OLS line fit within each size bin (small/mid/large).\nSpearman ρ: date = %.2f, size = %.2f. The large bin is near ceiling, so its within-bin slope is less stable.",
                         sp_date_s, sp_size_s),
      theme = theme(plot.title = element_text(face = "bold", size = 14),
                    plot.subtitle = element_text(color = "grey40", size = 10),
                    legend.position = "bottom"))
}, error = function(e) p3sa)
ggsave(file.path(out_dir, "coherence_resid_sizebin_vs_date_size.png"), p3siz,
       width = 11, height = 5.5, dpi = 200, bg = "white")

# ── Figure 3f: coherence ~ mean_acc + family (common slope, family intercepts)
# A single OLS with ONE shared mean_acc slope plus a per-family intercept shift.
# Far more stable than 5 separate within-family slopes (6 params vs 10, and no
# reliance on near-zero within-family accuracy spread). Residuals remove both the
# common competence trend and each family's baseline level.
cdm <- coh %>% mutate(family = factor_family(family),
                      release = as.Date("2024-01-01") + date_years * 365.25)
m_fam <- lm(coherence ~ mean_acc + family, data = cdm)
cdm$coherence_resid_famint <- residuals(m_fam)
cat("coherence ~ mean_acc + family:\n"); print(round(coef(m_fam), 3))

sp_date_m <- suppressWarnings(cor(cdm$date_years, cdm$coherence_resid_famint, method = "spearman"))
sp_size_m <- suppressWarnings(cor(log10(cdm$params_b), cdm$coherence_resid_famint,
                                  method = "spearman", use = "complete.obs"))
p3ma <- ggplot(cdm, aes(release, coherence_resid_famint)) +
  geom_hline(yintercept = 0, color = "grey80", linetype = 3) +
  geom_smooth(method = "lm", se = TRUE, color = "grey40", linewidth = 0.7) +
  geom_point(aes(color = family, size = params_b), alpha = 0.85) +
  scale_color_manual(values = FAMILY_COLORS, name = "Family") +
  scale_size_continuous(transform = "log10", name = "Params (B)", range = c(1.5, 7)) +
  labs(subtitle = "vs release date", x = "Release date",
       y = "Developmental Coherence (family-adjusted residual)") + bl
p3mb <- ggplot(cdm, aes(params_b, coherence_resid_famint)) +
  geom_hline(yintercept = 0, color = "grey80", linetype = 3) +
  geom_smooth(method = "lm", se = TRUE, color = "grey40", linewidth = 0.7) +
  geom_point(aes(color = family), size = 2.6, alpha = 0.85) +
  scale_color_manual(values = FAMILY_COLORS, name = "Family", guide = "none") +
  scale_x_log10() +
  labs(subtitle = "vs model size", x = "Parameters (billions, log scale)", y = NULL) + bl
p3mfam <- tryCatch({
  library(patchwork)
  (p3ma + p3mb) + plot_layout(guides = "collect") +
    plot_annotation(
      title = "Family-adjusted Residualized Developmental Coherence",
      subtitle = sprintf("Developmental Coherence (family-adjusted, residualized) computed using each model's residual value from fitting an\nordinary least squares line across all models with per-family intercepts.\nSpearman ρ: date = %.2f, size = %.2f",
                         sp_date_m, sp_size_m),
      theme = theme(plot.title = element_text(face = "bold", size = 14),
                    plot.subtitle = element_text(color = "grey40", size = 10),
                    legend.position = "bottom"))
}, error = function(e) p3ma)
ggsave(file.path(out_dir, "coherence_resid_famintercept_vs_date_size.png"), p3mfam,
       width = 11, height = 5.5, dpi = 200, bg = "white")

# ── Figure 4: DC(k) profile — the measure at every split point k ───────────
dk_means <- dk %>% group_by(size_bin, k) %>%
  summarise(D = mean(D), .groups = "drop")
p4 <- ggplot(dk, aes(k, D, group = model)) +
  geom_hline(yintercept = 0, color = "grey70", linetype = 2) +
  geom_line(aes(color = size_bin), alpha = 0.25, linewidth = 0.4) +
  geom_line(data = dk_means, aes(group = size_bin, color = size_bin), linewidth = 1.4) +
  scale_color_manual(values = SIZE_COLS, name = "Model size") +
  scale_x_continuous(breaks = 1:11) +
  labs(
    title = "Developmental coherence at every split point k",
    subtitle = "DC(k) = mean(accuracy of dims ≤ k) − mean(accuracy of dims > k), for each boundary dimension k.\nAbove 0 = better on the earlier/easier side of the split (coherent). Thin = models, thick = size-bin means.",
    x = "Split point k (boundary dimension, developmental order)",
    y = "DC(k) = earlier − later") +
  theme_devtom(base_size = 11) +
  theme(legend.position = "bottom")
ggsave(file.path(out_dir, "coherence_split_point_profile.png"), p4,
       width = 10, height = 6, dpi = 200, bg = "white")

cat("Wrote 9 figures to:", out_dir, "\n")
cat(list.files(out_dir, pattern = "\\.png$"), sep = "\n")
