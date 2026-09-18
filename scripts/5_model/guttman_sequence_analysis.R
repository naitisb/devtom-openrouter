#!/usr/bin/env Rscript
# guttman_sequence_analysis.R — Analysis 1: does the developmental SEQUENCE of
# theory-of-mind concept acquisition organize LLM performance?
#
# This is the load-bearing analysis for the claim that the developmental
# ordering (not just the tasks) is useful for evaluating models. It asks three
# things and emits tidy CSVs for scripts/6_visualize/visualize_guttman_sequence.R:
#
#   STRAND A — Scalability & permutation test
#     Build the model x dimension mastery matrix (>=80% per cell) with columns
#     in the project's developmental order (dim_rank). Compute Guttman
#     reproducibility (CR), minimal marginal reproducibility (MMR), coefficient
#     of scalability (CS), and Loevinger/Mokken H. Then the key test: recompute
#     CR under 10,000 random permutations of the 12 columns and against three
#     named rival orderings (empirical-best, construct-grouped, reverse). If the
#     developmental order sits in the upper tail of the null, the sequence
#     carries information no arbitrary ordering does.
#
#   STRAND B — Item difficulty vs. developmental age
#     Per item, difficulty = logit(1 - passrate) across models. Regress on the
#     item's validated developmental age (age_mid), pooled and with a
#     per-dimension random intercept. Slope in logits per developmental year is
#     the item-side evidence that the age axis is a difficulty axis. A Rasch
#     (1PL) difficulty is fit per format as confirmation.
#
#   STRAND C — Is developmental coherence explained by release date / size?
#     Per-model CONTINUOUS developmental coherence: using each dimension's accuracy
#     (not a pass/fail flag), the average over split points k of
#       mean(accuracy of dims after k) − mean(accuracy of dims at/before k)
#     — negative when accuracy declines across the developmental sequence. Because
#     ceiling compression ties the raw measure to overall level, we RESIDUALIZE it
#     on mean accuracy, then regress the residual on release date + log10(params)
#     + family to ask whether newer/larger models have a different developmental
#     profile SHAPE beyond simply being more accurate.
#
# All three strands run on pooled (MCQ+FRQ), MCQ-only, and FRQ-only mastery
# matrices; pooled is primary, the other two are robustness. FRQ has the most
# headroom (least ceiling), so watch it when pooled looks saturated.
#
# Usage:  Rscript scripts/5_model/guttman_sequence_analysis.R
# Reads:  results/item_level.csv   (run scripts/4_statistics/extract_item_level.py first)
# Writes: results/modeling/guttman_sequence/<timestamp>/*.csv  (+ a copy at .../latest/)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
})

set.seed(20260823)   # reproducible permutation null (Date.now-free)

# ── locate paths (works whether sourced or Rscript'd) ──────────────────────
this_dir <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) {
    args <- commandArgs(trailingOnly = FALSE)
    f <- grep("--file=", args, value = TRUE)
    if (length(f)) dirname(sub("--file=", "", f)) else "scripts/5_model"
  }
)
proj_root <- normalizePath(file.path(this_dir, "..", ".."))

MASTERY_THRESHOLD <- 0.80
N_PERM            <- 10000

item_csv <- file.path(proj_root, "results", "item_level.csv")
if (!file.exists(item_csv)) {
  stop("Missing ", item_csv,
       "\nRun: python scripts/4_statistics/extract_item_level.py")
}

ts      <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path(proj_root, "results", "modeling", "guttman_sequence", ts)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
cat("Output dir:", out_dir, "\n")

# ── load ───────────────────────────────────────────────────────────────────
dat <- read_csv(item_csv, show_col_types = FALSE) %>%
  mutate(correct = as.integer(correct),
         dim_rank = as.integer(dim_rank),
         age_mid  = as.numeric(age_mid))

# Canonical developmental order = dim_rank (project convention). NOTE: within the
# pragmatic block dim_rank puts Faux Pas (10) before Irony (11); the item age_mid
# instead puts Irony (8.0) before Faux Pas (11.0). docs/dev_norms.md flags that
# the pragmatic-block ranks are "a convention, not a measured difference". We use
# dim_rank for the ORDER test (Strand A) and age_mid as the continuous anchor for
# the item-difficulty regression (Strand B); they answer different questions.
dim_order <- dat %>%
  distinct(dim_rank, tom_dimension, tom_construct, age_mid) %>%
  group_by(dim_rank, tom_dimension, tom_construct) %>%
  summarise(age_mid = mean(age_mid), .groups = "drop") %>%
  arrange(dim_rank)
DEV_ORDER <- dim_order$tom_dimension
K <- length(DEV_ORDER)
cat(sprintf("Dimensions: %d | models: %d | rows: %d\n",
            K, n_distinct(dat$model), nrow(dat)))

# ── helper: build mastery matrix (rows = models, cols = dims in DEV_ORDER) ──
build_mastery <- function(d) {
  acc <- d %>%
    group_by(model, family, tier, date_years, tom_dimension) %>%
    summarise(acc = mean(correct), n = n(), .groups = "drop")
  wide <- acc %>%
    mutate(mastered = as.integer(acc >= MASTERY_THRESHOLD)) %>%
    select(model, tom_dimension, mastered) %>%
    pivot_wider(names_from = tom_dimension, values_from = mastered)
  # order columns developmentally; models keep chronological order
  meta <- acc %>% distinct(model, family, tier, date_years)
  wide <- wide %>% left_join(meta, by = "model") %>% arrange(date_years)
  list(
    matrix = as.matrix(wide[, DEV_ORDER]),
    models = wide$model, family = wide$family,
    tier = wide$tier, date_years = wide$date_years
  )
}

# ── Guttman metrics ────────────────────────────────────────────────────────
# CR for a FIXED column order: Goodenough ideal = prefix pattern set by row sum
# (first s columns = 1). Order-dependent, so it is the permutation statistic.
cr_fixed <- function(M) {
  n <- nrow(M); k <- ncol(M)
  errs <- sum(vapply(seq_len(n), function(i) {
    s <- sum(M[i, ]); ideal <- c(rep(1L, s), rep(0L, k - s))
    sum(M[i, ] != ideal)
  }, numeric(1)))
  1 - errs / (n * k)
}
guttman_errors_per_row <- function(M) {   # integer errors per model (dev order)
  k <- ncol(M)
  vapply(seq_len(nrow(M)), function(i) {
    s <- sum(M[i, ]); ideal <- c(rep(1L, s), rep(0L, k - s))
    sum(M[i, ] != ideal)
  }, numeric(1))
}
mmr <- function(M) { p <- colMeans(M); mean(pmax(p, 1 - p)) }

# Continuous developmental coherence (replaces the binary per-row Guttman count as
# the Strand C measure). Uses each dimension's ACCURACY, not a pass/fail flag. For
# every split point k = 1..K-1 (each dimension as the boundary), take
#   DC(k) = mean(accuracy of dims at/before k) − mean(accuracy of dims AFTER k)
#         = earlier − later,
# and average over all k. Sign convention (per request): POSITIVE = better on the
# earlier/easier dimensions than the later/harder ones = the child-like,
# developmentally-coherent direction; 0 = flat; NEGATIVE = better on the later/
# harder concepts = developmentally inverted. A is a models x dims accuracy matrix
# with columns in developmental order.
coherence_continuous <- function(A) {
  K <- ncol(A)
  apply(A, 1, function(a)
    mean(vapply(1:(K - 1), function(k) mean(a[1:k]) - mean(a[(k + 1):K]), numeric(1))))
}

# Loevinger / Mokken H — order-FREE scalability (items ranked by pass rate).
loevinger_H <- function(M) {
  k <- ncol(M); n <- nrow(M); p <- colMeans(M)
  ord <- order(p, decreasing = TRUE)      # easiest (highest pass) first
  Mo <- M[, ord, drop = FALSE]; po <- p[ord]
  obs <- 0; exp <- 0
  for (a in 1:(k - 1)) for (b in (a + 1):k) {
    obs <- obs + sum(Mo[, a] == 0 & Mo[, b] == 1)   # fail easier, pass harder
    exp <- exp + n * (1 - po[a]) * po[b]            # under independence
  }
  if (exp == 0) return(NA_real_)
  1 - obs / exp
}

# named rival orderings for the permutation reference lines
construct_grouped_order <- dim_order %>%
  mutate(tom_construct = factor(tom_construct,
           levels = c("Desire / intention inference", "Belief reasoning",
                      "Knowledge access", "Emotion recognition",
                      "Deception", "Pragmatic understanding"))) %>%
  arrange(tom_construct, dim_rank) %>% pull(tom_dimension)

analyse_dataset <- function(d, label) {
  cat("\n=====", label, "=====\n")
  mm <- build_mastery(d)
  M  <- mm$matrix
  storage.mode(M) <- "integer"

  # --- Strand A: scalability coefficients on the developmental order ---
  CR  <- cr_fixed(M)
  MMR <- mmr(M)
  CS  <- (CR - MMR) / (1 - MMR)
  H   <- loevinger_H(M)
  cat(sprintf("CR=%.3f  MMR=%.3f  CS=%.3f  Loevinger H=%.3f\n", CR, MMR, CS, H))

  # empirical-best order (columns sorted by descending pass rate) and reverse
  p_col      <- colMeans(M)
  emp_best   <- names(sort(p_col, decreasing = TRUE))
  rev_order  <- rev(DEV_ORDER)
  cr_of <- function(order_names) cr_fixed(M[, order_names, drop = FALSE])
  cr_emp <- cr_of(emp_best)
  cr_rev <- cr_of(rev_order)
  cr_con <- cr_of(construct_grouped_order)

  # --- permutation null: CR under random column permutations ---
  perm_cr <- replicate(N_PERM, cr_fixed(M[, sample(K), drop = FALSE]))
  p_dev <- (1 + sum(perm_cr >= CR)) / (N_PERM + 1)          # dev order in upper tail?
  p_con <- (1 + sum(perm_cr >= cr_con)) / (N_PERM + 1)
  cat(sprintf("Permutation: CR_dev=%.3f  p=%.4f  | CR_emp=%.3f CR_construct=%.3f CR_reverse=%.3f\n",
              CR, p_dev, cr_emp, cr_con, cr_rev))
  cat(sprintf("Null CR: mean=%.3f  sd=%.3f  min=%.3f  max=%.3f\n",
              mean(perm_cr), sd(perm_cr), min(perm_cr), max(perm_cr)))

  # Kendall tau: developmental order vs empirical difficulty order
  emp_rank <- rank(-p_col)[DEV_ORDER]      # 1 = easiest empirically
  tau <- suppressWarnings(cor(seq_len(K), emp_rank, method = "kendall"))
  cat(sprintf("Kendall tau (dev order vs empirical difficulty) = %.3f\n", tau))

  # --- outputs for this dataset ---
  scal <- tibble(
    dataset = label,
    CR = CR, MMR = MMR, pct_improvement = CR - MMR, CS = CS, loevinger_H = H,
    CR_empirical_best = cr_emp, CR_construct_grouped = cr_con, CR_reverse = cr_rev,
    kendall_tau_dev_vs_empirical = tau,
    n_models = nrow(M), n_dims = K
  )
  perm_summary <- tibble(
    dataset = label,
    order = c("developmental", "construct_grouped", "empirical_best", "reverse"),
    CR = c(CR, cr_con, cr_emp, cr_rev),
    p_value = c(p_dev, p_con, NA_real_, NA_real_),
    null_mean = mean(perm_cr), null_sd = sd(perm_cr),
    null_q95 = quantile(perm_cr, 0.95), n_perm = N_PERM
  )
  null_draws <- tibble(dataset = label, perm_cr = perm_cr)

  # tidy mastery matrix (long) for the scalogram
  mastery_long <- as_tibble(M) %>%
    mutate(model = mm$models, family = mm$family, tier = mm$tier,
           date_years = mm$date_years,
           row_errors = guttman_errors_per_row(M)) %>%
    pivot_longer(all_of(DEV_ORDER), names_to = "dimension", values_to = "mastered") %>%
    left_join(dim_order %>% select(tom_dimension, dim_rank, age_mid),
              by = c("dimension" = "tom_dimension"))

  # per-model coherence table (Strand C input) — CONTINUOUS measure.
  # Build the models x dims ACCURACY matrix (same row/col order as M) and score it.
  A <- d %>% group_by(model, tom_dimension) %>%
    summarise(a = mean(correct), .groups = "drop") %>%
    pivot_wider(names_from = tom_dimension, values_from = a)
  A <- A[match(mm$models, A$model), ]
  Amat <- as.matrix(A[, DEV_ORDER])
  overall_acc <- d %>% group_by(model) %>% summarise(mean_acc = mean(correct), .groups = "drop")
  coherence <- tibble(
    dataset = label, model = mm$models, family = mm$family, tier = mm$tier,
    date_years = mm$date_years,
    guttman_errors = guttman_errors_per_row(M),      # kept for reference (binary)
    coherence = coherence_continuous(Amat)           # continuous: later − earlier
  ) %>% left_join(overall_acc, by = "model")

  list(scal = scal, perm = perm_summary, null = null_draws,
       mastery = mastery_long, coherence = coherence)
}

datasets <- list(
  pooled = dat,
  mcq    = filter(dat, task == "tom_12dim_mcq"),
  frq    = filter(dat, task == "tom_12dim_freeresponse")
)
res <- Map(analyse_dataset, datasets, names(datasets))

scal_all  <- bind_rows(lapply(res, `[[`, "scal"))
perm_all  <- bind_rows(lapply(res, `[[`, "perm"))
null_all  <- bind_rows(lapply(res, `[[`, "null"))
mast_all  <- bind_rows(lapply(res, `[[`, "mastery"), .id = "dataset")
coh_all   <- bind_rows(lapply(res, `[[`, "coherence"))

write_csv(scal_all, file.path(out_dir, "scalability_coefficients.csv"))
write_csv(perm_all, file.path(out_dir, "permutation_results.csv"))
write_csv(null_all, file.path(out_dir, "permutation_null_draws.csv"))
write_csv(mast_all, file.path(out_dir, "mastery_matrix_long.csv"))

# ── STRAND B: item difficulty vs developmental age ─────────────────────────
cat("\n===== Strand B: item difficulty vs developmental age =====\n")
item_diff <- dat %>%
  group_by(item_id, task, tom_dimension, tom_construct, dim_rank, age_mid) %>%
  summarise(n = n(), pass = sum(correct), .groups = "drop") %>%
  mutate(passrate = pass / n,
         # +0.5/+1 continuity correction so 0% / 100% items stay finite
         passrate_adj = (pass + 0.5) / (n + 1),
         difficulty_logit = qlogis(1 - passrate_adj))   # higher = harder

fit_age <- function(df, lab) {
  ols <- lm(difficulty_logit ~ age_mid, data = df)
  sl  <- coef(summary(ols))["age_mid", ]
  sp  <- suppressWarnings(cor(df$age_mid, df$difficulty_logit, method = "spearman"))
  mixed_slope <- NA_real_; mixed_p <- NA_real_
  # Prefer lmerTest for a Satterthwaite p-value; fall back to lme4 (estimate +
  # Wald p from the t-value) so the mixed slope is still reported without it.
  if (length(unique(df$tom_dimension)) > 2 &&
      requireNamespace("lme4", quietly = TRUE)) {
    if (requireNamespace("lmerTest", quietly = TRUE)) {
      mm <- tryCatch(lmerTest::lmer(difficulty_logit ~ age_mid + (1 | tom_dimension),
                                    data = df), error = function(e) NULL)
      if (!is.null(mm)) {
        cc <- coef(summary(mm))
        if ("age_mid" %in% rownames(cc)) {
          mixed_slope <- cc["age_mid", "Estimate"]
          mixed_p <- cc["age_mid", grep("Pr", colnames(cc))]
        }
      }
    } else {
      mm <- tryCatch(lme4::lmer(difficulty_logit ~ age_mid + (1 | tom_dimension),
                                data = df), error = function(e) NULL)
      if (!is.null(mm)) {
        cc <- coef(summary(mm))
        if ("age_mid" %in% rownames(cc)) {
          mixed_slope <- cc["age_mid", "Estimate"]
          tval <- cc["age_mid", "t value"]
          mixed_p <- 2 * pnorm(-abs(tval))   # Wald approx (lmerTest absent)
        }
      }
    }
  }
  tibble(dataset = lab, n_items = nrow(df),
         ols_slope_logit_per_year = sl["Estimate"], ols_se = sl["Std. Error"],
         ols_p = sl["Pr(>|t|)"], ols_r2 = summary(ols)$r.squared,
         spearman_age_difficulty = sp,
         mixed_slope_logit_per_year = mixed_slope, mixed_p = mixed_p)
}
age_reg <- bind_rows(
  fit_age(item_diff, "pooled"),
  fit_age(filter(item_diff, task == "tom_12dim_mcq"), "mcq"),
  fit_age(filter(item_diff, task == "tom_12dim_freeresponse"), "frq")
)
print(as.data.frame(age_reg), digits = 3)

# add pooled OLS fitted line for the figure
ols_pooled <- lm(difficulty_logit ~ age_mid, data = item_diff)
item_diff$fitted_pooled <- predict(ols_pooled)

# Rasch (1PL) confirmatory difficulty per format (mirt); guarded — 28 persons
rasch_diff <- tryCatch({
  if (!requireNamespace("mirt", quietly = TRUE)) stop("no mirt")
  do_rasch <- function(task_name, lab) {
    d1 <- dat %>% filter(task == task_name) %>%
      select(model, item_id, correct) %>%
      pivot_wider(names_from = item_id, values_from = correct)
    resp <- as.matrix(d1[, -1])
    # drop all-correct / all-wrong items (no info for Rasch)
    keep <- apply(resp, 2, function(x) { v <- var(x, na.rm = TRUE); !is.na(v) && v > 0 })
    resp <- resp[, keep, drop = FALSE]
    m <- mirt::mirt(resp, 1, itemtype = "Rasch", verbose = FALSE)
    b <- mirt::coef(m, IRTpars = TRUE, simplify = TRUE)$items[, "b"]
    meta <- dat %>% distinct(item_id, tom_dimension, dim_rank, age_mid)
    tibble(dataset = lab, item_id = colnames(resp), rasch_b = as.numeric(b)) %>%
      left_join(meta, by = "item_id")
  }
  bind_rows(do_rasch("tom_12dim_mcq", "mcq"),
            do_rasch("tom_12dim_freeresponse", "frq"))
}, error = function(e) { cat("Rasch skipped:", conditionMessage(e), "\n"); NULL })

if (!is.null(rasch_diff)) {
  rasch_reg <- rasch_diff %>% group_by(dataset) %>%
    summarise(rasch_slope_logit_per_year = coef(lm(rasch_b ~ age_mid))["age_mid"],
              rasch_spearman = suppressWarnings(cor(age_mid, rasch_b, method = "spearman")),
              n_items = n(), .groups = "drop")
  print(as.data.frame(rasch_reg), digits = 3)
  write_csv(rasch_diff, file.path(out_dir, "rasch_item_difficulty.csv"))
  write_csv(rasch_reg, file.path(out_dir, "rasch_difficulty_vs_age.csv"))
}

write_csv(item_diff, file.path(out_dir, "item_difficulty_vs_age.csv"))
write_csv(age_reg,   file.path(out_dir, "item_age_regression.csv"))

# ── STRAND C: developmental coherence ~ date + size + family ───────────────
cat("\n===== Strand C: coherence ~ date + log_params + family =====\n")
params_tbl <- dat %>% distinct(model) %>%
  mutate(params_b = vapply(model, function(m) {
    # read PARAMS_B via python is overkill here; parse from item_level's model
    NA_real_
  }, numeric(1)))
# params come from src/roster.py; join via a small lookup emitted alongside the CSV
# (item_level.csv has no params column, so compute log_params from a helper file
#  if present, else from a minimal inline map is avoided — we call python once).
params_map <- tryCatch({
  py <- file.path(proj_root, ".venv", "bin", "python3")
  if (!file.exists(py)) py <- "python3"
  tmp <- tempfile(fileext = ".csv")
  models_txt <- paste(unique(dat$model), collapse = "\n")
  script <- sprintf(
    "import sys; sys.path.insert(0,'%s'); from src.roster import model_params_b;\nimport csv,io\nrows=[l for l in '''%s'''.split(chr(10)) if l]\nw=csv.writer(open('%s','w'));w.writerow(['model','params_b'])\n[w.writerow([m, model_params_b(m)]) for m in rows]",
    proj_root, models_txt, tmp)
  system2(py, args = c("-c", shQuote(script)), stdout = NULL, stderr = NULL)
  read_csv(tmp, show_col_types = FALSE)
}, error = function(e) { cat("params lookup failed:", conditionMessage(e), "\n"); NULL })

coh_pooled <- coh_all %>% filter(dataset == "pooled")
if (!is.null(params_map)) {
  coh_pooled <- coh_pooled %>% left_join(params_map, by = "model") %>%
    mutate(log_params = log10(params_b))
} else {
  coh_pooled$log_params <- NA_real_
}

# RESIDUALIZE the continuous coherence on overall mean accuracy. This is a
# regression residual, NOT a normalization: we fit  coherence ~ mean_acc  by OLS
# across all models and keep the residual  coherence_i − (b0 + b1*mean_acc_i)  —
# the part of a model's coherence that its overall accuracy does not linearly
# predict. Ceiling compression otherwise ties the raw measure to level (a
# near-100% model has no early-vs-late gap), so this residual isolates
# developmental profile SHAPE from competence and is the clean DV for the
# date/size question. NOTE: removes only the LINEAR dependence; if the
# coherence-vs-accuracy scatter is curved, swap in poly(mean_acc, 2) or a spline.
resid_fit <- lm(coherence ~ mean_acc, data = coh_pooled)
coh_pooled$coherence_resid <- residuals(resid_fit)
cat(sprintf("Residualizing: coherence ~ mean_acc  (slope=%.3f);  corr(coherence, mean_acc)=%.3f -> residual corr=%.3f\n",
            coef(resid_fit)[2], suppressWarnings(cor(coh_pooled$coherence, coh_pooled$mean_acc)),
            suppressWarnings(cor(coh_pooled$coherence_resid, coh_pooled$mean_acc))))

# per-split-point D(k) profile for the pooled dataset (for the figures)
acc_pooled <- dat %>% group_by(model, tom_dimension) %>%
  summarise(a = mean(correct), .groups = "drop") %>%
  pivot_wider(names_from = tom_dimension, values_from = a)
acc_pooled <- acc_pooled[match(coh_pooled$model, acc_pooled$model), ]
Ap <- as.matrix(acc_pooled[, DEV_ORDER])
# DC(k) = earlier − later (same sign convention as coherence_continuous)
Dk <- t(apply(Ap, 1, function(a) vapply(1:(K - 1),
        function(k) mean(a[1:k]) - mean(a[(k + 1):K]), numeric(1))))
colnames(Dk) <- paste0("k", 1:(K - 1))
Dk_long <- as_tibble(Dk) %>% mutate(model = coh_pooled$model) %>%
  pivot_longer(-model, names_to = "k", values_to = "D") %>%
  mutate(k = as.integer(sub("k", "", k)))
write_csv(Dk_long, file.path(out_dir, "coherence_by_split_point.csv"))

# per-dimension accuracy (long) — the gradient the measure summarizes
acc_long <- dat %>% group_by(model, tom_dimension) %>%
  summarise(accuracy = mean(correct), .groups = "drop") %>%
  left_join(dim_order %>% select(tom_dimension, dim_rank, age_mid), by = "tom_dimension") %>%
  left_join(coh_pooled %>% select(model, family, tier, date_years, params_b,
                                  log_params, mean_acc, coherence, coherence_resid),
            by = "model")
write_csv(acc_long, file.path(out_dir, "per_dimension_accuracy.csv"))

write_csv(coh_pooled, file.path(out_dir, "per_model_coherence.csv"))

coh_fit_rows <- list()
if (all(c("log_params") %in% names(coh_pooled)) && sum(!is.na(coh_pooled$log_params)) > 8) {
  cd <- coh_pooled %>% filter(!is.na(log_params), !is.na(date_years)) %>%
    mutate(date_c = date_years - mean(date_years),
           log_params_c = log_params - mean(log_params))
  tidy_lm <- function(m, lab) {
    s <- coef(summary(m))
    tibble(model_spec = lab, term = rownames(s),
           estimate = s[, 1], std_error = s[, 2], t = s[, 3], p = s[, 4])
  }
  # raw continuous measure (rides on level) vs residualized (level removed)
  m_raw   <- lm(coherence       ~ date_c + log_params_c + family, data = cd)
  m_resid <- lm(coherence_resid ~ date_c + log_params_c + family, data = cd)
  coh_fit_rows <- bind_rows(
    tidy_lm(m_raw,   "coherence (raw) ~ date + size + family"),
    tidy_lm(m_resid, "coherence (resid on mean_acc) ~ date + size + family"))
  sp_date_r <- suppressWarnings(cor(cd$date_years, cd$coherence_resid, method = "spearman"))
  sp_size_r <- suppressWarnings(cor(cd$log_params, cd$coherence_resid, method = "spearman"))
  cat(sprintf("Residualized coherence — Spearman ~date=%.3f  ~log_params=%.3f\n",
              sp_date_r, sp_size_r))
  coh_fit_rows <- bind_rows(coh_fit_rows,
    tibble(model_spec = "spearman (residualized)", term = c("date_years", "log_params"),
           estimate = c(sp_date_r, sp_size_r), std_error = NA, t = NA, p = NA))
  print(as.data.frame(coh_fit_rows), digits = 3)
  write_csv(coh_fit_rows, file.path(out_dir, "coherence_regression.csv"))
}

# ── convenience: mirror everything to .../latest/ ──────────────────────────
latest <- file.path(proj_root, "results", "modeling", "guttman_sequence", "latest")
unlink(latest, recursive = TRUE); dir.create(latest, recursive = TRUE, showWarnings = FALSE)
file.copy(list.files(out_dir, full.names = TRUE), latest, overwrite = TRUE)

cat("\nDone. CSV artifacts in:\n  ", out_dir, "\n  ", latest, "\n")
cat("Next: Rscript scripts/6_visualize/visualize_guttman_sequence.R\n")
