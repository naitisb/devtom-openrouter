"""Single source of truth for the DevToM-OpenRouter open-weight model roster.

This is the one place that defines *which* open models are in the study panel,
what family and size-tier each belongs to, its verified public-release date,
and its trend-line color. Both the shell runners (scripts/2a_runMCQ,
scripts/2b_runFR, scripts/3_runAll — via `python -m src.roster --models <family>`) and the
analysis script (scripts/4_analyze/summarize_visualize_results.py — via direct
import) read from here, so the roster can't drift between "what we ran" and
"what we plotted." This differs deliberately from the sibling devtom-eval
project, which hard-codes the roster separately in its shells and its analysis
script.

## The research design this encodes

The parent devtom-eval project compares *closed* frontier families (Anthropic,
OpenAI) within themselves, oldest to newest. This project does the same
"developmental trajectory" analysis for **open-weight** families served through
OpenRouter — deliberately reaching **back in time to older releases** (Llama 2,
Mistral 7B, the original DeepSeek LLM, Gemma 1) so each family has a real
multi-year history to trend, not just its two latest checkpoints.

- **family**  = the open-weight lineage (Llama, Qwen, DeepSeek, Mistral, Gemma).
  Analogous to "provider family" in devtom-eval. Derived from the OpenRouter
  author segment (`meta-llama` -> Llama, etc.).
- **type**    = size/architecture tier *within* a family (e.g. "Llama small",
  "Llama large", "Mistral MoE"). Orthogonal to family; each tier has its own
  release history worth trending on its own line, exactly like "Claude Opus"
  vs "Claude Sonnet" in devtom-eval. Collapsing tiers would hide whether a
  given tier improved release over release.

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
import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class ModelEntry:
    slug: str          # OpenRouter model id WITHOUT the leading "openrouter/"
    family: str        # lineage label (Llama, Qwen, DeepSeek, Mistral, Gemma)
    type: str          # size/arch tier within the family (own trend line)
    date: tuple[int, int, int]  # (year, month, day) public release

    @property
    def model(self) -> str:
        """Full Inspect model string, e.g. 'openrouter/meta-llama/llama-3.1-8b-instruct'."""
        return f"openrouter/{self.slug}"


# Ordered oldest -> newest overall; grouped by family in the docs. Dates are the
# upstream model's public-release date (re-verify — see module docstring).
# Contains ONLY models verified live + policy-routable (see EXCLUDED below for
# those dropped, with reasons). Last verified 2026-07-14.
ROSTER: list[ModelEntry] = [
    # ---------------- Meta Llama ----------------
    ModelEntry("meta-llama/llama-3.1-8b-instruct",   "Llama", "Llama small",    (2024, 7, 23)),
    ModelEntry("meta-llama/llama-3.1-70b-instruct",  "Llama", "Llama large",    (2024, 7, 23)),
    ModelEntry("meta-llama/llama-3.2-3b-instruct",   "Llama", "Llama small",    (2024, 9, 25)),
    ModelEntry("meta-llama/llama-3.3-70b-instruct",  "Llama", "Llama large",    (2024, 12, 6)),
    ModelEntry("meta-llama/llama-4-scout",           "Llama", "Llama frontier", (2025, 4, 5)),
    ModelEntry("meta-llama/llama-4-maverick",        "Llama", "Llama frontier", (2025, 4, 5)),

    # ---------------- Alibaba Qwen ----------------
    ModelEntry("qwen/qwen-2.5-7b-instruct",          "Qwen", "Qwen small", (2024, 9, 19)),
    ModelEntry("qwen/qwen-2.5-72b-instruct",         "Qwen", "Qwen large", (2024, 9, 19)),
    ModelEntry("qwen/qwen3-32b",                     "Qwen", "Qwen mid",   (2025, 4, 29)),

    # ---------------- DeepSeek ----------------
    ModelEntry("deepseek/deepseek-chat",             "DeepSeek", "DeepSeek V", (2024, 12, 26)),  # V3
    ModelEntry("deepseek/deepseek-r1",               "DeepSeek", "DeepSeek R", (2025, 1, 20)),
    ModelEntry("deepseek/deepseek-chat-v3-0324",     "DeepSeek", "DeepSeek V", (2025, 3, 24)),
    ModelEntry("deepseek/deepseek-r1-0528",          "DeepSeek", "DeepSeek R", (2025, 5, 28)),

    # ---------------- Mistral ----------------
    ModelEntry("mistralai/mistral-small-24b-instruct-2501", "Mistral", "Mistral small", (2025, 1, 30)),
    ModelEntry("mistralai/mistral-small-3.2-24b-instruct",  "Mistral", "Mistral small", (2025, 6, 20)),

    # ---------------- Google Gemma (open weights) ----------------
    ModelEntry("google/gemma-2-27b-it",  "Gemma", "Gemma large", (2024, 6, 27)),
    ModelEntry("google/gemma-3-4b-it",   "Gemma", "Gemma small", (2025, 3, 12)),
    ModelEntry("google/gemma-3-12b-it",  "Gemma", "Gemma mid",   (2025, 3, 12)),
    ModelEntry("google/gemma-3-27b-it",  "Gemma", "Gemma large", (2025, 3, 12)),
]

# Models the study intended to include but that were NOT routable at last check
# (2026-07-14). Kept for the audit trail — see the module docstring. Each tuple
# is (entry, reason) where reason is "delisted" (slug gone from OpenRouter) or
# "no-zdr" (exists but no Zero-Data-Retention provider). NOT used by the runners
# or the analysis script. The panel is frozen (see module docstring): these stay
# excluded for the duration of the study even if a slug later becomes routable.
EXCLUDED: list[tuple[ModelEntry, str]] = [
    # ---------------- Meta Llama ----------------
    (ModelEntry("meta-llama/llama-2-70b-chat",        "Llama", "Llama large",    (2023, 7, 18)),  "delisted"),
    (ModelEntry("meta-llama/llama-3-8b-instruct",     "Llama", "Llama small",    (2024, 4, 18)),  "delisted"),
    (ModelEntry("meta-llama/llama-3-70b-instruct",    "Llama", "Llama large",    (2024, 4, 18)),  "delisted"),
    (ModelEntry("meta-llama/llama-3.1-405b-instruct", "Llama", "Llama frontier", (2024, 7, 23)),  "delisted"),

    # ---------------- Alibaba Qwen ----------------
    (ModelEntry("qwen/qwen-1.5-72b-chat",             "Qwen", "Qwen large", (2024, 2, 4)),  "delisted"),
    (ModelEntry("qwen/qwen-2-7b-instruct",            "Qwen", "Qwen small", (2024, 6, 6)),  "delisted"),
    (ModelEntry("qwen/qwen-2-72b-instruct",           "Qwen", "Qwen large", (2024, 6, 6)),  "delisted"),
    (ModelEntry("qwen/qwen3-8b",                      "Qwen", "Qwen small", (2025, 4, 29)), "no-zdr"),
    (ModelEntry("qwen/qwen3-235b-a22b",               "Qwen", "Qwen large", (2025, 4, 29)), "no-zdr"),

    # ---------------- DeepSeek ----------------
    (ModelEntry("deepseek/deepseek-llm-67b-chat",     "DeepSeek", "DeepSeek V", (2023, 11, 29)),  "delisted"),

    # ---------------- Mistral ----------------
    (ModelEntry("mistralai/mistral-7b-instruct",      "Mistral", "Mistral small", (2023, 9, 27)),  "delisted"),
    (ModelEntry("mistralai/mixtral-8x7b-instruct",    "Mistral", "Mistral MoE",   (2023, 12, 11)), "delisted"),
    (ModelEntry("mistralai/mistral-large",            "Mistral", "Mistral large", (2024, 2, 26)),  "no-zdr"),
    (ModelEntry("mistralai/mixtral-8x22b-instruct",   "Mistral", "Mistral MoE",   (2024, 4, 17)),  "no-zdr"),
    (ModelEntry("mistralai/mistral-large-2407",       "Mistral", "Mistral large", (2024, 7, 24)),  "no-zdr"),
    (ModelEntry("mistralai/mistral-large-2411",       "Mistral", "Mistral large", (2024, 11, 18)), "delisted"),

    # ---------------- Google Gemma (open weights) ----------------
    (ModelEntry("google/gemma-7b-it",     "Gemma", "Gemma large", (2024, 2, 21)),  "delisted"),
    (ModelEntry("google/gemma-2-9b-it",   "Gemma", "Gemma small", (2024, 6, 27)),  "delisted"),
]

# Family display order (oldest-founded lineage first-ish; mostly stable grouping).
FAMILY_ORDER: list[str] = ["Llama", "Qwen", "DeepSeek", "Mistral", "Gemma"]

# OpenRouter author segment -> family label. Used to recover the family from a
# raw model string like 'openrouter/meta-llama/llama-3-8b-instruct'.
AUTHOR_TO_FAMILY: dict[str, str] = {
    "meta-llama": "Llama",
    "qwen": "Qwen",
    "deepseek": "DeepSeek",
    "mistralai": "Mistral",
    "google": "Gemma",
}

# Trend-line colors per size tier, hue-grouped by family so a chart reads as
# "blues = Llama, purples = Qwen, ..." at a glance.
TYPE_COLORS: dict[str, str] = {
    "Llama small":    "#9ecae1",
    "Llama mid":      "#4292c6",
    "Llama large":    "#08519c",
    "Llama frontier": "#08306b",
    "Qwen small":     "#bcbddc",
    "Qwen mid":       "#807dba",
    "Qwen large":     "#54278f",
    "DeepSeek V":     "#66c2a4",
    "DeepSeek R":     "#238b45",
    "Mistral small":  "#fdae6b",
    "Mistral MoE":    "#f16913",
    "Mistral large":  "#a63603",
    "Gemma small":    "#fa9fb5",
    "Gemma mid":      "#dd3497",
    "Gemma large":    "#7a0177",
}

# One representative color per family, for charts that collapse the size tiers
# into a single line per family. Each is the strong/large-tier shade of that
# family's TYPE_COLORS hue, so a family-collapsed chart reads with the same
# "blues = Llama, purples = Qwen, ..." mapping as the per-tier charts.
FAMILY_COLORS: dict[str, str] = {
    "Llama":    "#08519c",
    "Qwen":     "#54278f",
    "DeepSeek": "#238b45",
    "Mistral":  "#a63603",
    "Gemma":    "#7a0177",
}

# Size-tier display order within each family (small -> large), for stable legends.
TYPE_ORDER: list[str] = [
    "Llama small", "Llama mid", "Llama large", "Llama frontier",
    "Qwen small", "Qwen mid", "Qwen large",
    "DeepSeek V", "DeepSeek R",
    "Mistral small", "Mistral MoE", "Mistral large",
    "Gemma small", "Gemma mid", "Gemma large",
]


# ----- derived lookups (built once from ROSTER) -----
_BY_MODEL = {e.model: e for e in ROSTER}
MODEL_TYPE: dict[str, str] = {e.model: e.type for e in ROSTER}
MODEL_RELEASE_DATE: dict[str, tuple[int, int, int]] = {e.model: e.date for e in ROSTER}

# Chronological (oldest->newest) model list per family, matching the plotting
# order used by the analysis script.
FAMILY_CHRONOLOGICAL_ORDER: dict[str, list[str]] = {
    fam: [e.model for e in sorted((x for x in ROSTER if x.family == fam), key=lambda x: x.date)]
    for fam in FAMILY_ORDER
}


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
    ap.add_argument("--family", help="restrict to one family (Llama/Qwen/DeepSeek/Mistral/Gemma)")
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
