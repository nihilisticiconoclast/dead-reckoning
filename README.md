# Dead Reckoning

A personal forecasting and calibration engine. You log probabilistic forecasts on
questions that will resolve unambiguously; each resolved forecast is scored with
proper scoring rules; a nightly GitHub Action recomputes everything and regenerates
a dashboard served from GitHub Pages.

The name is the navigation sense: you commit a course *before* you have a fix.
Here, you commit a probability before the outcome is known — and the git commit
timestamp is tamper-evident proof the forecast came first. Calibration is model
validation turned on yourself, which is the whole idea.

The dashboard scores **you** against an optional **model rival** (Claude, via the
API) on identical questions and an identical scoring rule — a human-versus-model
validation harness you can actually look at.

## What it shows

- **Brier**, **log loss**, and **Brier Skill Score** for you and the model.
- A **reliability diagram**: of the times you said 70%, did ~70% happen?
- The **Murphy decomposition** — `Brier = Reliability − Resolution + Uncertainty` —
  which separates *calibration* (are your probabilities honest) from *resolution*
  (do they discriminate outcomes), and so explains *why* one forecaster is ahead.
- A running cumulative-Brier track, plus open positions, due-but-unresolved
  questions, and the resolved log.

The look is the in-house **Tunnel** aesthetic — chart-paper palette, Fraunces /
Public Sans / IBM Plex Mono, hard edges, and the contour-map signature (a route
that follows the valley and tunnels through the ridge). The locked layer
(`tokens.css`) and the seeded figure (`tunnel-figure.js`) are **linked from the
`cuddly-lamp` CDN, not vendored**, so a house-style update there reaches this page
automatically; `docs/app.css` only bridges the dashboard's variables onto those
tokens and lays out the page.

## Go live (4 steps)

1. **Push** this repo to GitHub (e.g. `nihilisticiconoclast/dead-reckoning`).
2. **Settings → Pages →** Source = *Deploy from a branch*, Branch = your default
   branch, Folder = **`/docs`**. The site is live at
   `https://<user>.github.io/dead-reckoning/`.
3. **Actions →** enable workflows. `reckon` runs nightly (06:00 UTC) and on demand;
   it resolves due questions, rescoring and committing `docs/data.json`.
4. *(Optional)* **Settings → Secrets → Actions →** add `ANTHROPIC_API_KEY` to turn on
   the model rival. Without it, everything else works; that step simply no-ops.

The committed `docs/data.json` is precomputed so the page renders on first deploy.
From then on the Action overwrites it with the output of `R/score.R`.

## Add a forecast

Append a block to `data/questions.yml`:

```yaml
  - id: q-0NN
    text: "A statement that will be unambiguously true or false"
    category: fx | equities | macro | football | personal | meta
    created: YYYY-MM-DD
    resolves: YYYY-MM-DD
    resolution: { type: manual, note: "where the answer will come from" }
    forecasts: { you: 0.62 }
```

Commit it. If you leave `claude` out and have set the API key, the model registers
its own probability while the question is still open (its forecast is committed and
git-dated too — same pre-registration discipline).

## Resolve a forecast

- **Manually**: set `outcome: 1` (true) or `outcome: 0` (false) on the block, commit.
- **Automatically**: give the question an `http_json` resolver and let the Action
  fetch and decide:

  ```yaml
    resolution:
      type: http_json
      url: "https://api.example.com/thing"
      path: "data.0.value"   # dot path; integer tokens are 1-based indices
      op: ">="               # one of  >  >=  <  <=  ==
      threshold: 100
  ```

  `q-021` is a working example that resolves against the GitHub REST API.

## Run it locally

```bash
Rscript -e 'install.packages(c("jsonlite","yaml"))'   # once
Rscript R/resolve.R        # auto-resolve any due http_json questions
Rscript R/score.R          # regenerate docs/data.json
python3 -m http.server 8000 --directory docs   # then open http://localhost:8000
```

Serve `docs/` over HTTP rather than opening `index.html` from disk — the page
fetches `data.json`. The Tunnel `tokens.css` and `tunnel-figure.js` load from the
`cuddly-lamp` CDN, so local preview needs network for the styling and the contour
signature (the dashboard itself still renders without them). With Claude Code, the
`reckon` skill does all three steps.

## Layout

```
data/questions.yml          source of truth (hand-edited; comments matter)
R/score.R                   scoring engine  → docs/data.json   (no network)
R/resolve.R                 auto-resolver for http_json questions
R/forecast_claude.R         optional model rival (needs ANTHROPIC_API_KEY)
docs/index.html             the Pages site; links Tunnel tokens.css + tunnel-figure.js (CDN)
docs/app.css  docs/app.js   dashboard layout + renderer; data.json changes nightly
.github/workflows/daily.yml the heartbeat: resolve → score → commit
CLAUDE.md                   guide for Claude Code
```

## The one rule

A forecast is pre-registered by its commit. Never edit a forecast after its
`resolves` date — adding new questions or resolving existing ones is fine, but
rewriting a probability in hindsight defeats the entire instrument.
