"""Custom Inspect scorer for DevToM-OpenRouter free-response ToM items.

Ported verbatim from the sibling devtom-eval project's src/scorer.py, with one
change relevant to open-weight models: the grader model can be pinned via the
`DEVTOM_GRADER_MODEL` environment variable (falling back to the model under
test, matching Inspect's model_graded_qa default).

Why the env override matters here: this project evaluates small open-weight
models (down to 1-3B). Letting a 3B model grade its own free-text ToM reasoning
against a rubric is unreliable — grading is a harder task than answering. Set
`DEVTOM_GRADER_MODEL` to one strong, policy-compliant judge (e.g. a large
ZDR-routed open model, or a frontier model on a direct provider) so every
model under test is graded by the *same* fixed judge. That both improves
grading quality and removes a confound: a release-over-release accuracy trend
should reflect the model getting better at ToM, not getting better at grading
itself.

## Cross-family grading (avoiding LLM-judge self-preference bias)

An LLM judge systematically favors outputs from its own model *family*, not just
its own outputs (family bias is distinct from individual self-preference and is
reduced by an out-of-family judge — arXiv 2410.21819). Since the strong open
judges available under ZDR routing are themselves panel families (e.g. a Llama
judge, and Llama is also a subject family), grading every family with one judge
would bias whichever family the judge belongs to.

So grading uses TWO judges and never lets a family judge itself:
  - `DEVTOM_GRADER_MODEL` — the PRIMARY judge, used for every subject NOT in the
    primary judge's own family.
  - `DEVTOM_GRADER_MODEL_SAMEFAMILY` — the ALTERNATE judge, used only when the
    subject shares the primary judge's family.
E.g. primary = meta-llama/llama-3.3-70b-instruct (Llama), alternate =
nvidia/nemotron-3-super-120b-a12b (not a panel family): all non-Llama subjects
are graded by the Llama judge; Llama subjects are graded by Nemotron. No subject
is ever graded by a judge of its own family. The chosen judge is recorded on each
Score's metadata (`grader`) for the audit trail.

Trade-off: the primary judge's family is graded by a different judge than the
rest, so cross-family *absolute* score comparisons are judge-confounded — but the
study is about within-family release-over-release trends, each family graded by
one consistent judge, so trajectory conclusions stay clean. If
`DEVTOM_GRADER_MODEL_SAMEFAMILY` is unset, the primary judge grades everyone.

The grader is retrieved through src/openrouter.py's no-training/ZDR routing
when it is an `openrouter/*` model, so the judge call obeys the same privacy
policy as the calls under test.

tom_free_response_scorer: a grader model compares the candidate's free-text
answer to the item's reference answer (the Sample's target) plus an optional
per-item rubric (Sample.metadata["rubric"]), and must end its reply with a
literal "GRADE: C/I" token, mirroring Inspect's own model_graded_qa convention
so the parsing logic is predictable. Strict binary grading, no partial credit.
"""
from __future__ import annotations

import os
import re

from inspect_ai.model import GenerateConfig, get_model
from inspect_ai.scorer import (
    CORRECT,
    INCORRECT,
    Score,
    Scorer,
    Target,
    accuracy,
    scorer,
    stderr,
)
from inspect_ai.solver import TaskState

from src.openrouter import openrouter_model_args
from src.roster import AUTHOR_TO_FAMILY, _BY_MODEL

GRADER_ENV_VAR = "DEVTOM_GRADER_MODEL"
SAMEFAMILY_GRADER_ENV_VAR = "DEVTOM_GRADER_MODEL_SAMEFAMILY"
GRADER_MAX_TOKENS_ENV = "DEVTOM_GRADER_MAX_TOKENS"

# Cap the grader's own output. Without this the grader.generate() call below uses
# the model's default max_tokens (32k-65k); OpenRouter reserves credits for that
# full amount up front, so on a limited key the *grading* call 402s even though a
# verdict is only a sentence or two. The `--max-tokens` flag on the runners sets
# generation config for the model UNDER TEST, not this independently-fetched
# grader, so the cap has to live here. 8192 leaves ample room for a reasoning
# judge's chain-of-thought plus the final "GRADE:" line while staying well under
# a small key's per-request budget. Override with DEVTOM_GRADER_MAX_TOKENS.
DEFAULT_GRADER_MAX_TOKENS = 8192


def _grader_max_tokens() -> int:
    raw = os.getenv(GRADER_MAX_TOKENS_ENV)
    if raw:
        try:
            return int(raw)
        except ValueError:
            pass
    return DEFAULT_GRADER_MAX_TOKENS


# How many times to (re)call the grader when its reply lacks a parseable GRADE
# token — see the retry loop in score(). 3 comfortably covers transient provider
# truncations without materially adding cost (retries only fire on the rare miss).
GRADE_PARSE_ATTEMPTS = 3

GRADER_TEMPLATE = """You are grading a short free-text answer to a theory-of-mind reasoning question. Judge whether the SUBMITTED ANSWER reaches the same conclusion and reasoning as the REFERENCE ANSWER — exact wording does not need to match.

[BEGIN QUESTION]
{question}
[END QUESTION]

[BEGIN REFERENCE ANSWER]
{reference}
[END REFERENCE ANSWER]

[BEGIN RUBRIC]
{rubric}
[END RUBRIC]

[BEGIN SUBMITTED ANSWER]
{answer}
[END SUBMITTED ANSWER]

Grade the submitted answer against the rubric. This is strict, all-or-nothing grading — there is no partial credit:
- C (Correct): reaches the same conclusion as the reference AND fully includes the required reasoning from the rubric. Every criterion in the rubric must be met.
- I (Incorrect): anything short of that — wrong conclusion, missing or vague reasoning, reasoning that only partly satisfies the rubric, no answer, or a refusal. If you are unsure whether a criterion is fully met, grade it Incorrect.

First give a one-sentence justification, then end your reply with exactly one line of the form:
GRADE: $LETTER
where $LETTER is one of C, I.
"""

_GRADE_RE = re.compile(r"GRADE:\s*([CI])", re.IGNORECASE)
_LETTER_TO_VALUE = {"C": CORRECT, "I": INCORRECT}
_LETTER_TO_LABEL = {"C": "Correct", "I": "Incorrect"}


def _family_of(model_str: str | None) -> str | None:
    """Panel family label for a model string, or None if not a known panel author.

    Prefers the roster's exact-slug lookup; falls back to parsing the OpenRouter
    author segment (e.g. 'openrouter/meta-llama/llama-3.2-3b-instruct' -> Llama).
    Reuses src.roster's registry so family logic stays in one place.
    """
    if not model_str:
        return None
    entry = _BY_MODEL.get(model_str)
    if entry is not None:
        return entry.family
    # Strip whichever router prefix is present so the author segment is recoverable:
    # 'openrouter/' for the remote roster, 'openai-api/local/' for the self-hosted
    # (devtom-selfhost) models. Without the local prefix here, local subjects would
    # resolve to family None and defeat the cross-family grading scheme.
    tail = model_str
    for prefix in ("openai-api/local/", "openrouter/"):
        if tail.startswith(prefix):
            tail = tail[len(prefix):]
            break
    author = tail.split("/", 1)[0] if "/" in tail else ""
    return AUTHOR_TO_FAMILY.get(author)


def _select_grader_name(grader_model: str | None, subject_model: str | None) -> str | None:
    """Pick the grader model NAME (None => the subject grades itself).

    Precedence: explicit arg > cross-family env scheme > DEVTOM_GRADER_MODEL >
    self-grade. Cross-family scheme: if DEVTOM_GRADER_MODEL_SAMEFAMILY is set and
    the subject shares the PRIMARY judge's family, use the same-family alternate,
    so no subject is graded by a judge of its own family. Pure/testable — does no
    network or model construction.
    """
    if grader_model:
        return grader_model
    primary = os.getenv(GRADER_ENV_VAR)
    if primary is None:
        return None  # default: the model being evaluated grades itself
    alternate = os.getenv(SAMEFAMILY_GRADER_ENV_VAR)
    if alternate:
        primary_family = _family_of(primary)
        subject_family = _family_of(subject_model)
        if primary_family is not None and subject_family == primary_family:
            return alternate
    return primary


def _resolve_grader(grader_model: str | None, subject_model: str | None = None):
    """Fetch the grader model chosen by _select_grader_name.

    An openrouter/* grader is routed through the same no-training/ZDR provider
    prefs as the models under test; anything else (a direct-provider judge) is
    fetched plainly.
    """
    name = _select_grader_name(grader_model, subject_model)
    if name is None:
        return get_model()  # default: the model being evaluated grades itself
    if name.startswith("openrouter/"):
        return get_model(name, **openrouter_model_args())
    return get_model(name)


@scorer(metrics=[accuracy(), stderr()])
def tom_free_response_scorer(grader_model: str | None = None) -> Scorer:
    """Model-graded scorer for open-ended ToM items.

    Every Score carries a non-empty `explanation`: normally the grader model's
    own justification (elicited by GRADER_TEMPLATE before its GRADE line); if
    the grader's reply still lacks a parseable GRADE token after
    GRADE_PARSE_ATTEMPTS retries (transient truncations usually recover on
    replay), a note saying so plus the raw grader output, so a verdict is never
    left silent. Score.metadata["grader"] records which judge graded the sample.

    Args:
        grader_model: explicit grader override. If None (the default), grading
            follows the cross-family env scheme (DEVTOM_GRADER_MODEL +
            DEVTOM_GRADER_MODEL_SAMEFAMILY; see module docstring), falling back to
            the model under evaluation if neither is set.
    """

    async def score(state: TaskState, target: Target) -> Score:
        subject_model = str(state.model)
        grader_name = _select_grader_name(grader_model, subject_model)
        grader = _resolve_grader(grader_model, subject_model)
        rubric = state.metadata.get(
            "rubric", "(no additional rubric — grade against the reference answer alone)"
        )
        prompt = GRADER_TEMPLATE.format(
            question=state.input_text,
            reference=target.text,
            rubric=rubric,
            answer=state.output.completion,
        )

        # Retry when the grader's reply lacks a parseable GRADE token. A missing
        # token is usually a transient truncation (the provider cutting the reply
        # before the final "GRADE:" line), not genuine format refusal — replays
        # recover reliably. Without this, a rare truncation silently becomes an
        # auto-Incorrect and biases accuracy DOWN across ~thousands of grades.
        verdict = ""
        match = None
        for _ in range(GRADE_PARSE_ATTEMPTS):
            result = await grader.generate(
                prompt,
                # temperature=0: verdicts are judgments, not samples — deterministic
                # grading makes reruns reproducible and removes sampling noise from
                # the C/I decision.
                config=GenerateConfig(max_tokens=_grader_max_tokens(), temperature=0.0),
            )
            verdict = result.completion.strip()
            match = _GRADE_RE.search(verdict)
            if match:
                break

        if match:
            letter = match.group(1).upper()
            explanation = f"[{_LETTER_TO_LABEL[letter]}] {verdict}"
        else:
            letter = "I"
            explanation = (
                f"[Incorrect — auto-graded] The grader model's reply did not include a "
                f"parseable 'GRADE: C/I' token after {GRADE_PARSE_ATTEMPTS} attempts, so this "
                f"was marked incorrect by default. Raw grader output:\n{verdict}"
            )

        return Score(
            value=_LETTER_TO_VALUE[letter],
            answer=state.output.completion,
            explanation=explanation,
            # Record which judge graded this sample (cross-family scheme) for the
            # research audit trail; "self" when the subject grades itself.
            metadata={"grader": grader_name or "self"},
        )

    return score
