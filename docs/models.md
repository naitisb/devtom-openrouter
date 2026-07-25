# Model roster — DevToM-OpenRouter

The **authoritative** roster is `src/roster.py` — the runners and the analysis
script both read it, so this document is the human-readable companion, not a
second source of truth. If they ever disagree, `src/roster.py` wins; update this
file to match.

## Comparison scope

This project runs the **12-dimension ToM instrument** across **5 model families**
spanning both closed frontier models (via direct API) and open-weight models (via
OpenRouter or Mistral la Plateforme), deliberately reaching **back in time to
older releases** so each family has a real multi-release history to trace a
developmental trajectory across.

- **family** = the model lineage. Five: **Claude** (Anthropic), **GPT**
  (OpenAI), **Llama** (Meta), **Qwen** (Alibaba), **Mistral**.
- **type** = size/architecture tier *within* a family (e.g. "Llama small",
  "Llama large", "Claude Opus", "Mistral Medium"). Each tier has its own release
  history and gets its own trend line + regression — collapsing tiers would hide
  whether a given tier improved release over release.

Routing:
- **Claude** models route via `anthropic/` (direct Anthropic API)
- **GPT** models route via `openai/` (direct OpenAI API)
- **Llama** and **Qwen** models route via `openrouter/` (OpenRouter API with
  no-training/ZDR preferences — see
  [`METHODS_non_training_openrouter.md`](METHODS_non_training_openrouter.md))
- **Mistral** models route via `mistral/` (Mistral la Plateforme API)

> **Env vars:** `OPENROUTER_API_KEY` (Llama, Qwen), `MISTRAL_API_KEY` (Mistral),
> `ANTHROPIC_API_KEY` (Claude), `OPENAI_API_KEY` (GPT). The runners skip models
> whose provider key is missing rather than aborting.

---

## Anthropic Claude — oldest -> newest

Direct API (`anthropic/` prefix). 9 models across 4 tiers.

| Slug | Tier (type) | Released |
|---|---|---|
| `claude-haiku-4-5-20251001` | Claude Haiku | 2025-10-01 |
| `claude-sonnet-4-5-20250929` | Claude Sonnet | 2025-09-29 |
| `claude-sonnet-4-6` | Claude Sonnet | 2026-01-14 |
| `claude-sonnet-5` | Claude Sonnet | 2026-06-24 |
| `claude-opus-4-5-20251101` | Claude Opus | 2025-11-01 |
| `claude-opus-4-6` | Claude Opus | 2026-03-04 |
| `claude-opus-4-7` | Claude Opus | 2026-05-22 |
| `claude-opus-4-8` | Claude Opus | 2026-07-10 |
| `claude-fable-5` | Claude Fable | 2026-06-24 |

## OpenAI GPT — oldest -> newest

Direct API (`openai/` prefix). 6 models across 4 tiers.

| Slug | Tier (type) | Released |
|---|---|---|
| `gpt-4o-mini` | GPT mini | 2024-07-18 |
| `gpt-4o-2024-08-06` | GPT standard | 2024-08-06 |
| `o1` | GPT reasoning | 2024-12-17 |
| `o3-mini` | GPT reasoning mini | 2025-01-31 |
| `o3` | GPT reasoning | 2025-04-16 |
| `o4-mini` | GPT reasoning mini | 2025-04-16 |

## Meta Llama — oldest -> newest

OpenRouter (`openrouter/` prefix). Author segment: `meta-llama`. 6 models across
3 tiers.

| Slug | Tier (type) | Released |
|---|---|---|
| `meta-llama/llama-3.1-8b-instruct` | Llama small | 2024-07-23 |
| `meta-llama/llama-3.1-70b-instruct` | Llama large | 2024-07-23 |
| `meta-llama/llama-3.2-3b-instruct` | Llama small | 2024-09-25 |
| `meta-llama/llama-3.3-70b-instruct` | Llama large | 2024-12-06 |
| `meta-llama/llama-4-scout` | Llama frontier | 2025-04-05 |
| `meta-llama/llama-4-maverick` | Llama frontier | 2025-04-05 |

## Alibaba Qwen — oldest -> newest

OpenRouter (`openrouter/` prefix). Author segment: `qwen`. 9 models across
3 tiers.

| Slug | Tier (type) | Released |
|---|---|---|
| `qwen/qwen-2.5-7b-instruct` | Qwen small | 2024-09-19 |
| `qwen/qwen-2.5-72b-instruct` | Qwen large | 2024-09-19 |
| `qwen/qwen3-8b` | Qwen small | 2025-04-29 |
| `qwen/qwen3-32b` | Qwen mid | 2025-04-29 |
| `qwen/qwen3-235b-a22b` | Qwen large | 2025-04-29 |
| `qwen/qwen3.5-397b-a17b` | Qwen large | 2026-02-16 |
| `qwen/qwen3.5-27b` | Qwen mid | 2026-02-24 |
| `qwen/qwen3.5-9b` | Qwen small | 2026-03-02 |
| `qwen/qwen3.6-27b` | Qwen mid | 2026-04-22 |

## Mistral — oldest -> newest

Mistral la Plateforme API (`mistral/` prefix). 8 models across 4 tiers.

| Slug | Tier (type) | Released |
|---|---|---|
| `ministral-8b-2410` | Ministral | 2024-10-16 |
| `mistral-small-2503` | Mistral Small | 2025-03-17 |
| `mistral-medium-2505` | Mistral Medium | 2025-05-07 |
| `mistral-medium-2508` | Mistral Medium | 2025-08-12 |
| `mistral-large-2512` | Mistral Large | 2025-12-02 |
| `ministral-3-8b-2512` | Ministral | 2025-12-02 |
| `mistral-small-2603` | Mistral Small | 2026-03-16 |
| `mistral-medium-3-5-26-04` | Mistral Medium | 2026-04-28 |

## Which tiers get a fitted regression?

A tier needs >=3 release-dated points (on distinct dates) for a regression line +
CI + p-value; fewer render as connected dots. As currently rostered: **Claude
Sonnet, Claude Opus, Llama small/large, Qwen small/mid/large, Mistral Medium**
clear the bar; **Claude Haiku, Claude Fable, GPT mini/standard/reasoning/
reasoning mini, Llama frontier, Ministral, Mistral Small, Mistral Large** are
points-only until more dated releases are added. Re-check after any roster edit
with:

```bash
python -c "from src.roster import ROSTER; from collections import Counter; \
c=Counter(e.type for e in ROSTER); \
print('\n'.join(f'{t}: {n} {\"regression\" if n>=3 else \"dots\"}' for t,n in sorted(c.items())))"
```

## Excluded / deferred

See `EXCLUDED` in `src/roster.py` for the full audit trail. Key categories:

- **DeepSeek** — excluded for insufficient response variability (near-identical
  answers across repeated trials, making ToM scoring unreliable).
- **Gemma** — excluded for the same insufficient-variability reason.
- **Old OpenRouter Mistral** (`mistralai/` slugs) — superseded by Mistral la
  Plateforme API routing; historical OpenRouter slugs were mostly delisted or
  lacked ZDR anyway.
- **Delisted historical models** (Llama 2, Qwen 1.5/2, old Mistral 7B, etc.) —
  gone from OpenRouter; the sibling devtom-selfhost project covers these via
  local vLLM serving.
- **Retired closed models** (o1-mini) — retired from the provider API.

## Pre-run checklist

- [ ] API keys in local `.env`: `OPENROUTER_API_KEY`, `MISTRAL_API_KEY`, and
  optionally `OPENAI_API_KEY` + `ANTHROPIC_API_KEY`; `.env` in `.gitignore`.
- [ ] Workspace privacy toggles set + recorded (`docs/privacy_config_checklist.md`).
- [ ] Spend limit/alert set — a full sweep is 38 models x 2 tasks x ~201 items.
- [ ] `check_providers.py --live` green for one model per family.
- [x] `DEVTOM_GRADER_MODEL` set to `openai/gpt-4o-2024-08-06` (primary judge, all
      non-GPT subject families). `DEVTOM_GRADER_MODEL_SAMEFAMILY` set to
      `anthropic/claude-sonnet-4-5-20250929` (alternate judge for GPT subjects — cross-family
      scheme ensures no subject is graded by a same-lab judge). Both pinned to
      snapshot ids for reproducibility. Decided 2026-07-22.
