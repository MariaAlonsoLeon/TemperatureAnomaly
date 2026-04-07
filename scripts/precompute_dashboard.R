# =========================================================
# PRECOMPUTE DASHBOARD RESULTS
# Full version aligned with dashboard_clima_canarias.Rmd
# =========================================================

options(scipen = 999)

# ── Libraries ────────────────────────────────────────────
library(tidyverse)
library(lubridate)
library(tsibble)
library(fpp3)
library(purrr)
library(zoo)
library(ggplot2)
library(broom)
library(lmtest)
library(sandwich)
library(trend)
library(nortest)
library(MASS)
library(tseries)

source("utilities.R")

# ── Parameters ───────────────────────────────────────────
START_DATE     <- as.Date("1970-01-01")
END_DATE       <- as.Date("2024-12-31")
N_RECENT_YEARS <- 10

area_order <- c(
  "GLOBAL", "NORTHERN HEMISPHERE", "SOUTHERN HEMISPHERE",
  "CANARY ISLANDS", "GRAN CANARIA/GANDO", "IZAÑA",
  "S.C. DE TENERIFE", "TENERIFE/LOS RODEOS"
)

MONTH_NAMES <- c(
  "January","February","March","April","May","June",
  "July","August","September","October","November","December"
)

# ── Helpers ──────────────────────────────────────────────
fmt_century <- function(slope, ic, digits = 2) {
  paste0(
    formatC(round(slope * 100, digits), format = "f", digits = digits),
    " ± ",
    formatC(round(ic * 100, digits), format = "f", digits = digits)
  )
}

ensure_yj_cols <- function(df) {
  yj_cols <- c("RMSE.YJ","SW.YJ","AD.YJ","BP.YJ","lambda.YJ","trend.YJ")
  for (col in yj_cols) {
    if (!col %in% names(df)) df[[col]] <- NA_real_
  }
  df
}

calc_reliability <- function(r2, ic, slope, ad, bp, mk, lb) {
  flags <- c(
    if (!is.na(r2) && r2 < 0.10)                         "⛔R²<0.10",
    if (!is.na(ic) && !is.na(slope) && ic > abs(slope)) "⚠️CI>slope",
    if (!is.na(ad) && ad < 0.05)                        "⚠️AD",
    if (!is.na(bp) && bp < 0.05)                        "⚠️BP",
    if (!is.na(mk) && mk > 0.05)                        "⚠️MK n.s.",
    if (!is.na(lb) && lb < 0.05)                        "⚠️LB"
  )
  if (length(flags) == 0) "✅ OK" else paste(flags, collapse = " ")
}

calc_reliability_num <- function(r2, ic, slope, ad, bp, mk, lb) {
  if (!is.na(r2) && r2 < 0.10) return(2L)
  n_fail <- 0L
  if (!is.na(ic) && !is.na(slope) && ic > abs(slope)) n_fail <- n_fail + 1L
  if (!is.na(ad) && ad < 0.05) n_fail <- n_fail + 1L
  if (!is.na(bp) && bp < 0.05) n_fail <- n_fail + 1L
  if (!is.na(mk) && mk > 0.05) n_fail <- n_fail + 1L
  if (!is.na(lb) && lb < 0.05) n_fail <- n_fail + 1L
  n_fail
}

calc_reliability_label <- function(r2, ic, slope, ad, bp, mk, lb) {
  if (!is.na(r2) && r2 < 0.10)                         return("⛔R²")
  if (!is.na(ic) && !is.na(slope) && ic > abs(slope)) return("⚠️CI")
  if (!is.na(ad) && ad < 0.05)                        return("⚠️AD")
  if (!is.na(bp) && bp < 0.05)                        return("⚠️BP")
  if (!is.na(mk) && mk > 0.05)                        return("⚠️MK")
  if (!is.na(lb) && lb < 0.05)                        return("⚠️LB")
  "✅OK"
}

optimise_yj_rmse <- function(x, y, lambda_range = c(-2, 3)) {
  mu <- mean(y)
  sigma <- sd(y)
  
  if (is.na(sigma) || sigma == 0) return(1)
  
  y_std <- (y - mu) / sigma
  
  error_fn <- function(lambda) {
    yj_trans <- yeo.johnson(y_std, lambda)
    fit <- lm(yj_trans ~ x)
    y_back <- mu + sigma * yeo.johnson.inverse(fitted(fit), lambda)
    sum((y - y_back)^2)
  }
  
  optimize(error_fn, interval = lambda_range)$minimum
}

# ── Load data ────────────────────────────────────────────
message("Loading data...")

all_data <- readRDS("data/temperature_anomaly_2025.rds") %>%
  as_tibble() %>%
  filter(as.Date(date) >= START_DATE, as.Date(date) <= END_DATE)

levels(all_data$AREA)[levels(all_data$AREA) == "LAS PALMAS DE GRAN CANARIA/GANDO"] <- "GRAN CANARIA/GANDO"
levels(all_data$AREA)[levels(all_data$AREA) == "SANTA CRUZ DE TENERIFE"]           <- "S.C. DE TENERIFE"
levels(all_data$AREA)[levels(all_data$AREA) == "NH"]                               <- "NORTHERN HEMISPHERE"
levels(all_data$AREA)[levels(all_data$AREA) == "SH"]                               <- "SOUTHERN HEMISPHERE"
levels(all_data$AREA)[levels(all_data$AREA) == "CANARIAS"]                         <- "CANARY ISLANDS"

all_data <- all_data %>%
  mutate(AREA = factor(AREA, levels = area_order)) %>%
  as_tsibble(index = date, key = AREA) %>%
  fill_gaps()

all_data_num <- all_data %>%
  as_tibble() %>%
  mutate(
    time = as.numeric(date),
    AREA = factor(AREA, levels = area_order)
  )

all_data_annual <- all_data %>%
  as_tibble() %>%
  mutate(
    year = year(date),
    AREA = factor(AREA, levels = area_order)
  ) %>%
  group_by(AREA, year) %>%
  summarise(value = mean(value, na.rm = TRUE), .groups = "drop") %>%
  filter(!is.na(value))

all_data_monthly <- all_data %>%
  as_tibble() %>%
  mutate(
    year  = year(date),
    month = month(date),
    AREA  = factor(AREA, levels = area_order)
  ) %>%
  filter(!is.na(value))

# =========================================================
# MAIN MODEL RESULTS
# =========================================================
message("Computing full monthly models...")

results_lm <- all_data_num %>%
  group_by(AREA) %>%
  filter(!is.na(value)) %>%
  nest() %>%
  mutate(
    model = map(data, ~ lm(value ~ time, data = .x)),
    analysis = map(
      model,
      ~ tryCatch(
        lm.analysis(.x, n_recent = N_RECENT_YEARS * 12L),
        error = function(e) tibble(error = conditionMessage(e))
      )
    )
  ) %>%
  select(AREA, analysis) %>%
  unnest(analysis) %>%
  mutate(
    reliability = pmap_chr(
      list(R2, CI95, lm.slope, AD, BP, MK, LB),
      calc_reliability
    )
  ) %>%
  mutate(
    across(
      any_of(c(
        "lm.slope", "CI95", "CI95.HAC", "sen.slope", "sen.CI95",
        "sen.recent", "sen.recent.CI95", "YJN.trend", "YJR.trend"
      )),
      ~ . * 12
    )
  ) %>%
  ensure_yj_cols() %>%
  ungroup()

message("Computing annual models...")

results_annual <- all_data_annual %>%
  group_by(AREA) %>%
  nest() %>%
  mutate(
    model = map(data, ~ lm(value ~ year, data = .x)),
    analysis = map(
      model,
      ~ tryCatch(
        lm.analysis(.x, n_recent = N_RECENT_YEARS),
        error = function(e) tibble(error = conditionMessage(e))
      )
    )
  ) %>%
  select(AREA, analysis) %>%
  unnest(analysis) %>%
  mutate(
    reliability = pmap_chr(
      list(R2, CI95, lm.slope, AD, BP, MK, LB),
      calc_reliability
    )
  ) %>%
  ensure_yj_cols() %>%
  ungroup()

message("Computing month-by-month models...")

results_monthly <- all_data_monthly %>%
  group_by(AREA, month) %>%
  nest() %>%
  mutate(
    model = map(data, ~ lm(value ~ year, data = .x)),
    analysis = map(
      model,
      ~ tryCatch(
        lm.analysis(.x, n_recent = N_RECENT_YEARS),
        error = function(e) tibble(error = conditionMessage(e))
      )
    )
  ) %>%
  select(AREA, month, analysis) %>%
  unnest(analysis) %>%
  mutate(
    month_name  = factor(MONTH_NAMES[month], levels = MONTH_NAMES),
    reliability = pmap_chr(
      list(R2, CI95, lm.slope, AD, BP, MK, LB),
      calc_reliability
    )
  ) %>%
  arrange(AREA, month) %>%
  ensure_yj_cols() %>%
  ungroup()

results_monthly2 <- results_monthly %>%
  mutate(
    reliability_num = pmap_int(
      list(R2, CI95, lm.slope, AD, BP, MK, LB),
      calc_reliability_num
    ),
    reliability_label = pmap_chr(
      list(R2, CI95, lm.slope, AD, BP, MK, LB),
      calc_reliability_label
    )
  )

# =========================================================
# TABLES / SUMMARY OBJECTS
# =========================================================
message("Building tables and summaries...")

table_annual_dashboard <- results_annual %>%
  transmute(
    AREA,
    R2 = round(R2, 3),
    `OLS ± CI95.HAC` = fmt_century(lm.slope, CI95.HAC),
    `Sen ± CI95`     = fmt_century(sen.slope, sen.CI95),
    reliability
  )

heatmap_slope_data <- results_monthly %>%
  select(AREA, month_name, lm.slope) %>%
  rename(period = month_name) %>%
  mutate(
    AREA = factor(AREA, levels = area_order),
    period = factor(period, levels = MONTH_NAMES),
    slope_century = lm.slope * 100
  ) %>%
  arrange(AREA, period)

heatmap_reliability_data <- results_monthly2 %>%
  select(AREA, month_name, reliability_num, reliability_label) %>%
  mutate(
    AREA = factor(AREA, levels = area_order),
    month_name = factor(month_name, levels = MONTH_NAMES)
  ) %>%
  arrange(AREA, month_name)

diagnostic_summary <- bind_rows(
  results_lm      %>% mutate(scale = "Full monthly"),
  results_annual  %>% mutate(scale = "Annual"),
  results_monthly %>% mutate(scale = "By month")
) %>%
  summarise(
    .by = scale,
    `AD > 0.05 (%)` = round(mean(AD > 0.05, na.rm = TRUE) * 100, 1),
    `BP > 0.05 (%)` = round(mean(BP > 0.05, na.rm = TRUE) * 100, 1),
    `LB > 0.05 (%)` = round(mean(LB > 0.05, na.rm = TRUE) * 100, 1),
    `MK < 0.05 (%)` = round(mean(MK < 0.05, na.rm = TRUE) * 100, 1),
    `Mean R²`                 = round(mean(R2, na.rm = TRUE), 3),
    `Mean slope (°C/century)` = round(mean(lm.slope, na.rm = TRUE) * 100, 2),
    `CI95 (°C/century)`       = round(mean(CI95, na.rm = TRUE) * 100, 2),
    `CI95.HAC (°C/century)`   = round(mean(CI95.HAC, na.rm = TRUE) * 100, 2)
  ) %>%
  mutate(scale = factor(scale, levels = c("Full monthly", "Annual", "By month"))) %>%
  arrange(scale)

# =========================================================
# CONFIDENCE BANDS
# =========================================================
message("Computing monthly bands...")

bands_monthly <- all_data %>%
  as_tibble() %>%
  mutate(
    date = as.Date(date),
    AREA = factor(AREA, levels = area_order)
  ) %>%
  filter(!is.na(value)) %>%
  group_by(AREA) %>%
  group_modify(~ {
    d <- .x %>% filter(!is.na(value))
    
    mod      <- lm(value ~ date, data = d)
    pred_ols <- predict(mod, newdata = d, interval = "confidence", level = 0.95)
    
    V_hac  <- sandwich::vcovHAC(mod)
    X      <- model.matrix(mod, data = d)
    se_hac <- sqrt(rowSums((X %*% V_hac) * X))
    tc     <- qt(0.975, df = mod$df.residual)
    
    tibble(
      date   = d$date,
      value  = d$value,
      fit    = pred_ols[, "fit"],
      ols_lo = pred_ols[, "lwr"],
      ols_hi = pred_ols[, "upr"],
      hac_lo = pred_ols[, "fit"] - tc * se_hac,
      hac_hi = pred_ols[, "fit"] + tc * se_hac
    )
  }) %>%
  ungroup()

message("Computing annual bands...")

bands_annual <- all_data_annual %>%
  group_by(AREA) %>%
  group_modify(~ {
    d <- .x %>% filter(!is.na(value))
    
    mod      <- lm(value ~ year, data = d)
    pred_ols <- predict(mod, newdata = d, interval = "confidence", level = 0.95)
    
    V_hac  <- sandwich::vcovHAC(mod)
    X      <- model.matrix(mod, data = d)
    se_hac <- sqrt(rowSums((X %*% V_hac) * X))
    tc     <- qt(0.975, df = mod$df.residual)
    
    tibble(
      year   = d$year,
      value  = d$value,
      fit    = pred_ols[, "fit"],
      ols_lo = pred_ols[, "lwr"],
      ols_hi = pred_ols[, "upr"],
      hac_lo = pred_ols[, "fit"] - tc * se_hac,
      hac_hi = pred_ols[, "fit"] + tc * se_hac
    )
  }) %>%
  ungroup() %>%
  mutate(date = as.Date(paste0(year, "-01-01")))

# =========================================================
# ALTERNATIVE MODELS
# =========================================================
message("Computing alternative models...")

acceleration <- tibble()
table_acceleration_dashboard <- tibble()
best_cp <- as.Date(NA)
kpi_changepoint <- "Not computed"
kpi_max_improvement <- NA_real_

try({
  acceleration <- all_data_num %>%
    filter(!is.na(value)) %>%
    group_by(AREA) %>%
    group_modify(~ {
      y <- .x$value
      x <- .x$time
      n <- length(y)
      
      mod <- lm(value ~ time, data = .x)
      slope_hist <- coef(mod)[2]
      ci95_hac <- qnorm(0.975) * sqrt(diag(sandwich::vcovHAC(mod)))[2]
      
      lambda <- optimise_yj_rmse(x, y)
      mu <- mean(y)
      sigma <- sd(y)
      y_std <- (y - mu) / sigma
      
      yj_trans <- yeo.johnson(y_std, lambda)
      fit_yj   <- lm(yj_trans ~ x)
      y_fitted <- mu + sigma * yeo.johnson.inverse(fitted(fit_yj), lambda)
      
      rmse_ols <- sqrt(mean((y - fitted(mod))^2))
      rmse_yj  <- sqrt(mean((y - y_fitted)^2))
      
      n_recent <- min(N_RECENT_YEARS * 12L, max(5L, n %/% 3L))
      y_fitted_tail <- tail(y_fitted, n_recent)
      x_tail        <- tail(x, n_recent)
      yj_slope_recent <- coef(lm(y_fitted_tail ~ x_tail))[2]
      
      tibble(
        slope_hist = slope_hist * 12,
        ci95_hac   = ci95_hac * 12,
        yj_recent  = yj_slope_recent * 12,
        lambda_yj  = round(lambda, 2),
        rmse_ols   = round(rmse_ols, 4),
        rmse_yj    = round(rmse_yj, 4)
      )
    }) %>%
    ungroup()
  
  n_dates <- length(unique(all_data$date))
  margin <- 0.15
  candidates <- sort(unique(all_data$date))[
    ceiling(n_dates * margin):floor(n_dates * (1 - margin))
  ]
  
  best_cp <- map_df(candidates, function(cp) {
    fit <- all_data %>%
      model(
        m = TSLM(value ~ trend() + I(pmax(0, as.numeric(date) - as.numeric(cp))))
      )
    tibble(cp = cp, mean_rmse = mean(accuracy(fit)$RMSE, na.rm = TRUE))
  }) %>%
    slice_min(mean_rmse, n = 1, with_ties = FALSE) %>%
    pull(cp)
  
  model_cp <- all_data %>%
    model(
      m = TSLM(value ~ trend() + I(pmax(0, as.numeric(date) - as.numeric(best_cp))))
    )
  
  metrics_cp <- accuracy(model_cp) %>% select(AREA, RMSE)
  
  coefs_cp <- tidy(model_cp) %>%
    group_by(AREA) %>%
    summarise(
      slope1 = estimate[term == "trend()"],
      slope2 = slope1 + estimate[grepl("pmax", term)],
      .groups = "drop"
    )
  
  result_cp <- coefs_cp %>%
    left_join(metrics_cp, by = "AREA") %>%
    mutate(changepoint = best_cp) %>%
    rename(rmse_cp = RMSE, slope2_cp = slope2) %>%
    select(AREA, changepoint, rmse_cp, slope2_cp)
  
  acceleration <- acceleration %>%
    left_join(result_cp, by = "AREA")
  
  table_acceleration_dashboard <- acceleration %>%
    mutate(AREA = factor(AREA, levels = area_order)) %>%
    arrange(AREA) %>%
    transmute(
      AREA,
      `RMSE (OLS)` = rmse_ols,
      `RMSE (YJ)`  = rmse_yj,
      `RMSE (CP)`  = round(rmse_cp, 4),
      `YJ improv. (%)` = round((1 - rmse_yj / rmse_ols) * 100, 2),
      `CP improv. (%)` = round((1 - rmse_cp / rmse_ols) * 100, 2),
      `Historical ± CI95.HAC (°C/century)` = fmt_century(slope_hist, ci95_hac),
      `YJ recent (°C/century)`   = round(yj_recent * 100, 2),
      `CP slope 2 (°C/century)`  = round(slope2_cp * 12 * 100, 2),
      `Changepoint`              = format(changepoint, "%Y-%m"),
      `YJ/hist. ratio`           = round(yj_recent / slope_hist, 2),
      `CP/hist. ratio`           = round(slope2_cp * 12 / slope_hist, 2)
    )
  
  kpi_changepoint <- format(best_cp, "%Y-%m")
  kpi_max_improvement <- table_acceleration_dashboard %>%
    summarise(m = max(c(`CP improv. (%)`, `YJ improv. (%)`), na.rm = TRUE)) %>%
    pull(m)
  
}, silent = TRUE)

# =========================================================
# KPI VALUES
# =========================================================
message("Extracting KPI values...")

kpi_canary_annual <- results_annual %>%
  filter(AREA == "CANARY ISLANDS") %>%
  pull(lm.slope) %>%
  .[1]

kpi_global_annual <- results_annual %>%
  filter(AREA == "GLOBAL") %>%
  pull(lm.slope) %>%
  .[1]

kpi_nh_annual <- results_annual %>%
  filter(AREA == "NORTHERN HEMISPHERE") %>%
  pull(lm.slope) %>%
  .[1]

kpi_sh_annual <- results_annual %>%
  filter(AREA == "SOUTHERN HEMISPHERE") %>%
  pull(lm.slope) %>%
  .[1]

kpi_n_areas_sig <- results_annual %>%
  filter(MK < 0.05) %>%
  nrow()

# =========================================================
# SAVE
# =========================================================
message("Saving precomputed dashboard objects...")

dir.create("data", showWarnings = FALSE)

saveRDS(
  list(
    results_lm = results_lm,
    results_annual = results_annual,
    results_monthly = results_monthly,
    results_monthly2 = results_monthly2,
    table_annual_dashboard = table_annual_dashboard,
    heatmap_slope_data = heatmap_slope_data,
    heatmap_reliability_data = heatmap_reliability_data,
    diagnostic_summary = diagnostic_summary,
    bands_monthly = bands_monthly,
    bands_annual = bands_annual,
    acceleration = acceleration,
    table_acceleration_dashboard = table_acceleration_dashboard,
    best_cp = best_cp,
    kpi_canary_annual = kpi_canary_annual,
    kpi_global_annual = kpi_global_annual,
    kpi_nh_annual = kpi_nh_annual,
    kpi_sh_annual = kpi_sh_annual,
    kpi_n_areas_sig = kpi_n_areas_sig,
    kpi_changepoint = kpi_changepoint,
    kpi_max_improvement = kpi_max_improvement
  ),
  file = "data/dashboard_results.rds"
)

message("✅ Done: data/dashboard_results.rds created successfully.")
