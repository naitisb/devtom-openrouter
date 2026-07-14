# Methods: Non-training LLM Usage via OpenRouter

> This is the project's implementation of the non-training OpenRouter workflow.
> It combines the original methods note (the workspace/provider policy) with a
> concrete map to **where in this repo each control lives**, so the write-up and
> the code stay in sync. The generic note is in the first five sections; the
> "In this repository" section at the end is the code map.

## Overview

This methods note describes a workflow for using large language models (LLMs)
through OpenRouter while minimizing participation in model training and prompt
retention.[cite:31][cite:32][cite:43] The approach is designed for longitudinal
research settings in which many models may be queried over time, but all calls
are treated as stateless inference requests rather than as contributions to
provider-side training pipelines.[cite:17][cite:31][cite:43] Here the
longitudinal dimension is explicit: the study deliberately reaches back to older
open-weight releases (Llama 2, Mistral 7B, the original DeepSeek LLM, Gemma 1)
so each open model family has a multi-year release history to trace a
developmental theory-of-mind trajectory across.

## Routing and privacy configuration

All model access is conducted through a dedicated OpenRouter workspace
configured with privacy-first defaults.[cite:31][cite:43][cite:51] Private input
and output logging is disabled so that prompt content is not retained in
workspace logs, while only operational metadata such as token counts and latency
are preserved for monitoring.[cite:31]

The workspace-level Zero Data Retention (ZDR) control is enabled so that requests
are routed only to providers that officially support zero data
retention.[cite:43][cite:46][cite:51] In addition, provider data collection is
denied so that requests are restricted to providers whose policies do not permit
training on submitted inputs and outputs.[cite:32][cite:46] These workspace
toggles are backed up at the **request level** by the routing preferences this
project attaches to every call (`data_collection: "deny"`, `zdr: true`), so a
compliant route is enforced even if a workspace setting is ever changed — a
belt-and-suspenders design.

## Provider selection criteria

Models are included in the research panel only if their documented provider
policy is compatible with non-training use.[cite:32][cite:46] Before a model is
added, the provider's published policy is checked for four requirements: no
training on standard API traffic, transparent retention terms, availability of
zero-retention or equivalent controls, and no hidden feedback or improvement
pathway enabled by default.[cite:32][cite:46][cite:52]

Providers or models that do not make these terms explicit are excluded from the
study set, even if they are otherwise attractive on cost or performance
grounds.[cite:32][cite:52] This exclusion rule is intended to preserve a
principled separation between inference and training participation.[cite:31][cite:43]
Because this project queries open-weight models that are typically served by
*several* upstream hosts on OpenRouter, the request-level `deny`/`zdr` filters do
the per-request enforcement: a model with no compliant upstream returns no route
(a fail-closed error) and is simply absent from the results, rather than being
silently sent to a non-compliant host.

## Request design

All API calls are implemented as stateless requests.[cite:17] No provider-side
conversation memory is assumed, and any context needed for a given trial is
supplied explicitly in the request payload.[cite:17] This design ensures that
model outputs can be compared across providers and time without hidden carryover
from earlier interactions.[cite:17][cite:31] Each `inspect eval` invocation is a
fully independent, stateless run.

Each experimental trial records the model identifier, provider, date, prompt
template version, and response metadata needed for reproducibility, while
avoiding storage of sensitive prompt content unless separately justified in the
research protocol.[cite:31][cite:39][cite:51] Where response content must be
retained for analysis, storage occurs in the research environment (the local
`logs/` and `results/` directories) rather than in provider-side
logs.[cite:31][cite:50][cite:52]

## Governance and documentation

Privacy and routing settings are documented at the start of each study period
and whenever providers are added or removed from the panel.[cite:31][cite:43][cite:51]
This documentation includes screenshots or written records showing disabled
prompt logging, enabled ZDR controls, denied provider data collection, and any
provider allowlists or blocks used in the workspace.[cite:31][cite:43][cite:46]
The written checklist for that record lives in
[`privacy_config_checklist.md`](privacy_config_checklist.md).

This configuration record functions as part of the reproducibility and ethics
documentation for the project.[cite:43][cite:52] It provides an auditable basis
for the claim that the study was designed to avoid participation in model
training beyond ordinary inference use.[cite:31][cite:32][cite:43]

## Scope and limitations

This workflow reduces training participation risk by combining OpenRouter-level
controls with provider-level screening, but it still depends on the accuracy and
continued validity of provider policy disclosures.[cite:32][cite:43][cite:52]
For that reason, provider policies are periodically re-reviewed during the study,
and any provider whose terms become ambiguous or incompatible with non-training
use is removed from the active panel.[cite:32][cite:52] A second, method-specific
limitation: OpenRouter load-balances a given open model across multiple upstream
hosts, so two calls to the "same" model may hit different hardware/quantizations.
The `sort` routing preference and, for maximum reproducibility,
`allow_fallbacks: false` (pin to a single upstream) mitigate this — at the cost
of more no-route failures. This project defaults to `allow_fallbacks: true`
(compliant fallback preferred over a failed trial) and documents the trade-off.

---

## In this repository (the code map)

| Control from the note | Where it lives |
|---|---|
| Request-level `data_collection:"deny"`, `zdr:true` routing prefs | [`src/openrouter.py`](../src/openrouter.py) — one source of truth for the policy dict |
| Prefs applied on every run (shells) | [`scripts/_provider_prefs.sh`](../scripts/_provider_prefs.sh) → `-M provider='{...}'` in the runners |
| Prefs applied on in-process calls (grader, connectivity check) | `openrouter_model_args()` splatted into `get_model(...)` |
| Fail-closed connectivity/route check per family | [`scripts/1_check-functionality/check_providers.py --live`](../scripts/1_check-functionality/check_providers.py) |
| Stateless request design | one `inspect eval` per (model, task); no conversation memory |
| Local-only response storage | `logs/` (`.eval`), `results/<timestamp>/` (CSV + figures) — both gitignored |
| Workspace-level toggles (dashboard) | [`privacy_config_checklist.md`](privacy_config_checklist.md) |
| Panel membership + provider screening | [`models.md`](models.md) + [`src/roster.py`](../src/roster.py) |

### How Inspect forwards the routing prefs

Inspect's OpenRouter provider accepts a `provider` model-arg (a dict) and
forwards it verbatim into the OpenAI-compatible request body's
`extra_body["provider"]`, which is exactly OpenRouter's provider-routing
preferences object. So

```bash
inspect eval scripts/3_runAll/tom_12dim_mcq.py \
  --model openrouter/meta-llama/llama-3.1-8b-instruct \
  -M provider='{"data_collection":"deny","zdr":true,"allow_fallbacks":true,"sort":"throughput"}'
```

is what actually restricts routing at request time. The runner scripts build that
JSON from `src/openrouter.py` (via `python -m src.openrouter`) so it is defined
once and cannot drift between scripts.

> **Citations.** The `[cite:NN]` markers are carried over from the source methods
> note and refer to that document's bibliography; resolve them there. They mark
> where each claim about OpenRouter/provider policy is grounded and should be
> re-verified against current OpenRouter documentation before publication, since
> provider retention/training policies change.
