"""Single source of truth for the DevToM model roster.

This is the one place that defines *which* models are in the study panel,
what family and size-tier each belongs to, its verified public-release date,
and its trend-line color. Both the shell runners (scripts/2a_runMCQ,
scripts/2b_runFR, scripts/3_runAll — via `python -m src.roster --models <family>`),
the analysis scripts (scripts/0_misc/, scripts/4_statistics/), and the R
modeling pipeline (scripts/5_model/, scripts/6_visualize/) read from here, so
the roster can't drift between "what we ran" and "what we plotted."

## The research design this encodes

The study compares model families across releases, oldest to newest. The roster
covers both **closed frontier families** (Claude, GPT) evaluated via direct API
and **open-weight families** (Llama, Qwen, Mistral) evaluated via OpenRouter
or Mistral la Plateforme API — deliberately reaching **back in time to older
releases** so each family has a real multi-release history to trend.

- **family**  = the model lineage (Claude, GPT, Llama, Qwen, Mistral).
  Derived from the provider prefix (`anthropic` -> Claude, `openai` -> GPT,
  `meta-llama` -> Llama, `mistral`/`mistralai` -> Mistral, etc.).
- **type**    = size/architecture tier *within* a family (e.g. "Llama small",
  "Llama large", "Claude Opus", "GPT reasoning"). Orthogonal to family; each
  tier has its own release history worth trending on its own line. Collapsing
  tiers would hide whether a given tier improved release over release.

## Slugs + dates: verified and frozen (2026-07-14)

This panel was verified on 2026-07-14 and is frozen (see EXCLUDED below), so the
steps here are a RECORD of the procedure used — not a per-run checklist. Repeat
them only if you ever start a fresh, re-frozen study period. OpenRouter slugs get
renamed and older models get delisted; every `slug` is a best-effort OpenRouter
model id and every `date` is the upstream model's public-release date as known at
authoring time (2026-01 knowledge cutoff). The procedure:
  1. Check each slug resolves on https://openrouter.ai/models (a delisted model
     404s — drop it or find the current slug).
  2. Confirm the family actually has ZDR / no-training upstreams available
     (see src/openrouter.py); if not, that model fails closed and is skipped.
  3. Re-verify any date that matters for the trend regression.

## EXCLUDED entries (audit trail — see docs/privacy_config_checklist.md)

`ROSTER` holds only models that were live AND policy-routable at last check.
Models that failed that check are NOT deleted — they are parked in `EXCLUDED`
below with a reason and the verification date, so the record shows what the
study *intended* to include and exactly why each is absent from results. Two
reasons occur:
  - "delisted": the slug no longer resolves on OpenRouter at all (verified
    against https://openrouter.ai/api/v1/models). No route is possible.
  - "no-zdr": the model exists but no provider offers Zero Data Retention, so it
    fails closed under the no-training prefs (src/openrouter.py).
Last verified 2026-07-14 via `scripts/1_check-functionality/check_providers.py
--live --all`. NOTE: this excludes the deep-history anchors the design wanted
(Llama 2, Mistral 7B, original DeepSeek LLM, Gemma 1 — all delisted), which
shortens the Mistral and DeepSeek trend lines in particular.

The panel is FROZEN as of 2026-07-14 for reproducibility: `ROSTER` and
`EXCLUDED` are the fixed model set for this study. Re-running the check later is
for refreshing the audit record (has anything changed?), NOT for adding or
removing models mid-study — that would make "what we ran" a moving target.
"""
from __future__ import annotations

import argparse
import datetime
import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class ModelEntry:
    slug: str          # Model id WITHOUT the leading prefix (e.g. "meta-llama/llama-3.1-8b-instruct")
    family: str        # lineage label (Claude, GPT, Llama, Qwen, DeepSeek, Mistral, Gemma)
    type: str          # size/arch tier within the family (own trend line)
    date: tuple[int, int, int]  # (year, month, day) public release
    prefix: str = "openrouter"  # provider prefix: "openrouter", "anthropic", etc.

    @property
    def model(self) -> str:
        """Full Inspect model string, e.g. 'openrouter/meta-llama/llama-3.1-8b-instruct'
        or 'anthropic/claude-opus-4-6'."""
        return f"{self.prefix}/{self.slug}"


# Ordered oldest -> newest overall; grouped by family in the docs. Dates are the
# upstream model's public-release date (re-verify — see module docstring).
# Contains ONLY models verified live + policy-routable (see EXCLUDED below for
# those dropped, with reasons). Last verified 2026-07-14.
ROSTER: list[ModelEntry] = [
    # ---------------- Anthropic Claude (closed, direct API) ----------------
    ModelEntry("claude-haiku-4-5-20251001",  "Claude", "Claude Haiku",  (2025, 10, 1),  prefix="anthropic"),
    ModelEntry("claude-sonnet-4-5-20250929", "Claude", "Claude Sonnet", (2025, 9, 29),  prefix="anthropic"),
    ModelEntry("claude-sonnet-4-6",          "Claude", "Claude Sonnet", (2026, 1, 14),  prefix="anthropic"),
    ModelEntry("claude-sonnet-5",            "Claude", "Claude Sonnet", (2026, 6, 24),  prefix="anthropic"),
    ModelEntry("claude-opus-4-5-20251101",   "Claude", "Claude Opus",   (2025, 11, 1),  prefix="anthropic"),
    ModelEntry("claude-opus-4-6",            "Claude", "Claude Opus",   (2026, 3, 4),   prefix="anthropic"),
    ModelEntry("claude-opus-4-7",            "Claude", "Claude Opus",   (2026, 5, 22),  prefix="anthropic"),
    ModelEntry("claude-opus-4-8",            "Claude", "Claude Opus",   (2026, 7, 10),  prefix="anthropic"),
    ModelEntry("claude-fable-5",             "Claude", "Claude Fable",  (2026, 6, 24),  prefix="anthropic"),

    # ---------------- OpenAI GPT (closed, direct API) ----------------
    ModelEntry("gpt-4o-2024-08-06",  "GPT", "GPT standard",       (2024, 8, 6),  prefix="openai"),
    ModelEntry("gpt-4o-mini",        "GPT", "GPT mini",           (2024, 7, 18), prefix="openai"),
    ModelEntry("o1",                 "GPT", "GPT reasoning",      (2024, 12, 17), prefix="openai"),
    ModelEntry("o3-mini",            "GPT", "GPT reasoning mini", (2025, 1, 31), prefix="openai"),
    ModelEntry("o3",                 "GPT", "GPT reasoning",      (2025, 4, 16), prefix="openai"),
    ModelEntry("o4-mini",            "GPT", "GPT reasoning mini", (2025, 4, 16), prefix="openai"),

    # ---------------- Meta Llama ----------------
    # selfhost (local GPU via vLLM — delisted from OpenRouter)
    ModelEntry("meta-llama/llama-2-7b-chat",         "Llama", "Llama small",    (2023, 7, 18)),
    ModelEntry("meta-llama/llama-2-13b-chat",        "Llama", "Llama mid",      (2023, 7, 18)),
    ModelEntry("meta-llama/llama-2-70b-chat",        "Llama", "Llama large",    (2023, 7, 18)),
    ModelEntry("meta-llama/llama-3-8b-instruct",     "Llama", "Llama small",    (2024, 4, 18)),
    ModelEntry("meta-llama/llama-3-70b-instruct",    "Llama", "Llama large",    (2024, 4, 18)),
    # openrouter / API
    ModelEntry("meta-llama/llama-3.1-8b-instruct",   "Llama", "Llama small",    (2024, 7, 23)),
    ModelEntry("meta-llama/llama-3.1-70b-instruct",  "Llama", "Llama large",    (2024, 7, 23)),
    ModelEntry("meta-llama/llama-3.2-3b-instruct",   "Llama", "Llama small",    (2024, 9, 25)),
    ModelEntry("meta-llama/llama-3.3-70b-instruct",  "Llama", "Llama large",    (2024, 12, 6)),
    ModelEntry("meta-llama/llama-4-scout",           "Llama", "Llama frontier", (2025, 4, 5)),
    ModelEntry("meta-llama/llama-4-maverick",        "Llama", "Llama frontier", (2025, 4, 5)),

    # ---------------- Alibaba Qwen ----------------
    # selfhost (local GPU via vLLM — delisted from OpenRouter)
    ModelEntry("qwen/qwen-1.5-7b-chat",              "Qwen", "Qwen small", (2024, 2, 4)),
    ModelEntry("qwen/qwen-1.5-14b-chat",             "Qwen", "Qwen mid",   (2024, 2, 4)),
    ModelEntry("qwen/qwen-1.5-72b-chat",             "Qwen", "Qwen large", (2024, 2, 4)),
    ModelEntry("qwen/qwen-2-7b-instruct",            "Qwen", "Qwen small", (2024, 6, 6)),
    ModelEntry("qwen/qwen-2-72b-instruct",           "Qwen", "Qwen large", (2024, 6, 6)),
    # openrouter / API
    ModelEntry("qwen/qwen-2.5-7b-instruct",          "Qwen", "Qwen small", (2024, 9, 19)),
    ModelEntry("qwen/qwen-2.5-32b-instruct",         "Qwen", "Qwen mid",   (2024, 9, 19)),
    ModelEntry("qwen/qwen-2.5-72b-instruct",         "Qwen", "Qwen large", (2024, 9, 19)),
    ModelEntry("qwen/qwen3-8b",                      "Qwen", "Qwen small", (2025, 4, 29)),
    ModelEntry("qwen/qwen3-32b",                     "Qwen", "Qwen mid",   (2025, 4, 29)),
    ModelEntry("qwen/qwen3-235b-a22b",               "Qwen", "Qwen large", (2025, 4, 29)),
    ModelEntry("qwen/qwen3.5-9b",                    "Qwen", "Qwen small", (2026, 3, 2)),
    ModelEntry("qwen/qwen3.5-27b",                   "Qwen", "Qwen mid",   (2026, 2, 24)),
    ModelEntry("qwen/qwen3.5-397b-a17b",             "Qwen", "Qwen large", (2026, 2, 16)),
    ModelEntry("qwen/qwen3.6-27b",                   "Qwen", "Qwen mid",   (2026, 4, 22)),

    # ---------------- Mistral (via Mistral la Plateforme API) ----------------
    ModelEntry("ministral-8b-2410",           "Mistral", "Ministral",       (2024, 10, 16), prefix="mistral"),
    ModelEntry("mistral-small-2503",          "Mistral", "Mistral Small",   (2025, 3, 17),  prefix="mistral"),
    ModelEntry("mistral-medium-2505",         "Mistral", "Mistral Medium",  (2025, 5, 7),   prefix="mistral"),
    ModelEntry("mistral-medium-2508",         "Mistral", "Mistral Medium",  (2025, 8, 12),  prefix="mistral"),
    ModelEntry("mistral-large-2512",          "Mistral", "Mistral Large",   (2025, 12, 2),  prefix="mistral"),
    ModelEntry("ministral-3-8b-2512",         "Mistral", "Ministral",       (2025, 12, 2),  prefix="mistral"),
    ModelEntry("mistral-small-2603",          "Mistral", "Mistral Small",   (2026, 3, 16),  prefix="mistral"),
    ModelEntry("mistral-medium-3-5-26-04",    "Mistral", "Mistral Medium",  (2026, 4, 28),  prefix="mistral"),
    # selfhost (local GPU via vLLM — delisted from OpenRouter)
    ModelEntry("mistralai/mistral-7b-instruct",      "Mistral", "Mistral small", (2023, 9, 27)),
    ModelEntry("mistralai/mistral-7b-instruct-v0.2", "Mistral", "Mistral small", (2024, 1, 15)),
    ModelEntry("mistralai/mistral-7b-instruct-v0.3", "Mistral", "Mistral small", (2024, 5, 22)),
    ModelEntry("mistralai/mixtral-8x7b-instruct",    "Mistral", "Mistral MoE",   (2023, 12, 11)),

]

# Models the study intended to include but that were NOT routable at last check
# (2026-07-14). Kept for the audit trail — see the module docstring. Each tuple
# is (entry, reason) where reason is "delisted" (slug gone from OpenRouter) or
# "no-zdr" (exists but no Zero-Data-Retention provider). NOT used by the runners
# or the analysis script. The panel is frozen (see module docstring): these stay
# excluded for the duration of the study even if a slug later becomes routable.
EXCLUDED: list[tuple[ModelEntry, str]] = [
    # ---------------- OpenAI GPT ----------------
    (ModelEntry("o1-mini", "GPT", "GPT reasoning mini", (2024, 9, 12), prefix="openai"), "retired"),

    # ---------------- Meta Llama (moved to ROSTER via selfhost) ----------------
    (ModelEntry("meta-llama/llama-2-7b-chat",         "Llama", "Llama small",    (2023, 7, 18)),  "selfhost"),
    (ModelEntry("meta-llama/llama-2-13b-chat",        "Llama", "Llama mid",      (2023, 7, 18)),  "selfhost"),
    (ModelEntry("meta-llama/llama-2-70b-chat",        "Llama", "Llama large",    (2023, 7, 18)),  "selfhost"),
    (ModelEntry("meta-llama/llama-3-8b-instruct",     "Llama", "Llama small",    (2024, 4, 18)),  "selfhost"),
    (ModelEntry("meta-llama/llama-3-70b-instruct",    "Llama", "Llama large",    (2024, 4, 18)),  "selfhost"),
    (ModelEntry("meta-llama/llama-3.1-405b-instruct", "Llama", "Llama frontier", (2024, 7, 23)),  "delisted"),

    # ---------------- Alibaba Qwen (moved to ROSTER via selfhost) ----------------
    (ModelEntry("qwen/qwen-1.5-7b-chat",              "Qwen", "Qwen small", (2024, 2, 4)),  "selfhost"),
    (ModelEntry("qwen/qwen-1.5-14b-chat",             "Qwen", "Qwen mid",   (2024, 2, 4)),  "selfhost"),
    (ModelEntry("qwen/qwen-1.5-72b-chat",             "Qwen", "Qwen large", (2024, 2, 4)),  "selfhost"),
    (ModelEntry("qwen/qwen-2-7b-instruct",            "Qwen", "Qwen small", (2024, 6, 6)),  "selfhost"),
    (ModelEntry("qwen/qwen-2-72b-instruct",           "Qwen", "Qwen large", (2024, 6, 6)),  "selfhost"),
    # ---------------- DeepSeek ----------------
    (ModelEntry("deepseek/deepseek-chat",             "DeepSeek", "DeepSeek V", (2024, 12, 26)),  "insufficient-variability"),
    (ModelEntry("deepseek/deepseek-r1",               "DeepSeek", "DeepSeek R", (2025, 1, 20)),   "insufficient-variability"),
    (ModelEntry("deepseek/deepseek-chat-v3-0324",     "DeepSeek", "DeepSeek V", (2025, 3, 24)),   "insufficient-variability"),
    (ModelEntry("deepseek/deepseek-r1-0528",          "DeepSeek", "DeepSeek R", (2025, 5, 28)),   "insufficient-variability"),
    (ModelEntry("deepseek/deepseek-llm-7b-chat",      "DeepSeek", "DeepSeek V", (2023, 11, 29)),  "delisted"),
    (ModelEntry("deepseek/deepseek-llm-67b-chat",     "DeepSeek", "DeepSeek V", (2023, 11, 29)),  "delisted"),

    # ---------------- Mistral (OpenRouter — superseded by Mistral la Plateforme API) ----------------
    (ModelEntry("mistralai/mistral-small-24b-instruct-2501", "Mistral", "Mistral Small", (2025, 1, 30)), "superseded"),
    (ModelEntry("mistralai/mistral-small-3.2-24b-instruct",  "Mistral", "Mistral Small", (2025, 6, 20)), "superseded"),
    # ---------------- Mistral (historical — moved to ROSTER via selfhost) --------
    (ModelEntry("mistralai/mistral-7b-instruct",      "Mistral", "Mistral small", (2023, 9, 27)),  "selfhost"),
    (ModelEntry("mistralai/mistral-7b-instruct-v0.2", "Mistral", "Mistral small", (2024, 1, 15)),  "selfhost"),
    (ModelEntry("mistralai/mistral-7b-instruct-v0.3", "Mistral", "Mistral small", (2024, 5, 22)),  "selfhost"),
    (ModelEntry("mistralai/mixtral-8x7b-instruct",    "Mistral", "Mistral MoE",   (2023, 12, 11)), "selfhost"),
    (ModelEntry("mistralai/mistral-large",            "Mistral", "Mistral large", (2024, 2, 26)),  "no-zdr"),
    (ModelEntry("mistralai/mixtral-8x22b-instruct",   "Mistral", "Mistral MoE",   (2024, 4, 17)),  "no-zdr"),
    (ModelEntry("mistralai/mistral-large-2407",       "Mistral", "Mistral large", (2024, 7, 24)),  "no-zdr"),
    (ModelEntry("mistralai/mistral-large-2411",       "Mistral", "Mistral large", (2024, 11, 18)), "delisted"),

    # ---------------- Google Gemma (open weights) ----------------
    (ModelEntry("google/gemma-2-27b-it",  "Gemma", "Gemma large", (2024, 6, 27)),  "insufficient-variability"),
    (ModelEntry("google/gemma-3-4b-it",   "Gemma", "Gemma small", (2025, 3, 12)),  "insufficient-variability"),
    (ModelEntry("google/gemma-3-12b-it",  "Gemma", "Gemma mid",   (2025, 3, 12)),  "insufficient-variability"),
    (ModelEntry("google/gemma-3-27b-it",  "Gemma", "Gemma large", (2025, 3, 12)),  "insufficient-variability"),
    (ModelEntry("google/gemma-7b-it",     "Gemma", "Gemma large", (2024, 2, 21)),  "delisted"),
    (ModelEntry("google/gemma-2-9b-it",   "Gemma", "Gemma small", (2024, 6, 27)),  "delisted"),
]

FAMILY_ORDER: list[str] = ["Claude", "GPT", "Llama", "Qwen", "Mistral"]

# Provider/author segment -> family label. Used to recover the family from a
# raw model string like 'anthropic/claude-opus-4-6' or
# 'openrouter/meta-llama/llama-3-8b-instruct'.
AUTHOR_TO_FAMILY: dict[str, str] = {
    "anthropic": "Claude",
    "openai": "GPT",
    "meta-llama": "Llama",
    "qwen": "Qwen",
    "deepseek": "DeepSeek",
    "mistral": "Mistral",
    "mistralai": "Mistral",
    "google": "Gemma",
}

# Trend-line colors per size tier, hue-grouped by family so a chart reads as
# "reds = Claude, teals = GPT, blues = Llama, purples = Qwen, ..." at a glance.
TYPE_COLORS: dict[str, str] = {
    "Claude Haiku":        "#fc9272",
    "Claude Sonnet":       "#ef3b2c",
    "Claude Opus":         "#a50f15",
    "Claude Fable":        "#67000d",
    "GPT mini":            "#99d8c9",
    "GPT standard":        "#41ae76",
    "GPT reasoning mini":  "#238b45",
    "GPT reasoning":       "#00441b",
    "Llama small":         "#9ecae1",
    "Llama mid":           "#4292c6",
    "Llama large":         "#08519c",
    "Llama frontier":      "#08306b",
    "Qwen small":          "#bcbddc",
    "Qwen mid":            "#807dba",
    "Qwen large":          "#54278f",
    "DeepSeek V":          "#66c2a4",
    "DeepSeek R":          "#006d2c",
    "Ministral":           "#fcbba1",
    "Mistral Small":       "#fc9272",
    "Mistral Medium":      "#de2d26",
    "Mistral Large":       "#a50f15",
    "Mistral small":       "#fdae6b",
    "Mistral MoE":         "#f16913",
    "Mistral large":       "#a63603",
    "Gemma small":         "#fa9fb5",
    "Gemma mid":           "#dd3497",
    "Gemma large":         "#7a0177",
}

# One representative color per family, for charts that collapse the size tiers
# into a single line per family.
FAMILY_COLORS: dict[str, str] = {
    "Claude":   "#a50f15",
    "GPT":      "#238b45",
    "Llama":    "#08519c",
    "Qwen":     "#54278f",
    "DeepSeek": "#006d2c",
    "Mistral":  "#a63603",
    "Gemma":    "#7a0177",
}

# Size-tier display order within each family (small -> large), for stable legends.
TYPE_ORDER: list[str] = [
    "Claude Haiku", "Claude Sonnet", "Claude Opus", "Claude Fable",
    "GPT mini", "GPT standard", "GPT reasoning mini", "GPT reasoning",
    "Llama small", "Llama mid", "Llama large", "Llama frontier",
    "Qwen small", "Qwen mid", "Qwen large",
    "DeepSeek V", "DeepSeek R",
    "Ministral", "Mistral Small", "Mistral Medium", "Mistral Large",
    "Mistral small", "Mistral MoE", "Mistral large",
    "Gemma small", "Gemma mid", "Gemma large",
]


# ----- derived lookups (built once from ROSTER + EXCLUDED) -----
_BY_MODEL = {e.model: e for e in ROSTER}
_BY_MODEL.update({e.model: e for e, _ in EXCLUDED})
MODEL_TYPE: dict[str, str] = {m: e.type for m, e in _BY_MODEL.items()}
MODEL_RELEASE_DATE: dict[str, tuple[int, int, int]] = {m: e.date for m, e in _BY_MODEL.items()}

# HuggingFace model ids sometimes differ from OpenRouter slugs (especially Qwen
# dropping the dash: "qwen2.5-72b" vs "qwen-2.5-72b"). Map variant slugs to
# the canonical slug used in ROSTER/EXCLUDED so local-run logs resolve correctly.
_SLUG_ALIASES: dict[str, str] = {
    "qwen/qwen2.5-7b-instruct":  "qwen/qwen-2.5-7b-instruct",
    "qwen/qwen2.5-32b-instruct": "qwen/qwen-2.5-32b-instruct",
    "qwen/qwen2.5-72b-instruct": "qwen/qwen-2.5-72b-instruct",
    "qwen/qwen2-7b-instruct":    "qwen/qwen-2-7b-instruct",
    "qwen/qwen2-72b-instruct":   "qwen/qwen-2-72b-instruct",
    "qwen/qwen1.5-7b-chat":      "qwen/qwen-1.5-7b-chat",
    "qwen/qwen1.5-14b-chat":     "qwen/qwen-1.5-14b-chat",
    "qwen/qwen1.5-72b-chat":     "qwen/qwen-1.5-72b-chat",
}

# Chronological (oldest->newest) model list per family, matching the plotting
# order used by the analysis script.
FAMILY_CHRONOLOGICAL_ORDER: dict[str, list[str]] = {
    fam: [e.model for e in sorted((x for x in ROSTER if x.family == fam), key=lambda x: x.date)]
    for fam in FAMILY_ORDER
}


# Total parameter count (billions) per roster model, keyed by the slug's last
# segment. Total (not active) params — see size_covariate_regression.py for the
# MoE caveat (DeepSeek 671B total / ~37B active, Llama-4 MoE).
PARAMS_B: dict[str, float] = {
    "llama-2-7b-chat": 7, "llama-2-13b-chat": 13, "llama-2-70b-chat": 70,
    "llama-3-8b-instruct": 8, "llama-3-70b-instruct": 70,
    "llama-3.1-8b-instruct": 8, "llama-3.1-70b-instruct": 70,
    "llama-3.2-3b-instruct": 3, "llama-3.3-70b-instruct": 70,
    "llama-4-scout": 109, "llama-4-maverick": 400,
    "qwen-1.5-7b-chat": 7, "qwen-1.5-14b-chat": 14, "qwen-1.5-72b-chat": 72,
    "qwen-2-7b-instruct": 7, "qwen-2-72b-instruct": 72,
    "qwen-2.5-7b-instruct": 7, "qwen-2.5-32b-instruct": 32, "qwen-2.5-72b-instruct": 72,
    "qwen3-8b": 8, "qwen3-32b": 32, "qwen3-235b-a22b": 235,
    "qwen3.5-9b": 9, "qwen3.5-27b": 27, "qwen3.5-397b-a17b": 397, "qwen3.6-27b": 27,
    "deepseek-chat": 671, "deepseek-r1": 671,
    "deepseek-chat-v3-0324": 671, "deepseek-r1-0528": 671,
    "mistral-7b-instruct": 7, "mistral-7b-instruct-v0.2": 7, "mistral-7b-instruct-v0.3": 7,
    "mixtral-8x7b-instruct": 47,
    "mistral-small-24b-instruct-2501": 24, "mistral-small-3.2-24b-instruct": 24,
    "ministral-8b-2410": 8, "mistral-small-2503": 24, "mistral-medium-2505": 73,
    "mistral-medium-2508": 73, "mistral-large-2512": 123,
    "ministral-3-8b-2512": 8, "mistral-small-2603": 24, "mistral-medium-3-5-26-04": 73,
    "gemma-2-27b-it": 27, "gemma-3-4b-it": 4,
    "gemma-3-12b-it": 12, "gemma-3-27b-it": 27,
    # --- Closed-source: estimated total params (widely cited, not official) ---
    # Claude — tier-based estimates: Haiku ~20B, Sonnet ~70B, Opus ~175B
    "claude-3-haiku": 20, "claude-haiku-4-5-20251001": 20,
    "claude-sonnet-4-5-20250929": 70, "claude-sonnet-4-6": 70, "claude-sonnet-5": 70,
    "claude-opus-4-5-20251101": 175, "claude-opus-4-6": 175,
    "claude-opus-4-7": 175, "claude-opus-4-8": 175, "claude-opus-4.1": 175,
    "claude-fable-5": 70,
    # GPT — per widely cited leak/estimate: GPT-4 ~1760B MoE total,
    # GPT-4o ~200B, GPT-4o-mini ~8B, o-series reasoning ~same base
    "gpt-3.5-turbo-0613": 20, "gpt-4-0613": 1760, "gpt-4": 1760,
    "gpt-4o-2024-08-06": 200, "gpt-4o-mini": 8, "gpt-4o-mini-2024-07-18": 8,
    "o1": 200, "o3-mini": 70, "o3": 200, "o4-mini": 70,
}


def model_family(model: str) -> str:
    """Family for a model string.

    'openrouter/meta-llama/llama-3.1-8b-instruct' -> 'Llama',
    'anthropic/claude-opus-4-6' -> 'Claude'. Strips leading router segments
    ('openrouter/' or 'openai-api/local/'), then maps the first segment via
    AUTHOR_TO_FAMILY. Unknown authors return the raw author string."""
    parts = model.split("/")
    if parts and parts[0] == "openrouter":
        parts = parts[1:]
    elif len(parts) >= 2 and parts[0] == "openai-api" and parts[1] == "local":
        parts = parts[2:]
    author = parts[0] if parts else model
    return AUTHOR_TO_FAMILY.get(author, author)


def _canonical_model(model: str) -> str:
    """Normalize a model string to the canonical form used as keys in _BY_MODEL.
    Handles 'openai-api/local/' prefix from selfhost GPU eval logs and slug
    aliases (e.g. HuggingFace 'qwen2.5' vs OpenRouter 'qwen-2.5')."""
    if model in _BY_MODEL:
        return model
    parts = model.split("/")
    if len(parts) >= 3 and parts[0] == "openai-api" and parts[1] == "local":
        slug = "/".join(parts[2:])
        candidate = "openrouter/" + slug
        if candidate in _BY_MODEL:
            return candidate
        aliased = _SLUG_ALIASES.get(slug)
        if aliased:
            candidate = "openrouter/" + aliased
            if candidate in _BY_MODEL:
                return candidate
    return model


def model_type(model: str) -> str:
    """Size/architecture tier label (e.g. 'Llama large', 'Qwen small'). Falls
    back to '<Family> other' for anything not in the roster."""
    canonical = _canonical_model(model)
    if canonical in MODEL_TYPE:
        return MODEL_TYPE[canonical]
    return f"{model_family(model)} other"


def model_release_date(model: str) -> datetime.date | None:
    """Real release date, or None if unmapped."""
    canonical = _canonical_model(model)
    ymd = MODEL_RELEASE_DATE.get(canonical)
    return datetime.date(*ymd) if ymd else None


def model_sort_key(model: str) -> tuple[int, int, str]:
    """(family rank, chronological rank within family, model) — unknown models
    sort last within their family."""
    family = model_family(model)
    family_rank = FAMILY_ORDER.index(family) if family in FAMILY_ORDER else len(FAMILY_ORDER)
    order = FAMILY_CHRONOLOGICAL_ORDER.get(family, [])
    canonical = _canonical_model(model)
    chrono_rank = order.index(canonical) if canonical in order else len(order)
    return (family_rank, chrono_rank, model)


def model_params_b(model: str) -> float | None:
    """Total parameters (billions) for a model string, or None if unmapped.

    Canonicalizes first so HuggingFace-style selfhost slugs (e.g.
    'openai-api/local/qwen/qwen2.5-7b-instruct') resolve to the same
    OpenRouter slug PARAMS_B is keyed by ('qwen-2.5-7b-instruct'); without
    this, six Qwen selfhost models silently returned None and dropped out of
    every size regression."""
    return PARAMS_B.get(_canonical_model(model).split("/")[-1])


def models_for_family(family: str) -> list[str]:
    """Full 'openrouter/...' model strings for one family, oldest -> newest."""
    return FAMILY_CHRONOLOGICAL_ORDER.get(family, [])


def all_models() -> list[str]:
    """Every model string in the roster, oldest -> newest overall."""
    return [e.model for e in sorted(ROSTER, key=lambda x: x.date)]


def excluded_models() -> list[tuple[str, str]]:
    """(model string, reason) for every entry parked in EXCLUDED, oldest first."""
    return [(e.model, reason) for e, reason in sorted(EXCLUDED, key=lambda t: t[0].date)]


def _main() -> int:
    ap = argparse.ArgumentParser(description="Print roster model strings (for shell runners).")
    ap.add_argument("--family", help="restrict to one family (Llama/Qwen/Mistral)")
    ap.add_argument("--list-families", action="store_true", help="print family names, one per line")
    ap.add_argument("--list-excluded", action="store_true",
                    help="print parked (unroutable) models as 'model\\treason', one per line")
    args = ap.parse_args()

    if args.list_excluded:
        print("\n".join(f"{m}\t{reason}" for m, reason in excluded_models()))
        return 0
    if args.list_families:
        print("\n".join(FAMILY_ORDER))
        return 0
    if args.family:
        if args.family not in FAMILY_ORDER:
            print(f"unknown family: {args.family}; known: {FAMILY_ORDER}", file=sys.stderr)
            return 1
        print("\n".join(models_for_family(args.family)))
        return 0
    print("\n".join(all_models()))
    return 0


if __name__ == "__main__":
    sys.exit(_main())
