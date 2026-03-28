# Temperature Anomaly Analysis in the Canary Islands (1970–2024)

[![R](https://img.shields.io/badge/R-276DC3?style=flat-square&logo=r&logoColor=white)](https://www.r-project.org/)
[![Climate Study](https://img.shields.io/badge/Climate-Temperature%20Analysis-1b4965?style=flat-square)](#)

---

### Study overview

This repository contains the materials associated with the study:

**Análisis de la evolución de la anomalía de temperatura en Canarias entre 1970 y 2024 en el contexto mundial**

The project analyses long-term temperature anomaly trends between **1970 and 2024**, combining **global datasets** with **regional observations from the Canary Islands**.

It includes:
- conference paper  
- extended report  
- dataset  
- reproducible analysis code  
- interactive dashboards  

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

## Contents

- AEMET_CONGRESO_CON_RESULTADOS.Rmd → source of the full analysis
- AEMET_CONGRESO_CON_RESULTADOS.html → rendered extended report
- OBS_018.docx → conference submission
- anomalia_temperatura_2025.rds → dataset
- utilidades.R → helper functions
- dashboards → interactive visual exploration

---
## Reproducibility
```text
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
```text
rmarkdown::render("AEMET_CONGRESO_CON_RESULTADOS.Rmd")
```
---
## Data sources

- **HadCRUT5** → global and hemispheric series
- **AEMET** → Canary Islands observations

Temperature anomalies are computed relative to the 1961–1990 baseline.

---
## Extended version

A detailed version of the study — including full methodology, additional figures and robustness analysis — is available in this repository (HTML report).

---
## License

The code in this repository is distributed under the MIT License.

Unless otherwise stated, the documentation, written content and original figures produced by the author are distributed under the Creative Commons Attribution 4.0 International (CC BY 4.0) license.

This allows sharing and adaptation of the material provided that proper attribution is given to the author.

Third-party data (e.g., AEMET, HadCRUT5 or other external sources) are not covered by these licenses and remain subject to their respective terms of use.
