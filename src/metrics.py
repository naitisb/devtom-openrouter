"""Shared Inspect metrics for DevToM-Eval.

dimension_breakdown_metrics: attaches Inspect's built-in grouped() metric
to a task so each eval run reports accuracy (and stderr) broken out by
ToM dimension, alongside the usual overall accuracy — the per-item
"tom_dimension" metadata that src/scorer.py's tom_free_response_scorer and
both 12-dimension datasets already carry. Pass this to a Task's `metrics=`
kwarg: `Task(..., metrics=dimension_breakdown_metrics())`. Note this
*replaces* rather than supplements the scorer's own default metrics
(Inspect's Task.metrics docs: "overrides the metrics provided by the
specified scorer"), which is why accuracy()/stderr() are included below
alongside the grouped breakdown rather than assumed to still be present.
"""
from __future__ import annotations

from inspect_ai.scorer import Metric, accuracy, grouped, stderr

DIMENSION_METADATA_KEY = "tom_dimension"


def dimension_breakdown_metrics() -> list[Metric]:
    return [
        accuracy(),
        stderr(),
        grouped(accuracy(), DIMENSION_METADATA_KEY, all=False, name_template="accuracy/{group_name}"),
        grouped(stderr(), DIMENSION_METADATA_KEY, all=False, name_template="stderr/{group_name}"),
    ]
