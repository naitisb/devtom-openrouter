# Model roster — DevToM-OpenRouter (open-weight families via OpenRouter)

The **authoritative** roster is `src/roster.py` — the runners and the analysis
script both read it, so this document is the human-readable companion, not a
second source of truth. If they ever disagree, `src/roster.py` wins; update this
file to match.

## Comparison scope

Where the sibling **devtom-eval** project compares *closed* frontier families
(Anthropic, OpenAI) within themselves oldest-to-newest, this project runs the
**same 12-dimension ToM instrument** across **open-weight** families served
through OpenRouter, and deliberately reaches **back in time to older releases**
so each family has a real multi-year history to trace a developmental trajectory
across — not just its two latest checkpoints.

- **family** = the open-weight lineage. Five: **Llama** (Meta), **Qwen**
  (Alibaba), **DeepSeek**, **Mistral**, **Gemma** (Google, open weights).
- **type** = size/architecture tier *within* a family (e.g. "Llama small",
  "Llama large", "Mistral MoE"). Each tier has its own release history and gets
  its own trend line + regression — collapsing tiers would hide whether a given
  tier improved release over release. This mirrors "Claude Opus" vs "Claude
  Sonnet" as separate trend lines in devtom-eval.

All calls route through OpenRouter with the no-training/ZDR provider preferences
in `src/openrouter.py` — see
[`METHODS_non_training_openrouter.md`](METHODS_non_training_openrouter.md).

> **Env var:** `OPENROUTER_API_KEY` (one key, all families).

## ⚠️ Panel verified + frozen (2026-07-14)

The tables below are the *intended* panel. It was verified on 2026-07-14 and is
now **frozen** for reproducibility: the live model set is `ROSTER` in
`src/roster.py` and the 18 unroutable slugs are parked in its `EXCLUDED` list
(see "Excluded / deferred" below). The set does not change mid-study.

The verification procedure (for the record, and to repeat if you ever start a
fresh, re-frozen study period) was:
1. Confirm each slug resolves on <https://openrouter.ai/models> (a delisted
   model 404s) — verified against `https://openrouter.ai/api/v1/models`.
2. Confirm the family has ZDR / no-training upstreams (`check_providers.py --live`);
   models with no compliant route fail closed and are absent from results.
3. Re-verify any date that matters for the trend regression.

OpenRouter renames slugs and delists older models. Every slug below is a
best-effort OpenRouter model id and every date is the upstream model's public
release date as known at authoring time (2026-01 knowledge cutoff). The oldest
open models (Llama 2, the original DeepSeek LLM, Gemma 1) were the highest-value
"back in time" trajectory points but are among the delisted set; a future study
period could restore them by finding equivalent community re-hosts.

---

## Meta Llama — oldest → newest

Author segment: `meta-llama`. Slugs below take the `openrouter/` prefix.

| Slug | Tier (type) | Released |
|---|---|---|
| `meta-llama/llama-2-70b-chat` | Llama large | 2023-07-18 |
| `meta-llama/llama-3-8b-instruct` | Llama small | 2024-04-18 |
| `meta-llama/llama-3-70b-instruct` | Llama large | 2024-04-18 |
| `meta-llama/llama-3.1-8b-instruct` | Llama small | 2024-07-23 |
| `meta-llama/llama-3.1-70b-instruct` | Llama large | 2024-07-23 |
| `meta-llama/llama-3.1-405b-instruct` | Llama frontier | 2024-07-23 |
| `meta-llama/llama-3.2-3b-instruct` | Llama small | 2024-09-25 |
| `meta-llama/llama-3.3-70b-instruct` | Llama large | 2024-12-06 |
| `meta-llama/llama-4-scout` | Llama frontier (MoE) | 2025-04-05 |
| `meta-llama/llama-4-maverick` | Llama frontier (MoE) | 2025-04-05 |

## Alibaba Qwen — oldest → newest

Author segment: `qwen`.

| Slug | Tier (type) | Released |
|---|---|---|
| `qwen/qwen-1.5-72b-chat` | Qwen large | 2024-02-04 |
| `qwen/qwen-2-7b-instruct` | Qwen small | 2024-06-06 |
| `qwen/qwen-2-72b-instruct` | Qwen large | 2024-06-06 |
| `qwen/qwen-2.5-7b-instruct` | Qwen small | 2024-09-19 |
| `qwen/qwen-2.5-72b-instruct` | Qwen large | 2024-09-19 |
| `qwen/qwen3-8b` | Qwen small | 2025-04-29 |
| `qwen/qwen3-32b` | Qwen mid | 2025-04-29 |
| `qwen/qwen3-235b-a22b` | Qwen large (MoE) | 2025-04-29 |

## DeepSeek — oldest → newest

Author segment: `deepseek`. Two lineages tracked separately: **V** (the general
chat line, DeepSeek LLM → V3 → V3-0324) and **R** (the reasoning line, R1 →
R1-0528). DeepSeek's public OpenRouter history is shorter than the others, so the
R line may render as points rather than a fitted regression (<3 dated points).

| Slug | Tier (type) | Released |
|---|---|---|
| `deepseek/deepseek-llm-67b-chat` | DeepSeek V | 2023-11-29 |
| `deepseek/deepseek-chat` (V3) | DeepSeek V | 2024-12-26 |
| `deepseek/deepseek-r1` | DeepSeek R | 2025-01-20 |
| `deepseek/deepseek-chat-v3-0324` | DeepSeek V | 2025-03-24 |
| `deepseek/deepseek-r1-0528` | DeepSeek R | 2025-05-28 |

## Mistral — oldest → newest

Author segment: `mistralai`. Three lineages: **small** (dense 7B → Small 3),
**MoE** (Mixtral 8x7B/8x22B), **large** (Mistral Large 1/2/2411).

| Slug | Tier (type) | Released |
|---|---|---|
| `mistralai/mistral-7b-instruct` | Mistral small | 2023-09-27 |
| `mistralai/mixtral-8x7b-instruct` | Mistral MoE | 2023-12-11 |
| `mistralai/mistral-large` | Mistral large | 2024-02-26 |
| `mistralai/mixtral-8x22b-instruct` | Mistral MoE | 2024-04-17 |
| `mistralai/mistral-large-2407` | Mistral large | 2024-07-24 |
| `mistralai/mistral-large-2411` | Mistral large | 2024-11-18 |
| `mistralai/mistral-small-24b-instruct-2501` | Mistral small | 2025-01-30 |
| `mistralai/mistral-small-3.2-24b-instruct` | Mistral small | 2025-06-20 |

## Google Gemma (open weights) — oldest → newest

Author segment: `google`. These are the **open-weight** Gemma releases, not the
closed Gemini API models (which belong in a closed-family study, not here).

| Slug | Tier (type) | Released |
|---|---|---|
| `google/gemma-7b-it` | Gemma large | 2024-02-21 |
| `google/gemma-2-9b-it` | Gemma small | 2024-06-27 |
| `google/gemma-2-27b-it` | Gemma large | 2024-06-27 |
| `google/gemma-3-4b-it` | Gemma small | 2025-03-12 |
| `google/gemma-3-12b-it` | Gemma mid | 2025-03-12 |
| `google/gemma-3-27b-it` | Gemma large | 2025-03-12 |

---

## Which tiers get a fitted regression?

A tier needs ≥3 release-dated points (on distinct dates) for a regression line +
CI + p-value; fewer render as connected dots. As currently rostered: **Llama
small/large/frontier, Qwen small/large, DeepSeek V, Mistral small/large, Gemma
large** clear the bar; **Qwen mid, DeepSeek R, Mistral MoE, Gemma small/mid** are
points-only until more dated releases are added. Re-check after any roster edit
with:

```bash
python -c "from src.roster import ROSTER; from collections import Counter; \
c=Counter(e.type for e in ROSTER); \
print('\n'.join(f'{t}: {n} {\"regression\" if n>=3 else \"dots\"}' for t,n in sorted(c.items())))"
```

## Excluded / deferred

- **Closed API-only models** (GPT-*, Claude-*, Gemini API) — those are the
  sibling devtom-eval project's scope; this repo is open-weight-only.
- **Very old base (non-chat/instruct) checkpoints** — the ToM tasks assume an
  instruction-tuned model; base completions score near chance for reasons
  unrelated to ToM, so base variants are left out.
- **Newer releases after the 2026-01 knowledge cutoff** — add them to
  `src/roster.py` with a verified slug + date as they appear; the analysis
  picks them up automatically.
- **Unroutable at last check (verified 2026-07-14)** — the tables above list the
  *intended* panel; 18 of those slugs were not runnable at last check and are
  parked in `src/roster.py`'s `EXCLUDED` list (the source of truth), so the
  runners and analysis skip them. Two reasons:
  - _Delisted_ (gone from OpenRouter, verified against
    `https://openrouter.ai/api/v1/models`): `llama-2-70b-chat`, `llama-3-8b`,
    `llama-3-70b`, `llama-3.1-405b`, `qwen-1.5-72b-chat`, `qwen-2-7b`,
    `qwen-2-72b`, `deepseek-llm-67b-chat`, `mistral-7b-instruct`,
    `mixtral-8x7b`, `mistral-large-2411`, `gemma-7b-it`, `gemma-2-9b-it`.
    This removes the deep-history anchors (Llama 2 / Mistral 7B / original
    DeepSeek LLM / Gemma 1), shortening the Mistral and DeepSeek trend lines.
  - _No ZDR provider_ (exists but fails closed under the no-training prefs):
    `mistral-large`, `mixtral-8x22b`, `mistral-large-2407`, `qwen3-8b`,
    `qwen3-235b-a22b`.
  The panel is **frozen as of 2026-07-14** for reproducibility — this is the
  fixed model set for the study. Re-running `check_providers.py --live --all`
  later refreshes the audit record (has routability changed?), but does not
  add or remove models mid-study.

## Pre-run checklist

- [ ] `OPENROUTER_API_KEY` in local `.env`; `.env` in `.gitignore`.
- [ ] Workspace privacy toggles set + recorded (`docs/privacy_config_checklist.md`).
- [ ] Spend limit/alert set — a full sweep is ~19 live models × 2 tasks × ~184 items.
- [ ] `check_providers.py --live` green for one model per family.
- [x] Slugs + dates verified against OpenRouter's live model list (2026-07-14;
      panel frozen — see "Panel verified + frozen" above).
- [ ] `DEVTOM_GRADER_MODEL` chosen (recommended) for the free-response task.
