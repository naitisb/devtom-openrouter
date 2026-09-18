#!/usr/bin/env Rscript
# visualize_dimension_age_vs_date.R — does model release date move the
# developmental age equivalent, and does it do so evenly across dimensions?
#
# Emits two figures:
#   dim_age_vs_date_facets.png — 12 small multiples (one per dimension),
#       age equivalent vs release date, with the validated developmental
#       window as a grey band and a per-dimension linear fit + slope label
#   dim_age_vs_date_slopes.png — forest plot of the 12 slopes in years of
#       developmental age gained per calendar year, pooled and family-adjusted
#
# Age equivalent is the UNCAPPED variant of the measure used in
# visualize_dimension_progress_frq.R: age_mid * (acc / 0.80). It equals the
# dimension's band midpoint exactly at the 80% mastery threshold and is free
# to run above it, so models at 85 / 92 / 100% no longer collapse onto one
# value the way the capped version forces them to.

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
})

this_dir <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) {
    args <- commandArgs(trailingOnly = FALSE)
    f <- grep("--file=", args, value = TRUE)
    if (length(f)) dirname(sub("--file=", "", f))
    else "scripts/6_visualize"
  }
)
source(file.path(this_dir, "_theme.R"))

MASTERY_THRESHOLD <- 0.80

# ── load item-level data, FRQ only ─────────────────────────────────────────
item_csv <- "results/item_level.csv"
if (!file.exists(item_csv)) stop("Missing: ", item_csv,
  "\nRun: python scripts/4_statistics/extract_item_level.py")

df <- read.csv(item_csv, stringsAsFactors = FALSE) %>%
  filter(task == "tom_12dim_freeresponse", family %in% FAMILY_ORDER) %>%
  mutate(release_date = as.Date(release_date)) %>%
  filter(!is.na(release_date))

cat("FRQ rows:", nrow(df),
    "  Models:", length(unique(df$model)),
    "  Dates:", format(min(df$release_date)), "->",
    format(max(df$release_date)), "\n")

# ── dimension order (Irony before Faux Pas, matching the recent figures) ───
DIM_ORDER <- c(
  "Diverse Desires",
  "Diverse Beliefs",
  "Knowledge Access / Ignorance",
  "Emotion Recognition",
  "First-Order False Belief",
  "Intention vs. Accident",
  "Hidden Emotion (Appearance vs. Reality)",
  "Second-Order False Belief",
  "White Lies / Prosocial Deception",
  "Sarcasm",
  "Irony",
  "Faux Pas Detection"
)

dim_bands <- tibble::tribble(
  ~tom_dimension,                             ~age_lo, ~age_hi, ~age_mid,
  "Diverse Desires",                           2,       3,       2.5,
  "Diverse Beliefs",                           3,       4,       3.5,
  "Knowledge Access / Ignorance",              3,       4,       3.5,
  "Emotion Recognition",                       3,       4,       3.5,
  "First-Order False Belief",                  4,       5,       4.5,
  "Intention vs. Accident",                    4,       5,       4.5,
  "Hidden Emotion (Appearance vs. Reality)",    4,       6,       5.0,
  "White Lies / Prosocial Deception",          5,       7,       6.0,
  "Second-Order False Belief",                 6,       7,       6.5,
  "Sarcasm",                                   6,       8,       7.0,
  "Irony",                                     6,       8,       7.0,
  "Faux Pas Detection",                        9,      11,      10.0
)

# ── per-model per-dimension accuracy -> uncapped age equivalent ────────────
model_dim <- df %>%
  group_by(model, family, tier, tom_dimension, release_date) %>%
  summarise(
    n_items   = n(),
    n_correct = sum(correct, na.rm = TRUE),
    acc       = mean(correct, na.rm = TRUE),
    .groups   = "drop"
  ) %>%
  select(-tom_dimension, tom_dimension = tom_dimension) %>%
  left_join(dim_bands, by = "tom_dimension") %>%
  filter(!is.na(age_mid)) %>%
  mutate(
    # UNCAPPED: no pmin at age_mid, no clamp at 11. Equals age_mid at acc = .80.
    age_equiv     = age_mid * (acc / MASTERY_THRESHOLD),
    at_ceiling    = acc >= 1.0,
    tom_dimension = factor(tom_dimension, levels = DIM_ORDER),
    family        = factor_family(family),
    tier          = factor_tier(tier)
  ) %>%
  filter(!is.na(tom_dimension))

# ── flag non-responsive models ─────────────────────────────────────────────
# A model scoring 0/N across every dimension is a format/scoring failure, not
# a competence estimate of zero. It would otherwise anchor all 12 fits at the
# left edge. Flagged, drawn hollow, and excluded from the fits; the inclusive
# slope is still written to the CSV as a sensitivity check.
nonresponsive <- model_dim %>%
  group_by(model) %>%
  summarise(overall_acc = sum(n_correct) / sum(n_items), .groups = "drop") %>%
  filter(overall_acc <= 0) %>%
  pull(model)

if (length(nonresponsive)) {
  cat("Non-responsive (0% overall on FRQ), excluded from fits:\n  ",
      paste(nonresponsive, collapse = "\n  "), "\n")
}

model_dim <- model_dim %>%
  mutate(responsive = !(model %in% nonresponsive))

# years since the first release in the roster -> slope reads as years/year
date_origin <- min(model_dim$release_date)
model_dim <- model_dim %>%
  mutate(release_years = as.numeric(release_date - date_origin) / 365.25)

cat("Models x dimensions:", nrow(model_dim),
    "  at 100%:", sum(model_dim$at_ceiling),
    sprintf("(%.0f%%)\n", 100 * mean(model_dim$at_ceiling)))

# ── per-dimension linear fits: pooled, and adjusted for family ─────────────
fit_one <- function(d_all) {
  d <- dplyr::filter(d_all, responsive)
  pooled <- lm(age_equiv ~ release_years, data = d)
  ci_p   <- confint(pooled)["release_years", ]
  out <- tibble::tibble(
    tom_dimension = d$tom_dimension[1],
    n_models      = nrow(d),
    n_excluded    = nrow(d_all) - nrow(d),
    pct_ceiling   = 100 * mean(d$at_ceiling),
    slope         = unname(coef(pooled)["release_years"]),
    lo            = unname(ci_p[1]),
    hi            = unname(ci_p[2]),
    p             = summary(pooled)$coefficients["release_years", "Pr(>|t|)"],
    r2            = summary(pooled)$r.squared
  )
  # family-adjusted slope: release date net of which family a model belongs to
  if (dplyr::n_distinct(d$family) > 1) {
    adj    <- lm(age_equiv ~ release_years + family, data = d)
    ci_a   <- confint(adj)["release_years", ]
    out$slope_adj <- unname(coef(adj)["release_years"])
    out$lo_adj    <- unname(ci_a[1])
    out$hi_adj    <- unname(ci_a[2])
    out$p_adj     <- summary(adj)$coefficients["release_years", "Pr(>|t|)"]
  } else {
    out$slope_adj <- NA_real_; out$lo_adj <- NA_real_
    out$hi_adj    <- NA_real_; out$p_adj  <- NA_real_
  }
  # sensitivity: same pooled fit with the non-responsive model(s) left in
  if (nrow(d_all) > nrow(d)) {
    incl <- lm(age_equiv ~ release_years, data = d_all)
    out$slope_incl <- unname(coef(incl)["release_years"])
    out$p_incl     <- summary(incl)$coefficients["release_years", "Pr(>|t|)"]
  } else {
    out$slope_incl <- out$slope; out$p_incl <- out$p
  }
  out
}

fits <- model_dim %>%
  group_split(tom_dimension) %>%
  lapply(fit_one) %>%
  bind_rows() %>%
  mutate(
    tom_dimension = factor(as.character(tom_dimension), levels = DIM_ORDER),
    sig     = !is.na(p) & p < 0.05,
    sig_adj = !is.na(p_adj) & p_adj < 0.05,
    label   = sprintf("%+.2f yr/yr [%+.2f, %+.2f]%s",
                      slope, lo, hi, ifelse(sig, "*", ""))
  ) %>%
  arrange(tom_dimension)

print(as.data.frame(fits[, c("tom_dimension", "n_models", "pct_ceiling",
                             "slope", "lo", "hi", "p", "slope_adj", "p_adj",
                             "slope_incl")]),
      digits = 3)

# ── output directory ───────────────────────────────────────────────────────
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path("results", "figures", "developmental_age", ts)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
cat("Writing to:", out_dir, "\n")

write.csv(fits, file.path(out_dir, "dim_age_vs_date_slopes.csv"),
          row.names = FALSE)

# ── Figure 1: 12 small multiples ───────────────────────────────────────────
bands_f <- dim_bands %>%
  mutate(tom_dimension = factor(tom_dimension, levels = DIM_ORDER))

y_lo <- min(model_dim$age_equiv, na.rm = TRUE)
y_hi <- max(model_dim$age_equiv, na.rm = TRUE)
y_lo <- y_lo - 0.25   # headroom so excluded markers render whole, not clipped
lab_y <- y_hi + 0.06 * (y_hi - y_lo)

fits_lab <- fits %>%
  mutate(x = min(model_dim$release_date), y = lab_y)

p_facets <- ggplot(model_dim, aes(x = release_date, y = age_equiv)) +
  geom_rect(data = bands_f, inherit.aes = FALSE,
            aes(xmin = -Inf, xmax = Inf, ymin = age_lo, ymax = age_hi),
            fill = "grey85", alpha = 0.55) +
  geom_hline(data = bands_f, inherit.aes = FALSE,
             aes(yintercept = age_mid),
             linetype = "dashed", color = "grey45", linewidth = 0.35) +
  geom_point(data = filter(model_dim, !responsive),
             shape = 4, size = 2.1, stroke = 0.7, color = "grey55") +
  geom_point(data = filter(model_dim, responsive),
             aes(color = family, shape = family), size = 1.9, alpha = 0.8) +
  geom_smooth(data = filter(model_dim, responsive),
              method = "lm", formula = y ~ x, se = TRUE,
              color = "grey20", fill = "grey60",
              linewidth = 0.8, alpha = 0.22) +
  geom_text(data = fits_lab, inherit.aes = FALSE,
            aes(x = x, y = y, label = label, fontface = ifelse(sig, "bold", "plain")),
            hjust = 0, vjust = 1, size = 2.9, color = "grey15") +
  facet_wrap(~ tom_dimension, ncol = 4) +
  scale_color_manual(values = FAMILY_COLORS, name = "Family") +
  scale_shape_manual(values = c(Claude = 16, GPT = 17, Llama = 15,
                                Qwen = 18, Mistral = 8), name = "Family") +
  scale_x_date(date_labels = "%b\n%Y", date_breaks = "1 year") +
  scale_y_continuous(breaks = seq(0, 16, 2)) +
  coord_cartesian(ylim = c(y_lo, lab_y + 0.04 * (y_hi - y_lo))) +
  labs(
    title = "Does Release Date Move the Developmental Age Equivalent? (Free-Response Only)",
    subtitle = paste0(
      "One point per model; grey band = validated developmental window, dashed line = band midpoint (80% mastery).\n",
      "Line = OLS fit with 95% CI; label = slope in years of developmental age per calendar year (* = p < .05, pooled across families)."
    ),
    x = "Release Date",
    y = "Age equivalent (years, uncapped)",
    caption = paste0("Age equivalent = band midpoint x (accuracy / 0.80), uncapped above the midpoint. ",
                     "Fits are marginal: release date and family are confounded in the roster.\n",
                     "Grey crosses = model scoring 0% across all dimensions (format/scoring failure); excluded from fits.")
  ) +
  theme_devtom(base_size = 11) +
  theme(
    axis.text.x  = element_text(size = 7.5),
    strip.text   = element_text(face = "bold", size = 9),
    plot.caption = element_text(color = "grey45", size = 8, hjust = 1),
    panel.spacing = unit(0.7, "lines")
  ) +
  guides(color = guide_legend(override.aes = list(size = 2.6)))

ggsave(file.path(out_dir, "dim_age_vs_date_facets.png"), p_facets,
       width = 16, height = 10, dpi = 300)

# ── Figure 2: forest plot of the 12 slopes ─────────────────────────────────
forest <- bind_rows(
  fits %>% transmute(tom_dimension, model_spec = "Pooled",
                     slope, lo, hi, sig),
  fits %>% filter(!is.na(slope_adj)) %>%
    transmute(tom_dimension, model_spec = "Adjusted for family",
              slope = slope_adj, lo = lo_adj, hi = hi_adj, sig = sig_adj)
) %>%
  mutate(
    model_spec    = factor(model_spec, levels = c("Pooled", "Adjusted for family")),
    tom_dimension = factor(as.character(tom_dimension), levels = rev(DIM_ORDER))
  )

p_forest <- ggplot(forest, aes(x = slope, y = tom_dimension,
                                color = model_spec, shape = sig)) +
  geom_vline(xintercept = 0, linetype = "dashed",
             color = "grey45", linewidth = 0.6) +
  geom_errorbar(aes(xmin = lo, xmax = hi), orientation = "y",
                width = 0, linewidth = 0.7,
                position = position_dodge(width = 0.6)) +
  geom_point(size = 2.8, position = position_dodge(width = 0.6)) +
  scale_color_manual(values = c("Pooled" = "#08519c",
                                "Adjusted for family" = "#a63603"),
                     name = "Specification") +
  scale_shape_manual(values = c(`TRUE` = 16, `FALSE` = 21),
                     labels = c(`TRUE` = "p < .05", `FALSE` = "n.s."),
                     name = "") +
  labs(
    title = "Release-Date Effect on Age Equivalent, by Dimension (Free-Response Only)",
    subtitle = paste0(
      "Slope of the per-dimension OLS fit, in years of developmental age gained per calendar year.\n",
      "Developmental order, earliest-acquired at top. Hollow points: CI includes zero."
    ),
    x = "Years of developmental age per calendar year",
    y = NULL,
    caption = paste0("Adjusted specification adds family as a fixed effect, isolating date from roster composition.\n",
                     "Models scoring 0% across all dimensions are excluded; see dim_age_vs_date_slopes.csv for the inclusive slopes.")
  ) +
  theme_devtom(base_size = 11) +
  theme(
    panel.grid.major.y = element_line(color = "grey92"),
    plot.caption = element_text(color = "grey45", size = 8, hjust = 1)
  )

ggsave(file.path(out_dir, "dim_age_vs_date_slopes.png"), p_forest,
       width = 11, height = 7.5, dpi = 300)

cat("Done.\n")
