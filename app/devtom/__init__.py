"""Shared library for the DevToM Streamlit app.

    constants.py  the instrument: 12 dimensions, age bands, thresholds
    theme.py      colors (frozen from src/roster.py) and the Plotly template
    data.py       cached loaders over the app/data/ snapshot
    compute.py    Python ports of the R pipeline's derived quantities
    charts.py     the figures
    ui.py         claim banners, filters, caveat panels
"""

__all__ = ["constants", "theme", "data", "compute", "charts", "ui"]
