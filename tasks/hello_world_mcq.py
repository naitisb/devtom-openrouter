"""
Hello-world Inspect eval: confirms Task -> Solver -> Scorer -> eval log
plumbing works end-to-end on a 5-item toy MCQ dataset.

Not a real benchmark. Purely a smoke test for the pipeline before 
specific tasks are built on top of it.

Run with: 
. .venv/bin/activate && 
    inspect eval tasks/hello_world_mcq.py --model anthropic/claude-haiku-4-5 --limit 1
    inspect eval tasks/hello_world_mcq.py --model openai/gpt-4.1-nano --limit 1

"""

from pathlib import Path

from inspect_ai import Task, task
from inspect_ai.dataset import json_dataset
from inspect_ai.scorer import choice
from inspect_ai.solver import multiple_choice

DATA_PATH = Path(__file__).parent / "data" / "toy_mcq_dataset.jsonl"


@task
def hello_world_mcq() -> Task:
    """Smoke-test task: 5-item toy MCQ, built-in solver + scorer."""
    return Task(
        dataset=json_dataset(str(DATA_PATH)),
        solver=multiple_choice(),
        scorer=choice(),
    )