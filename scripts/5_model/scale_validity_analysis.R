#!/usr/bin/env Rscript
# scale_validity_analysis.R — Analysis 4: is the developmental-age scale USEFUL?
#
# Analysis 1 showed the developmental ordering is real (a strong Guttman scale
# that beats random orderings). This asks the follow-on question that justifies
# using it as an evaluation instrument: does collapsing a model to a SINGLE
# developmental-age scalar actually predict behavior, and does it beat the
# obvious alternatives? Four strands, all emitting tidy CSVs for
# scripts/6_visualize/visualize_scale_validity.R:
#
#   STRAND A — Predict an UNSEEN concept (leave-one-dimension-out CV)
#     Hold out one ToM dimension, estimate each model's developmental age from
#     the other 11 (shared-slope logistic: correct ~ age_mid + model), then
#     predict accuracy on the held-out dimension. Compare held-out log-loss to:
#       grand mean · family mean · the model's own overall mean · date+size.
#     The key contrast is dev-age vs the model's OVERALL MEAN: if the age scale
#     wins, the developmental *sequence* carries predictive information beyond a
#     flat competence scalar. dev-age vs date+size asks whether the behavioral
#     scale beats external metadata for predicting an untested ability.
#
#   STRAND B — Parsimony (random item hold-out, 5-fold)
#     Here the saturated per-dimension model (12 params/model) is available as an
#     upper bound. If the 1-parameter dev-age model approaches the 12-parameter
#     saturated model in held-out log-loss, one number is nearly as good as
#     twelve — the scale is a defensible compact summary.
#
#   STRAND C — Format transfer
#     Fit developmental age on MCQ, predict free-response (and vice versa). A
#     scale that survives a change of elicitation format is a measurement, not an
#     artifact of one task shape. Emits per-model theta in each format.
#
#   STRAND D — Dimensionality
#     PCA of the model x dimension accuracy matrix with a parallel-analysis
#     retention test. One dominant factor whose loadings track developmental rank
#     is what a usable single-scalar scale should look like.
#
# Usage:  Rscript scripts/5_model/scale_validity_analysis.R
# Reads:  results/item_level.csv
# Writes: results/modeling/scale_validity/<timestamp>/*.csv  (+ .../latest/)

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr)
})
set.seed(20260823)

this_dir <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) {
    args <- commandArgs(trailingOnly = FALSE)
    f <- grep("--file=", args, value = TRUE)
    if (length(f)) dirname(sub("--file=", "", f)) else "scripts/5_model"
  })
proj_root <- normalizePath(file.path(this_dir, "..", ".."))

item_csv <- file.path(proj_root, "results", "item_level.csv")
if (!file.exists(item_csv)) stop("Missing ", item_csv,
  "\nRun: python scripts/4_statistics/extract_item_level.py")

ts      <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path(proj_root, "results", "modeling", "scale_validity", ts)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
cat("Output dir:", out_dir, "\n")

EPS <- 1e-6
logloss <- function(y, p) {
  p <- pmin(pmax(p, EPS), 1 - EPS)
  -mean(y * log(p) + (1 - y) * log(1 - p))
}

# ── load + attach params (via src/roster.py, same bridge as Analysis 1) ────
dat <- read_csv(item_csv, show_col_types = FALSE) %>%
  mutate(correct = as.integer(correct), age_mid = as.numeric(age_mid),
         dim_rank = as.integer(dim_rank))

params_map <- tryCatch({
  py <- file.path(proj_root, ".venv", "bin", "python3")
  if (!file.exists(py)) py <- "python3"
  tmp <- tempfile(fileext = ".csv")
  models_txt <- paste(unique(dat$model), collapse = "\n")
  script <- sprintf(
    "import sys; sys.path.insert(0,'%s'); from src.roster import model_params_b\nimport csv\nrows=[l for l in '''%s'''.split(chr(10)) if l]\nw=csv.writer(open('%s','w'));w.writerow(['model','params_b'])\n[w.writerow([m, model_params_b(m)]) for m in rows]",
    proj_root, models_txt, tmp)
  system2(py, args = c("-c", shQuote(script)), stdout = NULL, stderr = NULL)
  read_csv(tmp, show_col_types = FALSE)
}, error = function(e) { cat("params lookup failed:", conditionMessage(e), "\n"); NULL })
if (is.null(params_map)) stop("Cannot proceed without params (needed for date+size baseline)")

dat <- dat %>% left_join(params_map, by = "model") %>%
  mutate(log_params = log10(params_b),
         age_c       = age_mid    - mean(age_mid),
         date_c      = date_years - mean(date_years),
         log_params_c = log_params - mean(log_params),
         model = factor(model))

DEV_ORDER <- dat %>% distinct(dim_rank, tom_dimension) %>%
  arrange(dim_rank) %>% pull(tom_dimension)
cat(sprintf("models=%d dims=%d rows=%d\n",
            nlevels(dat$model), length(DEV_ORDER), nrow(dat)))

# fitwrap: silence separation warnings on ceiling models
gfit <- function(f, d) suppressWarnings(glm(f, data = d, family = binomial))

# ── STRAND A: leave-one-dimension-out ──────────────────────────────────────
cat("\n===== Strand A: leave-one-dimension-out prediction =====\n")
lodo_pred <- list()
for (dd in DEV_ORDER) {
  train <- filter(dat, tom_dimension != dd)
  test  <- filter(dat, tom_dimension == dd)

  g_dev <- gfit(correct ~ age_c + model, train)
  g_ds  <- gfit(correct ~ age_c + date_c + log_params_c, train)

  grand    <- mean(train$correct)
  fam_mean <- train %>% group_by(family) %>% summarise(p_family = mean(correct), .groups = "drop")
  mod_mean <- train %>% group_by(model)  %>% summarise(p_overall = mean(correct), .groups = "drop")

  test$p_devage   <- predict(g_dev, newdata = test, type = "response")
  test$p_datesize <- predict(g_ds,  newdata = test, type = "response")
  test$p_grand    <- grand
  test <- test %>% left_join(fam_mean, by = "family") %>%
                   left_join(mod_mean, by = "model")
  lodo_pred[[dd]] <- test %>%
    select(model, family, tier, date_years, params_b, tom_dimension, dim_rank,
           age_mid, correct, p_devage, p_datesize, p_grand, p_family, p_overall)
}
lodo <- bind_rows(lodo_pred)

METHODS_A <- c(devage = "p_devage", datesize = "p_datesize",
               grand = "p_grand", family = "p_family", overall = "p_overall")
overall_acc <- dat %>% group_by(model) %>% summarise(macc = mean(correct), .groups = "drop")
lodo <- lodo %>% left_join(overall_acc, by = "model") %>%
  mutate(subgroup = ifelse(macc < 0.95, "discriminating (<0.95)", "saturated (≥0.95)"))

cv_A <- lapply(names(METHODS_A), function(m) {
  col <- METHODS_A[[m]]
  overall <- tibble(scheme = "leave-one-dimension-out", method = m, subgroup = "all",
                    logloss = logloss(lodo$correct, lodo[[col]]),
                    n = nrow(lodo))
  bygrp <- lodo %>% group_by(subgroup) %>%
    summarise(logloss = logloss(correct, .data[[col]]), n = n(), .groups = "drop") %>%
    mutate(scheme = "leave-one-dimension-out", method = m) %>%
    select(scheme, method, subgroup, logloss, n)
  bind_rows(overall, bygrp)
}) %>% bind_rows()
print(cv_A %>% filter(subgroup == "all") %>% arrange(logloss) %>% as.data.frame(), digits = 4)

# dimension-level observed vs predicted (dev-age) for the pred-vs-obs figure
lodo_dim <- lodo %>%
  group_by(tom_dimension, dim_rank, age_mid, model, family, tier, macc, subgroup) %>%
  summarise(observed = mean(correct),
            pred_devage = mean(p_devage),
            pred_overall = mean(p_overall), .groups = "drop")

# ── STRAND B: random item hold-out, 5-fold (parsimony vs saturated) ────────
cat("\n===== Strand B: 5-fold item hold-out (parsimony) =====\n")
K_FOLDS <- 5
dat_f <- dat %>% group_by(model, tom_dimension) %>%
  mutate(fold = sample(rep_len(1:K_FOLDS, n()))) %>% ungroup()

fold_rows <- list()
for (k in 1:K_FOLDS) {
  train <- filter(dat_f, fold != k)
  test  <- filter(dat_f, fold == k)
  g_dev <- gfit(correct ~ age_c + model, train)
  g_ds  <- gfit(correct ~ age_c + date_c + log_params_c, train)
  grand <- mean(train$correct)
  mod_mean <- train %>% group_by(model) %>% summarise(p_overall = mean(correct), .groups = "drop")
  dim_mean <- train %>% group_by(model, tom_dimension) %>%
    summarise(p_saturated = mean(correct), .groups = "drop")
  test$p_devage    <- predict(g_dev, newdata = test, type = "response")
  test$p_datesize  <- predict(g_ds,  newdata = test, type = "response")
  test$p_grand     <- grand
  test <- test %>% left_join(mod_mean, by = "model") %>%
                   left_join(dim_mean, by = c("model", "tom_dimension"))
  fold_rows[[k]] <- test
}
holdout <- bind_rows(fold_rows)
METHODS_B <- c(devage = "p_devage", saturated = "p_saturated",
               overall = "p_overall", datesize = "p_datesize", grand = "p_grand")
cv_B <- lapply(names(METHODS_B), function(m) {
  tibble(scheme = "item hold-out (5-fold)", method = m, subgroup = "all",
         logloss = logloss(holdout$correct, holdout[[METHODS_B[[m]]]]),
         n = nrow(holdout))
}) %>% bind_rows()
# n free params per model, for the parsimony axis
PARAMS_PER_MODEL <- c(devage = 1, saturated = 12, overall = 1, datesize = 0, grand = 0)
cv_B$params_per_model <- PARAMS_PER_MODEL[cv_B$method]
print(cv_B %>% arrange(logloss) %>% as.data.frame(), digits = 4)

cv_all <- bind_rows(cv_A, cv_B)
write_csv(cv_all, file.path(out_dir, "cv_logloss.csv"))
write_csv(lodo_dim, file.path(out_dir, "lodo_dimension_predictions.csv"))

# ── STRAND C: format transfer ──────────────────────────────────────────────
cat("\n===== Strand C: format transfer (MCQ <-> FRQ) =====\n")
mcq <- filter(dat, task == "tom_12dim_mcq")
frq <- filter(dat, task == "tom_12dim_freeresponse")
g_mcq <- gfit(correct ~ age_c + model, mcq)
g_frq <- gfit(correct ~ age_c + model, frq)

# Per-model position on the scale = ToM ABILITY on the logit scale: each model's
# predicted linear predictor at the median item age (age_c = 0) from the
# shared-slope logistic. This is the finite, continuous quantity the age
# equivalent is a monotone rescaling of. We compare ability rather than the
# derived age because the P=0.5 age crossing extrapolates to absurd values
# (100s of years) for near-ceiling models whose accuracy never falls to 50%
# within the 3.5–11 yr item range, and the coarse mastery-based age is dominated
# by ceiling ties. Ability preserves the ranking without either pathology.
theta_from <- function(g, models) {
  lp <- predict(g, newdata = data.frame(age_c = 0, model = models), type = "link")
  tibble(model = models, theta = as.numeric(lp))
}
mods <- levels(dat$model)
theta_mcq <- theta_from(g_mcq, mods) %>% rename(ability_mcq = theta)
theta_frq <- theta_from(g_frq, mods) %>% rename(ability_frq = theta)
# Raw per-format accuracy: bounded [0,1], no separation artifact, defined for all
# models (the logit ability is unidentified for the ~13 models at 100% on MCQ).
# This is the robust quantity the transfer figure plots; ability stays in the CSV.
acc_fmt <- dat %>% group_by(model, task) %>% summarise(acc = mean(correct), .groups = "drop") %>%
  pivot_wider(names_from = task, values_from = acc) %>%
  rename(acc_mcq = tom_12dim_mcq, acc_frq = tom_12dim_freeresponse)
theta_tbl <- theta_mcq %>% left_join(theta_frq, by = "model") %>%
  left_join(acc_fmt, by = "model") %>%
  mutate(headroom = acc_mcq < 0.97 & acc_frq < 0.97) %>%
  left_join(params_map, by = "model") %>%
  left_join(distinct(dat, model, family, tier, date_years), by = "model")
# Correlation of raw accuracy across formats: all models, and the headroom subset
# (models not saturated in either format, where the comparison is informative).
theta_cor   <- suppressWarnings(cor(theta_tbl$acc_mcq, theta_tbl$acc_frq))
theta_cor_s <- suppressWarnings(cor(theta_tbl$acc_mcq, theta_tbl$acc_frq, method = "spearman"))
hr <- filter(theta_tbl, headroom)
theta_cor_hr <- suppressWarnings(cor(hr$acc_mcq, hr$acc_frq))
cat(sprintf("accuracy MCQ vs FRQ: Pearson r=%.3f Spearman=%.3f (all %d models); r=%.3f (headroom, n=%d)\n",
            theta_cor, theta_cor_s, nrow(theta_tbl), theta_cor_hr, nrow(hr)))

transfer <- tibble(
  direction = c("MCQ→MCQ (in-sample)", "MCQ→FRQ (transfer)",
                "FRQ→FRQ (in-sample)", "FRQ→MCQ (transfer)"),
  logloss = c(
    logloss(mcq$correct, predict(g_mcq, mcq, type = "response")),
    logloss(frq$correct, predict(g_mcq, frq, type = "response")),
    logloss(frq$correct, predict(g_frq, frq, type = "response")),
    logloss(mcq$correct, predict(g_frq, mcq, type = "response")))
)
print(as.data.frame(transfer), digits = 4)
write_csv(theta_tbl,  file.path(out_dir, "theta_by_format.csv"))
write_csv(transfer,   file.path(out_dir, "format_transfer.csv"))
write_csv(tibble(pearson = theta_cor, spearman = theta_cor_s,
                 pearson_headroom = theta_cor_hr, n_headroom = nrow(hr)),
          file.path(out_dir, "format_transfer_theta_cor.csv"))

# ── STRAND D: dimensionality (PCA + parallel analysis) ─────────────────────
cat("\n===== Strand D: dimensionality =====\n")
accw <- dat %>% group_by(model, tom_dimension) %>%
  summarise(a = mean(correct), .groups = "drop") %>%
  pivot_wider(names_from = tom_dimension, values_from = a)
M <- as.matrix(accw[, DEV_ORDER])
pca <- prcomp(M, scale. = TRUE)
eig <- pca$sdev^2
pct <- eig / sum(eig)

# manual parallel analysis: 95th pct eigenvalues of random matrices, same shape
n <- nrow(M); p <- ncol(M); NSIM <- 500
sim_eig <- replicate(NSIM, sort(eigen(cor(matrix(rnorm(n * p), n, p)),
                                      only.values = TRUE)$values, decreasing = TRUE))
par_95 <- apply(sim_eig, 1, quantile, 0.95)
retain <- eig > par_95
cat(sprintf("PC1 explains %.1f%% variance; components retained (obs eig > parallel 95th): %d\n",
            100 * pct[1], sum(retain)))

# orient PC1 so it increases with developmental rank, then correlate loadings
load1 <- pca$rotation[, 1]
if (cor(load1, seq_along(DEV_ORDER)) < 0) { load1 <- -load1 }
rho_rank <- suppressWarnings(cor(load1, seq_along(DEV_ORDER), method = "spearman"))
cat(sprintf("Spearman(PC1 loading, developmental rank) = %.3f\n", rho_rank))

pca_load <- tibble(tom_dimension = DEV_ORDER,
                   dim_rank = seq_along(DEV_ORDER) - 1L,
                   PC1_loading = load1,
                   PC2_loading = pca$rotation[, 2])
pca_var <- tibble(PC = seq_along(eig), eigenvalue = eig, pct_var = pct,
                  parallel_95 = par_95, retain = retain)
write_csv(pca_load, file.path(out_dir, "pca_loadings.csv"))
write_csv(pca_var,  file.path(out_dir, "pca_variance.csv"))

# headline summary
summary_tbl <- tibble(
  metric = c("LODO logloss: dev-age", "LODO logloss: overall-mean",
             "LODO logloss: date+size", "LODO logloss: grand-mean",
             "LODO dev-age advantage over overall-mean (discriminating models)",
             "hold-out logloss: dev-age (1 param)", "hold-out logloss: saturated (12 params)",
             "accuracy MCQ~FRQ Pearson r (all models)", "PC1 variance explained",
             "components retained (parallel analysis)", "Spearman(PC1 loading, dev rank)"),
  value = c(
    cv_A$logloss[cv_A$method == "devage" & cv_A$subgroup == "all"],
    cv_A$logloss[cv_A$method == "overall" & cv_A$subgroup == "all"],
    cv_A$logloss[cv_A$method == "datesize" & cv_A$subgroup == "all"],
    cv_A$logloss[cv_A$method == "grand" & cv_A$subgroup == "all"],
    cv_A$logloss[cv_A$method == "overall" & cv_A$subgroup == "discriminating (<0.95)"] -
      cv_A$logloss[cv_A$method == "devage" & cv_A$subgroup == "discriminating (<0.95)"],
    cv_B$logloss[cv_B$method == "devage"], cv_B$logloss[cv_B$method == "saturated"],
    theta_cor, pct[1], sum(retain), rho_rank))
write_csv(summary_tbl, file.path(out_dir, "summary.csv"))
cat("\n"); print(as.data.frame(summary_tbl), digits = 4)

# mirror to latest/
latest <- file.path(proj_root, "results", "modeling", "scale_validity", "latest")
unlink(latest, recursive = TRUE); dir.create(latest, recursive = TRUE, showWarnings = FALSE)
file.copy(list.files(out_dir, full.names = TRUE), latest, overwrite = TRUE)
cat("\nDone. CSVs in:\n  ", out_dir, "\n  ", latest, "\n")
cat("Next: Rscript scripts/6_visualize/visualize_scale_validity.R\n")
