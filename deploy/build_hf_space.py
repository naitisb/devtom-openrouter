"""Assemble a deployable Hugging Face Space from `app/`.

The Space is a *derived artifact*, not a fork. Everything it contains is copied
from `app/`, with two deliberate transformations applied on the way out:

1. **The item-disclosure escape hatch is removed.** `app/` keeps
   `DEVTOM_REVEAL_ITEMS` so you can browse the full item bank while working
   locally. A public Space must not carry that switch — not because the env var
   would be easy to set (it wouldn't), but because a deployed instance should
   have no code path that renders all 184 validated items as a crawlable page.
   The build rewrites `REVEAL_ALL_ITEMS` to a literal `False`, drops the now
   unused `os` import, and deletes the branch in `views/instrument.py` that
   exists only to warn about the flag. It then *verifies* the result.

2. **The layout is flattened.** Spaces run from the repository root, so
   `app/streamlit_app.py` becomes `streamlit_app.py` with `devtom/`, `views/`
   and `data/` as siblings. No code change is needed: every path in the app is
   resolved relative to `__file__` or to the entrypoint's directory.

`app/prepare_data.py` is deliberately left out — it imports from `src/`, which
does not exist in the Space. The Space ships the snapshot that
`prepare_data.py` produced; rebuild it with `make app-data` and re-run this
script to refresh.

Usage:

    python deploy/build_hf_space.py                 # -> build/hf-space
    python deploy/build_hf_space.py --out /tmp/spc  # somewhere else
    python deploy/build_hf_space.py --git           # also init/commit the repo
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import textwrap
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
APP_DIR = REPO_ROOT / "app"
DEFAULT_OUT = REPO_ROOT / "build" / "hf-space"

# Hugging Face no longer offers a first-class Streamlit SDK — the Spaces API
# accepts only "gradio", "docker" or "static". Streamlit apps therefore ship as
# Docker Spaces, which is what this script generates: a Dockerfile plus
# `sdk: docker` / `app_port` in the README frontmatter.
#
# Pinned to the versions the app was built and verified against.
STREAMLIT_VERSION = "1.64.0"
PYTHON_VERSION = "3.10"
APP_PORT = 7860  # the port Spaces routes to by default

SPACE_TITLE = "DevToM"
SPACE_EMOJI = "🪜"
# Where this Space is published. Only used to print exact push instructions —
# the build never contacts Hugging Face.
HF_OWNER = "naitisb"
HF_SPACE_NAME = "devtom-tom-eval"
SPACE_SHORT_DESCRIPTION = (
    "Do language models acquire theory of mind in the order children do?"
)
GITHUB_URL = "https://github.com/naitisb/devtom-openrouter"
ESSAY_URL = "https://naiti.substack.com/p/towards-a-mental-model-for-understanding"

# Copied verbatim from app/ into the Space root.
COPY_ITEMS = ("streamlit_app.py", "devtom", "views", "data")

EXCLUDE = shutil.ignore_patterns("__pycache__", "*.pyc", ".DS_Store")


class BuildError(RuntimeError):
    """A transformation did not match. Never emit a half-patched Space."""


# --- Transformation 1: constants.py ----------------------------------------
CONSTANTS_OLD = '''# Set DEVTOM_REVEAL_ITEMS=1 to browse the full bank — intended for local work,
# never for a deployed instance.
REVEAL_ALL_ITEMS: bool = os.environ.get("DEVTOM_REVEAL_ITEMS", "").strip().lower() in {
    "1",
    "true",
    "yes",
}


def item_is_disclosed(item_id: str) -> bool:
    return REVEAL_ALL_ITEMS or item_id in WORKED_EXAMPLE_IDS
'''

CONSTANTS_NEW = '''# This is the deployed build. There is no switch to reveal the full bank, by
# construction: the only items whose text this app can render are the worked
# examples above. The development copy in the source repository has a local
# override; it is stripped by deploy/build_hf_space.py.
REVEAL_ALL_ITEMS: bool = False


def item_is_disclosed(item_id: str) -> bool:
    return item_id in WORKED_EXAMPLE_IDS
'''


def patch_constants(text: str) -> str:
    if CONSTANTS_OLD not in text:
        raise BuildError(
            "app/devtom/constants.py no longer contains the expected "
            "disclosure block. Update CONSTANTS_OLD in this script — do not "
            "ship a Space whose disclosure behaviour has not been checked."
        )
    text = text.replace(CONSTANTS_OLD, CONSTANTS_NEW, 1)

    # `os` was imported solely for the env lookup that just went away.
    if re.search(r"\bos\.", text):
        raise BuildError("`os` is still used in constants.py; leaving the import.")
    text, n = re.subn(r"^import os\n\n", "", text, count=1, flags=re.MULTILINE)
    if n != 1:
        raise BuildError("could not drop the now-unused `import os`.")
    return text


# --- Transformation 2: views/instrument.py ---------------------------------
INSTRUMENT_HEADER = '''    if K.REVEAL_ALL_ITEMS:
        st.warning(
            "`DEVTOM_REVEAL_ITEMS` is set, so the full stimulus text is shown "
            "for every item. Do not run a public instance this way.",
            icon=":material/lock_open:",
        )
    else:
'''


def patch_instrument(text: str) -> str:
    """Delete the flag-warning branch and promote the `else:` body one level."""
    if INSTRUMENT_HEADER not in text:
        raise BuildError(
            "views/instrument.py no longer contains the expected "
            "REVEAL_ALL_ITEMS branch. Update INSTRUMENT_HEADER in this script."
        )
    start = text.index(INSTRUMENT_HEADER)
    body_start = start + len(INSTRUMENT_HEADER)

    # The else-body runs until indentation returns to 4 spaces or less.
    lines = text[body_start:].splitlines(keepends=True)
    body: list[str] = []
    for line in lines:
        if line.strip() and not line.startswith(" " * 8):
            break
        body.append(line)
    if not body:
        raise BuildError("the REVEAL_ALL_ITEMS else-branch appears to be empty.")

    dedented = textwrap.dedent("".join(body))
    reindented = "".join(
        ("    " + ln if ln.strip() else ln) for ln in dedented.splitlines(keepends=True)
    )
    return text[:start] + reindented + text[body_start + len("".join(body)) :]


# --- README ----------------------------------------------------------------
def space_readme() -> str:
    return f"""---
title: {SPACE_TITLE}
emoji: {SPACE_EMOJI}
colorFrom: gray
colorTo: indigo
sdk: docker
app_port: {APP_PORT}
pinned: false
license: mit
short_description: {SPACE_SHORT_DESCRIPTION}
tags:
  - theory-of-mind
  - evaluation
  - developmental-psychology
  - interpretability
---

# DevToM

**Do language models acquire theory of mind in the order children do?**

An interactive companion to [*Towards a Mental Model for Understanding Machine
Reasoning*]({ESSAY_URL}).

28 models across 5 families were evaluated on 184 items spanning 12
theory-of-mind dimensions, each anchored to the age band at which children
typically acquire it. Every item was administered twice — once as multiple
choice, once as free response.

The headline result is that the answer depends on the format. In multiple
choice, the human developmental ordering organizes model performance
significantly better than chance. In free response, among models that still
have room to vary, **not one** produces a developmental profile that climbs
monotonically, and the typical model's largest backward step is close to four
age-equivalent years.

The app also turns the instrument on itself: the developmental scale is
essentially unidimensional and radically parsimonious, but it does *not*
predict better than simply knowing a model's overall accuracy, and it does not
transfer across elicitation formats. Those failures are reported alongside the
successes.

## A note on the items

The **Browse items** tab shows every item's metadata, difficulty and
discrimination, but the stimulus text only for two worked examples. These are
validated instruments from the developmental literature, and rendering the full
bank as a crawlable page would feed it to the next generation of training
crawlers — the outcome the study's zero-data-retention routing policy was
chosen to avoid at evaluation time. Anyone reproducing the study reads the
datasets directly from the source repository.

## Source

Code, data and the full analysis pipeline: [{GITHUB_URL.split('//')[1]}]({GITHUB_URL})

This Space is built from that repository's `app/` directory by
`deploy/build_hf_space.py`; edit it there rather than here.
"""


SPACE_GITIGNORE = """__pycache__/
*.pyc
.DS_Store
"""

SPACE_DOCKERIGNORE = """.git
.gitignore
__pycache__
*.pyc
.DS_Store
"""


def dockerfile() -> str:
    return f"""# Hugging Face Spaces has no first-class Streamlit SDK — the API accepts only
# "gradio", "docker" or "static" — so this runs as a Docker Space. Spaces
# execute the container as uid 1000 and route traffic to the `app_port`
# declared in README.md.
#
# Generated by deploy/build_hf_space.py in naitisb/devtom-openrouter.
FROM python:{PYTHON_VERSION}-slim

RUN useradd --create-home --uid 1000 user
USER user

ENV HOME=/home/user \\
    PATH=/home/user/.local/bin:$PATH \\
    PYTHONUNBUFFERED=1 \\
    PYTHONDONTWRITEBYTECODE=1 \\
    STREAMLIT_SERVER_PORT={APP_PORT} \\
    STREAMLIT_SERVER_ADDRESS=0.0.0.0 \\
    STREAMLIT_SERVER_HEADLESS=true \\
    STREAMLIT_SERVER_FILE_WATCHER_TYPE=none \\
    STREAMLIT_BROWSER_GATHER_USAGE_STATS=false

WORKDIR $HOME/app

# Dependencies first so edits to the app do not invalidate the pip layer.
COPY --chown=user:user requirements.txt ./
RUN pip install --no-cache-dir --upgrade pip \\
 && pip install --no-cache-dir -r requirements.txt

COPY --chown=user:user . ./

EXPOSE {APP_PORT}

HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \\
  CMD python -c "import sys,urllib.request; \\
sys.exit(0 if urllib.request.urlopen('http://localhost:{APP_PORT}/_stcore/health', timeout=4).status == 200 else 1)"

CMD ["streamlit", "run", "streamlit_app.py"]
"""


# --- Build -----------------------------------------------------------------
def build(out: Path) -> Path:
    if not (APP_DIR / "data" / "item_level.parquet").exists():
        raise BuildError(
            "app/data is missing or empty. Build the snapshot first:\n"
            "    python app/prepare_data.py"
        )

    if out.exists():
        # Preserve an existing .git so repeated builds keep the Space history.
        git_dir = out / ".git"
        keep = None
        if git_dir.exists():
            keep = out.parent / f".{out.name}.git.keep"
            if keep.exists():
                shutil.rmtree(keep)
            shutil.move(str(git_dir), str(keep))
        shutil.rmtree(out)
        out.mkdir(parents=True)
        if keep is not None:
            shutil.move(str(keep), str(out / ".git"))
    else:
        out.mkdir(parents=True)

    for name in COPY_ITEMS:
        src = APP_DIR / name
        dest = out / name
        if src.is_dir():
            shutil.copytree(src, dest, ignore=EXCLUDE)
        else:
            shutil.copy2(src, dest)

    # Streamlit theme lives at the repo root in both layouts.
    theme_src = REPO_ROOT / ".streamlit" / "config.toml"
    if theme_src.exists():
        (out / ".streamlit").mkdir(exist_ok=True)
        shutil.copy2(theme_src, out / ".streamlit" / "config.toml")

    # Pin Streamlit to the verified version and drop the source repo's header,
    # which describes a layout the Space does not have.
    reqs = (APP_DIR / "requirements.txt").read_text(encoding="utf-8")
    reqs = re.sub(r"\A(?:#.*\n)+", "", reqs)
    reqs = re.sub(
        r"^streamlit>=.*$",
        f"streamlit=={STREAMLIT_VERSION}  # must match sdk_version in README.md",
        reqs,
        count=1,
        flags=re.MULTILINE,
    )
    header = (
        "# Generated by deploy/build_hf_space.py in naitisb/devtom-openrouter.\n"
        "# Edit app/requirements.txt there, not this file.\n"
    )
    (out / "requirements.txt").write_text(header + reqs, encoding="utf-8")

    # The two transformations.
    constants = out / "devtom" / "constants.py"
    constants.write_text(
        patch_constants(constants.read_text(encoding="utf-8")), encoding="utf-8"
    )
    instrument = out / "views" / "instrument.py"
    instrument.write_text(
        patch_instrument(instrument.read_text(encoding="utf-8")), encoding="utf-8"
    )

    (out / "README.md").write_text(space_readme(), encoding="utf-8")
    (out / ".gitignore").write_text(SPACE_GITIGNORE, encoding="utf-8")
    (out / ".dockerignore").write_text(SPACE_DOCKERIGNORE, encoding="utf-8")
    (out / "Dockerfile").write_text(dockerfile(), encoding="utf-8")
    return out


def verify(out: Path) -> None:
    """Fail loudly rather than publish a Space with the hatch still in it."""
    # The Space contract: a Dockerfile, and frontmatter that matches it.
    if not (out / "Dockerfile").exists():
        raise BuildError("no Dockerfile was written.")
    readme = (out / "README.md").read_text(encoding="utf-8")
    for required in ("sdk: docker", f"app_port: {APP_PORT}"):
        if required not in readme:
            raise BuildError(f"README frontmatter is missing `{required}`.")
    if "sdk: streamlit" in readme:
        raise BuildError(
            "README declares `sdk: streamlit`, which the Spaces API rejects "
            '(it accepts only "gradio", "docker" or "static").'
        )
    docker_text = (out / "Dockerfile").read_text(encoding="utf-8")
    if f"EXPOSE {APP_PORT}" not in docker_text:
        raise BuildError(f"Dockerfile does not EXPOSE {APP_PORT}.")

    offenders = []
    for path in out.rglob("*.py"):
        text = path.read_text(encoding="utf-8", errors="replace")
        if "DEVTOM_REVEAL_ITEMS" in text or "os.environ" in text:
            offenders.append(path.relative_to(out))
    if offenders:
        raise BuildError(
            "escape hatch still present in: "
            + ", ".join(str(p) for p in offenders)
        )

    # Everything must still compile.
    result = subprocess.run(
        [sys.executable, "-m", "compileall", "-q", str(out)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise BuildError(f"built Space does not compile:\n{result.stdout}{result.stderr}")

    # And the disclosure behaviour must actually be locked.
    probe = (
        "import sys; sys.path.insert(0, %r)\n"
        "from devtom import constants as K\n"
        "assert K.REVEAL_ALL_ITEMS is False, 'REVEAL_ALL_ITEMS is not False'\n"
        "assert K.item_is_disclosed('DD_01'), 'worked example not disclosed'\n"
        "assert not K.item_is_disclosed('FP_01'), 'FP_01 leaked'\n"
        "import os; os.environ['DEVTOM_REVEAL_ITEMS'] = '1'\n"
        "import importlib; importlib.reload(K)\n"
        "assert K.REVEAL_ALL_ITEMS is False, 'env var still flips the flag'\n"
        "assert not K.item_is_disclosed('FP_01'), 'env var still leaks items'\n"
        "print('OK')\n" % str(out)
    )
    result = subprocess.run(
        [sys.executable, "-c", probe], capture_output=True, text=True, cwd=str(out)
    )
    if result.returncode != 0 or "OK" not in result.stdout:
        raise BuildError(
            f"disclosure lock failed verification:\n{result.stdout}{result.stderr}"
        )

    for cleanup in out.rglob("__pycache__"):
        shutil.rmtree(cleanup, ignore_errors=True)


def git_init(out: Path) -> None:
    if not (out / ".git").exists():
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=out, check=True)
    subprocess.run(["git", "add", "-A"], cwd=out, check=True)
    status = subprocess.run(
        ["git", "status", "--porcelain"], cwd=out, capture_output=True, text=True
    )
    if not status.stdout.strip():
        print("  git: nothing to commit, Space is unchanged")
        return
    subprocess.run(
        ["git", "commit", "-q", "-m", "Build DevToM Space from app/"],
        cwd=out,
        check=True,
    )
    print("  git: committed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument(
        "--git", action="store_true", help="init the Space repo and commit the build"
    )
    args = parser.parse_args()

    try:
        out = build(args.out.resolve())
        verify(out)
    except BuildError as exc:
        print(f"BUILD FAILED: {exc}", file=sys.stderr)
        return 1

    if args.git:
        git_init(out)

    size = sum(f.stat().st_size for f in out.rglob("*") if f.is_file() and ".git" not in f.parts)
    files = sum(1 for f in out.rglob("*") if f.is_file() and ".git" not in f.parts)
    print(f"\nSpace built: {out}")
    print(f"  {files} files, {size / 1_048_576:.1f} MB")
    print(f"  docker Space on port {APP_PORT}")
    print(f"  python {PYTHON_VERSION}, streamlit {STREAMLIT_VERSION}")
    print("  escape hatch: removed and verified")
    repo_id = f"{HF_OWNER}/{HF_SPACE_NAME}"
    print(
        "\nCheck the container locally first (needs the Docker daemon):\n"
        f"    docker build -t devtom-space {out}\n"
        f"    docker run --rm -p {APP_PORT}:{APP_PORT} devtom-space\n"
        "\nTo publish (creates the Space if it does not exist yet):\n"
        f"    hf repos create {repo_id} --type space --sdk docker\n"
        f"    cd {out}\n"
        f"    git remote add origin https://huggingface.co/spaces/{repo_id}\n"
        "    git push -u origin main\n"
        f"\nAfter the first push, `git push` from {out.name} is enough.\n"
        f"Live at: https://huggingface.co/spaces/{repo_id}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
