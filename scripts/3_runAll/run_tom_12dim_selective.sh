#!/usr/bin/env bash
# DevToM-OpenRouter — run BOTH ToM tasks on an ARBITRARY subset of models, for a
# quick/cheap pass or a targeted re-run. Same routing/grader behavior as
# run_tom_12dim_all_within_family.sh, but you pass the model slugs yourself
# instead of pulling the whole roster.
#
# Pass slugs WITHOUT the 'openrouter/' prefix as args (it's added for you), or
# full 'openrouter/...' strings — both work. Does NOT archive prior logs (so you
# can accumulate a subset onto an existing run); pass --fresh to archive first.
#
#   bash scripts/3_runAll/run_tom_12dim_selective.sh \
#       meta-llama/llama-3.2-3b-instruct meta-llama/llama-3.1-8b-instruct meta-llama/llama-3.3-70b-instruct
#   bash scripts/3_runAll/run_tom_12dim_selective.sh --fresh qwen/qwen3-32b

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

FRESH=0
if [[ "${1:-}" == "--fresh" ]]; then
  FRESH=1
  shift
fi

if [[ "$#" -eq 0 ]]; then
  echo "Usage: bash scripts/3_runAll/run_tom_12dim_selective.sh [--fresh] <model-slug> [<model-slug> ...]" >&2
  echo "Roster slugs: python -m src.roster   (or --family <Llama|Qwen|DeepSeek|Mistral|Gemma>)" >&2
  exit 1
fi

if ! command -v inspect >/dev/null 2>&1; then
  echo "Inspect executable not found. Activate the intended environment first." >&2
  exit 1
fi
INSPECT_BIN="$(command -v inspect)"

if [[ -f "$PROJECT_ROOT/.env" ]]; then
  set -a; source "$PROJECT_ROOT/.env"; set +a
fi
if [[ -z "${OPENROUTER_API_KEY:-}" && -z "${OPENAI_API_KEY:-}" && -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "No API keys set (OPENROUTER_API_KEY / OPENAI_API_KEY / ANTHROPIC_API_KEY). Add at least one to .env." >&2
  exit 1
fi

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

if [[ "$FRESH" -eq 1 ]]; then
  LOG_DIR="$PROJECT_ROOT/logs"; ARCHIVE_DIR="$LOG_DIR/Archive"; mkdir -p "$ARCHIVE_DIR"
  shopt -s nullglob
  for f in "$LOG_DIR"/*; do
    [[ "$(basename "$f")" == "Archive" ]] && continue
    mv "$f" "$ARCHIVE_DIR/"
  done
  shopt -u nullglob
  echo "Archived prior logs to $ARCHIVE_DIR"
fi

TASKS=(
  "scripts/3_runAll/tom_12dim_freeresponse.py"
  "scripts/3_runAll/tom_12dim_mcq.py"
)

for raw in "$@"; do
  # Accept full model strings (openrouter/..., openai/..., anthropic/...) or
  # bare 'author/slug' (defaults to openrouter/ prefix for open-weight models).
  if [[ "$raw" == openrouter/* || "$raw" == openai/* || "$raw" == anthropic/* ]]; then
    m="$raw"
  else
    m="openrouter/$raw"
  fi
  for t in "${TASKS[@]}"; do
    echo "=== Running $t on $m ==="
    temp_args=()
    if [[ -n "$TEMPERATURE" ]] && ! python -m src.decoding --omits "$m"; then
      temp_args=(--temperature "$TEMPERATURE")
    fi
    provider_args=()
    if [[ "$m" == openrouter/* ]]; then
      provider_args=(-M provider="$PROVIDER_PREFS_JSON")
    fi
    "$INSPECT_BIN" eval "$t" --model "$m" --display plain ${provider_args[@]+"${provider_args[@]}"} --max-tokens "$MAX_TOKENS" ${temp_args[@]+"${temp_args[@]}"} || {
      echo "WARNING: eval failed for $m on $t — continuing" >&2
    }
  done
done

echo
echo "Done. Analyze with: python scripts/0_misc/summarize_visualize_results.py"
