#!/usr/bin/env bash
# DevToM-OpenRouter — FREE-RESPONSE task ONLY, across every open-weight model in
# the roster, oldest to newest within each family, through OpenRouter. This is the
# open-ended half of the sweep (custom solver + model-graded scorer). It is the
# more expensive half because every answer is graded by a judge model — for a
# first, cheaper look use scripts/2a_runMCQ/run_tom_12dim_mcq_within_family.sh; for
# both tasks together use scripts/3_runAll/run_tom_12dim_all_within_family.sh.
#
# Model list comes from src/roster.py; routing prefs from src/openrouter.py.
# ONLY_FAMILY=<Llama|Qwen|DeepSeek|Mistral|Gemma> restricts to one family.
# MAX_TOKENS=<n> overrides the per-call output cap (default 16000).
# DEVTOM_GRADER_MODEL=<model> pins one strong judge for grading (recommended —
# small open models grading their own ToM reasoning is unreliable; see src/scorer.py).
# DEVTOM_GRADER_MODEL_SAMEFAMILY=<model> enables cross-family grading: this judge
# grades only subjects sharing the primary judge's family, so no model is graded
# by its own family (avoids LLM-judge self-preference bias).
#
# Run from root: bash scripts/2b_runFR/run_tom_12dim_fr_within_family.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

if ! command -v inspect >/dev/null 2>&1; then
  echo "Inspect executable not found. Activate the intended environment first." >&2
  exit 1
fi
INSPECT_BIN="$(command -v inspect)"

if [[ -f "$PROJECT_ROOT/.env" ]]; then
  set -a; source "$PROJECT_ROOT/.env"; set +a
fi
if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
  echo "OPENROUTER_API_KEY not set (add it to .env)." >&2
  exit 1
fi

source "$PROJECT_ROOT/scripts/_provider_prefs.sh"
echo "Routing prefs: $PROVIDER_PREFS_JSON"
if [[ -n "${DEVTOM_GRADER_MODEL:-}" ]]; then
  echo "Free-response grader (primary): $DEVTOM_GRADER_MODEL"
  if [[ -n "${DEVTOM_GRADER_MODEL_SAMEFAMILY:-}" ]]; then
    echo "Cross-family grader (same-family subjects): $DEVTOM_GRADER_MODEL_SAMEFAMILY"
  fi
else
  echo "NOTE: DEVTOM_GRADER_MODEL not set — each model will grade its own free-response answers (less reliable)."
fi

# Per-call output cap. OpenRouter reserves credits for the full max_tokens up
# front, so an uncapped request (model default 32k-65k) 402s on a limited key.
# 16000 sits just under a typical small-key ceiling while leaving reasoning
# models (deepseek-r1*, qwen3*) room to think. If a reasoning model truncates,
# raise this (MAX_TOKENS=32000 bash ...) or raise the key's budget instead.
MAX_TOKENS="${MAX_TOKENS:-16000}"
echo "Per-call max_tokens: $MAX_TOKENS"

# Archive prior logs so the analysis script only sees this run.
LOG_DIR="$PROJECT_ROOT/logs"; ARCHIVE_DIR="$LOG_DIR/Archive"; mkdir -p "$ARCHIVE_DIR"
shopt -s nullglob
for f in "$LOG_DIR"/*; do
  [[ "$(basename "$f")" == "Archive" ]] && continue
  mv "$f" "$ARCHIVE_DIR/"
done
shopt -u nullglob

if [[ -n "${ONLY_FAMILY:-}" ]]; then
  mapfile -t MODELS < <(python -m src.roster --family "$ONLY_FAMILY")
else
  mapfile -t MODELS < <(python -m src.roster)
fi
echo "Running free-response task on ${#MODELS[@]} models"

TASK="scripts/3_runAll/tom_12dim_freeresponse.py"
for m in "${MODELS[@]}"; do
  echo "=== Running $TASK on $m ==="
  "$INSPECT_BIN" eval "$TASK" --model "$m" -M provider="$PROVIDER_PREFS_JSON" --max-tokens "$MAX_TOKENS" || {
    echo "WARNING: eval failed for $m — continuing" >&2
  }
done

echo
echo "Done. Analyze with: python scripts/4_analyze/summarize_visualize_results.py"
