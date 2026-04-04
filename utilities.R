# =============================================================================
# utilities.R — Helper functions for the temperature anomaly analysis
# (AEMET/HadCRUT5, period 1970-2024)
#
# Contents:
#   1. moving_average()                      — moving average with NA interpolation
#   2. yeo.johnson()                         — Yeo-Johnson transformation
#   3. yeo.johnson.inverse()                 — inverse Yeo-Johnson transformation
#   4. yj.curve()                            — fitted YJ curve on original scale
#   5. optimise.yeojohnson.normality()       — lambda by maximum likelihood
#   6. optimise.yeojohnson.R2()              — lambda maximising regression R²
#   7. lm.analysis()                         — full diagnostic of a lm model
#
# Required packages: zoo, lmtest, nortest, sandwich, trend
# =============================================================================


# -----------------------------------------------------------------------------
# 1. MOVING AVERAGE WITH PRIOR INTERPOLATION OF MISSING VALUES
#
# Computes the causal moving average of a vector, first interpolating NAs
# linearly to prevent a single missing value from nullifying the whole window.
#
# Parameters:
#   x           — numeric input vector (may contain NAs)
#   window_size — window size (number of observations)
#
# Returns:
#   Vector of the same length as x. The first (window_size - 1) elements are
#   NA by construction. If window_size <= 0 the interpolated vector is returned
#   directly without averaging.
# -----------------------------------------------------------------------------
moving_average <- function(x, window_size) {

  # Linear interpolation of NAs; boundary NAs are kept as NA
  x_interp <- zoo::na.approx(x, na.rm = FALSE)

  if (window_size <= 0) return(x_interp)

  out <- numeric(length(x_interp))
  for (k in seq_along(x_interp)) {
    if (k < window_size) {
      out[k] <- NA   # incomplete window at the start
    } else {
      out[k] <- mean(na.omit(x_interp[(k - window_size + 1):k]))
    }
  }
  return(out)
}


# -----------------------------------------------------------------------------
# 2. YEO-JOHNSON TRANSFORMATION
#
# Parametric family of transformations indexed by lambda that symmetrises the
# distribution of y. Accepts positive and negative values (unlike Box-Cox).
# Piecewise definition (Yeo & Johnson, 2000):
#
#   y >= 0, lambda != 0 : ((y+1)^lambda - 1) / lambda
#   y >= 0, lambda == 0 : log(y+1)
#   y <  0, lambda != 2 : -((-y+1)^(2-lambda) - 1) / (2-lambda)
#   y <  0, lambda == 2 : -log(-y+1)
#
# Parameters:
#   y      — numeric input vector
#   lambda — family parameter (scalar)
#
# Returns: transformed vector of the same length as y
# -----------------------------------------------------------------------------
yeo.johnson <- function(y, lambda) {

  y_trans <- numeric(length(y))

  # Positive part (y >= 0)
  pos_idx <- which(y >= 0)
  if (lambda == 0) {
    y_trans[pos_idx] <- log(y[pos_idx] + 1)
  } else {
    y_trans[pos_idx] <- ((y[pos_idx] + 1)^lambda - 1) / lambda
  }

  # Negative part (y < 0)
  neg_idx <- which(y < 0)
  if (lambda == 2) {
    y_trans[neg_idx] <- -log(-y[neg_idx] + 1)
  } else {
    y_trans[neg_idx] <- -(( (-y[neg_idx] + 1)^(2 - lambda) - 1) / (2 - lambda))
  }

  return(y_trans)
}


# -----------------------------------------------------------------------------
# 3. INVERSE YEO-JOHNSON TRANSFORMATION
#
# Undoes yeo.johnson(y, lambda) to recover the original scale.
# Needed to reconstruct the fitted curve after modelling in the transformed
# space and back-transforming.
#
# Parameters:
#   z      — vector in the transformed space (output of yeo.johnson)
#   lambda — same lambda used in the forward transformation
#
# Returns: vector on the original scale of the same length as z
# -----------------------------------------------------------------------------
yeo.johnson.inverse <- function(z, lambda) {

  y <- numeric(length(z))

  # Positive part (z >= 0)
  pos <- z >= 0
  y[pos] <- if (lambda == 0) {
    exp(z[pos]) - 1
  } else {
    (lambda * z[pos] + 1)^(1 / lambda) - 1
  }

  # Negative part (z < 0)
  neg <- !pos
  y[neg] <- if (lambda == 2) {
    1 - exp(-z[neg])
  } else {
    1 - (1 - (2 - lambda) * z[neg])^(1 / (2 - lambda))
  }

  return(y)
}


# -----------------------------------------------------------------------------
# 4. FITTED YEO-JOHNSON CURVE ON THE ORIGINAL SCALE
#
# Helper function that encapsulates the full Yeo-Johnson pipeline:
# standardises y, transforms with the given lambda, fits lm in the YJ space,
# and reconstructs the fitted values on the original scale of y.
#
# Prior standardisation ((y - mean) / sd) is required for numerical stability:
# the YJ transformation is sensitive to the absolute scale of y.
#
# Parameters:
#   y      — response variable vector (original scale)
#   x      — predictor vector
#   lambda — transformation parameter
#
# Returns: vector of fitted values on the original scale (same length as y)
# -----------------------------------------------------------------------------
yj.curve <- function(y, x, lambda) {
  mu    <- mean(y)
  sigma <- sd(y)
  y_std <- (y - mu) / sigma                             # standardise
  y_yj  <- yeo.johnson(y_std, lambda)                   # transform
  fit   <- lm(y_yj ~ x)                                 # fit in YJ space
  mu + sigma * yeo.johnson.inverse(fitted(fit), lambda)  # back-transform
}


# -----------------------------------------------------------------------------
# 5. LAMBDA ESTIMATION BY MAXIMUM LIKELIHOOD UNDER NORMALITY
#
# Standard criterion for the Yeo-Johnson transformation, equivalent to the
# one used in car::powerTransform and MASS::boxcox adapted to YJ.
#
# The profiled log-likelihood under normality is maximised:
#
#   l(lambda) = -n/2 · log(sigma²_lambda)
#               + (lambda - 1) · sum(sign(y_i) · log(|y_i| + 1))
#
# where sigma²_lambda is the MLE variance of the transformed data and the
# second term is the Jacobian of the transformation.
# This criterion depends only on y (not on x): it finds the most normal
# distribution of y regardless of the regression model.
#
# Parameters:
#   y            — response variable vector
#   lambda_range — search interval (default [-2, 3])
#
# Returns: optimal lambda (scalar)
# -----------------------------------------------------------------------------
optimise.yeojohnson.normality <- function(y, lambda_range = c(-2, 3)) {

  n <- length(y)

  # Negative log-likelihood (optimize minimises; we want to maximise l)
  neg_loglik <- function(lambda) {
    y_trans <- yeo.johnson(y, lambda)
    sigma2  <- sum((y_trans - mean(y_trans))^2) / n  # MLE variance (denominator n)
    if (sigma2 <= 0) return(Inf)                      # numerical safeguard
    ll <- -n / 2 * log(sigma2) +
           (lambda - 1) * sum(sign(y) * log(abs(y) + 1))
    return(-ll)
  }

  optimize(neg_loglik, interval = lambda_range)$minimum
}


# -----------------------------------------------------------------------------
# 6. LAMBDA ESTIMATION MAXIMISING THE REGRESSION R²
#
# Alternative criterion: finds the lambda that makes the y ~ x relationship
# most linear by maximising the R² of lm(yj ~ x) in the transformed space.
# Unlike the normality criterion, this one does depend on x.
# Used as the second method in the comparative section (method "R").
#
# Parameters:
#   x            — predictor vector
#   y            — response variable vector
#   lambda_range — search interval (default [-2, 3])
#
# Returns: optimal lambda (scalar)
# -----------------------------------------------------------------------------
optimise.yeojohnson.R2 <- function(x, y, lambda_range = c(-2, 3)) {
  mu    <- mean(y)
  sigma <- sd(y)

  # Negative R² because optimize minimises
  neg_r2 <- function(lambda) {
    y_std <- (y - mu) / sigma
    y_yj  <- yeo.johnson(y_std, lambda)
    -summary(lm(y_yj ~ x))$r.squared
  }

  optimize(neg_r2, interval = lambda_range)$minimum
}


# -----------------------------------------------------------------------------
# 7. FULL DIAGNOSTIC OF A LINEAR REGRESSION MODEL
#
# Receives an already-fitted lm() object and applies a battery of estimators
# and diagnostic tests. Returns a one-row tibble with all results.
#
# TREND ESTIMATORS:
#   lm.slope        — OLS slope (°C per predictor unit)
#   CI95            — half-width of the classical 95% OLS CI
#   CI95.HAC        — half-width of the robust Newey-West 95% CI
#                     (sandwich::vcovHAC). Valid under autocorrelation or
#                     heteroscedasticity. If CI95.HAC >> CI95, the OLS CI
#                     underestimates uncertainty.
#   sen.slope       — Sen/Theil-Sen slope: median of all pairwise slopes
#                     (y_j - y_i) / (x_j - x_i). Robust: tolerates up to
#                     29% outliers without distortion (Mudelsee, 2019).
#   sen.CI95        — half-width of the 95% CI for Sen's slope
#   sen.recent      — Sen's slope over the last n_recent points
#                     (adaptive window: min(n_recent, max(5, n/3)))
#   sen.recent.CI95 — 95% CI half-width for sen.recent
#   sen.recent.MK   — MK p-value over the last n_recent points
#
# GOODNESS OF FIT:
#   RMSE            — root mean square error of the OLS fit
#   R2              — OLS coefficient of determination
#
# YEO-JOHNSON (method N = normality, method R = R²):
#   YJN.lambda, YJN.RMSE, YJN.SW, YJN.AD, YJN.BP, YJN.trend
#   YJR.lambda, YJR.RMSE, YJR.SW, YJR.AD, YJR.BP, YJR.trend
#   trend = finite difference over the last n_recent points of the YJ curve,
#           divided by n_recent → mean rate per predictor unit in the recent period
#
# RESIDUAL NORMALITY TESTS:
#   SW              — Shapiro-Wilk (high power for n < 50; indicative for
#                     n > 50 where it may reject trivial deviations)
#   AD              — Anderson-Darling (nortest::ad.test): greater weight on
#                     tails, more appropriate than SW for n > 50.
#                     Primary normality test.
#
# DIAGNOSTIC TESTS:
#   BP              — Breusch-Pagan (lmtest::bptest): homoscedasticity.
#                     p < 0.05 → non-constant variance → OLS CIs underestimated.
#   LB              — Ljung-Box (lag = min(10, n/5)): residual autocorrelation.
#                     p < 0.05 → use CI95.HAC instead of CI95.
#   MK              — Mann-Kendall: non-parametric test of monotonic trend.
#                     Does not assume normality. p < 0.05 → significant trend.
#
# Parameters:
#   model    — already-fitted lm() object
#   n_recent — recent window size for sen.recent and YJ trend
#              (default 10; adapted automatically when n is small)
#
# Returns: 1-row tibble with all columns described above
# -----------------------------------------------------------------------------
lm.analysis <- function(model, n_recent = 10L) {

  y <- model$model[[1]]   # response variable
  x <- model$model[[2]]   # predictor
  n <- length(y)

  # ── OLS FIT ─────────────────────────────────────────────────────────────────
  y_fitted <- fitted(model)
  summ     <- summary(model)

  RMSE     <- round(sqrt(mean((y - y_fitted)^2)), digits = 4)
  R2       <- round(summ$r.squared,               digits = 2)
  lm.slope <- round(summ$coefficients[2],         digits = 4)

  # Classical 95% OLS CI
  ci_mat   <- confint(model, level = 0.95)
  CI95     <- round((ci_mat[4] - ci_mat[2]) / 2, digits = 4)

  # Robust HAC 95% CI (Newey-West): corrects OLS CI underestimation when
  # residuals exhibit autocorrelation or heteroscedasticity
  se_hac   <- sqrt(diag(sandwich::vcovHAC(model)))[2]
  CI95.HAC <- round(qnorm(0.975) * se_hac, digits = 4)

  # ── DIAGNOSTIC TESTS (on OLS residuals) ─────────────────────────────────────
  res_ols <- residuals(model)

  # Normality: SW (indicative) + AD (primary test for n > 50)
  SW <- round(shapiro.test(res_ols)$p.value,     digits = 3)
  AD <- round(nortest::ad.test(res_ols)$p.value, digits = 3)

  # Homoscedasticity: Breusch-Pagan
  BP <- round(bptest(model)$p.value, digits = 3)

  # Autocorrelation: Ljung-Box with adaptive lag
  n_res <- length(res_ols)
  LB    <- round(
    Box.test(res_ols,
             lag  = min(10L, n_res %/% 5L),
             type = "Ljung-Box")$p.value,
    digits = 3)

  # ── MANN-KENDALL + SEN'S SLOPE (full series) ────────────────────────────────
  # trend::sens.slope() computes both in a single call.
  # Sen's slope is the median of all pairwise (y_j - y_i) / (x_j - x_i).
  mk_res    <- trend::sens.slope(y)
  MK        <- round(mk_res$p.value,   digits = 3)
  sen.slope <- round(mk_res$estimates, digits = 4)
  sen.CI95  <- round((mk_res$conf.int[2] - mk_res$conf.int[1]) / 2, digits = 4)

  # ── RECENT SEN'S SLOPE (window of n_recent points) ──────────────────────────
  # Adaptive window: capped at min(n_recent, n/3) but never below 5
  # to ensure sens.slope has enough point pairs.
  n_eff <- max(min(as.integer(n_recent), max(5L, n %/% 3L)), 5L)

  if (n_eff <= n) {
    y_tail          <- tail(y, n_eff)
    sen_tail        <- trend::sens.slope(y_tail)
    sen.recent      <- round(sen_tail$estimates, digits = 4)
    sen.recent.CI95 <- round((sen_tail$conf.int[2] - sen_tail$conf.int[1]) / 2,
                             digits = 4)
    sen.recent.MK   <- round(sen_tail$p.value, digits = 3)
  } else {
    sen.recent <- sen.recent.CI95 <- sen.recent.MK <- NA_real_
  }

  # ── YEO-JOHNSON: METHOD N (normality criterion, standard) ───────────────────
  lambda_N  <- optimise.yeojohnson.normality(y)   # optimal lambda by MLE
  y_fit_N   <- yj.curve(y, x, lambda_N)           # fitted curve on original scale
  res_N     <- y - y_fit_N                         # residuals on original scale

  YJN.lambda <- round(lambda_N, digits = 2)
  YJN.RMSE   <- round(sqrt(mean(res_N^2)), digits = 4)
  YJN.SW     <- round(shapiro.test(res_N)$p.value,     digits = 3)
  YJN.AD     <- round(nortest::ad.test(res_N)$p.value, digits = 3)
  YJN.BP     <- round(bptest(lm(res_N ~ x))$p.value,   digits = 3)

  # Recent YJ-N trend: finite difference over the last n_eff points
  # divided by n_eff → mean rate per predictor unit in the recent period
  if (length(y_fit_N) > n_eff) {
    nn        <- length(y_fit_N)
    YJN.trend <- round((y_fit_N[nn] - y_fit_N[nn - n_eff]) / n_eff, digits = 6)
  } else {
    YJN.trend <- NA_real_
  }

  # ── YEO-JOHNSON: METHOD R (R² criterion, alternative) ───────────────────────
  lambda_R  <- optimise.yeojohnson.R2(x, y)
  y_fit_R   <- yj.curve(y, x, lambda_R)
  res_R     <- y - y_fit_R

  YJR.lambda <- round(lambda_R, digits = 2)
  YJR.RMSE   <- round(sqrt(mean(res_R^2)), digits = 4)
  YJR.SW     <- round(shapiro.test(res_R)$p.value,     digits = 3)
  YJR.AD     <- round(nortest::ad.test(res_R)$p.value, digits = 3)
  YJR.BP     <- round(bptest(lm(res_R ~ x))$p.value,   digits = 3)

  if (length(y_fit_R) > n_eff) {
    nn        <- length(y_fit_R)
    YJR.trend <- round((y_fit_R[nn] - y_fit_R[nn - n_eff]) / n_eff, digits = 6)
  } else {
    YJR.trend <- NA_real_
  }

  # ── OUTPUT ───────────────────────────────────────────────────────────────────
  return(
    tibble(
      # OLS fit
      RMSE     = RMSE,
      R2       = R2,
      lm.slope = lm.slope,
      CI95     = CI95,
      CI95.HAC = CI95.HAC,
      # Non-parametric (full series)
      sen.slope = sen.slope,
      sen.CI95  = sen.CI95,
      MK        = MK,
      # OLS diagnostic tests
      SW = SW,
      AD = AD,
      BP = BP,
      LB = LB,
      # Non-parametric (recent period)
      sen.recent      = sen.recent,
      sen.recent.CI95 = sen.recent.CI95,
      sen.recent.MK   = sen.recent.MK,
      # Yeo-Johnson method N (normality)
      YJN.lambda = YJN.lambda,
      YJN.RMSE   = YJN.RMSE,
      YJN.SW     = YJN.SW,
      YJN.AD     = YJN.AD,
      YJN.BP     = YJN.BP,
      YJN.trend  = YJN.trend,
      # Yeo-Johnson method R (R²)
      YJR.lambda = YJR.lambda,
      YJR.RMSE   = YJR.RMSE,
      YJR.SW     = YJR.SW,
      YJR.AD     = YJR.AD,
      YJR.BP     = YJR.BP,
      YJR.trend  = YJR.trend
    )
  )
}
