#!/usr/bin/env Rscript
# visualize_age_progression_by_size.R — overall mastery age vs release date,
# with models separated within each family by size tier.
#
# Rebuild of age_progression_overall.png (visualize_age_progression.R, plot 1),
# which drew one series per family. Two differences beyond the size split:
#
#   1. Mastery age is recomputed directly from results/item_level.csv rather
#      than read from results/modeling/developmental_age_mapping/. The newest
#      mapping run predates the current item_level.csv and uses different route
#      prefixes for the open-weight models (openrouter/... vs openai-api/local/...),
#      so joining it to release dates silently drops most of the roster.
#   2. The original used scale_y_continuous(limits = c(4, 9)), which DELETES
#      rather than clips out-of-range points — every model at mastery age 10 or
#      11 vanished, and the LOESS was fit on the surviving minority. Y-range here
#      is set with coord_cartesian, which never drops data.
#
# Emits:
#   age_progression_overall_by_size.png   — faceted by family, one color per size tier
#   age_progression_overall_size_single.png — single panel, all families together

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
MIN_N_FIT         <- 4      # families with fewer models get points only, no line

# ── load item-level data (both tasks = the "all" task filter) ──────────────
item_csv <- "results/item_level.csv"
if (!file.exists(item_csv)) stop("Missing: ", item_csv,
  "\nRun: python scripts/4_statistics/extract_item_level.py")

df <- read.csv(item_csv, stringsAsFactors = FALSE) %>%
  filter(family %in% FAMILY_ORDER) %>%
  mutate(release_date = as.Date(release_date)) %>%
  filter(!is.na(release_date))

cat("Rows:", nrow(df), "  Models:", length(unique(df$model)),
    "  Tasks:", paste(unique(df$task), collapse = ", "), "\n")

# ── overall mastery age ────────────────────────────────────────────────────
# Matches compute_mastery_age() in scripts/5_model/developmental_age_mapping.R:
# pool items by validated age band (age_mid varies WITHIN a dimension in
# item_level.csv, so bands are an item property, not a dimension property),
# then take the highest band the model passes at >= 80%.
age_acc <- df %>%
  group_by(model, family, tier, release_date, age_mid) %>%
  summarise(acc = sum(correct, na.rm = TRUE) / n(), n_items = n(), .groups = "drop")

mastery <- age_acc %>%
  group_by(model, family, tier, release_date) %>%
  summarise(
    mastery_age = if (any(acc >= MASTERY_THRESHOLD)) {
      max(age_mid[acc >= MASTERY_THRESHOLD], na.rm = TRUE)
    } else NA_real_,
    n_bands        = n(),
    n_bands_passed = sum(acc >= MASTERY_THRESHOLD),
    .groups = "drop"
  ) %>%
  mutate(
    family     = factor_family(family),
    tier       = factor_tier(tier),
    short_name = short_model(model)
  )

n_none <- sum(is.na(mastery$mastery_age))
if (n_none) cat("Models passing no dimension (no mastery age, dropped):", n_none, "\n")
mastery <- filter(mastery, !is.na(mastery_age))

cat("Models plotted:", nrow(mastery), "\n")
print(mastery %>% count(family, tier) %>% as.data.frame())

# ── per-family trends ──────────────────────────────────────────────────────
fam_fit <- mastery %>%
  group_by(family) %>%
  group_modify(~{
    n_mod <- nrow(.x)
    # a family whose models all share one mastery age has no trend to fit --
    # the OLS is degenerate and reports a spurious slope of exactly zero
    if (n_mod < MIN_N_FIT || dplyr::n_distinct(.x$mastery_age) < 2) {
      return(tibble::tibble(
        slope = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_,
        n = n_mod, fitted = FALSE,
        note = if (dplyr::n_distinct(.x$mastery_age) < 2)
          sprintf("all %d models at %.1f yr", n_mod, .x$mastery_age[1])
        else sprintf("n = %d, no fit", n_mod)
      ))
    }
    yrs <- as.numeric(.x$release_date - min(mastery$release_date)) / 365.25
    m   <- lm(.x$mastery_age ~ yrs)
    ci  <- confint(m)["yrs", ]
    tibble::tibble(slope = unname(coef(m)["yrs"]),
                   lo = unname(ci[1]), hi = unname(ci[2]),
                   p = summary(m)$coefficients["yrs", "Pr(>|t|)"],
                   n = n_mod, fitted = TRUE, note = NA_character_)
  }) %>%
  ungroup() %>%
  mutate(label = ifelse(fitted,
                        sprintf("%+.2f yr/yr [%+.2f, %+.2f]%s",
                                slope, lo, hi, ifelse(p < 0.05 & !is.na(p), "*", "")),
                        note))

cat("\nPer-family trends in overall mastery age:\n")
print(as.data.frame(fam_fit), digits = 3)

# ── output directory ───────────────────────────────────────────────────────
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path("results", "figures", "developmental_age", ts)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
cat("\nWriting to:", out_dir, "\n")
write.csv(mastery, file.path(out_dir, "age_progression_by_size.csv"), row.names = FALSE)
write.csv(fam_fit, file.path(out_dir, "age_progression_family_slopes.csv"), row.names = FALSE)

tiers_present <- levels(droplevels(mastery$tier))
tc <- TYPE_COLORS[tiers_present]

y_lo <- min(mastery$mastery_age) - 0.4
y_hi <- max(mastery$mastery_age) + 0.4

# ── Figure 1: faceted by family, colored by size tier ──────────────────────
fam_lab <- fam_fit %>%
  mutate(x = min(mastery$release_date), y = y_hi)

p_facet <- ggplot(mastery, aes(x = release_date, y = mastery_age)) +
  geom_smooth(data = filter(mastery, family %in% fam_fit$family[fam_fit$fitted]),
              aes(group = family), method = "lm", formula = y ~ x, se = TRUE,
              color = "grey35", fill = "grey65", linewidth = 0.7, alpha = 0.18) +
  geom_point(aes(color = tier, shape = tier), size = 3.2, alpha = 0.9) +
  geom_text(data = filter(fam_lab, fitted), inherit.aes = FALSE,
            aes(x = x, y = y, label = label,
                fontface = ifelse(!is.na(p) & p < 0.05, "bold", "plain")),
            hjust = 0, vjust = 1, size = 3.1, color = "grey15") +
  geom_text(data = filter(fam_lab, !fitted), inherit.aes = FALSE,
            aes(x = x, y = y, label = label),
            hjust = 0, vjust = 1, size = 3.1, color = "grey55", fontface = "italic") +
  facet_wrap(~ family, nrow = 1) +
  scale_color_manual(values = tc, name = "Size tier") +
  scale_shape_manual(values = rep(c(16, 17, 15, 18), length.out = length(tiers_present)),
                     breaks = tiers_present, name = "Size tier") +
  scale_x_date(date_labels = "%b\n%Y", date_breaks = "1 year") +
  scale_y_continuous(breaks = seq(2, 12, 1)) +
  coord_cartesian(ylim = c(y_lo, y_hi)) +
  labs(
    title = "Overall Mastery Age Over Time, by Family and Size Tier",
    subtitle = paste0(
      "One point per model, colored light-to-dark by size within each family. ",
      "Grey line = OLS fit across all sizes in that family, 95% CI.\n",
      "Label = years of developmental age per calendar year (* = p < .05); grey label = no fit ",
      "(fewer than ", MIN_N_FIT, " models, or every model at the same mastery age)."
    ),
    x = "Release Date",
    y = "Overall Mastery Age (years)",
    caption = paste0("Mastery age = highest validated age band passed at >= 80% accuracy, both tasks pooled; ",
                     "bands are item-level, matching compute_mastery_age() in developmental_age_mapping.R.")
  ) +
  theme_devtom(base_size = 11) +
  theme(
    axis.text.x   = element_text(size = 7.5),
    strip.text    = element_text(face = "bold", size = 11),
    legend.text   = element_text(size = 8),
    legend.key.size = unit(0.42, "cm"),
    plot.caption  = element_text(color = "grey45", size = 8, hjust = 1),
    panel.spacing = unit(0.7, "lines")
  ) +
  guides(color = guide_legend(ncol = 1, override.aes = list(size = 2.8)))

ggsave(file.path(out_dir, "age_progression_overall_by_size.png"), p_facet,
       width = 16, height = 6.5, dpi = 300)

# ── Figure 2: single panel, all families, tier as color ────────────────────
p_single <- ggplot(mastery, aes(x = release_date, y = mastery_age)) +
  geom_smooth(aes(group = 1), method = "lm", formula = y ~ x, se = TRUE,
              color = "grey35", fill = "grey65", linewidth = 0.8, alpha = 0.18) +
  geom_point(aes(color = tier, shape = family), size = 3.4, alpha = 0.9) +
  scale_color_manual(values = tc, name = "Size tier") +
  scale_shape_manual(values = c(Claude = 16, GPT = 17, Llama = 15,
                                Qwen = 18, Mistral = 8), name = "Family") +
  scale_x_date(date_labels = "%b %Y", date_breaks = "6 months") +
  scale_y_continuous(breaks = seq(2, 12, 1)) +
  coord_cartesian(ylim = c(y_lo, y_hi)) +
  labs(
    title = "Overall Mastery Age Over Time",
    subtitle = "One point per model; color = size tier (light to dark within family), shape = family; OLS fit with 95% CI",
    x = "Release Date",
    y = "Overall Mastery Age (years)",
    caption = paste0("Mastery age = highest validated age band passed at >= 80% accuracy, both tasks pooled; ",
                     "bands are item-level, matching compute_mastery_age() in developmental_age_mapping.R.")
  ) +
  theme_devtom(base_size = 11) +
  theme(
    axis.text.x  = element_text(angle = 30, hjust = 1),
    legend.text  = element_text(size = 8),
    legend.key.size = unit(0.42, "cm"),
    plot.caption = element_text(color = "grey45", size = 8, hjust = 1)
  ) +
  guides(
    color = guide_legend(ncol = 1, order = 1, override.aes = list(size = 2.8)),
    shape = guide_legend(ncol = 1, order = 2, override.aes = list(size = 2.8))
  )

ggsave(file.path(out_dir, "age_progression_overall_size_single.png"), p_single,
       width = 13, height = 7, dpi = 300)

cat("Done.\n")
