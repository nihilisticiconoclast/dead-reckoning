# Dead Reckoning — continuous (CRPS) scoring
# ------------------------------------------
# The binary engine in score.R handles yes/no questions with Brier + the Murphy
# decomposition. This file is its continuous sibling: for questions of type
# `continuous` (a forecast of a number), it scores each forecaster's predictive
# distribution with CRPS, a skill score vs a climatological reference, and a PIT
# histogram — the continuous analogue of the calibration bins. It is additive:
# score.R sources it and merges the result under `out$continuous`; nothing here
# touches the binary path.
#
# Returns NULL when there are no resolved continuous questions yet (the current
# all-binary ledger), so the dashboard data is unchanged until you add one.

source("R/crps.R", local = TRUE)

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
round4  <- function(x) if (is.na(x)) NA_real_ else round(x, 4)
.pitbin <- function(p) pmin(as.integer(p * 10), 9L)   # [0,.1) .. [.9,1]

# rows: the same simplified row list score.R builds, carrying
#   type, units, reference, you, claude, outcome (numeric), resolves, ...
score_continuous <- function(rows, forecasters, today) {

  num_ok <- function(r) !is.null(r$outcome) &&
                        is.finite(suppressWarnings(as.numeric(r$outcome)))
  cont <- Filter(function(r) identical(r$type, "continuous") && num_ok(r), rows)
  if (!length(cont)) return(NULL)

  cont <- cont[order(vapply(cont, function(r)
            as.integer(as.Date(as.character(r$resolves))), 0L))]
  ys <- vapply(cont, function(r) as.numeric(r$outcome), 0)

  # ---- per forecaster: mean CRPS, skill score, PIT histogram -----------------
  fc <- list(); pit_out <- list()
  for (key in forecasters) {
    crps_i <- ref_i <- pit_i <- rep(NA_real_, length(cont))
    for (j in seq_along(cont)) {
      d <- cont[[j]][[key]]; if (is.null(d)) next
      y <- ys[j]
      crps_i[j] <- tryCatch(crps_dist(d, y), error = function(e) NA_real_)
      pit_i[j]  <- tryCatch(pit_dist(d,  y), error = function(e) NA_real_)
      refd <- cont[[j]]$reference                 # climatology for the skill score
      ref_i[j] <- if (!is.null(refd)) {
        tryCatch(crps_dist(refd, y), error = function(e) NA_real_)
      } else {                                    # fall back to leave-one-out empirical
        others <- ys[-j]
        if (length(others) >= 2) crps_sample(others, y) else NA_real_
      }
    }
    ok <- which(!is.na(crps_i)); n <- length(ok)
    mean_crps <- if (n) mean(crps_i[ok]) else NA_real_   # pooled, mixed units — see note
    # Skill score: normalise each question by its OWN reference (so it is
    # unit-free) and average with equal weight. A plain pooled ratio would let
    # large-scale questions (an index in the thousands) drown out small ones
    # (an fx rate near 1), which is not what "skill" should mean here.
    ss    <- ifelse(!is.na(ref_i) & ref_i > 0, 1 - crps_i / ref_i, NA_real_)
    crpss <- if (any(!is.na(ss))) mean(ss, na.rm = TRUE) else NA_real_

    counts <- integer(10); pv <- pit_i[!is.na(pit_i)]
    if (length(pv)) for (k in 0:9) counts[k + 1] <- sum(.pitbin(pv) == k)

    fc[[key]] <- list(label = if (key == "you") "You" else "Claude",
                      n = n, crps = round4(mean_crps), crpss = round4(crpss))
    pit_out[[key]] <- as.list(counts)
  }

  # ---- per-question detail (parallels resolved[] in the binary output) --------
  one_crps <- function(d, y) if (is.null(d)) NA_real_ else
                round4(tryCatch(crps_dist(d, y), error = function(e) NA_real_))
  questions <- lapply(seq_along(cont), function(j) {
    r <- cont[[j]]
    list(id = r$id, text = r$text, category = r$category,
         units = r$units %||% NA, resolves = as.character(r$resolves),
         outcome = ys[j],
         crps_you = one_crps(r$you, ys[j]), crps_claude = one_crps(r$claude, ys[j]))
  })

  list(n = length(cont), forecasters = fc, pit = pit_out, questions = questions)
}
