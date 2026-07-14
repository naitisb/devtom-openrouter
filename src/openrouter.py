"""OpenRouter routing + privacy configuration for DevToM-OpenRouter.

This module centralizes the request-level controls described in
docs/METHODS_non_training_openrouter.md so that *every* eval call in this
project routes only to upstream providers that (a) support zero data
retention and (b) do not train on submitted inputs/outputs. It is the code
half of the two-layer control described in the methods note — the other
half is the workspace-level configuration you set once in the OpenRouter
dashboard (private logging off, workspace ZDR on, provider data collection
denied); see docs/METHODS_non_training_openrouter.md and
docs/privacy_config_checklist.md.

## How Inspect forwards these

Inspect's OpenRouter provider (inspect_ai.model._providers.openrouter) accepts
a `provider` model-arg (a dict) and forwards it verbatim into the request
body's `extra_body["provider"]`, which is exactly OpenRouter's provider-routing
preferences object. So passing

    provider={"data_collection": "deny", "zdr": true}

on the model is what actually restricts routing at request time. We build that
dict here rather than hand-writing it at each call site, so the policy is
defined in one place and can't drift between scripts.

Two ways to apply it:

1. CLI (shell scripts): expand `openrouter_provider_cli_args` into the
   `inspect eval ... -M provider='{...}'` flag. This is what
   scripts/2a_runMCQ, scripts/2b_runFR and scripts/3_runAll do.

2. In-process (get_model): pass `**openrouter_model_args()` to
   `inspect_ai.model.get_model(...)`. Used by the free-response grader and the
   connectivity check.

## What the routing dict means (OpenRouter semantics)

- data_collection="deny": exclude any upstream provider that may store/train on
  prompts. This is the no-training control.
- zdr=True: only route to providers that OpenRouter flags as zero-data-retention.
- allow_fallbacks=True: still allow OpenRouter to fall back to *another*
  policy-compliant provider if the first is down (the deny/zdr filters are
  applied first, so a fallback is still compliant) — set False for maximum
  reproducibility (pin to a single upstream, fail rather than reroute).
- sort="throughput": deterministic-ish provider ordering among the compliant
  set; swap to "price" or drop it depending on what you're optimizing.
- ignore=[...]: drop named providers from the candidate set even if compliant —
  used to exclude a provider that is ZDR-compliant but incompatible with our
  request shape (Nebius 422s on the `seed` param Inspect sends). See the dict.

None of these can *make* a non-compliant provider compliant — they only filter
the candidate set. A model with no ZDR/no-train upstream at all will simply
return no route (a 404-style error), which is the desired fail-closed behavior:
better to skip a model than to silently send data somewhere that trains on it.
"""
from __future__ import annotations

import json
from typing import Any

# The single source of truth for this project's routing policy. Edit here to
# change the policy everywhere (scripts + in-process calls) at once.
NON_TRAINING_PROVIDER_PREFS: dict[str, Any] = {
    "data_collection": "deny",  # no upstream that stores/trains on prompts
    "zdr": True,                # zero-data-retention providers only
    "allow_fallbacks": True,    # fall back only *within* the compliant set
    "sort": "throughput",       # stable-ish ordering among compliant providers
    # Exclude specific compliant providers by name. Nebius is ZDR-compliant but
    # rejects the `seed` parameter Inspect sends (HTTP 422 "seed: Extra inputs
    # are not permitted"), which aborts a run when OpenRouter falls back to it
    # (observed on the Nemotron grader under load, 2026-07-14). Excluding it here
    # applies to every call — subjects and grader alike — so no request can be
    # routed to a provider that 422s on our request shape. Re-evaluate if Nebius
    # fixes its schema or if it becomes some model's only compliant route.
    "ignore": ["Nebius"],
}


def openrouter_provider_prefs() -> dict[str, Any]:
    """Return a fresh copy of the no-training / ZDR provider-routing prefs."""
    return dict(NON_TRAINING_PROVIDER_PREFS)


def openrouter_model_args() -> dict[str, Any]:
    """Model-args to splat into inspect_ai.model.get_model(model, **kwargs).

    Example:
        from inspect_ai.model import get_model
        grader = get_model("openrouter/qwen/qwen-2.5-72b-instruct",
                           **openrouter_model_args())
    """
    return {"provider": openrouter_provider_prefs()}


def openrouter_provider_cli_arg() -> str:
    """The value for `inspect eval -M provider='<value>'` (compact JSON).

    Shell scripts build the flag as:
        -M provider="$(python -c 'from src.openrouter import ...')"
    or, more simply, hard-code the same JSON — but importing keeps the policy
    in one place. See scripts/_provider_prefs.sh for how the shells consume it.
    """
    return json.dumps(NON_TRAINING_PROVIDER_PREFS, separators=(",", ":"))


if __name__ == "__main__":
    # `python -m src.openrouter` prints the compact JSON so shell scripts can
    # capture it: PROVIDER_PREFS="$(python -m src.openrouter)"
    print(openrouter_provider_cli_arg())
