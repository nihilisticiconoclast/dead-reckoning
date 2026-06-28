# Dead Reckoning — guide for Claude Code

A personal forecasting and calibration engine. You log probabilistic forecasts on
objectively-resolvable questions; resolved forecasts are scored with proper scoring
rules; a nightly GitHub Action regenerates the dashboard. Calibration is model
validation done on yourself — that is the point of the project.

## The one rule

A forecast is **pre-registered by its commit**. The git timestamp is the evidence
that the probability pre-dates the outcome. Never edit `forecasts.you` (or
`forecasts.claude`) for a question after its `resolves` date. Adding a *new*
question or resolving an existing one is fine; rewriting history is not.

## Layout

- `data/questions.yml` — source of truth. Hand-edited. Comments matter; preserve them.
- `R/score.R` — scoring engine. Reads the YAML, writes `docs/data.json`. No network.
- `R/resolve.R` — auto-resolves `http_json` questions that are past due; patches the
  outcome back into the YAML by surgical text edit (does not reserialise the file).
- `R/forecast_claude.R` — optional. Registers the model's probability on *open*
  questions via the Anthropic API. Runs only when `ANTHROPIC_API_KEY` is set. Also
  traces each generation to Langfuse when `LANGFUSE_*` is set (see below).
- `R/crps.R` — continuous scoring primitives (CRPS for Gaussian / quantile / sample
  forecasts, plus PIT). Pure functions, no I/O.
- `R/score_continuous.R` — the continuous sibling of `score.R`: scores `type:
  continuous` questions with CRPS + a PIT histogram; merged into `data.json` under
  `continuous`. Additive — the binary path and dashboard are untouched.
- `R/langfuse.R` — optional Langfuse REST client (observability only; not a ledger,
  not a scorer). No-ops without `LANGFUSE_*` env vars.
- `R/push_scores.R` — resolution bridge: reads `docs/data.json` and attaches each
  resolved outcome + Brier/CRPS to its Langfuse trace as scores.
- `data/questions.example.yml` — a resolved binary+continuous fixture for exercising
  the pipeline locally; not the real ledger.
- `docs/` — the GitHub Pages site. `index.html` + `app.css` + `app.js` are static;
  only `data.json` changes nightly. The Tunnel locked layer (`tokens.css`) and the
  seeded signature (`tunnel-figure.js`) are linked from the `cuddly-lamp` CDN, not
  vendored — keep them linked; `app.css` only bridges the dashboard's variables onto
  those tokens. To restyle, change the tokens upstream, not here.
- `.github/workflows/daily.yml` — the heartbeat: resolve → score → commit.

The committed `docs/data.json` was precomputed so the site renders on first deploy;
the Action overwrites it with the R output thereafter.

## Scoring (what the numbers mean)

For a forecast `p` and outcome `y ∈ {0,1}`:

- **Brier** = mean `(p − y)²` — lower is better.
- **Log loss** = mean `−(y log p + (1−y) log(1−p))` — lower is better; `p` is clipped
  off 0/1 only to avoid infinities.
- **Murphy decomposition**: `Brier = Reliability − Resolution + Uncertainty`, where
  reliability is calibration error (want 0), resolution is discrimination (want high),
  and uncertainty is `base_rate·(1−base_rate)` (irreducible).
- **BSS** = `1 − Brier / Uncertainty` — skill over always forecasting the base rate.

Calibration bins are width 0.1: `[0,0.1), … , [0.9,1.0]`.

### Continuous questions (CRPS)

A question with `type: continuous` forecasts a *number*, not a yes/no event. Each
forecaster gives a predictive distribution — `{ mu, sigma }` (recommended),
`{ q: {...} }` quantiles, or `{ samples: [...] }` — and resolves with the realised
value. These are scored by `R/score_continuous.R` with:

- **CRPS** = `∫ (F(x) − 1{x ≥ y})² dx` — proper scoring rule, generalises absolute
  error, in the units of `y`; lower is better. Reported per question (mixed units, so
  don't read the pooled mean as a verdict).
- **CRPSS** = equal-weight mean of per-question `1 − CRPS/CRPS_ref` (each normalised by
  its own `reference` climatology, so scales don't dominate). `> 0` beats climatology.
- **PIT histogram** — where each outcome fell in its predictive CDF; flat = calibrated,
  ∪ = over-confident, ∩ = under-confident. The continuous analogue of the calibration bins.

See the commented template at the bottom of `data/questions.yml`.

## Adding a question

Append a block to `data/questions.yml`:

```yaml
  - id: q-0NN
    text: "A statement that will be unambiguously true or false"
    category: fx | equities | macro | football | personal | meta
    created: YYYY-MM-DD
    resolves: YYYY-MM-DD
    resolution: { type: manual, note: "where the answer comes from" }
    forecasts: { you: 0.62 }
```

Leave `claude` out and the optional model step will fill it while the question is
still open. For automatic resolution, give it an `http_json` block (see `q-021`).

## Resolving

- **Manual**: add `outcome: 1` (statement true) or `outcome: 0` (false) to the block.
- **Automatic**: `Rscript R/resolve.R` fetches and resolves any due `http_json`
  questions.

Then `Rscript R/score.R` to regenerate `docs/data.json`, or just let the Action do it.

## Langfuse observability (optional)

Langfuse instruments the *generation* step — it does **not** store forecasts (git +
`questions.yml` remain the tamper-evident ledger) or re-score anything (`score.R`
owns that). When `forecast_claude.R` asks the model for a probability it logs the
prompt version, model, raw response, latency and token cost as a trace + generation;
`push_scores.R` then attaches the resolved Brier/CRPS back as scores, so you can slice
calibration by `prompt_version` / `model` in the Langfuse UI. That is the eval loop,
and where Phase-3 rival forecasters plug in (each rival = another generation per trace).

```
env LANGFUSE_PUBLIC_KEY   pk-lf-...        # absent ⇒ everything no-ops (dry-run prints)
env LANGFUSE_SECRET_KEY   sk-lf-...
env LANGFUSE_HOST         https://cloud.langfuse.com   (default)
env LANGFUSE_DRY_RUN      1                # force dry-run even with keys
```

Caveat: the free Hobby tier retains data for **30 days**, so for long-horizon
questions treat Langfuse as a recent-window dashboard, not an archive — `data.json`
and git are the durable record.

## Local regeneration

Use the `reckon` skill (`.claude/skills/reckon/SKILL.md`): it resolves, scores, and
serves `docs/` for a local preview.

To exercise the new scoring paths end to end without touching the real ledger:

```
DR_QUESTIONS=data/questions.example.yml DR_OUT=/tmp/dr-demo.json Rscript R/score.R
DR_OUT=/tmp/dr-demo.json LANGFUSE_DRY_RUN=1 Rscript R/push_scores.R
```
