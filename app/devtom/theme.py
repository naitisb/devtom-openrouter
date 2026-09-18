"""Colors and the shared Plotly template.

Palettes are read from the frozen snapshot (`app/data/reference.json`), which
`prepare_data.py` pulls from `src/roster.py` and `src/constructs.py` — so the
app's colors cannot drift from the R figures'. Bundled fallbacks keep the app
renderable if the snapshot has not been built yet.
"""
from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

import plotly.graph_objects as go
import plotly.io as pio

DATA_DIR = Path(__file__).resolve().parent.parent / "data"

# --- Editorial palette ------------------------------------------------------
INK = "#1b1b1f"
BODY = "#3d3d46"
MUTED = "#73737f"
HAIRLINE = "#e2e2e8"
PAPER = "#ffffff"
WASH = "#f7f7f9"

# The normative developmental window, drawn behind every strip chart.
BAND_FILL = "rgba(120,120,134,0.13)"
BAND_LINE = "rgba(120,120,134,0.30)"

# Semantic accents, shared with the R scripts where they exist.
ACCENT = "#e76f51"        # the developmental ordering / the thing being argued for
TEAL = "#2a9d8f"          # mastered, retained, the winning model
AMBER = "#e9c46a"
SLATE = "#457b9d"
CRIMSON = "#b2182b"       # above target / over-performing
AZURE = "#2166ac"         # below target / under-performing

# Task palette, from visualize_accuracy_trajectory.R.
TASK_COLORS = {"MCQ": "#2171b5", "Free response": "#cb181d"}

# Guttman ordering comparison, from visualize_guttman_sequence.R.
ORDER_COLORS = {
    "developmental": ACCENT,
    "construct_grouped": SLATE,
    "empirical_best": TEAL,
    "reverse": "#8a8a96",
}

_FALLBACK_FAMILY_COLORS = {
    "Claude": "#a50f15",
    "GPT": "#238b45",
    "Llama": "#08519c",
    "Qwen": "#54278f",
    "Mistral": "#a63603",
    "DeepSeek": "#006d2c",
    "Gemma": "#7a0177",
}

_FALLBACK_CONSTRUCT_COLORS = {
    "Desire / intention inference": "#4C72B0",
    "Belief reasoning": "#DD8452",
    "Knowledge access": "#55A868",
    "Emotion recognition": "#C44E52",
    "Deception": "#8172B3",
    "Pragmatic understanding": "#937860",
}


@lru_cache(maxsize=1)
def reference() -> dict:
    """The frozen roster/construct constants, or bundled fallbacks."""
    path = DATA_DIR / "reference.json"
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {
        "family_order": ["Claude", "GPT", "Llama", "Qwen", "Mistral"],
        "family_colors": _FALLBACK_FAMILY_COLORS,
        "type_order": [],
        "type_colors": {},
        "construct_order": list(_FALLBACK_CONSTRUCT_COLORS),
        "construct_colors": _FALLBACK_CONSTRUCT_COLORS,
        "model_params_b": {},
        "model_release_date": {},
        "excluded_models": [],
    }


def family_colors() -> dict[str, str]:
    return dict(reference().get("family_colors") or _FALLBACK_FAMILY_COLORS)


def construct_colors() -> dict[str, str]:
    return dict(reference().get("construct_colors") or _FALLBACK_CONSTRUCT_COLORS)


def family_order() -> list[str]:
    return list(reference().get("family_order") or ["Claude", "GPT", "Llama", "Qwen", "Mistral"])


def tier_colors(tiers: list[str] | None = None) -> dict[str, str]:
    """Tier -> hex, with collisions resolved.

    `roster.py` gives `Mistral Small` and `Claude Haiku` the same hex (and
    `Mistral Large` / `Claude Opus` likewise). That is harmless when a figure is
    faceted by family, but wrong in a pooled legend. When two tiers from
    different families would collide, the later one is nudged.
    """
    palette = dict(reference().get("type_colors") or {})
    if tiers is None:
        return palette

    seen: dict[str, str] = {}
    out: dict[str, str] = {}
    for tier in tiers:
        color = palette.get(tier)
        if color is None:
            color = MUTED
        if color in seen and seen[color] != tier:
            color = _nudge(color)
        seen[color] = tier
        out[tier] = color
    return out


def _nudge(hex_color: str, amount: int = 38) -> str:
    """Lighten a hex color so a collided legend entry stays distinguishable."""
    hex_color = hex_color.lstrip("#")
    rgb = [int(hex_color[i : i + 2], 16) for i in (0, 2, 4)]
    rgb = [min(255, channel + amount) for channel in rgb]
    return "#{:02x}{:02x}{:02x}".format(*rgb)


def tier_order(present: list[str]) -> list[str]:
    """Order tiers the way the roster does, keeping any unknown ones last."""
    canonical = reference().get("type_order") or []
    index = {tier: i for i, tier in enumerate(canonical)}
    return sorted(present, key=lambda t: (index.get(t, len(index)), t))


def short_model(model: str) -> str:
    """Strip provider prefixes, mirroring `short_model()` in `_theme.R`."""
    for prefix in (
        "openai-api/local/",
        "openrouter/",
        "anthropic/",
        "openai/",
        "mistral/",
    ):
        if model.startswith(prefix):
            model = model[len(prefix) :]
    # What remains may still be `author/slug`.
    return model.split("/")[-1]


# --- Plotly template --------------------------------------------------------
DEVTOM_TEMPLATE = go.layout.Template(
    layout=go.Layout(
        font=dict(
            family="ui-sans-serif, -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif",
            size=13,
            color=BODY,
        ),
        title=dict(font=dict(size=16, color=INK), x=0, xanchor="left"),
        paper_bgcolor=PAPER,
        plot_bgcolor=PAPER,
        colorway=[
            "#a50f15", "#238b45", "#08519c", "#54278f",
            "#a63603", "#2a9d8f", "#e76f51", "#457b9d",
        ],
        xaxis=dict(
            gridcolor=HAIRLINE,
            zerolinecolor=HAIRLINE,
            linecolor=HAIRLINE,
            ticks="outside",
            ticklen=4,
            tickcolor=HAIRLINE,
            title=dict(font=dict(size=12, color=MUTED)),
            automargin=True,
        ),
        yaxis=dict(
            gridcolor=HAIRLINE,
            zerolinecolor=HAIRLINE,
            linecolor=HAIRLINE,
            ticks="outside",
            ticklen=4,
            tickcolor=HAIRLINE,
            title=dict(font=dict(size=12, color=MUTED)),
            automargin=True,
        ),
        legend=dict(
            bgcolor="rgba(0,0,0,0)",
            font=dict(size=11),
            title=dict(font=dict(size=11, color=MUTED)),
        ),
        margin=dict(l=10, r=10, t=44, b=10),
        hoverlabel=dict(
            bgcolor=PAPER,
            bordercolor=HAIRLINE,
            font=dict(size=12, color=INK),
        ),
    )
)

pio.templates["devtom"] = DEVTOM_TEMPLATE
pio.templates.default = "devtom"
