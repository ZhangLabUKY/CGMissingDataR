
<!-- README.md is generated from README.Rmd. Please edit that file -->

# CGMissingDataR

<!-- badges: start -->

[![R-CMD-check](https://github.com/ZhangLabUKY/CGMissingDataR/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/ZhangLabUKY/CGMissingDataR/actions/workflows/R-CMD-check.yaml)
[![CRAN
status](https://www.r-pkg.org/badges/version/CGMissingDataR)](https://CRAN.R-project.org/package=CGMissingDataR)
[![CRAN
checks](https://badges.cranchecks.info/summary/CGMissingDataR.svg)](https://cran.r-project.org/web/checks/check_results_CGMissingDataR.html)
[![Downloads](https://cranlogs.r-pkg.org/badges/grand-total/CGMissingDataR)](https://cran.r-project.org/package=CGMissingDataR)
[![Last Commit
Release](https://img.shields.io/github/last-commit/ZhangLabUKY/CGMissingDataR/master)](https://github.com/ZhangLabUKY/CGMissingDataR/commits/master/)
<!-- badges: end -->

CGMissingDataR supports continuous glucose monitoring-style missing-data
workflows. It can benchmark imputation methods by masking known glucose
values, or impute glucose values that are already missing in user data.

Current workflows include:

- `run_comprehensive_imputation_benchmark()` for artificial masking
  benchmarks,
- `run_missing_glucose_imputation()` for real missing glucose values,
- model selection with `models = "mice_only"`, a subset of models, or
  `models = "all"`, and
- automatic creation of `TimeSeries` and `TimeDifferenceMinutes` from a
  raw timestamp column.

## Installation

Before installation, make sure the modeling dependencies are available:

``` r
install.packages(c(
  "FNN", "ranger", "mice", "xgboost", "lightgbm", "forecast",
  "CGManalyzer", "lifecycle"
))
```

Install the development version of CGMissingDataR from GitHub:

``` r
devtools::install_github("ZhangLabUKY/CGMissingDataR")
```

Install `CGMissingDataR` from CRAN with:

``` r
install.packages("CGMissingDataR")
```

## Learn More

The vignette is the main tutorial and includes runnable examples,
dataset summaries, benchmark results, and real-imputation output:

<https://zhanglabuky.github.io/CGMissingDataR/articles/How-To-Use-CGMissingDataR.html>

## Changelog

The changelog is available at:

<https://zhanglabuky.github.io/CGMissingDataR/news/index.html>
