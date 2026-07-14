# DevToM-OpenRouter
.PHONY: setup check smoke run run-mcq analyze clean freeze

setup:        ## install deps into a venv
	python3.10 -m venv .venv && . .venv/bin/activate && pip install --upgrade pip setuptools wheel && pip install -r requirements.txt

freeze:       ## refresh requirements.lock.txt from the active env
	. .venv/bin/activate && pip freeze > requirements.lock.txt

check:        ## verify OPENROUTER_API_KEY + per-family routing (add ARGS=--live for a real call)
	python scripts/1_check-functionality/check_providers.py $(ARGS)

smoke:        ## tiny end-to-end hello-world on one model per family
	bash scripts/1_check-functionality/run_hello_world_all_families.sh

run:          ## full sweep: both tasks x whole open-weight roster (ONLY_FAMILY=Qwen to scope)
	bash scripts/3_runAll/run_tom_12dim_all_within_family.sh

run-mcq:      ## cheaper: MCQ task only, whole roster
	bash scripts/2a_runMCQ/run_tom_12dim_mcq_within_family.sh

run-fr:       ## free-response task only, whole roster (model-graded)
	bash scripts/2b_runFR/run_tom_12dim_fr_within_family.sh

analyze:      ## logs -> results/<timestamp>/ CSV + trajectory figures
	python scripts/4_analyze/summarize_visualize_results.py

all: setup check smoke run analyze

clean:
	rm -rf .inspect __pycache__ */__pycache__ src/__pycache__ scripts/*/__pycache__
