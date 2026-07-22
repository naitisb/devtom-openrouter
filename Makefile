# DevToM-OpenRouter
.PHONY: setup check smoke run run-mcq run-fr analyze visualize extract profile-dataset profile-results glmm irt viz-descriptives viz-inference viz-mapping viz-accuracy viz-profiles pipeline archive clean freeze

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

analyze: extract profile-dataset profile-results glmm irt ## run all analyses: extract -> profile -> model

# --------------- pipeline stages: 4_statistics -> 5_model -> 6_visualize ---

extract:      ## extract item-level data from .eval logs -> results/item_level.csv
	python scripts/4_statistics/extract_item_level.py

profile-dataset: ## profile the JSONL item banks -> results/stats/dataset/
	python scripts/4_statistics/profile_dataset.py

profile-results: extract ## profile eval outcomes + CTT -> results/stats/results/
	python scripts/4_statistics/profile_results.py

glmm: extract ## fit binomial GLMM trajectory -> results/modeling/inference/
	Rscript scripts/5_model/glmm_trajectory.R

irt: extract  ## fit developmental scaling + IRT -> results/modeling/mapping/
	Rscript scripts/5_model/developmental_scaling_irt.R

visualize: viz-descriptives viz-inference viz-mapping viz-accuracy viz-profiles ## run all visualization scripts

viz-descriptives: profile-dataset profile-results ## descriptive figures
	Rscript scripts/6_visualize/visualize_descriptives.R

viz-inference: glmm ## GLMM trajectory figures
	Rscript scripts/6_visualize/visualize_glmm_trajectory.R

viz-mapping: irt ## developmental mapping figures
	Rscript scripts/6_visualize/visualize_developmental_mapping.R

viz-accuracy: extract ## accuracy vs release date figures
	Rscript scripts/6_visualize/visualize_accuracy_trajectory.R

viz-profiles: extract ## dimension profile heatmaps, rankings, regression grids
	Rscript scripts/6_visualize/visualize_dimension_profiles.R

pipeline: analyze visualize ## full pipeline: analyze then visualize

archive:      ## move old timestamped result folders to results/Archive/
	@mkdir -p results/Archive
	@for d in results/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_*/; do \
		[ -d "$$d" ] && mv "$$d" results/Archive/ && echo "Archived $$d"; \
	done; true

all: setup check smoke run analyze

clean:
	rm -rf .inspect __pycache__ */__pycache__ src/__pycache__ scripts/*/__pycache__
