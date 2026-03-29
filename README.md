# Temperature Anomaly Analysis in the Canary Islands (1970–2024)

[![R](https://img.shields.io/badge/R-276DC3?style=flat-square&logo=r&logoColor=white)](https://www.r-project.org/)
[![Climate Study](https://img.shields.io/badge/Climate-Temperature%20Analysis-1b4965?style=flat-square)](#)

---

## Repository contents

- `AEMET_CONGRESO_CON_RESULTADOS.Rmd` → source of the extended analysis (main contribution)  
- `AEMET_CONGRESO_CON_RESULTADOS.html` → rendered extended report  
- `OBS_018.docx` → conference submission (short version, accepted at XIV Congreso AEC 2026)  
- `anomalia_temperatura_2025.rds` → dataset  
- `utilidades.R` → helper functions  
- `dashboard_clima_canarias.rmd` → climate dashboard  

---

## Study overview

This repository presents a **complete and reproducible study** of temperature anomaly trends in the Canary Islands between **1970 and 2024**, analysed in a global context.

**Evolution of Temperature Anomalies in the Canary Islands (1970–2024) in a Global Context**

The project combines **global climate datasets (HadCRUT5)** with **regional observations (AEMET)** and applies a rigorous statistical framework to quantify long-term warming and assess recent trend behaviour.

A **condensed version of this work** has been accepted at the **XIV Congreso AEC (2026)**.  
The conference paper included in this repository corresponds to a **short version** of the full analysis.

---

## Study design

The analysis covers eight spatial series:

| Scale        | Areas |
|-------------|------|
| Global      | Global · Northern Hemisphere · Southern Hemisphere |
| Regional    | Canary Islands (average) |
| Stations    | Izaña · Tenerife/Los Rodeos · Santa Cruz de Tenerife · Gran Canaria/Gando |

The objective is to quantify warming trends and evaluate whether **recent behaviour differs from historical trends**.

---

## Methodological framework

The core model is **ordinary least squares regression (OLS)**, supported by a full diagnostic framework:

- normality → Anderson-Darling  
- homoscedasticity → Breusch-Pagan  
- autocorrelation → Ljung-Box  
- robust inference → HAC (Newey-West)  
- trend validation → Mann-Kendall + Sen slope  

To evaluate deviations from linearity:

- Yeo-Johnson transformation  
- segmented regression (changepoint model)  

The analysis is performed at three temporal resolutions:

- monthly series  
- annual averages  
- month-specific models  

---

## Key findings

- all regions show statistically significant warming  
- Canary Islands exhibit warming rates comparable to the Northern Hemisphere  
- linear regression provides a highly stable description of the trend  
- alternative models improve RMSE by **less than 2%**  
- global series indicate a **moderate recent acceleration**  
- Canary Islands suggest a **possible recent deceleration**  
- observed trends are consistent with **high-emission climate scenarios**  

---

## Reproducibility

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
```

```r
rmarkdown::render("AEMET_CONGRESO_CON_RESULTADOS.Rmd")
```
---

## Data sources
- HadCRUT5 → global and hemispheric temperature series
- AEMET → Canary Islands station data

Temperature anomalies are computed relative to the 1961–1990 baseline.

---

## Extended version

The full study — including detailed methodology, robustness analysis, additional figures and complete results — is available in this repository as an HTML report.

This extended version constitutes the main scientific contribution, while the conference paper provides a condensed summary of the results.

---

## License

The code in this repository is distributed under the MIT License.

Unless otherwise stated, the documentation, written content and original figures produced by the author are distributed under the Creative Commons Attribution 4.0 International (CC BY 4.0) license.

This allows sharing and adaptation of the material provided that proper attribution is given to the author.

Third-party data (e.g., AEMET, HadCRUT5 or other external sources) are not covered by these licenses and remain subject to their respective terms of use.
