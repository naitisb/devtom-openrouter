# OpenRouter privacy / no-training configuration checklist

The request-level routing prefs in `src/openrouter.py` are one half of the
two-layer control described in
[`METHODS_non_training_openrouter.md`](METHODS_non_training_openrouter.md). This
is the other half: the **workspace-level** settings you set once in the
OpenRouter dashboard and record here (with a date + screenshot) at the start of
each study period and whenever the panel changes. Keeping this file current is
part of the project's reproducibility/ethics record.

## One-time workspace setup (record date + screenshot for each)

- [ ] **Private prompt logging OFF.** Dashboard → Settings → Privacy: disable
      storage of prompt/completion content in workspace logs. Only operational
      metadata (token counts, latency) retained.
      _Set on: __________  screenshot: ___________
- [ ] **Zero Data Retention (ZDR) ON at the workspace level.** Restricts routing
      to providers that officially support zero data retention.
      _Set on: __________  screenshot: ___________
- [ ] **Provider data collection DENIED.** Restrict to providers whose policies
      do not permit training on submitted inputs/outputs.
      _Set on: __________  screenshot: ___________
- [ ] **Spend limit / alert set.** A full sweep is ~19 live open models × 2 tasks ×
      ~184 items (plus grader calls). Budget before an unattended run.
      _Set on: ___________

## Per-request enforcement (already wired in code — verify, don't re-do)

- [ ] `src/openrouter.py` `NON_TRAINING_PROVIDER_PREFS` still reads
      `{"data_collection":"deny","zdr":true,...}`.
- [ ] Runners pass `-M provider="$PROVIDER_PREFS_JSON"` (see
      `scripts/_provider_prefs.sh`). Grep confirms no runner calls `inspect eval`
      without it.
- [ ] `check_providers.py --live` passes for one model per family (a no-route
      error means that family has no compliant upstream — expected fail-closed
      behavior; drop the model or accept its absence from results).

## Per-study-period review

- [ ] Re-read provider policies for every family in `docs/models.md` /
      `src/roster.py`; remove any whose terms became ambiguous or
      training-permitting. _Reviewed on: ___________
- [ ] Re-verify each roster slug still resolves on
      https://openrouter.ai/models (delisted models 404). _Reviewed on: ___________

## Notes / deviations

_(Record any model run without full ZDR — e.g. because it was the only host for
an older release — with the justification, so the audit trail is complete.)_
