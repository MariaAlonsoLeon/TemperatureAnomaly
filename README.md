# Temperature Anomaly Analysis in the Canary Islands (1970–2024)

[![R](https://img.shields.io/badge/R-276DC3?style=flat-square&logo=r&logoColor=white)](https://www.r-project.org/)
[![Climate Study](https://img.shields.io/badge/Climate-Temperature%20Analysis-1b4965?style=flat-square)](#)
[![Reproducible Research](https://img.shields.io/badge/Reproducible-Yes-2a9d8f?style=flat-square)](#)

---

## Contents

- `temperature_anomaly_analysis.Rmd` → **main extended study (source code)**  
- `temperature_anomaly_analysis.html` → **rendered full report (recommended reading)**  
- `OBS_018.docx` → **conference paper (short version, XIV Congreso AEC 2026)**  
- `temperature_anomaly_2025.rds` → dataset  
- `utilities.R` → helper functions  
- `dashboard_anomalies_en.html` → interactive dashboard  
- `*_cache/`, `*_files/` → RMarkdown cache and dependencies  

---

## Overview

This repository presents a **fully reproducible statistical analysis** of temperature anomaly trends in the Canary Islands between **1970 and 2024**, framed within a **global climate context**.

The study integrates:

- **HadCRUT5** → global and hemispheric temperature series  
- **AEMET** → high-resolution observational data from the Canary Islands  

A **short version of this work** has been accepted at the **XIV Congreso AEC (2026)**.  
The full HTML report included here constitutes the **extended scientific contribution**.

---

## Scientific contribution

This work aims to answer a key question:

> **Are recent temperature trends in the Canary Islands consistent with historical warming patterns and global behaviour?**

Main contributions:

- rigorous comparison between **global and regional warming trends**
- evaluation of **trend stability vs recent changes**
- validation of linear models under **strict statistical diagnostics**
- assessment of **non-linear alternatives** (segmented regression, transformations)

---

## Study design

The analysis includes **eight spatial series**:

| Scale        | Areas |
|-------------|------|
| Global      | Global · Northern Hemisphere · Southern Hemisphere |
| Regional    | Canary Islands (average) |
| Stations    | Izaña · Tenerife/Los Rodeos · Santa Cruz de Tenerife · Gran Canaria/Gando |

All series are analysed consistently across multiple temporal resolutions.

---

## Methodology

### Core model
- Ordinary Least Squares (OLS)

### Diagnostic framework
- Normality → Anderson-Darling  
- Homoscedasticity → Breusch-Pagan  
- Autocorrelation → Ljung-Box  
- Robust inference → HAC (Newey-West)  
- Trend validation → Mann-Kendall + Sen slope  

### Non-linear analysis
- Yeo-Johnson transformation  
- Segmented regression (changepoint detection)

### Temporal resolutions
- Monthly series  
- Annual averages  
- Month-specific models  

---

## Key results

- All analysed regions show **statistically significant warming**
- Canary Islands warming is **comparable to the Northern Hemisphere**
- Linear models provide a **robust and stable representation**
- Non-linear alternatives improve RMSE by **< 2%**
- Global series suggest **recent acceleration**
- Canary Islands show **possible recent deceleration**
- Results are consistent with **high-emission climate scenarios**

---

## Reproducibility

Install dependencies:

```r
install.packages(c(
  "tidyverse",
  "ggplot2",
  "fpp3",
  "lmtest",
  "sandwich",
  "nortest",
  "trend",
  "patchwork",
  "kableExtra"
))

Render the full report:

```r
rmarkdown::render("temperature_anomaly_analysis.Rmd")
```

---

### Data sources

- HadCRUT5 → global temperature datasets
- AEMET → observational station data

Temperature anomalies are computed relative to the 1961–1990 baseline.

---

### Extended vs conference version
- 📄 HTML report → full methodology, diagnostics, robustness analysis
- 📝 Conference paper (OBS_018.docx) → condensed version of results

The extended version should be considered the primary reference.

---

### License
Code → MIT License
Documentation & figures → CC BY 4.0

Third-party data (AEMET, HadCRUT5, etc.) remain subject to their respective licenses.
