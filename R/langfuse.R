# Dead Reckoning — Langfuse client (optional observability)
# ---------------------------------------------------------
# A thin REST wrapper over the Langfuse public API. It does NOT store forecasts
# (git + questions.yml remain the tamper-evident ledger) and it does NOT re-score
# anything (score.R owns that). Its single job is to make the *generation step*
# legible: when forecast_claude.R asks the model for a probability, we log the
# prompt version, model, raw response, latency and token cost as a trace +
# generation, so you can later ask "which prompt/model forecasts best-calibrated?"
# push_scores.R then attaches the resolved Brier/CRPS back onto each trace.
#
# Safe by construction, mirroring forecast_claude.R's key-gated pattern:
#   * no LANGFUSE_PUBLIC_KEY / LANGFUSE_SECRET_KEY  -> dry-run (prints, no network)
#   * LANGFUSE_DRY_RUN=1                            -> dry-run even with keys
# So sourcing this in CI without secrets changes nothing.
#
#   env LANGFUSE_PUBLIC_KEY   pk-lf-...
#   env LANGFUSE_SECRET_KEY   sk-lf-...
#   env LANGFUSE_HOST         default https://cloud.langfuse.com
#   env LANGFUSE_DRY_RUN      set to 1 to force dry-run

suppressMessages(library(jsonlite))

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

LF_HOST    <- sub("/+$", "", Sys.getenv("LANGFUSE_HOST", "https://cloud.langfuse.com"))
LF_PUBLIC  <- Sys.getenv("LANGFUSE_PUBLIC_KEY")
LF_SECRET  <- Sys.getenv("LANGFUSE_SECRET_KEY")
LF_OBS_EVENT <- "generation-create"   # observation event type; some self-host V4 setups use "span-create"

lf_enabled <- function()
  nzchar(LF_PUBLIC) && nzchar(LF_SECRET) && Sys.getenv("LANGFUSE_DRY_RUN") != "1"

# ISO-8601 UTC with milliseconds, the timestamp format the ingestion API expects
lf_now <- function(t = Sys.time())
  format(as.POSIXlt(t, tz = "UTC"), "%Y-%m-%dT%H:%M:%OS3Z")

# Langfuse ids may be any string; readable, deterministic ids make updates
# idempotent (re-running attaches to the same trace instead of duplicating).
lf_id <- function(...) gsub("[^A-Za-z0-9_.:-]", "-", paste(..., sep = ":"))

# unique-per-event envelope id (only needs to be unique within a request)
.lf_event_id <- function()
  paste0(format(Sys.time(), "%Y%m%d%H%M%OS3"), "-",
         paste0(sample(c(0:9, letters), 10, TRUE), collapse = ""))

.lf_json <- function(x) toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA)

# Low-level POST. Loads httr2 only when actually sending, so the file sources
# fine without it. Returns the HTTP status invisibly; never throws.
.lf_post <- function(path, body) {
  json <- .lf_json(body)
  if (!lf_enabled()) {
    cat(sprintf("[langfuse dry-run] POST %s%s\n%s\n", LF_HOST, path,
                toJSON(body, auto_unbox = TRUE, null = "null", na = "null", pretty = TRUE)))
    return(invisible(0L))
  }
  if (!requireNamespace("httr2", quietly = TRUE)) {
    message("langfuse: httr2 not installed; skipping POST ", path); return(invisible(-1L))
  }
  tryCatch({
    resp <- httr2::request(paste0(LF_HOST, path)) |>
      httr2::req_auth_basic(LF_PUBLIC, LF_SECRET) |>
      httr2::req_headers("content-type" = "application/json") |>
      httr2::req_body_raw(json, type = "application/json") |>
      httr2::req_retry(max_tries = 3) |>
      httr2::req_error(is_error = function(r) FALSE) |>   # 207 is success here
      httr2::req_perform()
    st <- httr2::resp_status(resp)
    if (st >= 400) message(sprintf("langfuse %s -> HTTP %d", path, st))
    invisible(st)
  }, error = function(e) { message("langfuse POST failed: ", conditionMessage(e)); invisible(-1L) })
}

# ---- batch ingestion: one trace (the question) + one generation (this model) -
# Returns the trace id so the caller can stash it for later scoring.
lf_log_forecast <- function(question_id, text, category, resolves, forecaster,
                            model, system_prompt, user_content, raw_text, prob,
                            prompt_version = NA, usage = NULL, params = NULL,
                            started = NULL, ended = NULL) {
  ts       <- lf_now()
  trace_id <- lf_id(question_id)
  obs_id   <- lf_id(question_id, forecaster, model)
  run_date <- as.character(Sys.Date())

  trace_body <- list(
    id = trace_id, name = "forecast", timestamp = ts,
    input = list(question = text, resolves = as.character(resolves)),
    metadata = list(question_id = question_id, category = category,
                    resolves = as.character(resolves), dr_run_date = run_date),
    tags = c("dead-reckoning", category))

  gen_body <- list(
    id = obs_id, traceId = trace_id, name = paste0(forecaster, "-forecast"),
    model = model, modelParameters = params,
    startTime = started %||% ts, endTime = ended %||% ts,
    input = list(system = system_prompt, user = user_content),
    output = raw_text, usage = usage,
    metadata = list(forecaster = forecaster, prompt_version = prompt_version,
                    parsed_prob = prob, category = category,
                    resolves = as.character(resolves)))

  batch <- list(batch = list(
    list(id = .lf_event_id(), type = "trace-create",  timestamp = ts, body = trace_body),
    list(id = .lf_event_id(), type = LF_OBS_EVENT,    timestamp = ts, body = gen_body)))

  .lf_post("/api/public/ingestion", batch)
  invisible(trace_id)
}

# ---- attach a score to a trace (the resolution bridge uses this) -------------
# data_type: NUMERIC | BOOLEAN | CATEGORICAL | TEXT. Pass a stable score_id
# (e.g. "<trace>:brier:you") to update rather than duplicate on re-runs.
lf_score <- function(trace_id, name, value, data_type = "NUMERIC",
                     comment = NULL, observation_id = NULL, score_id = NULL) {
  body <- list(traceId = trace_id, name = name, value = value, dataType = data_type,
               observationId = observation_id, comment = comment, id = score_id)
  body <- body[!vapply(body, is.null, logical(1))]
  .lf_post("/api/public/scores", body)
}
