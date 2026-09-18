"""Build the frozen data snapshot the Streamlit app reads.

The app never touches `results/` at runtime. This script copies the small set of
*current* artifacts into `app/data/` so the app is fast, reproducible, and safe
to deploy anywhere.

## Why only these artifacts

`results/item_level.csv` was regenerated 2026-08-23 when two models were
excluded from the panel. Only two modeling subtrees were re-run after that:

    results/modeling/guttman_sequence/latest/    (2026-08-24)
    results/modeling/scale_validity/latest/      (2026-08-23)

Everything else under `results/modeling/` and `results/stats/` predates the
regeneration and still contains the excluded models. Rather than ship stale
tables, the app recomputes every descriptive and age-mapping quantity in Python
directly from `item_level.csv` (5,152 rows — trivially fast) and reads only the
two current modeling dirs for the things that genuinely cannot be recomputed
cheaply: the 10,000-draw permutation null, the Rasch/IRT item parameters, the
cross-validated log-loss, and the PCA.

Run it with `make app-data`, or:

    python app/prepare_data.py
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

REPO_ROOT = Path(__file__).resolve().parent.parent
APP_DIR = Path(__file__).resolve().parent
OUT_DIR = APP_DIR / "data"

sys.path.insert(0, str(REPO_ROOT))

# Source-of-truth modules. Imported here (build time) so the app itself never
# has to depend on `src/` — the constants get frozen into reference.json.
from src import constructs as C  # noqa: E402
from src import roster as R  # noqa: E402

ITEM_LEVEL = REPO_ROOT / "results" / "item_level.csv"
MCQ_ITEMS = REPO_ROOT / "data" / "12dimToM_mcq_dataset.jsonl"
FRQ_ITEMS = REPO_ROOT / "data" / "12dimToM_freeresponse_dataset.jsonl"

# R writes `NA`; pandas needs to be told.
R_NA = ["NA", "NaN", "nan", ""]


@dataclass
class ModelingSource:
    """A modeling subtree to snapshot verbatim."""

    key: str
    relpath: str
    files: tuple[str, ...]

    @property
    def path(self) -> Path:
        return REPO_ROOT / "results" / "modeling" / self.relpath


MODELING_SOURCES = (
    ModelingSource(
        key="guttman",
        relpath="guttman_sequence/latest",
        files=(
            "scalability_coefficients.csv",
            "permutation_results.csv",
            "permutation_null_draws.csv",
            "mastery_matrix_long.csv",
            "per_model_coherence.csv",
            "per_dimension_accuracy.csv",
            "coherence_by_split_point.csv",
            "coherence_regression.csv",
            "item_difficulty_vs_age.csv",
            "item_age_regression.csv",
            "rasch_item_difficulty.csv",
            "rasch_difficulty_vs_age.csv",
        ),
    ),
    ModelingSource(
        key="scale_validity",
        relpath="scale_validity/latest",
        files=(
            "summary.csv",
            "cv_logloss.csv",
            "lodo_dimension_predictions.csv",
            "pca_variance.csv",
            "pca_loadings.csv",
            "theta_by_format.csv",
            "format_transfer.csv",
            "format_transfer_theta_cor.csv",
        ),
    ),
)


def _read_jsonl(path: Path) -> pd.DataFrame:
    """Flatten a task dataset's JSONL into a tidy item table."""
    rows = []
    with path.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            meta = rec.get("metadata", {}) or {}
            choices = rec.get("choices") or []
            rows.append(
                {
                    "item_id": rec.get("id"),
                    "format": "MCQ" if choices else "Free response",
                    "prompt": rec.get("input", ""),
                    # MCQ targets are letters ("D"); FRQ targets are model answers.
                    "target": rec.get("target", ""),
                    "choices": json.dumps(choices, ensure_ascii=False),
                    "n_choices": len(choices),
                    "rubric": meta.get("rubric", ""),
                    "tom_dimension": meta.get("tom_dimension", ""),
                    "tom_construct": meta.get("tom_construct", ""),
                    "validated_age_band": meta.get("validated_age_band", ""),
                    "literature_basis": meta.get("literature_basis", ""),
                }
            )
    return pd.DataFrame(rows)


def _write_reference(observed_models: list[str]) -> dict:
    """Freeze roster/construct constants so the app needs no `src/` import.

    The model strings in `item_level.csv` do not always match `ModelEntry.model`
    verbatim — open-weight models are recorded with an `openai-api/local/...`
    prefix. The roster's own accessors resolve those aliases, so every lookup
    map is keyed by the strings that actually appear in the data as well as by
    the canonical roster string.
    """
    keys = {entry.model for entry in R.ROSTER} | set(observed_models)

    params = {}
    release = {}
    for key in sorted(keys):
        value = R.model_params_b(key)
        if value is not None:
            params[key] = value
        date = R.model_release_date(key)
        if date is not None:
            release[key] = date.isoformat()

    missing = [m for m in observed_models if m not in params]
    if missing:
        print(f"  NOTE: no parameter count for {len(missing)} model(s):", file=sys.stderr)
        for name in missing:
            print(f"    - {name}", file=sys.stderr)

    ref = {
        "family_order": list(R.FAMILY_ORDER),
        "family_colors": dict(R.FAMILY_COLORS),
        "type_order": list(R.TYPE_ORDER),
        "type_colors": dict(R.TYPE_COLORS),
        "construct_order": list(C.CONSTRUCT_DEVELOPMENTAL_ORDER),
        "construct_colors": dict(C.CONSTRUCT_COLORS),
        "dimension_to_construct": dict(C.DIMENSION_TO_CONSTRUCT),
        "model_params_b": params,
        "model_release_date": release,
        "model_family": {k: R.model_family(k) for k in sorted(keys)},
        "model_tier": {k: R.model_type(k) for k in sorted(keys)},
        "excluded_models": [
            {"model": entry.model, "family": entry.family, "reason": reason}
            for entry, reason in R.EXCLUDED
        ],
        "roster_size": len(R.ROSTER),
    }
    (OUT_DIR / "reference.json").write_text(
        json.dumps(ref, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    return ref


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--force",
        action="store_true",
        help="Rebuild even if the snapshot already exists.",
    )
    args = parser.parse_args()

    if OUT_DIR.exists() and not args.force:
        print(f"Snapshot exists at {OUT_DIR}. Rebuilding (use --force to silence).")
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    provenance: dict[str, object] = {
        "built_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "repo_root": str(REPO_ROOT),
        "sources": {},
    }

    # ---- 1. The spine -----------------------------------------------------
    if not ITEM_LEVEL.exists():
        print(f"FATAL: {ITEM_LEVEL} not found. Run `make analyze` first.", file=sys.stderr)
        return 1

    items = pd.read_csv(ITEM_LEVEL, na_values=R_NA, keep_default_na=True)
    # `log_file` is an absolute file:// URI from the machine that ran the eval;
    # it leaks local paths and is useless to the app. Drop it.
    items = items.drop(columns=[c for c in ("log_file",) if c in items.columns])
    items["release_date"] = pd.to_datetime(items["release_date"], errors="coerce")
    items.to_parquet(OUT_DIR / "item_level.parquet", index=False)

    provenance["sources"]["item_level"] = {
        "path": str(ITEM_LEVEL.relative_to(REPO_ROOT)),
        "mtime": datetime.fromtimestamp(
            ITEM_LEVEL.stat().st_mtime, tz=timezone.utc
        ).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "rows": int(len(items)),
        "models": int(items["model"].nunique()),
        "items": int(items["item_id"].nunique()),
        "tasks": sorted(items["task"].unique().tolist()),
    }
    print(
        f"  item_level      {len(items):>6,} rows  "
        f"{items['model'].nunique()} models  {items['item_id'].nunique()} items"
    )

    # ---- 2. The item bank (the instrument itself) -------------------------
    banks = []
    for path in (MCQ_ITEMS, FRQ_ITEMS):
        if not path.exists():
            print(f"  WARNING: item bank missing: {path}", file=sys.stderr)
            continue
        banks.append(_read_jsonl(path))
    if banks:
        bank = pd.concat(banks, ignore_index=True)
        bank.to_parquet(OUT_DIR / "items.parquet", index=False)
        provenance["sources"]["item_bank"] = {
            "rows": int(len(bank)),
            "mcq": int((bank["format"] == "MCQ").sum()),
            "frq": int((bank["format"] == "Free response").sum()),
        }
        print(f"  item_bank       {len(bank):>6,} items")

    # ---- 3. The two current modeling subtrees -----------------------------
    for source in MODELING_SOURCES:
        dest = OUT_DIR / source.key
        if dest.exists():
            shutil.rmtree(dest)
        dest.mkdir(parents=True, exist_ok=True)

        if not source.path.exists():
            print(
                f"  WARNING: {source.path} not found — the "
                f"'{source.key}' pages will show a friendly placeholder.",
                file=sys.stderr,
            )
            continue

        copied = []
        for name in source.files:
            src_file = source.path / name
            if not src_file.exists():
                print(f"  WARNING: missing {source.key}/{name}", file=sys.stderr)
                continue
            # The permutation null is 676 KB of one float column; parquet it.
            if name == "permutation_null_draws.csv":
                frame = pd.read_csv(src_file, na_values=R_NA)
                frame.to_parquet(dest / "permutation_null_draws.parquet", index=False)
            else:
                shutil.copy2(src_file, dest / name)
            copied.append(name)

        provenance["sources"][source.key] = {
            "path": str(source.path.relative_to(REPO_ROOT)),
            "files": copied,
            "mtime": datetime.fromtimestamp(
                source.path.stat().st_mtime, tz=timezone.utc
            ).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
        print(f"  {source.key:<15} {len(copied):>6} files")

    # ---- 4. Frozen constants ---------------------------------------------
    ref = _write_reference(sorted(items["model"].unique().tolist()))
    print(f"  reference       {ref['roster_size']:>6} roster entries")

    (OUT_DIR / "provenance.json").write_text(
        json.dumps(provenance, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    total = sum(f.stat().st_size for f in OUT_DIR.rglob("*") if f.is_file())
    print(f"\nSnapshot ready: {OUT_DIR}  ({total / 1_048_576:.1f} MB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
