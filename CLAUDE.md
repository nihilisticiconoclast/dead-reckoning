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
  questions via the Anthropic API. Runs only when `ANTHROPIC_API_KEY` is set.
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

## Local regeneration

Use the `reckon` skill (`.claude/skills/reckon/SKILL.md`): it resolves, scores, and
serves `docs/` for a local preview.
