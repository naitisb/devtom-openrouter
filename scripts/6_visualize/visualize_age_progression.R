#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

source("scripts/6_visualize/_theme.R")

base_dir <- "results/modeling/developmental_age_mapping"
ts_dirs <- list.dirs(base_dir, recursive = FALSE, full.names = TRUE)
model_dir <- sort(ts_dirs, decreasing = TRUE)[1]
cat("Reading from:", model_dir, "\n")

fig_dir <- file.path("results", "figures", "developmental_age",
                      basename(model_dir))
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

# Load mastery data
mastery_dim <- read_csv(file.path(model_dir, "mastery_age_dimension.csv"),
                        show_col_types = FALSE) %>%
  filter(task_filter == "all")

mastery_con <- read_csv(file.path(model_dir, "mastery_age_construct.csv"),
                        show_col_types = FALSE) %>%
  filter(task_filter == "all")

mastery_ovr <- read_csv(file.path(model_dir, "mastery_age_overall.csv"),
                        show_col_types = FALSE) %>%
  filter(task_filter == "all")

item_csv <- "results/item_level.csv"
df <- read_csv(item_csv, show_col_types = FALSE) %>%
  filter(family %in% FAMILY_ORDER)

models_meta <- df %>%
  distinct(model, family, tier, release_date) %>%
  mutate(release_date = as.Date(release_date),
         short_name = short_model(model))

# Dimension-to-construct mapping
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

FAMILY_SHAPES <- c(
  Claude = 16,   # filled circle
  GPT = 17,      # filled triangle
  Llama = 15,    # filled square
  Qwen = 18,     # filled diamond
  Mistral = 8    # asterisk
)

# Dimension colors: shades within each construct
# Each construct gets a base hue; dimensions within it get lighter/darker variants
DIMENSION_COLORS <- c(
  "Diverse Desires"                       = "#6B94D0",  # lighter blue
  "Intention vs. Accident"                = "#2C5498",  # darker blue
  "Diverse Beliefs"                       = "#F4A76C",  # lighter orange
  "First-Order False Belief"              = "#DD8452",  # mid orange
  "Second-Order False Belief"             = "#B05A20",  # darker orange
  "Knowledge Access / Ignorance"          = "#55A868",  # green (single dim)
  "Emotion Recognition"                   = "#E07070",  # lighter red
  "Hidden Emotion (Appearance vs. Reality)" = "#A0302E", # darker red
  "White Lies / Prosocial Deception"      = "#8172B3",  # purple (single dim)
  "Sarcasm"                               = "#B8A488",  # lighter brown
  "Faux Pas Detection"                    = "#937860",  # mid brown
  "Irony"                                 = "#6A5238"   # darker brown
)

# =========================================================================
# Plot 1: Overall mastery age vs release date
# =========================================================================
cat("Plot 1: Overall age progression...\n")

ovr_plot <- mastery_ovr %>%
  left_join(models_meta, by = "model") %>%
  filter(!is.na(mastery_age), !is.na(release_date)) %>%
  mutate(family = factor_family(family))

p1 <- ggplot(ovr_plot, aes(x = release_date, y = mastery_age,
                            color = family, shape = family)) +
  geom_point(size = 3.5, alpha = 0.85) +
  geom_smooth(aes(group = 1), method = "loess", se = TRUE,
              color = "grey40", linewidth = 0.8, alpha = 0.2) +
  scale_color_manual(values = FAMILY_COLORS, name = "Family") +
  scale_shape_manual(values = FAMILY_SHAPES, name = "Family") +
  scale_x_date(date_labels = "%b %Y", date_breaks = "6 months") +
  scale_y_continuous(limits = c(4, 9), breaks = seq(4, 9, 1)) +
  labs(
    title = "Overall Mastery Age Over Time",
    subtitle = "Each point is one model; LOESS trend with 95% CI",
    x = "Release Date",
    y = "Overall Mastery Age (years)"
  ) +
  theme_devtom(base_size = 11) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

ggsave(file.path(fig_dir, "age_progression_overall.png"), p1,
       width = 12, height = 6, dpi = 200)

# =========================================================================
# Plot 2: Per-dimension mastery age vs release date
# =========================================================================
cat("Plot 2: Per-dimension age progression...\n")

dim_plot <- mastery_dim %>%
  left_join(models_meta, by = "model") %>%
  filter(!is.na(release_date)) %>%
  mutate(
    mastery_age = as.numeric(mastery_age),
    tom_dimension = factor_dimension(tom_dimension),
    construct = DIM_TO_CONSTRUCT[as.character(tom_dimension)],
    family = factor_family(family)
  ) %>%
  filter(!is.na(mastery_age))

p2 <- ggplot(dim_plot, aes(x = release_date, y = mastery_age,
                            color = tom_dimension, shape = family)) +
  geom_point(size = 2, alpha = 0.7) +
  geom_smooth(aes(group = tom_dimension, color = tom_dimension),
              method = "loess", se = FALSE, linewidth = 0.6, alpha = 0.6) +
  scale_color_manual(values = DIMENSION_COLORS, name = "Dimension") +
  scale_shape_manual(values = FAMILY_SHAPES, name = "Family") +
  scale_x_date(date_labels = "%b %Y", date_breaks = "6 months") +
  scale_y_continuous(breaks = seq(2, 12, 1)) +
  labs(
    title = "Mastery Age by Dimension Over Time",
    subtitle = "Each point is one model; LOESS trends per dimension",
    x = "Release Date",
    y = "Mastery Age (years)"
  ) +
  theme_devtom(base_size = 10) +
  theme(
    axis.text.x = element_text(angle = 30, hjust = 1),
    legend.text = element_text(size = 7),
    legend.key.size = unit(0.4, "cm")
  ) +
  guides(
    color = guide_legend(ncol = 2, override.aes = list(size = 2.5)),
    shape = guide_legend(ncol = 1, override.aes = list(size = 2.5))
  )

ggsave(file.path(fig_dir, "age_progression_by_dimension.png"), p2,
       width = 14, height = 7, dpi = 200)

# =========================================================================
# Plot 3: Per-construct mastery age vs release date
# =========================================================================
cat("Plot 3: Per-construct age progression...\n")

con_plot <- mastery_con %>%
  left_join(models_meta, by = "model") %>%
  filter(!is.na(release_date)) %>%
  mutate(
    mastery_age = as.numeric(mastery_age),
    tom_construct = factor_construct(tom_construct),
    family = factor_family(family)
  ) %>%
  filter(!is.na(mastery_age))

p3 <- ggplot(con_plot, aes(x = release_date, y = mastery_age,
                            color = tom_construct, shape = family)) +
  geom_point(size = 3, alpha = 0.75) +
  geom_smooth(aes(group = tom_construct, color = tom_construct),
              method = "loess", se = TRUE, linewidth = 0.7, alpha = 0.15) +
  scale_color_manual(values = CONSTRUCT_COLORS, name = "Construct") +
  scale_shape_manual(values = FAMILY_SHAPES, name = "Family") +
  scale_x_date(date_labels = "%b %Y", date_breaks = "6 months") +
  scale_y_continuous(breaks = seq(2, 12, 1)) +
  labs(
    title = "Mastery Age by Construct Over Time",
    subtitle = "Each point is one model; LOESS trends with 95% CI per construct",
    x = "Release Date",
    y = "Mastery Age (years)"
  ) +
  theme_devtom(base_size = 11) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1)) +
  guides(
    color = guide_legend(override.aes = list(size = 3)),
    shape = guide_legend(override.aes = list(size = 3))
  )

ggsave(file.path(fig_dir, "age_progression_by_construct.png"), p3,
       width = 13, height = 7, dpi = 200)

cat("\n=== Progression figures written ===\n")
list.files(fig_dir, pattern = "progression") %>% cat(sep = "\n")
cat("\nDone.\n")
