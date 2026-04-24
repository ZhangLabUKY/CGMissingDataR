# How To Use CGMissingDataR

## CGMissingDataR

CGMissingDataR supports two related continuous glucose monitoring
missing-data workflows:

- benchmarking imputation methods by masking known glucose values, and
- imputing glucose values that are already missing in user data.

The current workflow functions accept a raw timestamp column and create
`TimeSeries` and `TimeDifferenceMinutes` internally. You can choose
which model outputs to return with `models`. The default is
`models = "mice_only"` for a quick MICE-only run. Use `models = "all"`
to run MICE-only, Random Forest, kNN, XGBoost, LightGBM, and ARIMA, or
pass a subset such as `models = c("mice_only", "rf")`.

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

The package includes two small multi-subject CGM example datasets. Both
contain raw timestamps, not precomputed `TimeSeries` or
`TimeDifferenceMinutes` columns. Those generated time features are
created inside the imputation functions.

`CGMExampleData` is intended for benchmarking. The glucose values are
complete, so the benchmark function can mask known values and compare
imputed values against the truth.

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
#> 1 CGMExampleData  500        5              0              0

head(CGMExampleData)
#>   USUBJID LBORRES             Time AGE hba1c
#> 1      11     150 2020:01:16:00:00  34   6.4
#> 2      11     134 2020:01:16:00:05  34   6.4
#> 3      11     125 2020:01:16:00:10  34   6.4
#> 4      11     132 2020:01:16:00:15  34   6.4
#> 5      11     132 2020:01:16:00:20  34   6.4
#> 6      11     132 2020:01:16:00:25  34   6.4
```

`CGMExampleData2` has the same columns but includes deterministic
missing glucose values. It is intended for demonstrating imputation of
actual missing target values.

``` r
data("CGMExampleData2")

data.frame(
  Dataset = "CGMExampleData2",
  Rows = nrow(CGMExampleData2),
  Subjects = length(unique(CGMExampleData2$USUBJID)),
  MissingGlucose = sum(is.na(CGMExampleData2$LBORRES)),
  MissingPercent = round(mean(is.na(CGMExampleData2$LBORRES)) * 100, 1)
)
#>           Dataset Rows Subjects MissingGlucose MissingPercent
#> 1 CGMExampleData2  500        5             50             10

head(CGMExampleData2)
#>   USUBJID LBORRES             Time AGE hba1c
#> 1      11     150 2020:01:16:00:00  34   6.4
#> 2      11     134 2020:01:16:00:05  34   6.4
#> 3      11     125 2020:01:16:00:10  34   6.4
#> 4      11     132 2020:01:16:00:15  34   6.4
#> 5      11     132 2020:01:16:00:20  34   6.4
#> 6      11     132 2020:01:16:00:25  34   6.4
```

### Benchmark Known Glucose Values

Use
[`run_comprehensive_imputation_benchmark()`](https://zhanglabuky.github.io/CGMissingDataR/dev/reference/run_comprehensive_imputation_benchmark.md)
when glucose values are known and you want to mask a portion of them to
compare model performance.

This example masks 5% of the glucose rows using random masking and runs
all available methods. Smaller model iteration counts are used so the
example stays reasonably quick.

``` r
benchmark_out <- run_comprehensive_imputation_benchmark(
  CGMExampleData,
  target_col = "LBORRES",
  feature_cols = c("AGE", "hba1c"),
  id_col = "USUBJID",
  time_col = "Time",
  time_format = "yyyy:mm:dd:hh:nn",
  mask_rates = 0.05,
  mask_type = "random",
  models = "all",
  rf_n_estimators = 25,
  xgb_nrounds = 25,
  lgb_nrounds = 25
)
```

The `results` table contains one row per selected model and mask rate.

``` r
benchmark_out$results
#>   MaskRate MaskType                                    Method      MAPE
#> 1       5%   random     ARIMA(4,1,0) on MICE-completed target 1.9770378
#> 2       5%   random      MICE + KNN (engineered lag features) 0.5088444
#> 3       5%   random MICE + LightGBM (engineered lag features) 0.8230684
#> 4       5%   random       MICE + RF (engineered lag features) 0.3515021
#> 5       5%   random  MICE + XGBoost (engineered lag features) 0.8499923
#> 6       5%   random MICE-only (base features; impute LBORRES) 2.0344169
#>          R2         MRD MaskedCount
#> 1 0.9496530 0.019770378          25
#> 2 0.9965445 0.005088444          25
#> 3 0.9946395 0.008230684          25
#> 4 0.9976854 0.003515021          25
#> 5 0.9945244 0.008499923          25
#> 6 0.9606598 0.020344169          25
```

Each selected model also gets its own completed data frame in
`benchmark_out$imputed_data`.

``` r
names(benchmark_out$imputed_data)
#> [1] "mice_only" "rf"        "knn"       "xgboost"   "lightgbm"  "arima"
```

The model-specific data frames include the original observed glucose
value, whether the row was masked, and the model-specific completed
value.

``` r
head(
  benchmark_out$imputed_data$rf[
    ,
    c(
      "USUBJID", "Time", ".Masked", "ObservedValue", "ImputedValue",
      "TimeSeries", "TimeDifferenceMinutes"
    )
  ]
)
#>   USUBJID             Time .Masked ObservedValue ImputedValue TimeSeries
#> 1      11 2020:01:16:00:00   FALSE           150          150      31075
#> 2      11 2020:01:16:00:05   FALSE           134          134      31080
#> 3      11 2020:01:16:00:10   FALSE           125          125      31085
#> 4      11 2020:01:16:00:15   FALSE           132          132      31090
#> 5      11 2020:01:16:00:20   FALSE           132          132      31095
#> 6      11 2020:01:16:00:25   FALSE           132          132      31100
#>   TimeDifferenceMinutes
#> 1                     0
#> 2                     5
#> 3                     5
#> 4                     5
#> 5                     5
#> 6                     5
```

### Impute Real Missing Glucose Values

Use
[`run_missing_glucose_imputation()`](https://zhanglabuky.github.io/CGMissingDataR/dev/reference/run_missing_glucose_imputation.md)
when your data already contains missing glucose values. This function
returns imputed values but does not calculate accuracy metrics, because
the true values for those missing rows are unknown.

This example uses `CGMExampleData2`, where 50 of the 500 glucose rows
are missing.

``` r
impute_out <- run_missing_glucose_imputation(
  CGMExampleData2,
  target_col = "LBORRES",
  feature_cols = c("AGE", "hba1c"),
  id_col = "USUBJID",
  time_col = "Time",
  time_format = "yyyy:mm:dd:hh:nn",
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

In real-imputation output, the original target column is left unchanged.
That means `LBORRES` is still `NA` where glucose was originally missing,
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
