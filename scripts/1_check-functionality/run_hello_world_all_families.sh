#!/usr/bin/env bash
# DevToM-OpenRouter — smoke test: one tiny hello-world MCQ on one representative
# model per open-weight family, through OpenRouter with the no-training/ZDR
# routing prefs. Confirms end-to-end wiring (key, routing, task loader, scorer)
# for cents, before launching a full sweep.
#
# Run from root: bash scripts/1_check-functionality/run_hello_world_all_families.sh

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

# Cap generation length for the smoke test. Without this, Inspect sends the
# model's default max_tokens (32k-65k), and OpenRouter reserves credits for the
# full amount up-front — small key budgets get a 402 before any tokens are used.
# A hello-world MCQ needs only a few output tokens; the headroom here also lets
# reasoning models emit a short chain of thought. Override with MAX_TOKENS=... .
MAX_TOKENS="${MAX_TOKENS:-4096}"

# One representative (newest) model per family.
mapfile -t FAMILIES < <(python -m src.roster --list-families)
TASK="tasks/hello_world_mcq.py"

for fam in "${FAMILIES[@]}"; do
  m="$(python -m src.roster --family "$fam" | tail -n 1)"
  echo "=== [$fam] smoke: $TASK on $m ==="
  "$INSPECT_BIN" eval "$TASK" --model "$m" -M provider="$PROVIDER_PREFS_JSON" --limit 2 --max-tokens "$MAX_TOKENS" || {
    echo "WARNING: smoke failed for $fam ($m) — check routing/availability" >&2
  }
done

echo
echo "Smoke test done. If all families passed, run the full sweep:"
echo "  bash scripts/3_runAll/run_tom_12dim_all_within_family.sh"
