#!/usr/bin/env bash
# Shared helper: exports PROVIDER_PREFS_JSON, the compact no-training/ZDR
# provider-routing preferences that every eval call must pass to OpenRouter
# (see src/openrouter.py and docs/METHODS_non_training_openrouter.md). Sourced
# by the runner scripts so the policy lives in exactly one place (src/roster.py's
# sibling src/openrouter.py) rather than being copy-pasted per script.
#
# Usage (from a runner, after PROJECT_ROOT is set):
#   source "$PROJECT_ROOT/scripts/_provider_prefs.sh"
#   inspect eval "$task" --model "$m" -M provider="$PROVIDER_PREFS_JSON"

# Ask src/openrouter.py for the canonical JSON. Fall back to a hard-coded copy
# only if Python/import fails, so a runner never silently drops the privacy
# routing (fail loud instead if even the fallback is somehow wrong).
if PROVIDER_PREFS_JSON="$(cd "$PROJECT_ROOT" && python -m src.openrouter 2>/dev/null)" \
     && [[ -n "$PROVIDER_PREFS_JSON" ]]; then
  :
else
  echo "WARNING: could not import src.openrouter; using inline fallback provider prefs" >&2
  PROVIDER_PREFS_JSON='{"data_collection":"deny","zdr":true,"allow_fallbacks":true,"sort":"throughput","ignore":["Nebius"]}'
fi
export PROVIDER_PREFS_JSON
