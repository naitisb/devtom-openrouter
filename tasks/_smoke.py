"""Smoke test (Spike 0.2 / T0.2.3): confirm Inspect runs end-to-end and writes a log.

Run:
    inspect eval tasks/_smoke.py --model anthropic/claude-3-5-sonnet-latest --limit 5
    inspect view        # then open http://localhost:7575

This is a TEMPLATE — confirm imports/signatures against your installed inspect-ai
version (see docs/inspect_notes.md). It uses the standard MCQ pattern:
multiple_choice() solver + choice() scorer, with the gold answer as a LETTER.
"""
from inspect_ai import Task, task
from inspect_ai.dataset import Sample
from inspect_ai.solver import multiple_choice
from inspect_ai.scorer import choice

# Five trivially-correct items: a green run proves the harness works, not the model.
_SAMPLES = [
    Sample(input="What is 2 + 2?", choices=["3", "4", "5"], target="B"),
    Sample(input="Which is a mammal?", choices=["Trout", "Dog", "Sparrow"], target="B"),
    Sample(input="What color is a clear daytime sky?", choices=["Green", "Blue", "Red"], target="B"),
    Sample(input="How many legs does a spider have?", choices=["6", "8", "10"], target="B"),
    Sample(input="Which is largest?", choices=["Ant", "Elephant", "Mouse"], target="B"),
]


@task
def smoke():
    return Task(
        dataset=_SAMPLES,
        solver=[multiple_choice()],
        scorer=choice(),
    )
