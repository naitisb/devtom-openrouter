#!/usr/bin/env bash
# DevToM-OpenRouter — run BOTH ToM tasks across every open-weight model in the
# roster, oldest to newest within each family, through OpenRouter.
#
# For each model it runs the tom_12dim_freeresponse task (open-ended, custom
# solver + model-graded scorer) and the tom_12dim_mcq task (multiple-choice/
# true-false) — in that order, since the two tasks mirror the same scenarios and
# free-response has no answer options to leak. Each `inspect eval` call is a
# fully separate, stateless request (no provider-side memory) — see
# docs/METHODS_non_training_openrouter.md.
#
# The model list is NOT hard-coded here: it comes from src/roster.py (the single
# source of truth the analysis script also reads), so "what we ran" and "what we
# plotted" can't drift. The current roster is ~19 live/routable open models across
# 5 families (Llama, Qwen, DeepSeek, Mistral, Gemma) x 2 tasks x ~184 items (see
# src/roster.py EXCLUDED for models dropped as delisted or no-ZDR). That's a real
# cost/time commitment — set ONLY_FAMILY=Llama (etc.) to trim to one family, or
# use scripts/3_runAll/run_tom_12dim_selective.sh for an arbitrary subset.
# MAX_TOKENS=<n> overrides the per-call output cap (default 16000).
# TEMPERATURE=<t> standardizes decoding (skipped for models that reject it).
#
# Privacy: every call passes the no-training/ZDR provider-routing prefs from
# src/openrouter.py (via scripts/_provider_prefs.sh). This is the request-level
# half of the two-layer control; also set the workspace-level toggles once in the
# OpenRouter dashboard (see docs/privacy_config_checklist.md).
#
# Grader: set DEVTOM_GRADER_MODEL to pin one strong judge for the free-response
# task (strongly recommended — small open models grading their own ToM reasoning
# is unreliable). Optionally set DEVTOM_GRADER_MODEL_SAMEFAMILY for cross-family
# grading — it grades only subjects sharing the primary judge's family, so no
# model is graded by its own family (avoids LLM-judge self-preference bias).
# See src/scorer.py.
#
# Assumes a venv with inspect-ai installed and OPENROUTER_API_KEY in .env.
# Run from root with: bash scripts/3_runAll/run_tom_12dim_all_within_family.sh
#   ONLY_FAMILY=Qwen bash scripts/3_runAll/run_tom_12dim_all_within_family.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if ! command -v inspect >/dev/null 2>&1; then
  echo "Inspect executable not found. Activate the intended environment or install inspect-ai first." >&2
  exit 1
fi
INSPECT_BIN="$(command -v inspect)"
echo "Using Inspect executable: $INSPECT_BIN"

cd "$PROJECT_ROOT"

if [[ -f "$PROJECT_ROOT/.env" ]]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

# At least one provider key is needed. OpenRouter for open-weight families,
# OpenAI for GPT, Anthropic for Claude — check later per-model which applies.
if [[ -z "${OPENROUTER_API_KEY:-}" && -z "${OPENAI_API_KEY:-}" && -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "No API keys set (OPENROUTER_API_KEY / OPENAI_API_KEY / ANTHROPIC_API_KEY). Add at least one to .env." >&2
  exit 1
fi

# Load the no-training/ZDR provider prefs into $PROVIDER_PREFS_JSON (used only
# for openrouter/* models; direct-API models skip it).
source "$PROJECT_ROOT/scripts/_provider_prefs.sh"
echo "Routing prefs (OpenRouter models only): $PROVIDER_PREFS_JSON"

# Per-call output cap. OpenRouter reserves credits for the full max_tokens up
# front, so an uncapped request (model default 32k-65k) 402s on a limited key.
# 16000 sits just under a typical small-key ceiling while leaving reasoning
# models (deepseek-r1*, qwen3*) room to think. If a reasoning model truncates,
# raise this (MAX_TOKENS=32000 bash ...) or raise the key's budget instead.
MAX_TOKENS="${MAX_TOKENS:-16000}"

# Optional standardized decoding: TEMPERATURE=<t> (e.g. TEMPERATURE=0.0) adds
# `--temperature <t>` to every eval call EXCEPT for models that reject sampling
# params (Claude Opus 4.7+/Sonnet 5/Fable 5 return HTTP 400 on any non-default
# value — see src/decoding.py). Flagged models run at provider-default decoding
# and must be analyzed as a separate uncontrolled-decoding stratum.
TEMPERATURE="${TEMPERATURE:-}"
if [[ -n "$TEMPERATURE" ]]; then
  echo "Standardized temperature: $TEMPERATURE (auto-omitted for models that reject sampling params)"
fi
echo "Per-call max_tokens: $MAX_TOKENS"
if [[ -n "${DEVTOM_GRADER_MODEL:-}" ]]; then
  echo "Free-response grader (primary): $DEVTOM_GRADER_MODEL"
  if [[ -n "${DEVTOM_GRADER_MODEL_SAMEFAMILY:-}" ]]; then
    echo "Cross-family grader (same-family subjects): $DEVTOM_GRADER_MODEL_SAMEFAMILY"
  fi
else
  echo "NOTE: DEVTOM_GRADER_MODEL not set — each model will grade its own free-response answers (less reliable)."
fi

# Move any logs left over from a previous run into logs/Archive/ before starting
# a fresh one, so summarize_visualize_results.py (which only scans logs/ itself,
# not subfolders) always sees just the latest run.
LOG_DIR="$PROJECT_ROOT/logs"
ARCHIVE_DIR="$LOG_DIR/Archive"
mkdir -p "$ARCHIVE_DIR"
shopt -s nullglob
moved=0
for f in "$LOG_DIR"/*; do
  [[ "$(basename "$f")" == "Archive" ]] && continue
  mv "$f" "$ARCHIVE_DIR/"
  moved=$((moved + 1))
done
shopt -u nullglob
if [[ "$moved" -gt 0 ]]; then
  echo "Archived $moved log file(s) from a previous run to $ARCHIVE_DIR"
fi

# Pull the model list from the roster. ONLY_FAMILY restricts to one family.
if [[ -n "${ONLY_FAMILY:-}" ]]; then
  mapfile -t MODELS < <(python -m src.roster --family "$ONLY_FAMILY")
  echo "Restricting to family: $ONLY_FAMILY (${#MODELS[@]} models)"
else
  mapfile -t MODELS < <(python -m src.roster)
  echo "Running full roster (${#MODELS[@]} models)"
fi

TASKS=(
  "scripts/3_runAll/tom_12dim_freeresponse.py"
  "scripts/3_runAll/tom_12dim_mcq.py"
)

for m in "${MODELS[@]}"; do
  for t in "${TASKS[@]}"; do
    echo "=== Running $t on $m ==="
    # `|| true`: one unavailable/delisted model (or one with no ZDR upstream, which
    # fails closed) shouldn't abort the whole multi-hour sweep. Its log just won't
    # be written, and it'll be absent from the plots.
    temp_args=()
    if [[ -n "$TEMPERATURE" ]] && ! python -m src.decoding --omits "$m"; then
      temp_args=(--temperature "$TEMPERATURE")
    fi
    # OpenRouter provider prefs only apply to openrouter/* models; direct-API
    # models (openai/*, anthropic/*) would ignore or reject them.
    provider_args=()
    if [[ "$m" == openrouter/* ]]; then
      provider_args=(-M provider="$PROVIDER_PREFS_JSON")
    fi
    "$INSPECT_BIN" eval "$t" --model "$m" --display plain ${provider_args[@]+"${provider_args[@]}"} --max-tokens "$MAX_TOKENS" ${temp_args[@]+"${temp_args[@]}"} || {
      echo "WARNING: eval failed for $m on $t (delisted model, no compliant route, or transient error) — continuing" >&2
    }
  done
done

echo
echo "Done. To compare accuracy by ToM dimension across the models just run, use:"
echo "  python scripts/0_misc/summarize_visualize_results.py"
