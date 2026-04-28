# Changelog

## CGMissingDataR (development version)

- Made
  [`run_missing_glucose_imputation()`](https://zhanglabuky.github.io/CGMissingDataR/dev/reference/run_missing_glucose_imputation.md)
  the primary public workflow for imputing glucose values that are
  already missing in user data.
- Made the simulation-based comprehensive masking benchmark internal for
  development and validation.
- Added automatic raw timestamp standardization for common character,
  `POSIXct`, and `Date` inputs before using
  [`CGManalyzer::timeSeqConversion.fn()`](https://rdrr.io/pkg/CGManalyzer/man/timeSeqConversion.fn.html)
  to create `TimeSeries`, plus within-subject `TimeDifferenceMinutes`.
- Added model selection with the `models` argument. The default is
  `models = "mice_only"`; use `models = "all"` to run MICE-only, Random
  Forest, kNN, XGBoost, LightGBM, and ARIMA.
- Updated real-imputation outputs to return nested model-specific
  `imputed_data` data frames.
- Updated `CGMExampleData` to be the public 500-row multi-subject CGM
  example dataset with deterministic missing glucose values for
  real-imputation examples.
- Deprecated
  [`run_missingness_benchmark()`](https://zhanglabuky.github.io/CGMissingDataR/dev/reference/run_missingness_benchmark.md).
  It remains available for backward compatibility and now warns users to
  prefer
  [`run_missing_glucose_imputation()`](https://zhanglabuky.github.io/CGMissingDataR/dev/reference/run_missing_glucose_imputation.md)
  for real missing glucose values.
- Preparing for version 0.0.2 of CGMissingDataR after transferring
  GitHub Repository and fixing URLs.

## CGMissingDataR 0.0.1

CRAN release: 2026-02-03

- Initial package creation preparing for CRAN submission.
