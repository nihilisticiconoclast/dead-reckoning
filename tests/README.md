# Dead Reckoning  Tests

This directory contains unit tests for the R scripts in this project.

## Running Tests

### Local Execution
Run tests directly with R:
```bash
# Run all tests
Rscript tests/test_crps.R

# Run with verbose output (if tests fail)
Rscript tests/test_crps.R 2>&1 | less
```

### In CI
Add a step to your GitHub Actions workflow:
```yaml
- name: Run CRPS tests
  run: Rscript tests/test_crps.R
```

## Test Files

| File | Purpose | Dependencies |
|------|---------|--------------|
| `test_crps.R` | Tests for `R/crps.R` (CRPS, PIT) | Base R only |

## Test Coverage

### `test_crps.R`
Validates the continuous scoring primitives in `R/crps.R`:
- **Gaussian CRPS** (`crps_normal`):
  - Closed-form vs. brute-force integral.
  - Limit as `sigma -> 0` (CRPS -> `|mu - y|`).
  - Edge cases (NA, sigma <= 0).
- **Sample CRPS** (`crps_sample`):
  - Single sample (CRPS = `|x - y|`).
  - Two samples (manual calculation).
  - Convergence to Gaussian CRPS for large samples.
- **Quantile CRPS** (`crps_quantiles`):
  - Dense quantiles approximate Gaussian CRPS.
  - Single quantile (pinball loss).
- **PIT** (`pit_normal`, `pit_sample`, `pit_quantiles`):
  - Correct CDF mapping for normal, sample, and quantile distributions.
- **Dispatch** (`crps_dist`, `pit_dist`):
  - Routes to correct implementation based on input type.
- **Edge Cases**:
  - `.dist_kind()` classification.
  - NA/empty inputs.

## Adding New Tests
1. Create a new file in `tests/` (e.g., `test_score.R`).
2. Source the target script (e.g., `source("R/score.R")`).
3. Use the `pass()` helper for assertions:
   ```r
   all_pass <- pass("Test name", condition) && all_pass
   ```
4. Exit with `quit(save = "no")` (success) or `quit(save = "no", status = 1)` (failure).

## Numerical Tolerance
Tests use a tolerance of `1e-10` for floating-point comparisons. Adjust `TOL` in the test file if needed for your use case.
