# How To Use CGMissingDataR

## CGMissingDataR

CGMissingDataR imputes missing glucose values in continuous glucose
monitoring (CGM) data. The main public workflow is
[`run_missing_glucose_imputation()`](https://zhanglabuky.github.io/CGMissingDataR/dev/reference/run_missing_glucose_imputation.md),
which accepts a raw timestamp column, creates `TimeSeries` and
`TimeDifferenceMinutes` internally, and returns completed values from
the selected imputation models.

The timestamp column can be stored in common formats such as
`2020:01:16:00:00`, `2020-01-16 00:00:00`, `2020/01/16 00:00:00`, or as
a `POSIXct` column. The function standardizes those timestamps before
calling
[`CGManalyzer::timeSeqConversion.fn()`](https://rdrr.io/pkg/CGManalyzer/man/timeSeqConversion.fn.html).

Use `models = "mice_only"` for a quick MICE-only run. Use
`models = "all"` to run MICE-only, Random Forest, kNN, XGBoost,
LightGBM, and ARIMA, or pass a subset such as
`models = c("mice_only", "rf")`.

Simulation-based benchmarking is kept as an internal development and
validation workflow.

### Installation

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

Load the package:

``` r
library(CGMissingDataR)
```

### Example Data

`CGMExampleData` is a small multi-subject CGM dataset with raw
timestamps and deterministic missing glucose values. It does not include
`TimeSeries` or `TimeDifferenceMinutes`; those generated time features
are created inside the imputation function.

``` r
data("CGMExampleData")

data.frame(
  Dataset = "CGMExampleData",
  Rows = nrow(CGMExampleData),
  Subjects = length(unique(CGMExampleData$USUBJID)),
  MissingGlucose = sum(is.na(CGMExampleData$LBORRES)),
  MissingPercent = round(mean(is.na(CGMExampleData$LBORRES)) * 100, 1)
)
#>          Dataset Rows Subjects MissingGlucose MissingPercent
#> 1 CGMExampleData  500        5             50             10

head(CGMExampleData)
#>   USUBJID LBORRES             Time AGE hba1c
#> 1      11     150 2020:01:16:00:00  34   6.4
#> 2      11     134 2020:01:16:00:05  34   6.4
#> 3      11     125 2020:01:16:00:10  34   6.4
#> 4      11     132 2020:01:16:00:15  34   6.4
#> 5      11     132 2020:01:16:00:20  34   6.4
#> 6      11     132 2020:01:16:00:25  34   6.4
```

### Impute Missing Glucose Values

Use
[`run_missing_glucose_imputation()`](https://zhanglabuky.github.io/CGMissingDataR/dev/reference/run_missing_glucose_imputation.md)
when your data already contains missing glucose values. This function
returns imputed values but does not calculate accuracy metrics, because
the true values for those missing rows are unknown.

This example uses all available methods. Smaller model iteration counts
are used so the example stays reasonably quick.

``` r
impute_out <- run_missing_glucose_imputation(
  CGMExampleData,
  target_col = "LBORRES",
  feature_cols = c("AGE", "hba1c"),
  id_col = "USUBJID",
  time_col = "Time",
  models = "all",
  rf_n_estimators = 25,
  xgb_nrounds = 25,
  lgb_nrounds = 25
)
```

The `summary` table reports the missingness seen after preprocessing.

``` r
impute_out$summary
#>                                      Method MissingRate MissingCount RowsUsed
#> 1 MICE-only (base features; impute LBORRES)         0.1           50      500
#> 2       MICE + RF (engineered lag features)         0.1           50      500
#> 3      MICE + KNN (engineered lag features)         0.1           50      500
#> 4  MICE + XGBoost (engineered lag features)         0.1           50      500
#> 5 MICE + LightGBM (engineered lag features)         0.1           50      500
#> 6     ARIMA(4,1,0) on MICE-completed target         0.1           50      500
```

The returned `imputed_data` object is a named list with one completed
data frame per selected method.

``` r
names(impute_out$imputed_data)
#> [1] "mice_only" "rf"        "knn"       "xgboost"   "lightgbm"  "arima"
```

In the returned data, the original target column is left unchanged. That
means `LBORRES` is still `NA` where glucose was originally missing,
while `ImputedValue` contains the completed glucose value.

``` r
rf_missing_rows <- impute_out$imputed_data$rf[
  impute_out$imputed_data$rf$.Missing,
  c(
    "USUBJID", "Time", ".Missing", "LBORRES", "ObservedValue",
    "ImputedValue", "TimeSeries", "TimeDifferenceMinutes"
  )
]

head(rf_missing_rows)
#>    USUBJID             Time .Missing LBORRES ObservedValue ImputedValue
#> 10      11 2020:01:16:00:45     TRUE      NA            NA       135.08
#> 31      11 2020:01:16:02:30     TRUE      NA            NA        82.52
#> 32      11 2020:01:16:02:35     TRUE      NA            NA        75.36
#> 33      11 2020:01:16:02:40     TRUE      NA            NA       155.76
#> 34      11 2020:01:16:02:45     TRUE      NA            NA       123.36
#> 55      11 2020:01:16:04:30     TRUE      NA            NA        78.68
#>    TimeSeries TimeDifferenceMinutes
#> 10      31120                     5
#> 31      31225                     5
#> 32      31230                     5
#> 33      31235                     5
#> 34      31240                     5
#> 55      31345                     5
```
