#!/usr/bin/env Rscript
# Dead Reckoning — scoring engine
# -------------------------------
# Reads data/questions.yml, scores every resolved forecast with proper scoring
# rules, computes a reliability/resolution/uncertainty (Murphy) decomposition,
# and writes docs/data.json for the dashboard. No network, no secrets.
#
#   Brier        mean (p - y)^2                         lower is better, [0,1]
#   Log loss     mean -(y log p + (1-y) log(1-p))       lower is better
#   Reliability  sum_k (n_k/N)(f_k - o_k)^2             calibration error, want 0
#   Resolution   sum_k (n_k/N)(o_k - obar)^2            discrimination, want high
#   Uncertainty  obar (1 - obar)                        irreducible (base rate)
#   Brier  ==  Reliability - Resolution + Uncertainty   (Murphy 1973)
#   BSS          1 - Brier / Uncertainty                skill vs always-base-rate

suppressMessages({
  library(yaml)
  library(jsonlite)
})

TODAY <- Sys.Date()
EPS   <- 1e-15
FORECASTERS <- c("you", "claude")

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

bin_of <- function(p) pmin(as.integer(p * 10), 9L)   # [0,.1) .. [.9,1]; p==1 -> 9

round4 <- function(x) round(x, 4)

# ---- load --------------------------------------------------------------------
# Paths are env-overridable so you can score an example ledger to a throwaway
# output without clobbering the real one (see data/questions.example.yml).
QSRC <- Sys.getenv("DR_QUESTIONS", "data/questions.yml")
q <- yaml::read_yaml(QSRC)$questions

field <- function(item, ...) {
  path <- c(...); v <- item
  for (k in path) v <- v[[k]]
  v
}

rows <- lapply(q, function(it) {
  list(
    id        = it$id,
    text      = it$text,
    category  = it$category %||% "uncategorised",
    type      = it$type %||% "binary",     # yes/no unless the block declares continuous
    units     = it$units %||% NA_character_,
    resolves  = as.Date(as.character(it$resolves)),
    you       = field(it, "forecasts", "you"),
    claude    = field(it, "forecasts", "claude") %||% NA_real_,
    reference = it$reference,               # optional climatology for the CRPS skill score
    outcome   = if (is.null(it$outcome)) NA_real_ else as.numeric(it$outcome),
    hint      = field(it, "resolution", "type") %||% "manual"
  )
})

# The binary engine below scores yes/no questions only. Continuous questions
# (numeric outcome) are routed out here and scored with CRPS in
# R/score_continuous.R, so the existing dashboard fields stay binary-meaningful.
is_resolved <- function(r) identical(r$type, "binary") && !is.na(r$outcome) && r$outcome %in% c(0, 1)
binary   <- Filter(function(r) identical(r$type, "binary"), rows)
resolved <- Filter(is_resolved, binary)
pending  <- Filter(function(r) !is_resolved(r), binary)
awaiting <- Filter(function(r) r$resolves <= TODAY, pending)
openq    <- Filter(function(r) r$resolves >  TODAY, pending)

# deterministic order
ord <- function(lst) lst[order(vapply(lst, function(r) as.integer(r$resolves), 0L))]
resolved <- ord(resolved)
openq    <- ord(openq)

# ---- score one forecaster ----------------------------------------------------
score_one <- function(rs, key) {
  p <- vapply(rs, function(r) r[[key]], 0)
  y <- vapply(rs, function(r) r$outcome, 0L)
  n <- length(y)
  obar <- mean(y)
  brier <- mean((p - y)^2)
  pc <- pmin(pmax(p, EPS), 1 - EPS)
  logloss <- mean(-(y * log(pc) + (1 - y) * log(1 - pc)))

  b <- bin_of(p)
  reliability <- 0; resolution <- 0; bins <- list()
  for (k in 0:9) {
    sel <- which(b == k)
    if (!length(sel)) next
    nk <- length(sel)
    fk <- mean(p[sel]); ok <- mean(y[sel])
    reliability <- reliability + (nk / n) * (fk - ok)^2
    resolution  <- resolution  + (nk / n) * (ok - obar)^2
    bins[[length(bins) + 1]] <- list(
      lo = k / 10, hi = (k + 1) / 10, n = nk,
      mean_forecast = round4(fk), observed = round4(ok)
    )
  }
  uncertainty <- obar * (1 - obar)
  bss <- if (!is.na(uncertainty) && uncertainty > 0) 1 - brier / uncertainty else NA_real_

  list(
    summary = list(
      label = if (key == "you") "You" else "Claude",
      n = n, brier = round4(brier), logloss = round4(logloss),
      bss = round4(bss), reliability = round4(reliability),
      resolution = round4(resolution), uncertainty = round4(uncertainty)
    ),
    bins = bins
  )
}

# ---- assemble ----------------------------------------------------------------
forecasters <- list(); calibration <- list()
timeseries <- list(labels = vapply(resolved, function(r) r$id, ""))
for (key in FORECASTERS) {
  s <- score_one(resolved, key)
  forecasters[[key]] <- s$summary
  calibration[[key]] <- s$bins
  run <- numeric(length(resolved)); acc <- 0
  for (i in seq_along(resolved)) {
    acc <- acc + (resolved[[i]][[key]] - resolved[[i]]$outcome)^2
    run[i] <- round4(acc / i)
  }
  timeseries[[key]] <- run
}

resolved_out <- lapply(resolved, function(r) list(
  id = r$id, text = r$text, category = r$category,
  resolves = as.character(r$resolves), you = r$you, claude = r$claude,
  outcome = r$outcome,
  brier_you = round4((r$you - r$outcome)^2),
  brier_claude = round4((r$claude - r$outcome)^2)
))
open_out <- lapply(openq, function(r) list(
  id = r$id, text = r$text, category = r$category,
  resolves = as.character(r$resolves), you = r$you, claude = r$claude
))
awaiting_out <- lapply(awaiting, function(r) list(
  id = r$id, text = r$text, category = r$category,
  resolves = as.character(r$resolves), you = r$you, claude = r$claude,
  hint = r$hint
))

out <- list(
  generated_at = format(as.POSIXlt(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ"),
  counts = list(resolved = length(resolved), open = length(openq),
                awaiting = length(awaiting)),
  base_rate = rou