"""Which models reject decoding overrides, and how to build safe GenerateConfigs.

Anthropic DEPRECATED temperature/top_p/top_k on Claude Opus 4.7 and later
(including 4.8), Sonnet 5, and Fable 5: any non-default value returns HTTP 400
("`temperature` is deprecated for this model"). A sweep that standardizes
decoding via temperature therefore hard-fails on those models unless the
override is omitted — they run at provider-default decoding and must be
analyzed as a separate uncontrolled-decoding stratum.

This module is the harness-side mirror of the `omit_sampling_params: true`
entries in devtom-selfhost/models/manifest-expanded.yaml, smoke-verified
2026-07-16 at the sweep's temperature=0.0 (see that repo's
scripts/0_misc/verify_expanded_manifest.py --smoke). Patterns are matched on a
normalized model string, so `anthropic/claude-opus-4-8` (Inspect direct),
`openrouter/anthropic/claude-opus-4.8` (OpenRouter route), and dated snapshot
ids all match. EXTEND the tuple when Anthropic ships new models — assume new
Claude models also reject sampling params until verified otherwise.

Used by:
  - src/scorer.py — the FR grader pins temperature=0 for deterministic verdicts;
    this keeps that safe if DEVTOM_GRADER_MODEL is ever pointed at a new Claude.
  - the shell runners (scripts/2a_runMCQ, 2b_runFR, 3_runAll) — an optional
    TEMPERATURE=<t> env var adds `--temperature` to every eval call EXCEPT for
    models flagged here, via the CLI below.

CLI:
    python -m src.decoding --omits <model>   # exit 0 if <model> must NOT receive
                                             # sampling params, 1 otherwise
"""
from __future__ import annotations

import sys
from typing import Any

# Normalized (lowercase, "." -> "-") substrings of model ids that reject
# sampling params. claude-sonnet-5 does NOT match claude-sonnet-4-5 etc.
NO_SAMPLING_PATTERNS: tuple[str, ...] = (
    "claude-opus-4-7",
    "claude-opus-4-8",
    "claude-sonnet-5",
    "claude-fable-5",
)


def omits_sampling_params(model: str) -> bool:
    """True if `model` rejects temperature/top_p/top_k (HTTP 400 on non-default)."""
    normalized = model.lower().replace(".", "-")
    return any(p in normalized for p in NO_SAMPLING_PATTERNS)


def generate_config(model: str, *, temperature: float | None = None, **kwargs: Any):
    """A GenerateConfig with `temperature` dropped for models that reject it.

    Everything else in kwargs (max_tokens, ...) passes through unchanged. Import
    of inspect_ai is deferred so the CLI works without it installed.
    """
    from inspect_ai.model import GenerateConfig

    if temperature is not None and not omits_sampling_params(model):
        kwargs["temperature"] = temperature
    return GenerateConfig(**kwargs)


def _main() -> int:
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "--omits":
        return 0 if omits_sampling_params(args[1]) else 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(_main())
