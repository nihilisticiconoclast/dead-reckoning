---
name: reckon
description: Resolve due questions, recompute scores, and preview the Dead Reckoning dashboard locally. Use when forecasts have been added or resolved in data/questions.yml, when docs/data.json needs regenerating, or when the user wants to see the dashboard before pushing.
---

# reckon

Regenerate the forecasting dashboard from `data/questions.yml`.

## Steps

1. **Resolve** anything past due that resolves automatically:
   ```bash
   Rscript R/resolve.R
   ```
   Manual questions are left for the user to resolve by hand (set `outcome:` in the
   YAML). Do not invent outcomes.

2. **Score** — regenerate `docs/data.json`:
   ```bash
   Rscript R/score.R
   ```
   Echoes Brier / log loss / BSS / reliability / resolution for `you` and `claude`.

3. **Preview** — serve `docs/` and open it:
   ```bash
   python3 -m http.server 8000 --directory docs
   ```
   then visit http://localhost:8000 . The page fetches `data.json`, so serve it over
   HTTP rather than opening the file directly. The Tunnel `tokens.css` and
   `tunnel-figure.js` load from the `cuddly-lamp` CDN, so styling and the contour
   signature need network; the dashboard data still renders offline.

## Notes

- First run needs the R packages: `Rscript -e 'install.packages(c("jsonlite","yaml"))'`
  (add `httr2` only if using the optional model-forecast step).
- Never rewrite a forecast after its `resolves` date — the commit history is the
  pre-registration record.
- If `data.json` looks wrong, re-read `data/questions.yml`: a missing `outcome` keeps a
  question out of the resolved scores; a date in the future keeps it in *open*.
