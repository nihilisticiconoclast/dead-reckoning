#!/usr/bin/env Rscript
# Dead Reckoning — model rival (optional)
# ---------------------------------------
# For every OPEN question that does not yet carry a committed `claude:` forecast,
# ask the Anthropic API for a probability and write it back into questions.yml.
# This is the fairness mechanism: the model's number is committed (and git-dated)
# before the question resolves, exactly like yours. Runs only when ANTHROPIC_API_KEY
# is present; otherwise it is a no-op. Seed questions already carry a forecast, so
# this only fires for new questions you add with `you:` alone.
#
#   env ANTHROPIC_API_KEY  required to do anything
#   env DR_MODEL           optional, defaults to claude-sonnet-4-6

suppressMessages(library(yaml))

key <- Sys.getenv("ANTHROPIC_API_KEY")
if (!nzchar(key)) { cat("No ANTHROPIC_API_KEY; skipping model forecasts.\n"); quit(save = "no") }
suppressMessages(library(httr2))

# Optional Langfuse observability: traces each model forecast (prompt version,
# raw response, tokens, latency). No-ops without LANGFUSE_* env vars, so this is
# a safe add to the nightly Action. See R/langfuse.R.
if (file.exists("R/langfuse.R")) source("R/langfuse.R")

MODEL          <- Sys.getenv("DR_MODEL", "claude-sonnet-4-6")
PROMPT_VERSION <- "dr-forecast-v1"   # bump when you change SYSTEM, to compare calibration by version
SRC   <- "data/questions.yml"
TODAY <- Sys.Date()
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

SYSTEM <- paste(
  "You are a careful, well-calibrated forecaster.",
  "You will be given a yes/no question with a resolution date.",
  "Reply with ONLY your probability that the statement resolves TRUE:",
  "a single decimal between 0.01 and 0.99, no other text."
)

# Returns a list so the caller can both write the number into the ledger and log
# the full generation (raw text, usage, latency) to Langfuse.
ask <- function(question, resolves) {
  user <- sprintf("Question: %s\nResolves: %s\nProbability TRUE:", question, resolves)
  body <- list(
    model = MODEL, max_tokens = 16,
    system = SYSTEM,
    messages = list(list(role = "user", content = user))
  )
  started <- Sys.time()
  resp <- request("https://api.anthropic.com/v1/messages") |>
    req_headers("x-api-key" = key, "anthropic-version" = "2023-06-01",
                "content-type" = "application/json") |>
    req_body_json(body) |>
    req_retry(max_tries = 3) |>
    req_perform()
  ended  <- Sys.time()
  parsed <- resp_body_json(resp)
  txt <- parsed$content[[1]]$text
  p <- suppressWarnings(as.numeric(regmatches(txt, regexpr("0?\\.[0-9]+|[01]", txt))))
  if (is.na(p)) stop("could not parse probability from: ", txt)
  u <- parsed$usage %||% list()
  list(
    p = round(min(max(p, 0.01), 0.99), 2), raw = txt, user = user,
    usage = list(input  = u$input_tokens  %||% NA, output = u$output_tokens %||% NA,
                 total  = (u$input_tokens %||% 0) + (u$output_tokens %||% 0), unit = "TOKENS"),
    started = started, ended = ended
  )
}

# insert ", claude: Y" into a flow-style forecasts line lacking claude
patch_forecast <- function(text, id, p) {
  pat <- sprintf("(?s)(  - id:\\s*%s\\b.*?)(?=(\\n  - id:|\\Z))", id)
  m <- regmatches(text, regexpr(pat, text, perl = TRUE))
  if (!length(m)) return(text)
  block <