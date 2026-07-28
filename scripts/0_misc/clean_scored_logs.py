"""Deduplicate scored/unscored .eval log pairs.

When Inspect grades a free-response eval it writes a new file with a
'-scored' suffix alongside the original:

    <timestamp>_tom-12dim-freeresponse_<id>.eval          ← unscored (no grades)
    <timestamp>_tom-12dim-freeresponse_<id>-scored.eval   ← scored   (has grades)

This script finds every '-scored.eval' file, deletes its unscored twin (if it
still exists), then renames the scored file to drop the '-scored' tag so the
log dir is clean and extract_item_level.py sees exactly one file per run.

    python scripts/0_misc/clean_scored_logs.py
    python scripts/0_misc/clean_scored_logs.py logs ../devtom-selfhost/logs
    python scripts/0_misc/clean_scored_logs.py --dry-run logs ../devtom-selfhost/logs
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

SUFFIX = "-scored"


def clean_dir(log_dir: Path, dry_run: bool) -> tuple[int, int]:
    """Return (renamed, deleted) counts."""
    renamed = deleted = 0
    scored = sorted(log_dir.glob(f"*{SUFFIX}.eval"))
    if not scored:
        return 0, 0

    for scored_path in scored:
        # e.g. foo-scored.eval  →  foo.eval
        clean_name = scored_path.name[: -len(f"{SUFFIX}.eval")] + ".eval"
        clean_path = log_dir / clean_name

        if clean_path.exists():
            if dry_run:
                print(f"  [dry] would delete  {clean_path}")
            else:
                clean_path.unlink()
                print(f"  deleted  {clean_path.name}")
            deleted += 1

        if dry_run:
            print(f"  [dry] would rename  {scored_path.name}  →  {clean_name}")
        else:
            scored_path.rename(clean_path)
            print(f"  renamed  {scored_path.name}  →  {clean_name}")
        renamed += 1

    return renamed, deleted


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("log_dirs", nargs="*", default=["logs", "../devtom-selfhost/logs"],
                    help="Directories to clean (default: logs ../devtom-selfhost/logs)")
    ap.add_argument("--dry-run", action="store_true",
                    help="Print what would happen without touching any files")
    args = ap.parse_args()

    total_renamed = total_deleted = 0
    for raw in args.log_dirs:
        p = Path(raw)
        if not p.is_dir():
            print(f"skipping {raw}: not a directory", file=sys.stderr)
            continue
        print(f"\n{p.resolve()}")
        r, d = clean_dir(p, args.dry_run)
        total_renamed += r
        total_deleted += d
        if r == 0:
            print("  nothing to do")

    tag = " (dry run)" if args.dry_run else ""
    print(f"\ndone{tag}: {total_renamed} renamed, {total_deleted} unscored twins deleted")


if __name__ == "__main__":
    main()
