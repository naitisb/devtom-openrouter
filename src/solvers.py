"""Custom Inspect solvers for DevToM-Eval (Story 2.1's src/solvers.py).

free_response_solver: elicits a short free-text answer for ToM items whose
correct response is an explanation/judgment rather than a discrete option
(e.g. "why did she say that?", "what does he really feel, and why?"),
where forcing a multiple_choice() letter would trivialize the reasoning
being tested. Pairs with src/scorer.py's tom_free_response_scorer.
"""
from __future__ import annotations

from inspect_ai.solver import Generate, Solver, TaskState, solver

FREE_RESPONSE_INSTRUCTIONS = (
    "\n\nAnswer in 1-3 sentences, in your own words. State your conclusion and briefly "
    "explain the reasoning behind it. Do not just restate the scenario."
)


@solver
def free_response_solver(instructions: str = FREE_RESPONSE_INSTRUCTIONS) -> Solver:
    """Appends free-response elicitation instructions to the prompt, then generates.

    Unlike multiple_choice(), this does not format/shuffle answer options or
    parse a letter out of the completion — state.output.completion is passed
    through to the scorer as free text.
    """

    async def solve(state: TaskState, generate: Generate) -> TaskState:
        state.user_prompt.text = state.user_prompt.text + instructions
        return await generate(state)

    return solve
