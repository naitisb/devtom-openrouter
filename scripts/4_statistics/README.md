# 4_statistics — Descriptive statistics and data prep

This stage extracts item-level data from the eval logs and computes descriptive
statistics. Its outputs feed into `scripts/5_model/` (modeling) and
`scripts/6_visualize/` (visualization).

## Run order

1. **`extract_item_level.py`** (run first) — reads `logs/*.eval`, writes
   `results/item_level.csv`. This is the shared data table consumed by both
   `profile_results.py` and the R modeling scripts.

2. **`profile_dataset.py`** (standalone) — profiles the JSONL item banks in
   `data/` (composition, coverage, readability, duplicates). Does not need the
   eval logs.

3. **`profile_results.py`** — reads `results/item_level.csv` and computes
   accuracy summaries (Wilson CI), CTT item analysis (facility, discrimination),
   KR-20 reliability, and response quality.

## Dependencies

- Python: `inspect_ai`, `pandas`, `numpy` (all in requirements.txt)
- **`textstat`** (new — for readability in `profile_dataset.py`):
  `pip install textstat`

## Quick start

```bash
python scripts/4_statistics/extract_item_level.py
python scripts/4_statistics/profile_dataset.py
python scripts/4_statistics/profile_results.py
```

Or via Make:

```bash
make extract
make profile-dataset
make profile-results
```
