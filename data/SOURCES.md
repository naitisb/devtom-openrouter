# Data sources & licenses

Record every dataset here before ingesting. A clean license trail is part of the
open-science signal. The DevToM item bank draws on validated tasks from the
developmental psychology literature (see `docs/dev_norms.md` for empirical age
norms and citations) to evaluate LLMs on the same theory-of-mind milestones
children pass between ages 2 and 11.

| Dataset | Version / commit | License | URL | Notes |
|---|---|---|---|---|
| ToMi | generator pinned @ `dea2bca` (master) | CC-BY-NC 4.0 | https://github.com/facebookresearch/ToMi | Not a static file — regenerate with `main.py --seed <N>`; record the seed used. Use corrected 2nd-order labels (Arodi & Cheung 2021 / Sap et al. 2022) if located. Non-commercial. See `data/raw/tomi/NOTES.md`. |
| BigToM | data pinned @ `fe647d6` (main) | MIT | https://github.com/cicl-stanford/procedural-evals-tom | Single `data/bigtom/bigtom.csv`, 25 controls + 5,000 model-written items, first-order only. See `data/raw/bigtom/NOTES.md`. |
| FANToM | data pinned @ `1cae6fa` (main) | MIT (code); **eval-only** (data usage restriction, see repo README) | https://github.com/skywalker023/fantom | Conversational ToM + answerability/info-access controls; downloads from a GCS tarball, hash-checked. See `data/raw/fantom/NOTES.md`. |
| (authored items) | v0.1 | MIT (this repo) | — | Original higher-order items; you own gold labels. |

Raw downloads go in `data/raw/{tomi,bigtom,fantom}/` (gitignored except the
`NOTES.md` fetch instructions in each). Normalized per-source output from
`src/load_*.py` goes in `data/processed/*.jsonl` (also gitignored — derived,
regenerable). Only the final merged/frozen `data/devtom_v0.1.jsonl` (Story 1.6)
gets committed.
