# CGMissingDataR

CGMissingDataR supports continuous glucose monitoring (CGM) workflows
for imputing glucose values that are already missing in user data.

Current workflow features include:

- [`run_missing_glucose_imputation()`](https://zhanglabuky.github.io/CGMissingDataR/dev/reference/run_missing_glucose_imputation.md)
  for real missing glucose values,
- model selection with `models = "mice_only"`, a subset of models, or
  `models = "all"`, and
- automatic creation of `TimeSeries` and `TimeDifferenceMinutes` from a
  raw timestamp column, with common timestamp formats standardized
  internally.

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
dataset summaries, and real-imputation output:

<https://zhanglabuky.github.io/CGMissingDataR/articles/How-To-Use-CGMissingDataR.html>

## Changelog

The changelog is available at:

<https://zhanglabuky.github.io/CGMissingDataR/news/index.html>
