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

item_csv <- "results/item_level.csv"
df <- read_csv(item_csv, show_col_types = FALSE) %>%
  filter(family %in% FAMILY_ORDER)

models_meta <- df %>%
  distinct(model, family, tier, release_date) %>%
  mutate(release_date = as.Date(release_date),
         short_name = short_model(model))

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
  Claude = 16, GPT = 17, Llama = 15, Qwen = 18, Mistral = 8
)

FIRST_ORDER_DIMS <- c(
  "Diverse Desires",
  "Diverse Beliefs",
  "Knowledge Access / Ignorance",
  "Emotion Recognition",
  "First-Order False Belief",
  "Intention vs. Accident"
)

HIGHER_ORDER_DIMS <- c(
  "Hidden Emotion (Appearance vs. Reality)",
  "Second-Order False Belief",
  "White Lies / Prosocial Deception",
  "Irony",
  "Sarcasm",
  "Faux Pas Detection"
)

DIMENSION_COLORS <- c(
  "Diverse Desires"                         = "#6B94D0",
  "Intention vs. Accident"                  = "#2C5498",
  "Diverse Beliefs"                         = "#F4A76C",
  "First-Order False Belief"                = "#DD8452",
  "Second-Order False Belief"               = "#B05A20",
  "Knowledge Access / Ignorance"            = "#55A868",
  "Emotion Recognition"                     = "#E07070",
  "Hidden Emotion (Appearance vs. Reality)"  = "#A0302E",
  "White Lies / Prosocial Deception"        = "#8172B3",
  "Sarcasm"                                 = "#B8A488",
  "Faux Pas Detection"                      = "#937860",
  "Irony"                                   = "#6A5238"
)

DIMENSION_SHAPES <- c(
  "Diverse Desires"                         = 16,
  "Diverse Beliefs"                         = 17,
  "Knowledge Access / Ignorance"            = 15,
  "Emotion Recognition"                     = 18,
  "First-Order False Belief"                = 8,
  "Intention vs. Accident"                  = 3,
  "Hidden Emotion (Appearance vs. Reality)"  = 4,
  "Second-Order False Belief"               = 7,
  "White Lies / Prosocial Deception"        = 9,
  "Irony"                                   = 10,
  "Sarcasm"                                 = 13,
  "Faux Pas Detection"                      = 14
)

CONSTRUCT_SHAPES <- c(
  "Desire / intention inference" = 16,
  "Belief reasoning"             = 17,
  "Knowledge access"             = 15,
  "Emotion recognition"          = 18,
  "Deception"                    = 8,
  "Pragmatic understanding"      = 3
)

# Helper: make plots (overall, by-dimension, first/higher-order, by-construct)
# Lines/colors = model tier; shapes = dimension or construct
# mode: "absolute" = raw age on y-axis, "deviation" = age - target on y-axis
make_trio <- function(dim_data, con_data, ovr_data,
                      age_col, method_label, file_prefix,
                      mode = "absolute") {

  is_dev <- (mode == "deviation")
  y_lab <- if (is_dev) paste0(method_label, " Age − Target Age (years)") else paste0(method_label, " Age (years)")
  ref_line <- if (is_dev) geom_hline(yintercept = 0, linetype = "dashed", color = "grey50", linewidth = 0.6) else NULL
  title_tag <- if (is_dev) " Deviation" else ""
  sub_ovr <- if (is_dev) "Deviation from mean target age; dashed line = 0 (matches target)" else "Each point is one model; LOESS trend with 95% CI"
  sub_dim <- if (is_dev) "Deviation from per-dimension target age; dashed = 0" else "Lines = LOESS per tier; shapes = dimensions"
  sub_fo  <- if (is_dev) "Deviation from per-dimension target age; dashed = 0" else "Desires, beliefs, knowledge, emotion, first-order false belief, intention"
  sub_ho  <- if (is_dev) "Deviation from per-dimension target age; dashed = 0" else "Hidden emotion, second-order false belief, deception, irony, sarcasm, faux pas"
  sub_con <- if (is_dev) "Deviation from per-construct target age; dashed = 0" else "Lines = LOESS per tier; shapes = constructs"

  # --- Overall ---
  if (!is.null(ovr_data) && nrow(ovr_data) > 0) {
    cat("  ", method_label, title_tag, "overall...\n")
    p_ovr <- ggplot(ovr_data, aes(x = release_date, y = .data[[age_col]],
                                   color = tier, shape = family)) +
      ref_line +
      geom_point(size = 3.5, alpha = 0.85) +
      geom_smooth(aes(group = 1), method = "loess", se = TRUE,
                  color = "grey40", linewidth = 0.8, alpha = 0.2) +
      scale_color_manual(values = TYPE_COLORS, name = "Tier") +
      scale_shape_manual(values = FAMILY_SHAPES, name = "Family") +
      scale_x_date(date_labels = "%b %Y", date_breaks = "6 months") +
      labs(
        title = paste0("Overall ", method_label, " Age", title_tag, " Over Time"),
        subtitle = sub_ovr,
        x = "Release Date", y = y_lab
      ) +
      theme_devtom(base_size = 11) +
      theme(axis.text.x = element_text(angle = 30, hjust = 1)) +
      guides(
        color = guide_legend(ncol = 2, override.aes = list(size = 2.5)),
        shape = guide_legend(ncol = 1, override.aes = list(size = 2.5))
      )

    ggsave(file.path(fig_dir, paste0(file_prefix, "_overall.png")), p_ovr,
           width = 14, height = 7, dpi = 200)
  }

  # --- By dimension ---
  if (!is.null(dim_data) && nrow(dim_data) > 0) {
    cat("  ", method_label, title_tag, "by dimension...\n")
    p_dim <- ggplot(dim_data, aes(x = release_date, y = .data[[age_col]],
                                   color = tier, shape = tom_dimension)) +
      ref_line +
      geom_point(size = 2.5, alpha = 0.7) +
      geom_smooth(aes(group = tier, color = tier),
                  method = "loess", se = FALSE, linewidth = 0.6, alpha = 0.6) +
      scale_color_manual(values = TYPE_COLORS, name = "Tier") +
      scale_shape_manual(values = DIMENSION_SHAPES, name = "Dimension") +
      scale_x_date(date_labels = "%b %Y", date_breaks = "6 months") +
      labs(
        title = paste0(method_label, " Age", title_tag, " by Dimension Over Time"),
        subtitle = sub_dim,
        x = "Release Date", y = y_lab
      ) +
      theme_devtom(base_size = 10) +
      theme(
        axis.text.x = element_text(angle = 30, hjust = 1),
        legend.text = element_text(size = 7),
        legend.key.size = unit(0.4, "cm")
      ) +
      guides(
        color = guide_legend(ncol = 2, override.aes = list(size = 2.5)),
        shape = guide_legend(ncol = 2, override.aes = list(size = 2.5))
      )

    ggsave(file.path(fig_dir, paste0(file_prefix, "_by_dimension.png")), p_dim,
           width = 15, height = 8, dpi = 200)
  }

  # --- First-order dimensions ---
  if (!is.null(dim_data) && nrow(dim_data) > 0) {
    fo_data <- dim_data %>%
      filter(as.character(tom_dimension) %in% FIRST_ORDER_DIMS)
    if (nrow(fo_data) > 0) {
      cat("  ", method_label, title_tag, "first-order dimensions...\n")
      fo_shapes <- DIMENSION_SHAPES[names(DIMENSION_SHAPES) %in% FIRST_ORDER_DIMS]
      p_fo <- ggplot(fo_data, aes(x = release_date, y = .data[[age_col]],
                                   color = tier, shape = tom_dimension)) +
        ref_line +
        geom_point(size = 2.5, alpha = 0.7) +
        geom_smooth(aes(group = tier, color = tier),
                    method = "loess", se = FALSE, linewidth = 0.7, alpha = 0.6) +
        scale_color_manual(values = TYPE_COLORS, name = "Tier") +
        scale_shape_manual(values = fo_shapes, name = "Dimension") +
        scale_x_date(date_labels = "%b %Y", date_breaks = "6 months") +
        labs(
          title = paste0(method_label, " Age", title_tag, ": First-Order Reasoning"),
          subtitle = sub_fo,
          x = "Release Date", y = y_lab
        ) +
        theme_devtom(base_size = 10) +
        theme(
          axis.text.x = element_text(angle = 30, hjust = 1),
          legend.text = element_text(size = 8),
          legend.key.size = unit(0.45, "cm")
        ) +
        guides(
          color = guide_legend(ncol = 2, override.aes = list(size = 2.5)),
          shape = guide_legend(ncol = 1, override.aes = list(size = 2.5))
        )

      ggsave(file.path(fig_dir, paste0(file_prefix, "_first_order.png")), p_fo,
             width = 14, height = 7, dpi = 200)
    }
  }

  # --- Higher-order dimensions ---
  if (!is.null(dim_data) && nrow(dim_data) > 0) {
    ho_data <- dim_data %>%
      filter(as.character(tom_dimension) %in% HIGHER_ORDER_DIMS)
    if (nrow(ho_data) > 0) {
      cat("  ", method_label, title_tag, "higher-order dimensions...\n")
      ho_shapes <- DIMENSION_SHAPES[names(DIMENSION_SHAPES) %in% HIGHER_ORDER_DIMS]
      p_ho <- ggplot(ho_data, aes(x = release_date, y = .data[[age_col]],
                                   color = tier, shape = tom_dimension)) +
        ref_line +
        geom_point(size = 2.5, alpha = 0.7) +
        geom_smooth(aes(group = tier, color = tier),
                    method = "loess", se = FALSE, linewidth = 0.7, alpha = 0.6) +
        scale_color_manual(values = TYPE_COLORS, name = "Tier") +
        scale_shape_manual(values = ho_shapes, name = "Dimension") +
        scale_x_date(date_labels = "%b %Y", date_breaks = "6 months") +
        labs(
          title = paste0(method_label, " Age", title_tag, ": Higher-Order Reasoning"),
          subtitle = sub_ho,
          x = "Release Date", y = y_lab
        ) +
        theme_devtom(base_size = 10) +
        theme(
          axis.text.x = element_text(angle = 30, hjust = 1),
          legend.text = element_text(size = 8),
          legend.key.size = unit(0.45, "cm")
        ) +
        guides(
          color = guide_legend(ncol = 2, override.aes = list(size = 2.5)),
          shape = guide_legend(ncol = 1, override.aes = list(size = 2.5))
        )

      ggsave(file.path(fig_dir, paste0(file_prefix, "_higher_order.png")), p_ho,
             width = 14, height = 7, dpi = 200)
    }
  }

  # --- By construct ---
  if (!is.null(con_data) && nrow(con_data) > 0) {
    cat("  ", method_label, title_tag, "by construct...\n")
    p_con <- ggplot(con_data, aes(x = release_date, y = .data[[age_col]],
                                   color = tier, shape = tom_construct)) +
      ref_line +
      geom_point(size = 3, alpha = 0.75) +
      geom_smooth(aes(group = tier, color = tier),
                  method = "loess", se = FALSE, linewidth = 0.7, alpha = 0.6) +
      scale_color_manual(values = TYPE_COLORS, name = "Tier") +
      scale_shape_manual(values = CONSTRUCT_SHAPES, name = "Construct") +
      scale_x_date(date_labels = "%b %Y", date_breaks = "6 months") +
      labs(
        title = paste0(method_label, " Age", title_tag, " by Construct Over Time"),
        subtitle = sub_con,
        x = "Release Date", y = y_lab
      ) +
      theme_devtom(base_size = 11) +
      theme(axis.text.x = element_text(angle = 30, hjust = 1)) +
      guides(
        color = guide_legend(ncol = 2, override.aes = list(size = 3)),
        shape = guide_legend(override.aes = list(size = 3))
      )

    ggsave(file.path(fig_dir, paste0(file_prefix, "_by_construct.png")), p_con,
           width = 14, height = 7, dpi = 200)
  }
}

# =========================================================================
# Compute target ages from item data (mean age_mid per dimension/construct)
# =========================================================================
target_dim <- df %>%
  group_by(tom_dimension) %>%
  summarise(target_age = mean(age_mid, na.rm = TRUE), .groups = "drop")

target_con <- df %>%
  mutate(tom_construct = DIM_TO_CONSTRUCT[tom_dimension]) %>%
  group_by(tom_construct) %>%
  summarise(target_age = mean(age_mid, na.rm = TRUE), .groups = "drop")

target_ovr <- mean(df$age_mid, na.rm = TRUE)

cat("Target ages (mean item age_mid):\n")
cat("  Overall:", round(target_ovr, 2), "\n")
cat("  By dimension:\n")
print(target_dim, n = 12)
cat("  By construct:\n")
print(target_con, n = 6)

# Helper: join targets and compute deviation column
add_dev_dim <- function(data, age_col) {
  data %>%
    left_join(target_dim, by = c("tom_dimension")) %>%
    mutate(age_dev = .data[[age_col]] - target_age)
}
add_dev_con <- function(data, age_col) {
  data %>%
    left_join(target_con, by = c("tom_construct")) %>%
    mutate(age_dev = .data[[age_col]] - target_age)
}
add_dev_ovr <- function(data, age_col) {
  data %>%
    mutate(age_dev = .data[[age_col]] - target_ovr)
}

# =========================================================================
# 1. MASTERY
# =========================================================================
cat("=== Mastery-Based ===\n")

mastery_dim <- read_csv(file.path(model_dir, "mastery_age_dimension.csv"),
                        show_col_types = FALSE) %>%
  filter(task_filter == "all") %>%
  mutate(mastery_age = as.numeric(mastery_age)) %>%
  filter(!is.na(mastery_age)) %>%
  left_join(models_meta, by = "model") %>%
  filter(!is.na(release_date)) %>%
  mutate(tom_dimension = factor_dimension(tom_dimension),
         family = factor_family(family)) %>%
  add_dev_dim("mastery_age")

mastery_con <- read_csv(file.path(model_dir, "mastery_age_construct.csv"),
                        show_col_types = FALSE) %>%
  filter(task_filter == "all") %>%
  mutate(mastery_age = as.numeric(mastery_age)) %>%
  filter(!is.na(mastery_age)) %>%
  left_join(models_meta, by = "model") %>%
  filter(!is.na(release_date)) %>%
  mutate(tom_construct = factor_construct(tom_construct),
         family = factor_family(family)) %>%
  add_dev_con("mastery_age")

mastery_ovr <- read_csv(file.path(model_dir, "mastery_age_overall.csv"),
                        show_col_types = FALSE) %>%
  filter(task_filter == "all") %>%
  mutate(mastery_age = as.numeric(mastery_age)) %>%
  filter(!is.na(mastery_age)) %>%
  left_join(models_meta, by = "model") %>%
  filter(!is.na(release_date)) %>%
  mutate(family = factor_family(family)) %>%
  add_dev_ovr("mastery_age")

make_trio(mastery_dim, mastery_con, mastery_ovr,
          "mastery_age", "Mastery", "mastery_progression", mode = "absolute")
make_trio(mastery_dim, mastery_con, mastery_ovr,
          "age_dev", "Mastery", "mastery_dev_progression", mode = "deviation")

# =========================================================================
# 2. GLM
# =========================================================================
cat("\n=== Per-Model GLM ===\n")

glm_raw <- read_csv(file.path(model_dir, "glm_per_model_age.csv"),
                     show_col_types = FALSE) %>%
  left_join(models_meta, by = "model") %>%
  filter(!is.na(release_date)) %>%
  mutate(family = factor_family(family))

glm_dim <- glm_raw %>%
  filter(scope == "dimension",
         fit_flag == "positive_slope",
         is.finite(age_eq_50),
         age_eq_50 > 0, age_eq_50 < 15) %>%
  rename(tom_dimension = scope_name) %>%
  mutate(age_eq_50 = pmin(pmax(age_eq_50, 2.5), 11.0),
         tom_dimension = factor_dimension(tom_dimension)) %>%
  add_dev_dim("age_eq_50")

glm_con <- glm_raw %>%
  filter(scope == "construct",
         fit_flag == "positive_slope",
         is.finite(age_eq_50),
         age_eq_50 > 0, age_eq_50 < 15) %>%
  rename(tom_construct = scope_name) %>%
  mutate(age_eq_50 = pmin(pmax(age_eq_50, 2.5), 11.0),
         tom_construct = factor_construct(tom_construct)) %>%
  add_dev_con("age_eq_50")

glm_ovr <- glm_raw %>%
  filter(scope == "overall",
         fit_flag == "positive_slope",
         is.finite(age_eq_50),
         age_eq_50 > 0, age_eq_50 < 15) %>%
  mutate(age_eq_50 = pmin(pmax(age_eq_50, 2.5), 11.0)) %>%
  add_dev_ovr("age_eq_50")

make_trio(glm_dim, glm_con, glm_ovr,
          "age_eq_50", "GLM", "glm_progression", mode = "absolute")
make_trio(glm_dim, glm_con, glm_ovr,
          "age_dev", "GLM", "glm_dev_progression", mode = "deviation")

# =========================================================================
# 3. GLMM
# =========================================================================
cat("\n=== Cross-Model GLMM ===\n")

glmm_raw <- read_csv(file.path(model_dir, "glmm_age_equivalents.csv"),
                      show_col_types = FALSE) %>%
  left_join(models_meta, by = "model") %>%
  filter(!is.na(release_date),
         is.finite(age_eq_50)) %>%
  mutate(age_eq_50 = pmin(pmax(age_eq_50, 2.5), 11.0),
         family = factor_family(family))

glmm_dim <- glmm_raw %>%
  filter(scope %in% DIMENSION_DEVELOPMENTAL_ORDER) %>%
  rename(tom_dimension = scope) %>%
  mutate(tom_dimension = factor_dimension(tom_dimension)) %>%
  add_dev_dim("age_eq_50")

glmm_con <- glmm_raw %>%
  filter(scope %in% CONSTRUCT_DEVELOPMENTAL_ORDER) %>%
  rename(tom_construct = scope) %>%
  mutate(tom_construct = factor_construct(tom_construct)) %>%
  add_dev_con("age_eq_50")

glmm_ovr <- glmm_raw %>%
  filter(scope == "overall") %>%
  add_dev_ovr("age_eq_50")

make_trio(glmm_dim, glmm_con, glmm_ovr,
          "age_eq_50", "GLMM", "glmm_progression", mode = "absolute")
make_trio(glmm_dim, glmm_con, glmm_ovr,
          "age_dev", "GLMM", "glmm_dev_progression", mode = "deviation")

# =========================================================================
# 4. IRT
# =========================================================================
cat("\n=== Per-Dimension Rasch IRT ===\n")

irt_raw <- read_csv(file.path(model_dir, "irt_age_equivalents.csv"),
                    show_col_types = FALSE) %>%
  left_join(models_meta, by = "model") %>%
  filter(!is.na(release_date),
         is.finite(irt_age_eq)) %>%
  mutate(irt_age_eq = pmin(pmax(irt_age_eq, 2.5), 11.0),
         family = factor_family(family))

irt_dim <- irt_raw %>%
  mutate(tom_dimension = factor_dimension(tom_dimension)) %>%
  add_dev_dim("irt_age_eq")

irt_con <- irt_raw %>%
  mutate(tom_construct = DIM_TO_CONSTRUCT[tom_dimension]) %>%
  group_by(model, tom_construct, family, release_date, short_name, tier) %>%
  summarise(irt_age_eq = mean(irt_age_eq, na.rm = TRUE), .groups = "drop") %>%
  filter(is.finite(irt_age_eq)) %>%
  mutate(tom_construct = factor_construct(tom_construct)) %>%
  add_dev_con("irt_age_eq")

irt_ovr <- irt_raw %>%
  group_by(model, family, release_date, short_name, tier) %>%
  summarise(irt_age_eq = mean(irt_age_eq, na.rm = TRUE), .groups = "drop") %>%
  filter(is.finite(irt_age_eq)) %>%
  add_dev_ovr("irt_age_eq")

make_trio(irt_dim, irt_con, irt_ovr,
          "irt_age_eq", "IRT", "irt_progression", mode = "absolute")
make_trio(irt_dim, irt_con, irt_ovr,
          "age_dev", "IRT", "irt_dev_progression", mode = "deviation")

# =========================================================================
# 5. FAMILY-FACETED dimension plots (absolute age, one per method)
# =========================================================================
cat("\n=== Family-Faceted Dimension Plots ===\n")

make_family_facet <- function(dim_data, age_col, method_label, file_prefix,
                              shared_xlim, shared_ylim,
                              mode = "absolute") {
  if (is.null(dim_data) || nrow(dim_data) == 0) return(invisible(NULL))
  is_dev <- (mode == "deviation")
  tag <- if (is_dev) " Deviation" else ""
  y_lab <- if (is_dev) paste0(method_label, " Age − Target Age (years)") else paste0(method_label, " Age (years)")
  ref_line <- if (is_dev) geom_hline(yintercept = 0, linetype = "dashed", color = "grey50", linewidth = 0.6) else NULL
  sub <- if (is_dev) "Same axes across all families; dashed = 0 (matches target)" else "Same axes across all families; LOESS per dimension"

  cat("  ", method_label, tag, "faceted by family...\n")

  p <- ggplot(dim_data, aes(x = release_date, y = .data[[age_col]],
                             color = tom_dimension, shape = tom_dimension)) +
    ref_line +
    geom_point(size = 2.5, alpha = 0.7) +
    geom_smooth(aes(group = tom_dimension),
                method = "loess", se = FALSE, linewidth = 0.6, alpha = 0.6) +
    facet_wrap(~ family, nrow = 1) +
    scale_color_manual(values = DIMENSION_COLORS, name = "Dimension") +
    scale_shape_manual(values = DIMENSION_SHAPES, name = "Dimension") +
    scale_x_date(date_labels = "%b\n%Y", date_breaks = "1 year",
                 limits = shared_xlim) +
    coord_cartesian(ylim = shared_ylim) +
    labs(
      title = paste0(method_label, " Age", tag, " by Dimension — Faceted by Family"),
      subtitle = sub,
      x = "Release Date", y = y_lab
    ) +
    theme_devtom(base_size = 10) +
    theme(
      axis.text.x = element_text(angle = 30, hjust = 1, size = 7),
      legend.text = element_text(size = 7),
      legend.key.size = unit(0.4, "cm"),
      strip.text = element_text(face = "bold", size = 11)
    ) +
    guides(
      color = guide_legend(ncol = 2, override.aes = list(size = 2.5)),
      shape = guide_legend(ncol = 2, override.aes = list(size = 2.5))
    )

  ggsave(file.path(fig_dir, paste0(file_prefix, "_by_dim_family.png")), p,
         width = 20, height = 7, dpi = 200)
}

all_dates <- c(mastery_dim$release_date, glm_dim$release_date,
               glmm_dim$release_date, irt_dim$release_date)
shared_xlim <- range(all_dates, na.rm = TRUE)
shared_ylim <- c(2.5, 11.0)

# Absolute family-faceted
make_family_facet(mastery_dim, "mastery_age", "Mastery", "mastery_progression",
                  shared_xlim, shared_ylim)
make_family_facet(glm_dim, "age_eq_50", "GLM", "glm_progression",
                  shared_xlim, shared_ylim)
make_family_facet(glmm_dim, "age_eq_50", "GLMM", "glmm_progression",
                  shared_xlim, shared_ylim)
make_family_facet(irt_dim, "irt_age_eq", "IRT", "irt_progression",
                  shared_xlim, shared_ylim)

# Deviation family-faceted
all_devs <- c(mastery_dim$age_dev, glm_dim$age_dev,
              glmm_dim$age_dev, irt_dim$age_dev)
shared_dev_ylim <- range(all_devs, na.rm = TRUE) * 1.05

make_family_facet(mastery_dim, "age_dev", "Mastery", "mastery_dev_progression",
                  shared_xlim, shared_dev_ylim, mode = "deviation")
make_family_facet(glm_dim, "age_dev", "GLM", "glm_dev_progression",
                  shared_xlim, shared_dev_ylim, mode = "deviation")
make_family_facet(glmm_dim, "age_dev", "GLMM", "glmm_dev_progression",
                  shared_xlim, shared_dev_ylim, mode = "deviation")
make_family_facet(irt_dim, "age_dev", "IRT", "irt_dev_progression",
                  shared_xlim, shared_dev_ylim, mode = "deviation")

cat("\n=== All progression figures ===\n")
list.files(fig_dir, pattern = "progression") %>% sort() %>% cat(sep = "\n")
cat("\nDone.\n")
