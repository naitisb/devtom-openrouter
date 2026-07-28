"""Extract item-level correct/incorrect outcomes from .eval logs into a tidy CSV.

This is the shared data-prep step that both the descriptive statistics
(profile_results.py) and the modeling scripts (scripts/5_model/*.R) consume.
Run this FIRST in the 4_statistics → 5_model → 6_visualize pipeline.

Reads every .eval log under --log-dir with inspect_ai.log.read_eval_log (full,
not header-only) and emits one row per (model, task, item) with the binary
correct/incorrect outcome plus item and model metadata.

    python scripts/4_statistics/extract_item_level.py
    python scripts/4_statistics/extract_item_level.py --log-dir logs ../devtom-selfhost/logs
    python scripts/4_statistics/extract_item_level.py --log-dir logs/Archive --all-runs
"""
from __future__ import annotations

import argparse
import datetime
import math
import re
import sys
from pathlib import Path

import pandas as pd

PROJECT_ROOT = Path(__file__).parent.parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from inspect_ai.log import list_eval_logs, read_eval_log  # noqa: E402
from inspect_ai.scorer import CORRECT  # noqa: E402

from src.roster import (  # noqa: E402
    FAMILY_ORDER,
    MODEL_RELEASE_DATE,
    _canonical_model,
    model_family,
    model_params_b,
    model_release_date,
    model_type,
)
from src.constructs import (  # noqa: E402
    DIMENSION_DEVELOPMENTAL_ORDER,
    DIMENSION_TO_CONSTRUCT,
    construct_for_dimension,
)

TASK_NAMES = {"tom_12dim_mcq", "tom_12dim_freeresponse"}
_TASK_NORMALIZE = {"tom_12dim_mcqtf": "tom_12dim_mcq"}
_EPOCH = datetime.date(2024, 1, 1)


def _is_correct(value) -> int:
    if isinstance(value, str):
        return 1 if value.strip().upper().startswith("C") else 0
    return 1 if value in (CORRECT, 1, 1.0, True) else 0


def _parse_age_band(band: str | None) -> tuple[float | None, float | None, float | None]:
    """Parse '2-3 yrs' → (2.0, 3.0, 2.5). Returns (None, None, None) if unparseable."""
    if not band:
        return None, None, None
    m = re.match(r"(\d+)\s*[-–]\s*(\d+)", band)
    if m:
        lo, hi = float(m.group(1)), float(m.group(2))
        return lo, hi, (lo + hi) / 2
    return None, None, None


def extract(log_dirs: list[str], all_runs: bool = False) -> pd.DataFrame:
    """Read all .eval logs from one or more directories and return item-level DataFrame."""
    records: list[dict] = []
    log_meta: list[dict] = []

    for log_dir in log_dirs:
        for info in list_eval_logs(log_dir, formats=["eval"], recursive=False):
            log = read_eval_log(info)
            task_name = _TASK_NORMALIZE.get(log.eval.task, log.eval.task)
            if task_name not in TASK_NAMES:
                continue
            if log.status != "success":
                print(f"skipping {info.name}: status={log.status}", file=sys.stderr)
                continue
            model = log.eval.model
            canonical = _canonical_model(model)
            family = model_family(canonical)
            if family not in FAMILY_ORDER:
                print(f"skipping {info.name}: model '{model}' not in a recognized family",
                      file=sys.stderr)
                continue

            log_meta.append({
                "model": model, "task": task_name,
                "created": log.eval.created, "log_file": info.name,
            })

            date = model_release_date(canonical)
            date_years = (date - _EPOCH).days / 365.25 if date else None
            tier = model_type(canonical)
            params = model_params_b(canonical)
            log_params = math.log10(params) if params is not None else None

            for s in log.samples or []:
                if not s.scores:
                    continue
                score = next(iter(s.scores.values()))
                meta = s.metadata or {}
                dim = meta.get("tom_dimension", "unknown")
                construct = meta.get("tom_construct") or construct_for_dimension(dim) or "unknown"
                age_band = meta.get("validated_age_band")
                age_lo, age_hi, age_mid = _parse_age_band(age_band)
                dim_rank = (DIMENSION_DEVELOPMENTAL_ORDER.index(dim)
                            if dim in DIMENSION_DEVELOPMENTAL_ORDER
                            else len(DIMENSION_DEVELOPMENTAL_ORDER))

                records.append({
                    "model": model,
                    "family": family,
                    "tier": tier,
                    "task": task_name,
                    "created": log.eval.created,
                    "log_file": info.name,
                    "item_id": str(s.id),
                    "correct": _is_correct(score.value),
                    "tom_dimension": dim,
                    "tom_construct": construct,
                    "validated_age_band": age_band or "",
                    "age_lo": age_lo,
                    "age_hi": age_hi,
                    "age_mid": age_mid,
                    "dim_rank": dim_rank,
                    "literature_basis": meta.get("literature_basis", ""),
                    "date_years": date_years,
                    "release_date": str(date) if date else "",
                    "params_b": params,
                    "log_params": log_params,
                })

    if not records:
        return pd.DataFrame()

    df = pd.DataFrame(records)

    if not all_runs:
        latest = df.groupby(["model", "task"])["created"].transform("max")
        df = df[df["created"] == latest]

    # Deduplicate: when the same base model slug appears from both openrouter
    # and selfhost (openai-api/local/), keep the openrouter version.
    df["_slug"] = df["model"].apply(lambda m: m.split("/")[-1])
    df["_is_selfhost"] = df["model"].str.startswith("openai-api/local/")
    slug_counts = df.groupby(["_slug", "task"])["model"].transform("nunique")
    drop_mask = (slug_counts > 1) & df["_is_selfhost"]
    if drop_mask.any():
        dropped = df.loc[drop_mask, "model"].unique()
        for m in dropped:
            print(f"dedup: dropping selfhost '{m}' (openrouter version exists)",
                  file=sys.stderr)
        df = df[~drop_mask]
    df = df.drop(columns=["_slug", "_is_selfhost"])

    return df


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--log-dir", nargs="+", default=["logs"],
                    help="directories to scan for .eval logs (default: logs)")
    ap.add_argument("--out", default="results/item_level.csv",
                    help="output CSV path (default: results/item_level.csv)")
    ap.add_argument("--all-runs", action="store_true",
                    help="keep every run, not just the latest per (model, task)")
    args = ap.parse_args()

    df = extract(args.log_dir, all_runs=args.all_runs)
    if df.empty:
        print(f"No usable .eval logs found under {args.log_dir}", file=sys.stderr)
        return 1

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(out_path, index=False)

    n_models = df["model"].nunique()
    n_items = df["item_id"].nunique()
    tasks = sorted(df["task"].unique())
    print(f"Wrote {len(df)} rows to {out_path}")
    print(f"  {n_models} models | {n_items} items | {df['tom_dimension'].nunique()} dimensions | tasks={tasks}")
    print()

    print("Per-(family, tier) release counts:")
    for family in FAMILY_ORDER:
        fam_df = df[df["family"] == family]
        if fam_df.empty:
            continue
        tiers = fam_df.groupby("tier")["model"].nunique()
        parts = ", ".join(f"{t}: {n}" for t, n in tiers.items())
        print(f"  {family}: {parts}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
