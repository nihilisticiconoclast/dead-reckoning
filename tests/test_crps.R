# Dead Reckoning  Unit Tests for CRPS (R/crps.R)
# -----------------------------------------------
# Run with: Rscript tests/test_crps.R
#
# Tests the continuous scoring primitives in R/crps.R:
# - crps_normal, crps_sample, crps_quantiles
# - pit_normal, pit_sample, pit_quantiles
# - crps_dist, pit_dist (dispatch)
#
# All tests are numerical and self-contained (no external dependencies).

source("R/crps.R", local = TRUE)

# ---- Helpers ------------------------------------------------------------------
TOL <- 1e-10  # Tolerance for numerical equality

pass <- function(test_name, condition) {
  if (condition) {
    cat(sprintf("✅ PASS: %s\n", test_name))
    TRUE
  } else {
    cat(sprintf("❌ FAIL: %s\n", test_name))
    FALSE
  }
}

all_pass <- TRUE

# ---- 1. Gaussian CRPS (crps_normal) -------------------------------------------
# Test 1.1: Closed-form vs. brute-force integral (for a few (mu, sigma, y) combos)
# We approximate the integral: CRPS = ∫ (F(x) - 1{x >= y})^2 dx
# using a fine grid. This is slow but verifies the closed-form.
brute_crps_normal <- function(mu, sigma, y, n = 1e5) {
  x <- seq(mu - 5 * sigma, mu + 5 * sigma, length.out = n)
  F <- pnorm(x, mean = mu, sd = sigma)
  I <- as.numeric(x >= y)
  sum((F - I)^2) * (x[2] - x[1])  # Riemann sum
}

all_pass <- pass("Gaussian CRPS: closed-form vs. brute-force (mu=0, sigma=1, y=0)",
                 abs(crps_normal(0, 1, 0) - brute_crps_normal(0, 1, 0)) < 1e-3) && all_pass

all_pass <- pass("Gaussian CRPS: closed-form vs. brute-force (mu=1, sigma=2, y=-1)",
                 abs(crps_normal(1, 2, -1) - brute_crps_normal(1, 2, -1)) < 1e-3) && all_pass

# Test 1.2: CRPS -> |mu - y| as sigma -> 0
all_pass <- pass("Gaussian CRPS: sigma -> 0 => CRPS -> |mu - y|",
                 abs(crps_normal(10, 1e-6, 10.5) - 0.5) < 1e-4) && all_pass

all_pass <- pass("Gaussian CRPS: sigma -> 0 => CRPS -> |mu - y| (y < mu)",
                 abs(crps_normal(10, 1e-6, 9.3) - 0.7) < 1e-4) && all_pass

# Test 1.3: Edge cases
all_pass <- pass("Gaussian CRPS: sigma <= 0 returns NA",
                 is.na(crps_normal(0, 0, 0))) && all_pass
all_pass <- pass("Gaussian CRPS: NA inputs return NA",
                 is.na(crps_normal(NA, 1, 0))) && all_pass

# ---- 2. Sample CRPS (crps_sample) ----------------------------------------------
# Test 2.1: Single sample => CRPS = |x - y|
all_pass <- pass("Sample CRPS: single sample => |x - y|",
                 abs(crps_sample(5, 3) - 2) < TOL) && all_pass

# Test 2.2: Two samples => matches manual calculation
# For x = [a, b], CRPS = mean(|x_i - y|) - 0.5 * mean_{i,j} |x_i - x_j|
# mean_{i,j} |x_i - x_j| = |a - b| for 2 samples.
# So CRPS = (|a-y| + |b-y|)/2 - 0.5 * |a - b|
a <- 1; b <- 3; y <- 2
manual_crps <- (abs(a - y) + abs(b - y)) / 2 - 0.5 * abs(a - b)
all_pass <- pass("Sample CRPS: two samples => manual calculation",
                 abs(crps_sample(c(a, b), y) - manual_crps) < TOL) && all_pass

# Test 2.3: Empty samples => NA
all_pass <- pass("Sample CRPS: empty samples => NA",
                 is.na(crps_sample(numeric(0), 1))) && all_pass

# Test 2.4: Convergence to Gaussian CRPS for large samples
set.seed(42)
mu <- 0; sigma <- 1; y <- 0.5
samples <- rnorm(1e5, mean = mu, sd = sigma)
all_pass <- pass("Sample CRPS: converges to Gaussian (n=1e5)",
                 abs(crps_sample(samples, y) - crps_normal(mu, sigma, y)) < 0.01) && all_pass

# ---- 3. Quantile CRPS (crps_quantiles) ------------------------------------------
# Test 3.1: Matches Gaussian CRPS for dense quantiles
# Use 100 quantiles from a N(mu, sigma) distribution
taus <- seq(0.01, 0.99, by = 0.01)
qs <- qnorm(taus, mean = 0, sd = 1)
y <- 0
all_pass <- pass("Quantile CRPS: dense quantiles ~ Gaussian (mu=0, sigma=1, y=0)",
                 abs(crps_quantiles(taus, qs, y) - crps_normal(0, 1, y)) < 0.01) && all_pass

# Test 3.2: Pinball loss at a single quantile (tau=0.5, q=median)
# For tau=0.5, QL = 0.5 * |q - y| (since 1{x >= y} is 0 or 1)
# CRPS = 2 * integral_0^1 QL_tau d tau ≈ 2 * 0.5 * |q - y| for a single quantile at 0.5
# But with only one quantile, the trapezoid rule gives:
# taus = [0.5], qs = [q], y = y
# ql = ifelse(y >= q, 0.5 * (y - q), 0.5 * (q - y))
# padded: tg = [0, 0.5, 1], qg = [ql, ql, ql]
# integral = 2 * (0.5 * (ql + ql)/2 + 0.5 * (ql + ql)/2) = 2 * (0.5 * ql) = ql
# So CRPS = ql = 0.5 * |q - y|
q <- 1; y <- 2
manual_ql <- abs(q - y)  # CRPS = 2*int(QL); lone median => point-forecast |q-y|
all_pass <- pass("Quantile CRPS: single quantile (tau=0.5) => |q - y|",
                 abs(crps_quantiles(0.5, q, y) - manual_ql) < TOL) && all_pass

# ---- 4. PIT (Probability Integral Transform) ------------------------------------
# Test 4.1: pit_normal(mu, sigma, y) = pnorm((y - mu)/sigma)
all_pass <- pass("PIT: normal => pnorm",
                 abs(pit_normal(0, 1, 1) - pnorm(1)) < TOL) && all_pass

# Test 4.2: pit_sample(x, y) = mean(x <= y)
x <- c(1, 2, 3, 4, 5); y <- 3
all_pass <- pass("PIT: sample => mean(x <= y)",
                 abs(pit_sample(x, y) - mean(x <= y)) < TOL) && all_pass

# Test 4.3: pit_quantiles(taus, qs, y) = approx(qs, taus, xout = y)$y
# For taus = [0.1, 0.9], qs = [-1, 1], y = 0:
# approx([-1, 1], [0.1, 0.9], xout = 0) should interpolate to 0.5
taus <- c(0.1, 0.9); qs <- c(-1, 1); y <- 0
all_pass <- pass("PIT: quantiles => approx",
                 abs(pit_quantiles(taus, qs, y) - 0.5) < TOL) && all_pass

# ---- 5. Dispatch (crps_dist, pit_dist) --------------------------------------------
# Test 5.1: crps_dist routes to crps_normal for mu/sigma
d <- list(mu = 0, sigma = 1)
all_pass <- pass("Dispatch: crps_dist => crps_normal",
                 abs(crps_dist(d, 0) - crps_normal(0, 1, 0)) < TOL) && all_pass

# Test 5.2: crps_dist routes to crps_sample for samples
d <- list(samples = c(1, 2, 3))
all_pass <- pass("Dispatch: crps_dist => crps_sample",
                 abs(crps_dist(d, 2) - crps_sample(c(1, 2, 3), 2)) < TOL) && all_pass

# Test 5.3: crps_dist routes to crps_quantiles for q
d <- list(q = c(`0.5` = 1))
all_pass <- pass("Dispatch: crps_dist => crps_quantiles",
                 abs(crps_dist(d, 1) - crps_quantiles(0.5, 1, 1)) < TOL) && all_pass

# Test 5.4: pit_dist routes correctly
all_pass <- pass("Dispatch: pit_dist => pit_normal",
                 abs(pit_dist(list(mu = 0, sigma = 1), 0) - pit_normal(0, 1, 0)) < TOL) && all_pass

all_pass <- pass("Dispatch: pit_dist => pit_sample",
                 abs(pit_dist(list(samples = c(1, 2, 3)), 2) - pit_sample(c(1, 2, 3), 2)) < TOL) && all_pass

# ---- 6. Edge Cases --------------------------------------------------------------
# Test 6.1: .dist_kind returns correct type
all_pass <- pass("dist_kind: normal", .dist_kind(list(mu = 1, sigma = 1)) == "normal") && all_pass
all_pass <- pass("dist_kind: samples", .dist_kind(list(samples = c(1, 2))) == "samples") && all_pass
all_pass <- pass("dist_kind: quantiles", .dist_kind(list(q = c(`0.5` = 1))) == "quantiles") && all_pass
all_pass <- pass("dist_kind: NA for unknown", is.na(.dist_kind(list(foo = 1)))) && all_pass

# ---- Summary ------------------------------------------------------------------
cat("\n")
if (all_pass) {
  cat("✅ All tests passed!\n")
  quit(save = "no")
} else {
  cat("❌ Some tests failed.\n")
  quit(save = "no", status = 1)
}
