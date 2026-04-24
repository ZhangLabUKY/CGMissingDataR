# Run comprehensive imputation benchmark

Benchmarks target imputation under random, contiguous block, or
gap-distribution block masking. The workflow imputes the masked target
with MICE, recomputes lag features from the completed target series,
then evaluates MICE-only, Random Forest, kNN, XGBoost, LightGBM, and
ARIMA predictions on the full target series.

## Usage

``` r
run_comprehensive_imputation_benchmark(
  data,
  target_col,
  feature_cols = NULL,
  id_col = "USUBJID",
  time_col = "Time",
  time_format = "yyyy:mm:dd:hh:nn",
  time_unit = "minute",
  mask_rates = c(0.05, 0.1, 0.2, 0.3, 0.4),
  mask_type = c("random", "block", "gap_block"),
  models = "mice_only",
  rf_n_estimators = 200,
  knn_k = 7,
  xgb_nrounds = 300,
  lgb_nrounds = 400,
  arima_order = c(4L, 1L, 0L),
  seed = 42,
  lag_k = c(1, 2, 3),
  add_rollmean = TRUE,
  roll_window = 3,
  gap_bins = list(c(1, 5), c(6, 35), c(36, NA)),
  gap_probs = c(0.5923, 0.2569, 0.1509),
  open_cap = 0.5
)
```

## Arguments

- data:

  A data.frame, an object coercible to data.frame, or a path to a CSV
  file.

- target_col:

  Single character string: target column to mask and impute.

- feature_cols:

  Character vector of base feature columns excluding `target_col`. If
  `NULL`, all columns except `target_col`, `time_col`, and generated
  time features are used.

- id_col:

  Character string: subject identifier column used for lag features.

- time_col:

  Character string: raw timestamp column to convert into `TimeSeries`.

- time_format:

  Character string passed to
  [`CGManalyzer::timeSeqConversion.fn()`](https://rdrr.io/pkg/CGManalyzer/man/timeSeqConversion.fn.html).

- time_unit:

  Character string passed to
  [`CGManalyzer::timeSeqConversion.fn()`](https://rdrr.io/pkg/CGManalyzer/man/timeSeqConversion.fn.html).
  Use `"minute"` or `"second"`.

- mask_rates:

  Numeric vector in (0, 1): target-row masking rates.

- mask_type:

  One of `"random"`, `"block"`, or `"gap_block"`.

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

  Integer seed for masking, MICE, and model reproducibility.

- lag_k:

  Integer vector of target lags to compute.

- add_rollmean:

  Logical: add rolling mean of prior target values.

- roll_window:

  Integer rolling mean window.

- gap_bins:

  List of length-2 vectors defining gap-block size bins.

- gap_probs:

  Numeric probabilities for `gap_bins`.

- open_cap:

  Numeric cap used for the open-ended gap bin.

## Value

A list containing `results`, a data.frame with columns `MaskRate`,
`MaskType`, `Method`, `MAPE`, `R2`, `MRD`, and `MaskedCount`; and
`imputed_data`, a named list of model-specific completed data.frames.

## Details

The returned `imputed_data` object is a named list with one data.frame
per selected model. Each data.frame stacks rows across mask rates. For
unmasked rows, `ImputedValue` equals `ObservedValue`; for masked rows,
`ImputedValue` is the method-specific imputed or predicted target value.

`MRD` follows the comprehensive script convention:
`sum(abs(true - pred) / abs(true)) / length(true)`, with zero true
values excluded from the numerator but retained in the denominator.
`MAPE` is `MRD * 100`. `R2` is computed on the same full-length
prediction vector.

## Examples

``` r
data("CGMExampleData")
out <- run_comprehensive_imputation_benchmark(
  CGMExampleData,
  target_col = "LBORRES",
  feature_cols = c("AGE", "hba1c"),
  id_col = "USUBJID",
  time_col = "Time",
  time_format = "yyyy:mm:dd:hh:nn",
  mask_rates = 0.05,
  models = "all",
  rf_n_estimators = 25,
  xgb_nrounds = 25,
  lgb_nrounds = 25
)
out$results
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
names(out$imputed_data)
#> [1] "mice_only" "rf"        "knn"       "xgboost"   "lightgbm"  "arima"    
head(out$imputed_data$rf)
#>   MaskRate MaskType                              Method .Masked USUBJID LBORRES
#> 1       5%   random MICE + RF (engineered lag features)   FALSE      11     150
#> 2       5%   random MICE + RF (engineered lag features)   FALSE      11     134
#> 3       5%   random MICE + RF (engineered lag features)   FALSE      11     125
#> 4       5%   random MICE + RF (engineered lag features)   FALSE      11     132
#> 5       5%   random MICE + RF (engineered lag features)   FALSE      11     132
#> 6       5%   random MICE + RF (engineered lag features)   FALSE      11     132
#>               Time AGE hba1c TimeSeries TimeDifferenceMinutes LBORRES_lag1
#> 1 2020:01:16:00:00  34   6.4      31075                     0           NA
#> 2 2020:01:16:00:05  34   6.4      31080                     5          150
#> 3 2020:01:16:00:10  34   6.4      31085                     5          134
#> 4 2020:01:16:00:15  34   6.4      31090                     5          125
#> 5 2020:01:16:00:20  34   6.4      31095                     5          132
#> 6 2020:01:16:00:25  34   6.4      31100                     5          132
#>   LBORRES_lag2 LBORRES_lag3 LBORRES_rollmean_3 ObservedValue ImputedValue
#> 1           NA           NA                 NA           150          150
#> 2           NA           NA                 NA           134          134
#> 3          150           NA                 NA           125          125
#> 4          134          150           136.3333           132          132
#> 5          125          134           130.3333           132          132
#> 6          132          125           129.6667           132          132
```
