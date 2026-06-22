#!/usr/bin/env Rscript
# Dead Reckoning — automatic resolver
# -----------------------------------
# For every question that is (a) past its resolves date, (b) still unresolved,
# and (c) carries an `http_json` resolution block, fetch the document, walk
# `path`, compare against `threshold` with `op`, and write the 0/1 outcome back
# into data/questions.yml. Manual questions are left untouched for you to
# resolve by hand. Failures (unreachable / ambiguous) are skipped, never guessed.
#
# A resolution block looks like:
#   resolution:
#     type: http_json
#     url: "https://api.example.com/thing"
#     path: "data.0.value"      # dot path; integer tokens are 1-based indices
#     op: ">="                  # one of > >= < <= ==
#     threshold: 1

suppressMessages(library(yaml))
suppressMessages(library(jsonlite))

TODAY <- Sys.Date()
SRC   <- "data/questions.yml"
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

walk_path <- function(obj, path) {
  for (tok in strsplit(path, ".", fixed = TRUE)[[1]]) {
    obj <- if (grepl("^[0-9]+$", tok)) obj[[as.integer(tok)]] else obj[[tok]]
    if (is.null(obj)) stop("path miss at '", tok, "'")
  }
  obj
}

compare <- function(value, op, threshold) {
  v <- as.numeric(value); t <- as.numeric(threshold)
  res <- switch(op, ">" = v > t, ">=" = v >= t, "<" = v < t,
                "<=" = v <= t, "==" = v == t, stop("unknown op: ", op))
  as.integer(isTRUE(res))
}

fetch_json <- function(url) {
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp), add = TRUE)
  utils::download.file(url, tmp, quiet = TRUE,
                       headers = c("User-Agent" = "dead-reckoning-bot",
                                   "Accept" = "application/json"))
  jsonlite::fromJSON(tmp, simplifyVector = FALSE)
}

# patch a single `outcome:` line into the block for `id`, preserving everything
patch_outcome <- function(text, id, outcome) {
  pat <- sprintf("(?s)(  - id:\\s*%s\\b.*?)(?=(\\n  - id:|\\Z))", id)
  m <- regmatches(text, regexpr(pat, text, perl = TRUE))
  if (!length(m)) return(text)
  block <- m[[1]]
  if (grepl("\\n\\s*outcome:", block)) return(text)         # already resolved
  patched <- sub("\\s*$", sprintf("\n    outcome: %d\n", outcome), block)
  sub(pat, patched, text, perl = TRUE)
}

text <- paste(readLines(SRC, warn = FALSE), collapse = "\n")
q <- yaml::read_yaml(SRC)$questions

n_resolved <- 0
for (it in q) {
  resv <- as.Date(as.character(it$resolves))
  if (!is.null(it$outcome)) next
  if (resv > TODAY) next
  r <- it$resolution %||% list(type = "manual")
  if ((r$type %||% "manual") != "http_json") next
  out <- tryCatch({
    doc <- fetch_json(r$url)
    val <- walk_path(doc, r$path)
    compare(val, r$op, r$threshold)
  }, error = function(e) { message(sprintf("  skip %s: %s", it$id, conditionMessage(e))); NA_integer_ })
  if (is.na(out)) next
  text <- patch_outcome(text, it$id, out)
  n_resolved <- n_resolved + 1
  cat(sprintf("  resolved %s -> %d\n", it$id, out))
}

if (n_resolved > 0) writeLines(text, SRC)
cat(sprintf("Auto-resolved %d question(s)\n", n_resolved))
