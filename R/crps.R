# Dead Reckoning — CRPS (continuous scoring primitives)
# -----------------------------------------------------
# The Continuous Ranked Probability Score is the proper-scoring-rule cousin of
# the Brier score, for forecasts of a *number* rather than a yes/no event. It
# generalises absolute error: a point forecast scores exactly |mu - y|, and a
# sharp-but-wrong predictive distribution is penalised just as a brittle 0/1
# probability is under Brier. Lower is better; CRPS is in the units of y.
#
#   CRPS(F, y) = integral over x of ( F(x) - 1{x >= y} )^2 dx
#
# No I/O, no network — pure functions, sourced by R/score_continuous.R.
# Every formula here is cross-checked numerically (see the project's scoping
# notes): the Gaussian closed form matches a brute-force integral to ~1e-11,
# the sample estimator converges to it, and CRPS -> |mu - y| as sigma -> 0.

# ---- Gaussian predictive distribution (exact, preferred) ---------------------
# Gneiting & Raftery (2007). The cleanest representation: have the forecaster
# emit a mean mu and a standard deviation sigma.
crps_normal <- function(mu, sigma, y) {
  if (is.na(mu) || is.na(sigma) || sigma <= 0) return(NA_real_)
  z <- (y - mu) / sigma
  sigma * (z * (2 * pnorm(z) - 1) + 2 * dnorm(z) - 1 / sqrt(pi))
}

# ---- Monte-Carlo / ensemble samples ------------------------------------------
# Fair energy-form estimator, computed in O(m log m) via the sorted identity for
# the mean pairwise distance (never the naive m^2 matrix):
#   CRPS ~= mean|x_i - y| - 1/2 * mean_{i,j}|x_i - x_j|
crps_sample <- function(x, y) {
  x <- sort(as.numeric(x)); m <- length(x)
  if (m == 0) return(NA_real_)
  if (m == 1) return(abs(x - y))
  i <- seq_len(m)                                  # 1-based index
  pair_sum <- 2 * sum((2 * i - m - 1) * x)              # = sum_{i,j} |x_i - x_j|
  mean(abs(x - y)) - pair_sum / (2 * m * (m - 1))       # fair (unbiased) estimator
}

# ---- Predictive quantiles (approximate) --------------------------------------
# CRPS = 2 * integral_0^1 QL_tau d tau, where QL is the pinball (quantile) loss.
# We trapezoid that integral over the supplied quantile levels. Approximate at
# the tails; for accuracy prefer mu/sigma or samples. taus in (0,1), qs the
# matching quantile values.
crps_quantiles <- function(taus, qs, y) {
  o <- order(taus); taus <- taus[o]; qs <- qs[o]
  ql <- ifelse(y >= qs, taus * (y - qs), (1 - taus) * (qs - y))   # pinball loss
  tg <- c(0, taus, 1)                                # pad the level axis to [0,1]
  qg <- c(ql[1], ql, ql[length(ql)])                 # hold the end losses flat
  2 * sum(diff(tg) * (head(qg, -1) + tail(qg, -1)) / 2)
}

# ---- PIT: where the outcome fell in the predictive CDF -----------------------
# The probability integral transform F(y). Pooled across forecasts its histogram
# is the continuous analogue of the reliability diagram: flat = calibrated,
# U-shaped = over-confident (too narrow), hump = under-confident (too wide).
pit_normal    <- function(mu, sigma, y) pnorm((y - mu) / sigma)
pit_sample    <- function(x, y) mean(as.numeric(x) <= y)
pit_quantiles <- function(taus, qs, y) {
  o <- order(qs); stats::approx(qs[o], taus[o], xout = y, rule = 2)$y
}

# ---- Dispatch on a forecast's stated shape -----------------------------------
# A continuous forecast in questions.yml is one of:
#   { mu: , sigma: }            -> Gaussian   (recommended)
#   { q: { 0.1: , 0.5: , 0.9: } } -> quantiles
#   { samples: [ ... ] }        -> Monte-Carlo draws
.dist_kind <- function(d) {
  if (!is.null(d$mu) && !is.null(d$sigma)) "normal"
  else if (!is.null(d$samples))            "samples"
  else if (!is.null(d$q))                  "quantiles"
  else NA_character_
}

crps_dist <- function(d, y) {
  switch(.dist_kind(d),
    normal    = crps_normal(as.numeric(d$mu), as.numeric(d$sigma), y),
    samples   = crps_sample(unlist(d$samples), y),
    quantiles = crps_quantiles(as.numeric(names(d$q)), as.numeric(unlist(d$q)), y),
    stop("unrecognised continuous forecast shape"))
}

pit_dist <- function(d, y) {
  switch(.dist_kind(d),
    normal    = pit_normal(as.numeric(d$mu), as.numeric(d$sigma), y),
    samples   = pit_sample(unlist(d$samples), y),
    quantiles = pit_quantiles(as.numeric(names(d$q)), as.numeric(unlist(d$q)), y),
    stop("unrecognised continuous forecast shape"))
}
