# DevToM-OpenRouter
.PHONY: setup check smoke run run-mcq run-fr analyze visualize clean-logs extract profile-dataset profile-results glmm size-glmm irt guttman scale-validity viz-descriptives viz-inference viz-mapping viz-accuracy viz-profiles viz-size viz-guttman viz-coherence viz-scale-validity pipeline archive clean freeze app app-data app-deps hf-space

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

analyze: extract profile-dataset profile-results glmm size-glmm irt guttman scale-validity ## run all analyses: extract -> profile -> model

# --------------- pipeline stages: 4_statistics -> 5_model -> 6_visualize ---

clean-logs:   ## remove unscored FR evals that have a scored twin; strip -scored suffix
	python scripts/0_misc/clean_scored_logs.py logs ../devtom-selfhost/logs

extract: clean-logs ## extract item-level data from .eval logs -> results/item_level.csv
	python scripts/4_statistics/extract_item_level.py --log-dir logs ../devtom-selfhost/logs

profile-dataset: ## profile the JSONL item banks -> results/stats/dataset/
	python scripts/4_statistics/profile_dataset.py

profile-results: extract ## profile eval outcomes + CTT -> results/stats/results/
	python scripts/4_statistics/profile_results.py

glmm: extract ## fit binomial GLMM trajectory -> results/modeling/inference/
	Rscript scripts/5_model/glmm_trajectory.R

size-glmm: extract ## fit size-scaling GLMM -> results/modeling/size_scaling/
	Rscript scripts/5_model/size_scaling_glmm.R

irt: extract  ## fit developmental scaling + IRT -> results/modeling/mapping/
	Rscript scripts/5_model/developmental_scaling_irt.R

guttman: extract  ## Analysis 1: developmental sequence / Guttman scalability -> results/modeling/guttman_sequence/
	Rscript scripts/5_model/guttman_sequence_analysis.R

scale-validity: extract  ## Analysis 4: developmental-age scale validity/parsimony -> results/modeling/scale_validity/
	Rscript scripts/5_model/scale_validity_analysis.R

visualize: viz-descriptives viz-inference viz-mapping viz-accuracy viz-profiles viz-size viz-guttman viz-coherence viz-scale-validity ## run all visualization scripts

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

viz-size: size-glmm ## size-scaling figures
	Rscript scripts/6_visualize/visualize_size_scaling.R

viz-guttman: guttman ## Analysis 1 figures (Strands A/B): scalogram, permutation null, item difficulty
	Rscript scripts/6_visualize/visualize_guttman_sequence.R

viz-coherence: guttman ## Analysis 1 Strand C: continuous developmental-coherence figures
	Rscript scripts/6_visualize/visualize_coherence_continuous.R

viz-scale-validity: scale-validity ## Analysis 4 figures: CV log-loss, pred-vs-obs, format transfer, PCA
	Rscript scripts/6_visualize/visualize_scale_validity.R

pipeline: analyze visualize ## full pipeline: analyze then visualize

# ---- Streamlit app -------------------------------------------------------
# The app reads a frozen snapshot in app/data/, never results/ directly, so it
# stays fast and stays deployable. Rebuild the snapshot after re-running the
# pipeline.

app-deps:    ## install the app's Python dependencies
	python -m pip install -r app/requirements.txt

app-data: extract ## rebuild the app's frozen data snapshot from results/
	python app/prepare_data.py --force

app: ## serve the Streamlit app (builds the snapshot first if missing)
	@test -f app/data/item_level.parquet || python app/prepare_data.py
	streamlit run app/streamlit_app.py

hf-space: ## build the deployable Hugging Face Space into build/hf-space
	@test -f app/data/item_level.parquet || python app/prepare_data.py
	python deploy/build_hf_space.py --git

archive:      ## move old timestamped result folders to results/Archive/
	@mkdir -p results/Archive
	@for d in results/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_*/; do \
		[ -d "$$d" ] && mv "$$d" results/Archive/ && echo "Archived $$d"; \
	done; true

all: setup check smoke run analyze

clean:
	rm -rf .inspect __pycache__ */__pycache__ src/__pycache__ scripts/*/__pycache__
