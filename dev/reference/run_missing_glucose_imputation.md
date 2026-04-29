# Impute real missing glucose values

Imputes existing missing values in a target glucose column using
generated time features, lag features, and the selected model workflow.
This function does not calculate accuracy metrics because the true
values for the originally missing glucose rows are unknown.

## Usage

``` r
run_missing_glucose_imputation(
  data,
  target_col,
  feature_cols = NULL,
  id_col = "USUBJID",
  time_col = "Time",
  time_format = "yyyy:mm:dd:hh:nn",
  time_unit = "minute",
  models = "mice_only",
  rf_n_estimators = 200,
  knn_k = 7,
  xgb_nrounds = 300,
  lgb_nrounds = 400,
  arima_order = c(4L, 1L, 0L),
  seed = 42,
  lag_k = c(1, 2, 3),
  add_rollmean = TRUE,
  roll_window = 3
)
```

## Arguments

- data:

  A data.frame, an object coercible to data.frame, or a path to a CSV
  file.

- target_col:

  Single character string: target column with missing values to impute.

- feature_cols:

  Character vector of base feature columns excluding `target_col`. If
  `NULL`, all columns except `target_col`, `time_col`, and generated
  time features are used.

- id_col:

  Character string: subject identifier column used for time gaps and lag
  features.

- time_col:

  Character string: raw timestamp column to convert into `TimeSeries`.

- time_format:

  Advanced character string passed to
  [`CGManalyzer::timeSeqConversion.fn()`](https://rdrr.io/pkg/CGManalyzer/man/timeSeqConversion.fn.html).
  The default automatically handles common timestamp inputs, so most
  users only need to provide `time_col`.

- time_unit:

  Character string passed to
  [`CGManalyzer::timeSeqConversion.fn()`](https://rdrr.io/pkg/CGManalyzer/man/timeSeqConversion.fn.html).
  Use `"minute"` or `"second"`.

- models:

  Character vector of models to return. Use `"mice_only"`, `"rf"`,
  `"knn"`, `"xgboost"`, `"lightgbm"`, `"arima"`, or `"all"`. MICE is
  always run internally because the other models depend on the
  MICE-completed target.

- rf_n_estimators:

  Integer: number of random forest trees. Only used when `models`
  includes `"rf"` or `"all"`.

- knn_k:

  Integer: number of kNN neighbors. Only used when `models` includes
  `"knn"` or `"all"`.

- xgb_nrounds:

  Integer: number of XGBoost boosting rounds. Only used when `models`
  includes `"xgboost"` or `"all"`.

- lgb_nrounds:

  Integer: number of LightGBM boosting rounds. Only used when `models`
  includes `"lightgbm"` or `"all"`.

- arima_order:

  Integer vector of length 3 for
  [`forecast::Arima()`](https://pkg.robjhyndman.com/forecast/reference/Arima.html).
  Only used when `models` includes `"arima"` or `"all"`.

- seed:

  Integer seed for MICE and model reproducibility.

- lag_k:

  Integer vector of target lags to compute.

- add_rollmean:

  Logical: add rolling mean of prior target values.

- roll_window:

  Integer rolling mean window.

## Value

A list containing `summary`, a data.frame with columns `Method`,
`MissingRate`, `MissingCount`, and `RowsUsed`; and `imputed_data`, a
named list of model-specific completed data.frames.

## Details

Common timestamp inputs, including `POSIXct`, `Date`,
`2020:01:16:00:00`, `2020-01-16 00:00:00`, `2020/01/16 00:00:00`, and
`2020-01-16T00:00:00`, are standardized internally before
[`CGManalyzer::timeSeqConversion.fn()`](https://rdrr.io/pkg/CGManalyzer/man/timeSeqConversion.fn.html)
is called.

The returned `imputed_data` object is a named list with one data.frame
per selected model. The original target column is kept unchanged.
`ObservedValue` contains the original target values, including `NA`
where glucose was missing, and `ImputedValue` contains the completed
model-specific target values.

## Examples

``` r
data("CGMExampleData")
out <- run_missing_glucose_imputation(
  CGMExampleData,
  target_col = "LBORRES",
  feature_cols = c("AGE", "hba1c"),
  id_col = "USUBJID",
  time_col = "Time",
  models = c("mice_only", "rf"),
  rf_n_estimators = 25
)
out$summary
#>                                      Method MissingRate MissingCount RowsUsed
#> 1 MICE-only (base features; impute LBORRES)         0.1           50      500
#> 2       MICE + RF (engineered lag features)         0.1           50      500
names(out$imputed_data)
#> [1] "mice_only" "rf"       
head(subset(out$imputed_data$rf, .Missing == TRUE))
#>                                 Method .Missing USUBJID LBORRES
#> 10 MICE + RF (engineered lag features)     TRUE      11      NA
#> 31 MICE + RF (engineered lag features)     TRUE      11      NA
#> 32 MICE + RF (engineered lag features)     TRUE      11      NA
#> 33 MICE + RF (engineered lag features)     TRUE      11      NA
#> 34 MICE + RF (engineered lag features)     TRUE      11      NA
#> 55 MICE + RF (engineered lag features)     TRUE      11      NA
#>                Time AGE hba1c TimeSeries TimeDifferenceMinutes LBORRES_lag1
#> 10 2020:01:16:00:45  34   6.4      31120                     5    135.00000
#> 31 2020:01:16:02:30  34   6.4      31225                     5     83.00000
#> 32 2020:01:16:02:35  34   6.4      31230                     5     74.48172
#> 33 2020:01:16:02:40  34   6.4      31235                     5    140.24141
#> 34 2020:01:16:02:45  34   6.4      31240                     5    220.58479
#> 55 2020:01:16:04:30  34   6.4      31345                     5     80.00000
#>    LBORRES_lag2 LBORRES_lag3 LBORRES_rollmean_3 ObservedValue ImputedValue
#> 10    134.00000    131.00000          133.33333            NA       135.08
#> 31     83.00000     91.00000           85.66667            NA        82.52
#> 32     83.00000     83.00000           80.16057            NA        75.36
#> 33     74.48172     83.00000           99.24104            NA       155.76
#> 34    140.24141     74.48172          145.10264            NA       123.36
#> 55     84.00000     81.00000           81.66667            NA        78.68
```
