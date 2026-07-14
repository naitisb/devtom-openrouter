"""OpenRouter connectivity + routing check for DevToM-OpenRouter.

Default: report whether OPENROUTER_API_KEY is present.
With --live: attempt a 1-token generation on one representative model per family,
routed through the no-training/ZDR provider prefs (src/openrouter.py), so you can
confirm both that the key works AND that each family has a policy-compliant route
before spending money on a full sweep. A model that has no ZDR/no-training upstream
fails closed (an error rather than a silent fallback) — that's the desired behavior,
and this check surfaces it per family.

    python scripts/1_check-functionality/check_providers.py
    python scripts/1_check-functionality/check_providers.py --live
    python scripts/1_check-functionality/check_providers.py --live --all   # every roster model
"""
import argparse
import asyncio
import os
import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from src.openrouter import openrouter_model_args  # noqa: E402
from src.roster import FAMILY_ORDER, models_for_family, all_models  # noqa: E402

OPENROUTER_ENV = "OPENROUTER_API_KEY"


def load_dotenv_if_present() -> None:
    try:
        from dotenv import load_dotenv  # optional
        load_dotenv()
    except Exception:
        pass


def redact_sensitive_text(text: str) -> str:
    redacted = re.sub(r"(?i)(api[_-]?key|token|authorization|bearer)\s*[:=]\s*[^,\s;]+", r"\1=[REDACTED]", text)
    redacted = re.sub(r"(?i)(sk-[A-Za-z0-9\-]+|AIza[0-9A-Za-z\-_]+)", "[REDACTED]", redacted)
    return redacted[:180]


async def live_check(model_str: str) -> str:
    """Return 'ok' or a short error string, routing through the no-training prefs."""
    try:
        from inspect_ai.model import get_model
        m = get_model(model_str, **openrouter_model_args())
        out = await m.generate("ping", config={"max_tokens": 1})  # type: ignore[func-returns-value]
        return "ok" if out is not None else "no output"
    except Exception as e:  # noqa: BLE001
        return f"error: {type(e).__name__}: {redact_sensitive_text(str(e))}"


def representative_models() -> list[str]:
    """One recent model per family — a cheap way to confirm each family has a route."""
    reps = []
    for fam in FAMILY_ORDER:
        fam_models = models_for_family(fam)
        if fam_models:
            reps.append(fam_models[-1])  # newest in the family
    return reps


async def main_async() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--live", action="store_true", help="attempt a tiny real call")
    ap.add_argument("--all", action="store_true",
                    help="with --live, check every roster model (not just one per family)")
    args = ap.parse_args()

    load_dotenv_if_present()
    has_key = bool(os.getenv(OPENROUTER_ENV))

    print(f"{OPENROUTER_ENV}: {'set' if has_key else 'MISSING'}")
    if not has_key:
        print("\nAdd OPENROUTER_API_KEY to .env (see .env.example).")
        return 1

    if not args.live:
        print("\nKey present. Re-run with --live to verify routing per family.")
        return 0

    models = all_models() if args.all else representative_models()
    print(f"\nLive check ({'all roster models' if args.all else 'one per family'}), "
          f"routed with no-training/ZDR prefs:\n")
    print(f"{'model':<52} live")
    print("-" * 70)
    all_ok = True
    for model_str in models:
        live = await live_check(model_str)
        if live != "ok":
            all_ok = False
        print(f"{model_str:<52} {live}")

    if not all_ok:
        print("\nSome models had no compliant route or errored. A no-route error is the "
              "expected fail-closed behavior for a model with no ZDR/no-training upstream — "
              "drop it from the roster or accept it'll be absent from the plots.")
        return 1
    print("\nAll checked models reachable via a policy-compliant route.")
    return 0


def main() -> int:
    return asyncio.run(main_async())


if __name__ == "__main__":
    sys.exit(main())
