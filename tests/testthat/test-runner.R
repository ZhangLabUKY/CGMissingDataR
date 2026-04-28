test_that("public example dataset has expected missing glucose shape", {
  data("CGMExampleData", package = "CGMissingDataR")

  expect_equal(nrow(CGMExampleData), 500L)
  expect_equal(ncol(CGMExampleData), 5L)
  expect_equal(length(unique(CGMExampleData$USUBJID)), 5L)
  expect_equal(sum(is.na(CGMExampleData$LBORRES)), 50L)
  expect_false("TimeSeries" %in% names(CGMExampleData))
  expect_false("TimeDifferenceMinutes" %in% names(CGMExampleData))
})

test_that("real missing glucose imputation returns default MICE-only outputs", {
  skip_if_not_installed("mice")
  skip_if_not_installed("CGManalyzer")

  data("CGMExampleData", package = "CGMissingDataR")

  out <- run_missing_glucose_imputation(
    CGMExampleData,
    target_col = "LBORRES",
    feature_cols = c("AGE", "hba1c"),
    id_col = "USUBJID",
    time_col = "Time"
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
    run_missing_glucose_imputation(
      CGMExampleData,
      target_col = "LBORRES",
      feature_cols = c("AGE", "hba1c"),
      id_col = "USUBJID",
      time_col = "Time",
      models = "not_a_model"
    ),
    "Invalid models"
  )
})

.time_parser_data <- function(time_values) {
  n <- length(time_values)
  glucose <- 120 + seq_len(n)
  glucose[c(5L, 18L)] <- NA_real_
  data.frame(
    USUBJID = rep(c("S1", "S2"), each = n / 2L),
    LBORRES = glucose,
    Time = time_values,
    AGE = rep(c(42, 55), each = n / 2L),
    hba1c = rep(c(6.4, 7.1), each = n / 2L)
  )
}

.run_time_parser_imputation <- function(data) {
  run_missing_glucose_imputation(
    data,
    target_col = "LBORRES",
    feature_cols = c("AGE", "hba1c"),
    id_col = "USUBJID",
    time_col = "Time"
  )
}

test_that("automatic timestamp parsing accepts common character formats", {
  skip_if_not_installed("mice")
  skip_if_not_installed("CGManalyzer")

  base_time <- as.POSIXct("2020-01-16 00:00:00", tz = "UTC") +
    seq(0, by = 300, length.out = 24)
  time_formats <- list(
    colon = format(base_time, "%Y:%m:%d:%H:%M"),
    iso_minutes = format(base_time, "%Y-%m-%d %H:%M"),
    iso_seconds = format(base_time, "%Y-%m-%d %H:%M:%S"),
    slash_seconds = format(base_time, "%Y/%m/%d %H:%M:%S"),
    us_slash_minutes = format(base_time, "%m/%d/%Y %H:%M"),
    iso_t = format(base_time, "%Y-%m-%dT%H:%M:%S")
  )

  for (time_values in time_formats) {
    out <- .run_time_parser_imputation(.time_parser_data(time_values))
    expect_named(out$imputed_data, "mice_only")
    expect_true("TimeSeries" %in% names(out$imputed_data$mice_only))
    expect_true("TimeDifferenceMinutes" %in% names(out$imputed_data$mice_only))
  }
})

test_that("automatic timestamp parsing accepts POSIXct timestamps", {
  skip_if_not_installed("mice")
  skip_if_not_installed("CGManalyzer")

  base_time <- as.POSIXct("2020-01-16 00:00:00", tz = "UTC") +
    seq(0, by = 300, length.out = 24)

  out <- .run_time_parser_imputation(.time_parser_data(base_time))

  expect_named(out$imputed_data, "mice_only")
  expect_true("TimeSeries" %in% names(out$imputed_data$mice_only))
  expect_true("TimeDifferenceMinutes" %in% names(out$imputed_data$mice_only))
})

test_that("automatic timestamp parsing reports unparseable timestamps", {
  bad_data <- .time_parser_data(rep("not a timestamp", 24))

  expect_error(
    .run_time_parser_imputation(bad_data),
    "Unable to parse time_col timestamps automatically"
  )
})
