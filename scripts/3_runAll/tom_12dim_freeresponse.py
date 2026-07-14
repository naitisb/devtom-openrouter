"""Inspect eval: 12-dimension theory-of-mind FREE-RESPONSE benchmark (OpenRouter).

60-item companion to tom_12dim_mcq.py — open-ended "why"/"what does X really
feel or think, and why" questions across the same 12 ToM dimensions, for
reasoning a forced multiple-choice letter would trivialize. Uses a custom
solver (free_response_solver) + a model-graded scorer (tom_free_response_scorer)
that grades against a reference explanation + rubric. Each sample's metadata
carries "tom_dimension", so the task reports accuracy/stderr per dimension via
src/metrics.py's dimension_breakdown_metrics().

Grader: set DEVTOM_GRADER_MODEL to pin one strong, policy-compliant judge for
every model under test (strongly recommended here — a small open model grading
its own ToM reasoning is unreliable, and a shared judge removes a confound).
Optionally set DEVTOM_GRADER_MODEL_SAMEFAMILY for cross-family grading: it grades
only subjects sharing the primary judge's family, so no model is graded by its
own family (avoids LLM-judge self-preference bias). See src/scorer.py. If
DEVTOM_GRADER_MODEL is unset, the model under test grades itself (Inspect's default).

Run with:
. activate your env && export DEVTOM_GRADER_MODEL=openrouter/qwen/qwen-2.5-72b-instruct &&
    inspect eval scripts/3_runAll/tom_12dim_freeresponse.py \
        --model openrouter/meta-llama/llama-3.1-8b-instruct \
        -M provider='{"data_collection":"deny","zdr":true}' --limit 1
"""

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from inspect_ai import Task, task
from inspect_ai.dataset import json_dataset

from src.metrics import dimension_breakdown_metrics
from src.scorer import tom_free_response_scorer
from src.solvers import free_response_solver

DATA_PATH = PROJECT_ROOT / "data" / "12dimToM_freeresponse_dataset.jsonl"


@task
def tom_12dim_freeresponse() -> Task:
    """12-dimension ToM free-response task: custom solver + model-graded scorer, per-dimension metrics."""
    return Task(
        dataset=json_dataset(str(DATA_PATH)),
        solver=free_response_solver(),
        scorer=tom_free_response_scorer(),
        metrics=dimension_breakdown_metrics(),
    )
