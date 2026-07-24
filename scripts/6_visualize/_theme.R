# _theme.R — shared ggplot2 theme + color/ordering helpers for all viz scripts
#
# Source this file at the top of each 6_visualize script:
#   source(file.path(dirname(sys.frame(1)$ofile), "_theme.R"))
# Or if running from project root:
#   source("scripts/6_visualize/_theme.R")

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
})

# ---------------------------------------------------------------------------
# Color palettes (mirroring src/roster.py and src/constructs.py)
# ---------------------------------------------------------------------------
TYPE_COLORS <- c(
  "Claude Haiku"        = "#fc9272",
  "Claude Sonnet"       = "#ef3b2c",
  "Claude Opus"         = "#a50f15",
  "Claude Fable"        = "#67000d",
  "GPT mini"            = "#99d8c9",
  "GPT standard"        = "#41ae76",
  "GPT reasoning mini"  = "#238b45",
  "GPT reasoning"       = "#00441b",
  "Llama small"         = "#9ecae1",
  "Llama mid"           = "#4292c6",
  "Llama large"         = "#08519c",
  "Llama frontier"      = "#08306b",
  "Qwen small"          = "#bcbddc",
  "Qwen mid"            = "#807dba",
  "Qwen large"          = "#54278f",
  "DeepSeek V"          = "#66c2a4",
  "DeepSeek R"          = "#006d2c",
  "Mistral small"       = "#fdae6b",
  "Mistral MoE"         = "#f16913",
  "Mistral large"       = "#a63603",
  "Gemma small"         = "#fa9fb5",
  "Gemma mid"           = "#dd3497",
  "Gemma large"         = "#7a0177"
)

FAMILY_COLORS <- c(
  "Claude"   = "#a50f15",
  "GPT"      = "#238b45",
  "Llama"    = "#08519c",
  "Qwen"     = "#54278f",
  "DeepSeek" = "#006d2c",
  "Mistral"  = "#a63603",
  "Gemma"    = "#7a0177"
)

CONSTRUCT_COLORS <- c(
  "Desire / intention inference" = "#4C72B0",
  "Belief reasoning"             = "#DD8452",
  "Knowledge access"             = "#55A868",
  "Emotion recognition"          = "#C44E52",
  "Deception"                    = "#8172B3",
  "Pragmatic understanding"      = "#937860"
)

# ---------------------------------------------------------------------------
# Ordering helpers
# ---------------------------------------------------------------------------
# Trajectory-eligible families only. Claude and GPT excluded (reason:
# no-trajectory — see devtom-selfhost/models/manifest_excluded.yaml).
FAMILY_ORDER <- c("Llama", "Qwen", "Mistral")

TYPE_ORDER <- c(
  "Llama small", "Llama mid", "Llama large", "Llama frontier",
  "Qwen small", "Qwen mid", "Qwen large",
  "Mistral small", "Mistral MoE", "Mistral large"
)

DIMENSION_DEVELOPMENTAL_ORDER <- c(
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
  "Faux Pas Detection",
  "Irony"
)

CONSTRUCT_DEVELOPMENTAL_ORDER <- c(
  "Desire / intention inference",
  "Belief reasoning",
  "Knowledge access",
  "Emotion recognition",
  "Deception",
  "Pragmatic understanding"
)

# ---------------------------------------------------------------------------
# ggplot2 theme
# ---------------------------------------------------------------------------
theme_devtom <- function(base_size = 11) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title = element_text(face = "bold", size = base_size + 2),
      plot.subtitle = element_text(color = "grey40", size = base_size),
      strip.text = element_text(face = "bold"),
      legend.position = "right",
      panel.grid.minor = element_blank(),
      plot.margin = margin(10, 10, 10, 10)
    )
}

# Convenience: short model name from full model string
short_model <- function(model) {
  # Strip provider prefixes: openrouter/author/, anthropic/, openai/, openai-api/local/author/
  model <- sub("^openrouter/[^/]+/", "", model)
  model <- sub("^anthropic/", "", model)
  model <- sub("^openai/", "", model)
  model <- sub("^openai-api/local/[^/]+/", "", model)
  model
}

# Factor a tier column in TYPE_ORDER
factor_tier <- function(x) {
  factor(x, levels = intersect(TYPE_ORDER, unique(x)))
}

# Factor a family column in FAMILY_ORDER
factor_family <- function(x) {
  factor(x, levels = intersect(FAMILY_ORDER, unique(x)))
}

# Factor a dimension column in developmental order
factor_dimension <- function(x) {
  factor(x, levels = intersect(DIMENSION_DEVELOPMENTAL_ORDER, unique(x)))
}

# Factor a construct column in developmental order
factor_construct <- function(x) {
  factor(x, levels = intersect(CONSTRUCT_DEVELOPMENTAL_ORDER, unique(x)))
}
