#!/usr/bin/env Rscript
# Dead Reckoning — resolution bridge (push scores to Langfuse)
# ------------------------------------------------------------
# Reads docs/data.json (written by score.R) and attaches each resolved question's
# outcome and per-forecaster Brier/CRPS to its Langfuse trace as scores. That is
# what turns the traced generations into an eval surface: in Langfuse you can
# then filter calibration by prompt_version / model / category. score.R stays the
# scorer; this only mirrors its numbers across. Idempotent (stable score ids) and
# a no-op without LANGFUSE_* keys (prints in dry-run).
#
#   Rscript R/push_scores.R        # after Rscript R/score.R

suppressMessages(library(jsonlite))
source("R/langfuse.R")

DATA <- Sys.getenv("DR_OUT", "docs/data.json")
if (!file.exists(DATA)) { cat("no", DATA, "— run score.R first\n"); quit(save = "no") }
d <- fromJSON(DATA, simplifyVector = FALSE)

num <- function(x) if (is.null(x)) NA_real_ else as.numeric(x)
n <- 0L

# ---- binary: ground-truth outcome (0/1) + Brier per forecaster ---------------
for (r in d$resolved %||% list()) {
  tid <- lf_id(r$id)
  lf_score(tid, "outcome", as.numeric(r$outcome), "BOOLEAN",
           comment = r$text, score_id = lf_id(r$id, "outcome")); n <- n + 1L
  if (!is.null(r$brier_you))
    lf_score(tid, "brier_you",    num(r$brier_you),    "NUMERIC", score_id = lf_id(r$id, "brier", "you"))
  if (!is.null(r$brier_claude))
    lf_score(tid, "brier_claude", num(r$brier_claude), "NUMERIC", score_id = lf_id(r$id, "brier", "claude"))
}

# ---- continuous: realised value + CRPS per forecaster ------------------------
for (r in (d$continuous$questions %||% list())) {
  tid <- lf_id(r$id)
  lf_score(tid, "outcome_value", as.numeric(r$outcome), "NUMERIC",
           comment = r$text, score_id = lf_id(r$id, "outcome")); n <- n + 1L
  if (!is.null(r$crps_you))
    lf_score(tid, "crps_you",    num(r$crps_you),    "NUMERIC", score_id = lf_id(r$id, "crps", "you"))
  if (!is.null(r$crps_claude))
    lf_score(tid, "crps_claude", num(r$crps_claude), "NUMERIC", score_id = lf_id(r$id, "crps", "claude"))
}

cat(sprintf("Pushed scores for %d resolved question(s)%s\n", n,
            if (!lf_enabled()) " (dry-run)" else ""))
