"""Inspect eval: 12-dimension theory-of-mind MCQ/true-false benchmark (OpenRouter).

Same 124-item, 12-dimension ToM instrument as the sibling devtom-eval project
(diverse desires, diverse beliefs, knowledge access, first-/second-order false
belief, hidden emotion, emotion recognition, sarcasm, irony, faux pas, white
lies, intention vs. accident), scored with Inspect's built-in multiple_choice
solver + choice scorer. Each sample's metadata carries "tom_dimension", so the
task reports accuracy/stderr per dimension via src/metrics.py's
dimension_breakdown_metrics(). This project runs it across OPEN-WEIGHT model
families served through OpenRouter (Llama, Qwen, DeepSeek, Mistral, Gemma),
oldest release to newest, to trace developmental ToM trajectories within each
family — see docs/models.md and scripts/4_analyze/.

Routing note: pass the no-training/ZDR provider preferences on the model with
`-M provider='{...}'` (see src/openrouter.py and the runAll shell scripts).

Run with:
. activate your env &&
    inspect eval scripts/3_runAll/tom_12dim_mcq.py \
        --model openrouter/meta-llama/llama-3.1-8b-instruct \
        -M provider='{"data_collection":"deny","zdr":true}' --limit 1
"""

import sys
from pathlib import Path

# inspect eval's module loader execs this file directly without adding the
# project root to sys.path, so `import src` needs an explicit assist here.
PROJECT_ROOT = Path(__file__).parent.parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from inspect_ai import Task, task
from inspect_ai.dataset import json_dataset
from inspect_ai.scorer import choice
from inspect_ai.solver import multiple_choice

from src.metrics import dimension_breakdown_metrics

DATA_PATH = PROJECT_ROOT / "data" / "12dimToM_mcq_dataset.jsonl"


@task
def tom_12dim_mcq() -> Task:
    """12-dimension ToM MCQ/true-false task: built-in solver + scorer, per-dimension metrics."""
    return Task(
        dataset=json_dataset(str(DATA_PATH)),
        solver=multiple_choice(),
        scorer=choice(),
        metrics=dimension_breakdown_metrics(),
    )
