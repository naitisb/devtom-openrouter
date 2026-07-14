"""Tag each dataset item with its developmental construct (`tom_construct`).

Adds a `tom_construct` field to `metadata` in the 12-dimension MCQ and
free-response datasets, derived from each item's existing `tom_dimension` via the
canonical map in src/constructs.py. This makes the construct hierarchy a real,
queryable field in the INPUT datasets (it was previously a docs-only grouping) so
that downstream tooling — and the eval logs themselves, which carry sample
metadata through — can group by construct without re-deriving it.

Idempotent: re-running updates the field in place (and re-verifies it), so it's
safe to run after editing the map. Writes a timestamped backup of each file
before modifying it. Preserves key order (tom_construct is inserted right after
tom_dimension) and does not touch any other field.

    python scripts/0_prep/add_construct_to_datasets.py            # tag in place (+ backup)
    python scripts/0_prep/add_construct_to_datasets.py --check    # verify only, no writes
"""
from __future__ import annotations

import argparse
import datetime
import json
import shutil
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from src.constructs import METADATA_KEY, construct_for_dimension

DATASETS = [
    PROJECT_ROOT / "data" / "12dimToM_mcq_dataset.jsonl",
    PROJECT_ROOT / "data" / "12dimToM_freeresponse_dataset.jsonl",
]
DIMENSION_KEY = "tom_dimension"


def _reordered_metadata(metadata: dict, construct: str) -> dict:
    """Return metadata with tom_construct inserted immediately after tom_dimension,
    preserving the order of all other keys."""
    out: dict = {}
    for k, v in metadata.items():
        if k == METADATA_KEY:
            continue  # drop any existing copy; we re-insert in the canonical spot
        out[k] = v
        if k == DIMENSION_KEY:
            out[METADATA_KEY] = construct
    if METADATA_KEY not in out:  # no tom_dimension key at all — append at end
        out[METADATA_KEY] = construct
    return out


def process_file(path: Path, check_only: bool) -> tuple[int, list[str]]:
    """Returns (n_items, errors). Rewrites `path` in place unless check_only."""
    errors: list[str] = []
    lines_out: list[str] = []
    n = 0
    with path.open() as f:
        for lineno, raw in enumerate(f, 1):
            raw = raw.rstrip("\n")
            if not raw.strip():
                continue
            item = json.loads(raw)
            n += 1
            meta = item.get("metadata", {})
            dim = meta.get(DIMENSION_KEY)
            construct = construct_for_dimension(dim) if dim is not None else None
            if construct is None:
                errors.append(f"{path.name}:{lineno} id={item.get('id')!r} "
                              f"has unmappable {DIMENSION_KEY}={dim!r}")
                lines_out.append(raw)
                continue
            item["metadata"] = _reordered_metadata(meta, construct)
            lines_out.append(json.dumps(item, ensure_ascii=False))

    if not check_only and not errors:
        backup = path.with_name(
            f"{path.stem}_backup_{datetime.datetime.now():%Y%m%d_%H%M%S}{path.suffix}")
        shutil.copy2(path, backup)
        path.write_text("\n".join(lines_out) + "\n")
        print(f"  wrote {n} items to {path.name} (backup: {backup.name})")
    elif check_only:
        # verify every item already has the correct construct
        missing = 0
        with path.open() as f:
            for raw in f:
                if not raw.strip():
                    continue
                meta = json.loads(raw).get("metadata", {})
                want = construct_for_dimension(meta.get(DIMENSION_KEY))
                if meta.get(METADATA_KEY) != want:
                    missing += 1
        status = "OK" if missing == 0 else f"{missing} item(s) missing/wrong {METADATA_KEY}"
        print(f"  {path.name}: {n} items — {status}")
        if missing:
            errors.append(f"{path.name}: {missing} item(s) not tagged")
    return n, errors


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="verify only; do not write")
    args = ap.parse_args()

    all_errors: list[str] = []
    for path in DATASETS:
        if not path.exists():
            print(f"skipping {path.name}: not found", file=sys.stderr)
            continue
        print(f"{'Checking' if args.check else 'Tagging'} {path.name} ...")
        _, errors = process_file(path, check_only=args.check)
        all_errors.extend(errors)

    if all_errors:
        print("\nERRORS:", file=sys.stderr)
        for e in all_errors:
            print(f"  {e}", file=sys.stderr)
        return 1
    print("\nDone." if not args.check else "\nAll items correctly tagged.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
