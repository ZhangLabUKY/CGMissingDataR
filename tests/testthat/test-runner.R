test_that("example datasets have expected shapes", {
  data("CGMExampleData", package = "CGMissingDataR")
  data("CGMExampleData2", package = "CGMissingDataR")

  expect_equal(nrow(CGMExampleData), 500L)
  expect_equal(ncol(CGMExampleData), 5L)
  expect_equal(sum(is.na(CGMExampleData$LBORRES)), 0L)
  expect_false("TimeSeries" %in% names(CGMExampleData))
  expect_false("TimeDifferenceMinutes" %in% names(CGMExampleData))

  expect_equal(nrow(CGMExampleData2), 500L)
  expect_equal(ncol(CGMExampleData2), 5L)
  expect_equal(sum(is.na(CGMExampleData2$LBORRES)), 50L)
  expect_false("TimeSeries" %in% names(CGMExampleData2))
  expect_false("TimeDifferenceMinutes" %in% names(CGMExampleData2))
})

test_that("comprehensive benchmark returns default MICE-only outputs", {
  skip_if_not_installed("mice")
  skip_if_not_installed("CGManalyzer")

  data("CGMExampleData", package = "CGMissingDataR")

  out <- run_comprehensive_imputation_benchmark(
    CGMExampleData,
    target_col = "LBORRES",
    feature_cols = c("AGE", "hba1c"),
    id_col = "USUBJID",
    time_col = "Time",
    time_format = "yyyy:mm:dd:hh:nn",
    mask_rates = 0.05
  )

  expect_named(out, c("results", "imputed_data"))
  expect_true(all(
    c("MaskRate", "MaskType", "Method", "MAPE", "R2", "MRD", "MaskedCount") %in%
      names(out$results)
  ))
  expect_named(out$imputed_data, "mice_only")
  expect_true(all(
    c(".Masked", "ObservedValue", "ImputedValue", "TimeSeries",
      "TimeDifferenceMinutes") %in%
      names(out$imputed_data$mice_only)
  ))
})

test_that("real missing glucose imputation returns default MICE-only outputs", {
  skip_if_not_installed("mice")
  skip_if_not_installed("CGManalyzer")

  data("CGMExampleData2", package = "CGMissingDataR")

  out <- run_missing_glucose_imputation(
    CGMExampleData2,
    target_col = "LBORRES",
    feature_cols = c("AGE", "hba1c"),
    id_col = "USUBJID",
    time_col = "Time",
    time_format = "yyyy:mm:dd:hh:nn"
  )

  expect_named(out, c("summary", "imputed_data"))
  expect_true(all(
    c("Method", "MissingRate", "MissingCount", "RowsUsed") %in%
      names(out$summary)
  ))
  expect_named(out$imputed_data, "mice_only")
  expect_true(all(
    c(".Missing", "ObservedValue", "ImputedValue", "TimeSeries",
      "TimeDifferenceMinutes") %in%
      names(out$imputed_data$mice_only)
  ))
  expect_equal(out$summary$MissingCount, 50L)
})

test_that("model selection rejects invalid model names", {
  skip_if_not_installed("mice")
  skip_if_not_installed("CGManalyzer")

  data("CGMExampleData", package = "CGMissingDataR")

  expect_error(
    run_comprehensive_imputation_benchmark(
      CGMExampleData,
      target_col = "LBORRES",
      feature_cols = c("AGE", "hba1c"),
      id_col = "USUBJID",
      time_col = "Time",
      time_format = "yyyy:mm:dd:hh:nn",
      mask_rates = 0.05,
      models = "not_a_model"
    ),
    "Invalid models"
  )
})
