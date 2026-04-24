#' Run comprehensive imputation benchmark
#'
#' @description
#' Benchmarks target imputation under random, contiguous block, or
#' gap-distribution block masking. The workflow imputes the masked target with
#' MICE, recomputes lag features from the completed target series, then evaluates
#' MICE-only, Random Forest, kNN, XGBoost, LightGBM, and ARIMA predictions on the
#' full target series.
#'
#' @param data A data.frame, an object coercible to data.frame, or a path to a
#'   CSV file.
#' @param target_col Single character string: target column to mask and impute.
#' @param feature_cols Character vector of base feature columns excluding
#'   `target_col`. If `NULL`, all columns except `target_col`, `time_col`, and
#'   generated time features are used.
#' @param id_col Character string: subject identifier column used for lag
#'   features.
#' @param time_col Character string: raw timestamp column to convert into
#'   `TimeSeries`.
#' @param time_format Character string passed to
#'   `CGManalyzer::timeSeqConversion.fn()`.
#' @param time_unit Character string passed to
#'   `CGManalyzer::timeSeqConversion.fn()`. Use `"minute"` or `"second"`.
#' @param mask_rates Numeric vector in (0, 1): target-row masking rates.
#' @param mask_type One of `"random"`, `"block"`, or `"gap_block"`.
#' @param models Character vector of models to return. Use `"mice_only"`,
#'   `"rf"`, `"knn"`, `"xgboost"`, `"lightgbm"`, `"arima"`, or `"all"`.
#'   MICE is always run internally because the other models depend on the
#'   MICE-completed target.
#' @param rf_n_estimators Integer: number of random forest trees.
#'   Only used when `models` includes `"rf"` or `"all"`.
#' @param knn_k Integer: number of kNN neighbors. Only used when `models`
#'   includes `"knn"` or `"all"`.
#' @param xgb_nrounds Integer: number of XGBoost boosting rounds. Only used
#'   when `models` includes `"xgboost"` or `"all"`.
#' @param lgb_nrounds Integer: number of LightGBM boosting rounds. Only used
#'   when `models` includes `"lightgbm"` or `"all"`.
#' @param arima_order Integer vector of length 3 for `forecast::Arima()`. Only
#'   used when `models` includes `"arima"` or `"all"`.
#' @param seed Integer seed for masking, MICE, and model reproducibility.
#' @param lag_k Integer vector of target lags to compute.
#' @param add_rollmean Logical: add rolling mean of prior target values.
#' @param roll_window Integer rolling mean window.
#' @param gap_bins List of length-2 vectors defining gap-block size bins.
#' @param gap_probs Numeric probabilities for `gap_bins`.
#' @param open_cap Numeric cap used for the open-ended gap bin.
#'
#' @return A list containing `results`, a data.frame with columns
#'   `MaskRate`, `MaskType`, `Method`, `MAPE`, `R2`, `MRD`, and `MaskedCount`;
#'   and `imputed_data`, a named list of model-specific completed data.frames.
#'
#' @details
#' The returned `imputed_data` object is a named list with one data.frame per
#' selected model. Each data.frame stacks rows across mask rates. For unmasked
#' rows, `ImputedValue` equals `ObservedValue`; for masked rows, `ImputedValue`
#' is the method-specific imputed or predicted target value.
#'
#' `MRD` follows the comprehensive script convention:
#' `sum(abs(true - pred) / abs(true)) / length(true)`, with zero true values
#' excluded from the numerator but retained in the denominator. `MAPE` is
#' `MRD * 100`. `R2` is computed on the same full-length prediction vector.
#'
#' @importFrom FNN knn.reg
#' @importFrom ranger ranger
#' @importFrom mice mice complete
#' @importFrom data.table as.data.table setorderv shift frollmean
#' @importFrom stats complete.cases median predict
#' @importFrom CGManalyzer timeSeqConversion.fn
#'
#' @examples
#' data("CGMExampleData")
#' out <- run_comprehensive_imputation_benchmark(
#'   CGMExampleData,
#'   target_col = "LBORRES",
#'   feature_cols = c("AGE", "hba1c"),
#'   id_col = "USUBJID",
#'   time_col = "Time",
#'   time_format = "yyyy:mm:dd:hh:nn",
#'   mask_rates = 0.05,
#'   models = "all",
#'   rf_n_estimators = 25,
#'   xgb_nrounds = 25,
#'   lgb_nrounds = 25
#' )
#' out$results
#' names(out$imputed_data)
#' head(out$imputed_data$rf)
#'
#' @export
run_comprehensive_imputation_benchmark <- function(
  data,
  target_col,
  feature_cols = NULL,
  id_col = "USUBJID",
  time_col = "Time",
  time_format = "yyyy:mm:dd:hh:nn",
  time_unit = "minute",
  mask_rates = c(0.05, 0.10, 0.20, 0.30, 0.40),
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
  open_cap = 0.50
) {
  mask_type <- match.arg(mask_type)
  selected_models <- .cgmd_normalize_models(models)

  if (is.character(data) && length(data) == 1L && file.exists(data)) {
    df <- utils::read.csv(data, stringsAsFactors = FALSE)
  } else {
    df <- as.data.frame(data)
  }
  df$.RowID <- seq_len(nrow(df))

  if (!is.character(target_col) || length(target_col) != 1L) {
    stop("target_col must be a single character string.")
  }
  if (!is.character(id_col) || length(id_col) != 1L) {
    stop("id_col must be a single character string.")
  }
  if (!is.character(time_col) || length(time_col) != 1L) {
    stop("time_col must be a single character string.")
  }
  if (!is.character(time_format) || length(time_format) != 1L) {
    stop("time_format must be a single character string.")
  }
  if (!is.character(time_unit) || length(time_unit) != 1L) {
    stop("time_unit must be a single character string.")
  }
  if (!time_unit %in% c("minute", "second")) {
    stop("time_unit must be either 'minute' or 'second'.")
  }

  time_series_col <- "TimeSeries"
  time_diff_col <- "TimeDifferenceMinutes"
  generated_time_cols <- c(time_series_col, time_diff_col)

  if (is.null(feature_cols)) {
    feature_cols <- setdiff(
      names(df),
      c(target_col, time_col, generated_time_cols, ".RowID")
    )
  } else {
    feature_cols <- setdiff(
      unique(feature_cols),
      c(target_col, time_col, generated_time_cols, ".RowID")
    )
  }

  needed_cols <- unique(c(target_col, feature_cols, id_col, time_col))
  missing_cols <- setdiff(needed_cols, names(df))
  if (length(missing_cols) > 0L) {
    stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
  }

  df <- .cgmd_add_time_features(
    df = df,
    raw_time_col = time_col,
    id_col = id_col,
    time_format = time_format,
    time_unit = time_unit,
    time_series_col = time_series_col,
    time_diff_col = time_diff_col
  )
  feature_cols <- unique(c(feature_cols, generated_time_cols))

  coerce_numeric_strict <- function(x, nm) {
    if (is.numeric(x) || is.integer(x)) {
      return(as.double(x))
    }
    if (is.factor(x)) {
      x <- as.character(x)
    }
    if (is.character(x)) {
      num <- suppressWarnings(as.numeric(x))
      bad <- is.na(num) & !is.na(x) & nzchar(x)
      if (any(bad)) {
        stop(
          "Column '",
          nm,
          "' contains non-numeric values; recode it before benchmarking."
        )
      }
      return(num)
    }
    stop("Column '", nm, "' has unsupported type for numeric coercion.")
  }

  numeric_needed_cols <- unique(c(target_col, feature_cols))
  for (nm in numeric_needed_cols) {
    df[[nm]] <- coerce_numeric_strict(df[[nm]], nm)
  }

  complete_needed_cols <- unique(c(numeric_needed_cols, id_col))
  df <- df[
    stats::complete.cases(df[, complete_needed_cols, drop = FALSE]),
    ,
    drop = FALSE
  ]
  if (nrow(df) < 10L) {
    stop("Not enough complete rows after baseline cleaning.")
  }

  if (is.factor(mask_rates)) {
    mask_rates <- as.character(mask_rates)
  }
  if (is.character(mask_rates)) {
    mask_rates <- suppressWarnings(as.numeric(mask_rates))
  }
  if (!is.numeric(mask_rates) || any(!is.finite(mask_rates))) {
    stop("mask_rates must be a numeric vector in (0,1).")
  }
  if (any(mask_rates <= 0 | mask_rates >= 1)) {
    stop("mask_rates must be in (0,1).")
  }

  if (length(arima_order) != 3L || any(!is.finite(arima_order))) {
    stop("arima_order must be a finite numeric vector of length 3.")
  }
  arima_order <- as.integer(arima_order)

  df_base <- .cgmd_sort_by_id_time(df, id_col, time_series_col)
  y_true_full <- as.numeric(df_base[[target_col]])
  n_total <- nrow(df_base)

  eng_cols <- paste0(target_col, "_lag", lag_k)
  if (isTRUE(add_rollmean)) {
    eng_cols <- c(eng_cols, paste0(target_col, "_rollmean_", roll_window))
  }
  model_feature_cols <- unique(c(feature_cols, eng_cols))
  model_base_cols <- unique(c(
    id_col,
    time_series_col,
    target_col,
    feature_cols
  ))

  all_rows <- list()
  imputed_rows <- .cgmd_empty_model_rows(selected_models)
  ml_models <- c("rf", "knn", "xgboost", "lightgbm")
  needs_ml_models <- any(ml_models %in% selected_models)

  for (rate in mask_rates) {
    rate_label <- paste0(as.integer(rate * 100), "%")
    mask_seed <- seed + as.integer(rate * 100)
    mask_pos <- .cgmd_make_mask_pos(
      n = n_total,
      rate = rate,
      mask_type = mask_type,
      seed = mask_seed,
      gap_bins = gap_bins,
      gap_probs = gap_probs,
      open_cap = open_cap
    )
    test_idx <- which(mask_pos)
    train_idx <- which(!mask_pos)

    df_after <- df_base[, model_base_cols, drop = FALSE]
    df_after[[target_col]][test_idx] <- NA_real_

    imp_df <- df_after[, unique(c(target_col, feature_cols)), drop = FALSE]
    mice_method <- mice::make.method(imp_df)
    mice_method[] <- ""
    mice_method[target_col] <- "norm"

    pred_matrix <- mice::make.predictorMatrix(imp_df)
    pred_matrix[,] <- 0
    pred_matrix[target_col, setdiff(colnames(imp_df), target_col)] <- 1

    set.seed(seed)
    imp_obj <- mice::mice(
      imp_df,
      m = 1,
      maxit = 10,
      method = mice_method,
      predictorMatrix = pred_matrix,
      ridge = 1e-5,
      printFlag = FALSE,
      seed = seed
    )
    imp_mat <- mice::complete(imp_obj, 1)
    y_imp <- as.numeric(imp_mat[[target_col]])
    if (any(!is.finite(y_imp))) {
      stop("MICE returned non-finite values for ", target_col, ".")
    }

    df_model <- df_after
    df_model[[target_col]] <- y_imp
    df_model <- .cgmd_compute_lag_features(
      df = df_model,
      target_col = target_col,
      id_col = id_col,
      time_col = time_series_col,
      lag_k = lag_k,
      add_rollmean = add_rollmean,
      roll_window = roll_window
    )

    if (needs_ml_models) {
      X_imp <- as.matrix(df_model[, model_feature_cols, drop = FALSE])
      storage.mode(X_imp) <- "double"
      X_train <- X_imp[train_idx, , drop = FALSE]
      y_train <- y_true_full[train_idx]
      X_test <- X_imp[test_idx, , drop = FALSE]

      filled <- .cgmd_fill_missing_with_train_medians(
        train_mat = X_train,
        test_mat = X_test,
        cols = eng_cols
      )
      X_train <- filled$train
      X_test <- filled$test

      .cgmd_assert_all_finite_matrix(X_train, "X_train")
      .cgmd_assert_all_finite_matrix(X_test, "X_test")
    }

    p_mice <- y_true_full
    p_mice[test_idx] <- y_imp[test_idx]
    mice_method_label <- paste0(
      "MICE-only (base features; impute ",
      target_col,
      ")"
    )
    if ("mice_only" %in% selected_models) {
      all_rows[[length(all_rows) + 1L]] <- .cgmd_metric_row(
        rate = rate,
        rate_label = rate_label,
        mask_type = mask_type,
        method = mice_method_label,
        y_true = y_true_full,
        y_pred = p_mice,
        masked_count = length(test_idx)
      )
      imputed_rows$mice_only[[length(imputed_rows$mice_only) + 1L]] <-
        .cgmd_imputed_data_rows(
          rate = rate,
          rate_label = rate_label,
          mask_type = mask_type,
          method = mice_method_label,
          df_base = df_base,
          df_model = df_model,
          target_col = target_col,
          mask_pos = mask_pos,
          y_pred = p_mice
        )
    }

    if ("rf" %in% selected_models) {
      rf_model <- ranger::ranger(
        x = X_train,
        y = y_train,
        num.trees = rf_n_estimators,
        mtry = ncol(X_train),
        min.node.size = 1,
        replace = TRUE,
        sample.fraction = 1.0,
        seed = seed,
        num.threads = 1
      )
      y_rf <- stats::predict(rf_model, data = X_test)$predictions
      p_rf <- y_true_full
      p_rf[test_idx] <- y_rf
      rf_method_label <- "MICE + RF (engineered lag features)"
      all_rows[[length(all_rows) + 1L]] <- .cgmd_metric_row(
        rate = rate,
        rate_label = rate_label,
        mask_type = mask_type,
        method = rf_method_label,
        y_true = y_true_full,
        y_pred = p_rf,
        masked_count = length(test_idx)
      )
      imputed_rows$rf[[length(imputed_rows$rf) + 1L]] <-
        .cgmd_imputed_data_rows(
          rate = rate,
          rate_label = rate_label,
          mask_type = mask_type,
          method = rf_method_label,
          df_base = df_base,
          df_model = df_model,
          target_col = target_col,
          mask_pos = mask_pos,
          y_pred = p_rf
        )
    }

    if ("knn" %in% selected_models) {
      scaler <- .cgmd_fit_scaler(X_train)
      X_train_sc <- .cgmd_transform_scaler(X_train, scaler)
      X_test_sc <- .cgmd_transform_scaler(X_test, scaler)
      .cgmd_assert_all_finite_matrix(X_train_sc, "X_train_sc")
      .cgmd_assert_all_finite_matrix(X_test_sc, "X_test_sc")

      y_knn <- FNN::knn.reg(
        train = X_train_sc,
        test = X_test_sc,
        y = y_train,
        k = knn_k
      )$pred
      p_knn <- y_true_full
      p_knn[test_idx] <- y_knn
      knn_method_label <- "MICE + KNN (engineered lag features)"
      all_rows[[length(all_rows) + 1L]] <- .cgmd_metric_row(
        rate = rate,
        rate_label = rate_label,
        mask_type = mask_type,
        method = knn_method_label,
        y_true = y_true_full,
        y_pred = p_knn,
        masked_count = length(test_idx)
      )
      imputed_rows$knn[[length(imputed_rows$knn) + 1L]] <-
        .cgmd_imputed_data_rows(
          rate = rate,
          rate_label = rate_label,
          mask_type = mask_type,
          method = knn_method_label,
          df_base = df_base,
          df_model = df_model,
          target_col = target_col,
          mask_pos = mask_pos,
          y_pred = p_knn
        )
    }

    if ("xgboost" %in% selected_models) {
      dtrain <- xgboost::xgb.DMatrix(data = X_train, label = y_train)
      xgb_model <- xgboost::xgb.train(
        params = list(
          objective = "reg:squarederror",
          eta = 0.05,
          max_depth = 6,
          subsample = 0.8,
          colsample_bytree = 0.8,
          lambda = 1.0,
          eval_metric = "rmse",
          nthread = -1,
          seed = seed
        ),
        data = dtrain,
        nrounds = xgb_nrounds,
        verbose = 0
      )
      y_xgb <- stats::predict(
        xgb_model,
        xgboost::xgb.DMatrix(data = X_test)
      )
      p_xgb <- y_true_full
      p_xgb[test_idx] <- y_xgb
      xgb_method_label <- "MICE + XGBoost (engineered lag features)"
      all_rows[[length(all_rows) + 1L]] <- .cgmd_metric_row(
        rate = rate,
        rate_label = rate_label,
        mask_type = mask_type,
        method = xgb_method_label,
        y_true = y_true_full,
        y_pred = p_xgb,
        masked_count = length(test_idx)
      )
      imputed_rows$xgboost[[length(imputed_rows$xgboost) + 1L]] <-
        .cgmd_imputed_data_rows(
          rate = rate,
          rate_label = rate_label,
          mask_type = mask_type,
          method = xgb_method_label,
          df_base = df_base,
          df_model = df_model,
          target_col = target_col,
          mask_pos = mask_pos,
          y_pred = p_xgb
        )
    }

    if ("lightgbm" %in% selected_models) {
      lgb_train <- lightgbm::lgb.Dataset(data = X_train, label = y_train)
      lgb_model <- lightgbm::lgb.train(
        params = list(
          objective = "regression",
          learning_rate = 0.05,
          num_leaves = 31L,
          bagging_fraction = 0.8,
          feature_fraction = 0.8,
          seed = seed,
          verbose = -1
        ),
        data = lgb_train,
        nrounds = lgb_nrounds
      )
      y_lgb <- stats::predict(lgb_model, X_test)
      p_lgb <- y_true_full
      p_lgb[test_idx] <- y_lgb
      lgb_method_label <- "MICE + LightGBM (engineered lag features)"
      all_rows[[length(all_rows) + 1L]] <- .cgmd_metric_row(
        rate = rate,
        rate_label = rate_label,
        mask_type = mask_type,
        method = lgb_method_label,
        y_true = y_true_full,
        y_pred = p_lgb,
        masked_count = length(test_idx)
      )
      imputed_rows$lightgbm[[length(imputed_rows$lightgbm) + 1L]] <-
        .cgmd_imputed_data_rows(
          rate = rate,
          rate_label = rate_label,
          mask_type = mask_type,
          method = lgb_method_label,
          df_base = df_base,
          df_model = df_model,
          target_col = target_col,
          mask_pos = mask_pos,
          y_pred = p_lgb
        )
    }

    if ("arima" %in% selected_models) {
      arima_model <- forecast::Arima(y_imp, order = arima_order)
      y_arima <- as.numeric(
        forecast::forecast(arima_model, h = length(test_idx))$mean
      )
      p_arima <- y_true_full
      p_arima[test_idx] <- y_arima
      arima_method_label <- paste0(
        "ARIMA(",
        paste(arima_order, collapse = ","),
        ") on MICE-completed target"
      )
      all_rows[[length(all_rows) + 1L]] <- .cgmd_metric_row(
        rate = rate,
        rate_label = rate_label,
        mask_type = mask_type,
        method = arima_method_label,
        y_true = y_true_full,
        y_pred = p_arima,
        masked_count = length(test_idx)
      )
      imputed_rows$arima[[length(imputed_rows$arima) + 1L]] <-
        .cgmd_imputed_data_rows(
          rate = rate,
          rate_label = rate_label,
          mask_type = mask_type,
          method = arima_method_label,
          df_base = df_base,
          df_model = df_model,
          target_col = target_col,
          mask_pos = mask_pos,
          y_pred = p_arima
        )
    }
  }

  results <- do.call(rbind, all_rows)
  results <- results[order(results$MaskRateNum, results$Method), ]
  results$MaskRateNum <- NULL
  rownames(results) <- NULL

  imputed_data <- lapply(imputed_rows, .cgmd_bind_imputed_model_rows)

  list(results = results, imputed_data = imputed_data)
}

#' Impute real missing glucose values
#'
#' @description
#' Imputes existing missing values in a target glucose column using the same
#' time-feature, lag-feature, and model workflow as
#' `run_comprehensive_imputation_benchmark()`. This function does not calculate
#' accuracy metrics because the true values for the originally missing glucose
#' rows are unknown.
#'
#' @param data A data.frame, an object coercible to data.frame, or a path to a
#'   CSV file.
#' @param target_col Single character string: target column with missing values
#'   to impute.
#' @param feature_cols Character vector of base feature columns excluding
#'   `target_col`. If `NULL`, all columns except `target_col`, `time_col`, and
#'   generated time features are used.
#' @param id_col Character string: subject identifier column used for time gaps
#'   and lag features.
#' @param time_col Character string: raw timestamp column to convert into
#'   `TimeSeries`.
#' @param time_format Character string passed to
#'   `CGManalyzer::timeSeqConversion.fn()`.
#' @param time_unit Character string passed to
#'   `CGManalyzer::timeSeqConversion.fn()`. Use `"minute"` or `"second"`.
#' @param models Character vector of models to return. Use `"mice_only"`,
#'   `"rf"`, `"knn"`, `"xgboost"`, `"lightgbm"`, `"arima"`, or `"all"`.
#'   MICE is always run internally because the other models depend on the
#'   MICE-completed target.
#' @param rf_n_estimators Integer: number of random forest trees.
#'   Only used when `models` includes `"rf"` or `"all"`.
#' @param knn_k Integer: number of kNN neighbors. Only used when `models`
#'   includes `"knn"` or `"all"`.
#' @param xgb_nrounds Integer: number of XGBoost boosting rounds. Only used
#'   when `models` includes `"xgboost"` or `"all"`.
#' @param lgb_nrounds Integer: number of LightGBM boosting rounds. Only used
#'   when `models` includes `"lightgbm"` or `"all"`.
#' @param arima_order Integer vector of length 3 for `forecast::Arima()`. Only
#'   used when `models` includes `"arima"` or `"all"`.
#' @param seed Integer seed for MICE and model reproducibility.
#' @param lag_k Integer vector of target lags to compute.
#' @param add_rollmean Logical: add rolling mean of prior target values.
#' @param roll_window Integer rolling mean window.
#'
#' @return A list containing `summary`, a data.frame with columns `Method`,
#'   `MissingRate`, `MissingCount`, and `RowsUsed`; and `imputed_data`, a named
#'   list of model-specific completed data.frames.
#'
#' @details
#' The returned `imputed_data` object is a named list with one data.frame per
#' selected model. The original target column is kept unchanged. `ObservedValue`
#' contains the original target values, including `NA` where glucose was
#' missing, and `ImputedValue` contains the completed model-specific target
#' values.
#'
#' @examples
#' data("CGMExampleData2")
#' out <- run_missing_glucose_imputation(
#'   CGMExampleData2,
#'   target_col = "LBORRES",
#'   feature_cols = c("AGE", "hba1c"),
#'   id_col = "USUBJID",
#'   time_col = "Time",
#'   time_format = "yyyy:mm:dd:hh:nn",
#'   models = c("mice_only", "rf"),
#'   rf_n_estimators = 25
#' )
#' out$summary
#' names(out$imputed_data)
#' head(out$imputed_data$rf)
#'
#' @export
run_missing_glucose_imputation <- function(
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
) {
  selected_models <- .cgmd_normalize_models(models)

  if (is.character(data) && length(data) == 1L && file.exists(data)) {
    df <- utils::read.csv(data, stringsAsFactors = FALSE)
  } else {
    df <- as.data.frame(data)
  }
  df$.RowID <- seq_len(nrow(df))

  if (!is.character(target_col) || length(target_col) != 1L) {
    stop("target_col must be a single character string.")
  }
  if (!is.character(id_col) || length(id_col) != 1L) {
    stop("id_col must be a single character string.")
  }
  if (!is.character(time_col) || length(time_col) != 1L) {
    stop("time_col must be a single character string.")
  }
  if (!is.character(time_format) || length(time_format) != 1L) {
    stop("time_format must be a single character string.")
  }
  if (!is.character(time_unit) || length(time_unit) != 1L) {
    stop("time_unit must be a single character string.")
  }
  if (!time_unit %in% c("minute", "second")) {
    stop("time_unit must be either 'minute' or 'second'.")
  }

  time_series_col <- "TimeSeries"
  time_diff_col <- "TimeDifferenceMinutes"
  generated_time_cols <- c(time_series_col, time_diff_col)

  if (is.null(feature_cols)) {
    feature_cols <- setdiff(
      names(df),
      c(target_col, time_col, generated_time_cols, ".RowID")
    )
  } else {
    feature_cols <- setdiff(
      unique(feature_cols),
      c(target_col, time_col, generated_time_cols, ".RowID")
    )
  }

  needed_cols <- unique(c(target_col, feature_cols, id_col, time_col))
  missing_cols <- setdiff(needed_cols, names(df))
  if (length(missing_cols) > 0L) {
    stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
  }

  df <- .cgmd_add_time_features(
    df = df,
    raw_time_col = time_col,
    id_col = id_col,
    time_format = time_format,
    time_unit = time_unit,
    time_series_col = time_series_col,
    time_diff_col = time_diff_col
  )
  feature_cols <- unique(c(feature_cols, generated_time_cols))

  numeric_needed_cols <- unique(c(target_col, feature_cols))
  for (nm in numeric_needed_cols) {
    df[[nm]] <- .cgmd_coerce_numeric_strict(df[[nm]], nm)
  }

  complete_needed_cols <- unique(c(feature_cols, id_col))
  df <- df[
    stats::complete.cases(df[, complete_needed_cols, drop = FALSE]),
    ,
    drop = FALSE
  ]
  if (nrow(df) < 10L) {
    stop("Not enough complete rows after baseline cleaning.")
  }

  if (length(arima_order) != 3L || any(!is.finite(arima_order))) {
    stop("arima_order must be a finite numeric vector of length 3.")
  }
  arima_order <- as.integer(arima_order)

  df_base <- .cgmd_sort_by_id_time(df, id_col, time_series_col)
  y_observed_full <- as.numeric(df_base[[target_col]])
  missing_pos <- is.na(y_observed_full)
  missing_count <- sum(missing_pos)
  n_total <- nrow(df_base)
  missing_rate <- missing_count / n_total

  if (missing_count == 0L) {
    stop("No missing values found in target_col after preprocessing.")
  }
  if (missing_count == n_total) {
    stop(
      "All target_col values are missing; at least one observed value is required."
    )
  }

  eng_cols <- paste0(target_col, "_lag", lag_k)
  if (isTRUE(add_rollmean)) {
    eng_cols <- c(eng_cols, paste0(target_col, "_rollmean_", roll_window))
  }
  model_feature_cols <- unique(c(feature_cols, eng_cols))
  model_base_cols <- unique(c(
    id_col,
    time_series_col,
    target_col,
    feature_cols
  ))

  imp_df <- df_base[, unique(c(target_col, feature_cols)), drop = FALSE]
  mice_method <- mice::make.method(imp_df)
  mice_method[] <- ""
  mice_method[target_col] <- "norm"

  pred_matrix <- mice::make.predictorMatrix(imp_df)
  pred_matrix[,] <- 0
  pred_matrix[target_col, setdiff(colnames(imp_df), target_col)] <- 1

  set.seed(seed)
  imp_obj <- mice::mice(
    imp_df,
    m = 1,
    maxit = 10,
    method = mice_method,
    predictorMatrix = pred_matrix,
    ridge = 1e-5,
    printFlag = FALSE,
    seed = seed
  )
  imp_mat <- mice::complete(imp_obj, 1)
  y_imp <- as.numeric(imp_mat[[target_col]])
  if (any(!is.finite(y_imp))) {
    stop("MICE returned non-finite values for ", target_col, ".")
  }

  df_after <- df_base[, model_base_cols, drop = FALSE]
  df_model <- df_after
  df_model[[target_col]] <- y_imp
  df_model <- .cgmd_compute_lag_features(
    df = df_model,
    target_col = target_col,
    id_col = id_col,
    time_col = time_series_col,
    lag_k = lag_k,
    add_rollmean = add_rollmean,
    roll_window = roll_window
  )

  train_idx <- which(!missing_pos)
  test_idx <- which(missing_pos)
  imputed_rows <- .cgmd_empty_model_rows(selected_models)
  ml_models <- c("rf", "knn", "xgboost", "lightgbm")
  needs_ml_models <- any(ml_models %in% selected_models)

  if (needs_ml_models) {
    X_imp <- as.matrix(df_model[, model_feature_cols, drop = FALSE])
    storage.mode(X_imp) <- "double"
    X_train <- X_imp[train_idx, , drop = FALSE]
    y_train <- y_observed_full[train_idx]
    X_test <- X_imp[test_idx, , drop = FALSE]

    filled <- .cgmd_fill_missing_with_train_medians(
      train_mat = X_train,
      test_mat = X_test,
      cols = eng_cols
    )
    X_train <- filled$train
    X_test <- filled$test

    .cgmd_assert_all_finite_matrix(X_train, "X_train")
    .cgmd_assert_all_finite_matrix(X_test, "X_test")
  }

  p_mice <- y_observed_full
  p_mice[test_idx] <- y_imp[test_idx]
  mice_method_label <- paste0(
    "MICE-only (base features; impute ",
    target_col,
    ")"
  )
  if ("mice_only" %in% selected_models) {
    imputed_rows$mice_only[[1L]] <- .cgmd_real_imputed_data_rows(
      method = mice_method_label,
      df_base = df_base,
      df_model = df_model,
      target_col = target_col,
      missing_pos = missing_pos,
      y_pred = p_mice
    )
  }

  if ("rf" %in% selected_models) {
    rf_model <- ranger::ranger(
      x = X_train,
      y = y_train,
      num.trees = rf_n_estimators,
      mtry = ncol(X_train),
      min.node.size = 1,
      replace = TRUE,
      sample.fraction = 1.0,
      seed = seed,
      num.threads = 1
    )
    y_rf <- stats::predict(rf_model, data = X_test)$predictions
    p_rf <- y_observed_full
    p_rf[test_idx] <- y_rf
    rf_method_label <- "MICE + RF (engineered lag features)"
    imputed_rows$rf[[1L]] <- .cgmd_real_imputed_data_rows(
      method = rf_method_label,
      df_base = df_base,
      df_model = df_model,
      target_col = target_col,
      missing_pos = missing_pos,
      y_pred = p_rf
    )
  }

  if ("knn" %in% selected_models) {
    scaler <- .cgmd_fit_scaler(X_train)
    X_train_sc <- .cgmd_transform_scaler(X_train, scaler)
    X_test_sc <- .cgmd_transform_scaler(X_test, scaler)
    .cgmd_assert_all_finite_matrix(X_train_sc, "X_train_sc")
    .cgmd_assert_all_finite_matrix(X_test_sc, "X_test_sc")

    y_knn <- FNN::knn.reg(
      train = X_train_sc,
      test = X_test_sc,
      y = y_train,
      k = min(knn_k, length(y_train))
    )$pred
    p_knn <- y_observed_full
    p_knn[test_idx] <- y_knn
    knn_method_label <- "MICE + KNN (engineered lag features)"
    imputed_rows$knn[[1L]] <- .cgmd_real_imputed_data_rows(
      method = knn_method_label,
      df_base = df_base,
      df_model = df_model,
      target_col = target_col,
      missing_pos = missing_pos,
      y_pred = p_knn
    )
  }

  if ("xgboost" %in% selected_models) {
    dtrain <- xgboost::xgb.DMatrix(data = X_train, label = y_train)
    xgb_model <- xgboost::xgb.train(
      params = list(
        objective = "reg:squarederror",
        eta = 0.05,
        max_depth = 6,
        subsample = 0.8,
        colsample_bytree = 0.8,
        lambda = 1.0,
        eval_metric = "rmse",
        nthread = -1,
        seed = seed
      ),
      data = dtrain,
      nrounds = xgb_nrounds,
      verbose = 0
    )
    y_xgb <- stats::predict(
      xgb_model,
      xgboost::xgb.DMatrix(data = X_test)
    )
    p_xgb <- y_observed_full
    p_xgb[test_idx] <- y_xgb
    xgb_method_label <- "MICE + XGBoost (engineered lag features)"
    imputed_rows$xgboost[[1L]] <- .cgmd_real_imputed_data_rows(
      method = xgb_method_label,
      df_base = df_base,
      df_model = df_model,
      target_col = target_col,
      missing_pos = missing_pos,
      y_pred = p_xgb
    )
  }

  if ("lightgbm" %in% selected_models) {
    lgb_train <- lightgbm::lgb.Dataset(data = X_train, label = y_train)
    lgb_model <- lightgbm::lgb.train(
      params = list(
        objective = "regression",
        learning_rate = 0.05,
        num_leaves = 31L,
        bagging_fraction = 0.8,
        feature_fraction = 0.8,
        seed = seed,
        verbose = -1
      ),
      data = lgb_train,
      nrounds = lgb_nrounds
    )
    y_lgb <- stats::predict(lgb_model, X_test)
    p_lgb <- y_observed_full
    p_lgb[test_idx] <- y_lgb
    lgb_method_label <- "MICE + LightGBM (engineered lag features)"
    imputed_rows$lightgbm[[1L]] <- .cgmd_real_imputed_data_rows(
      method = lgb_method_label,
      df_base = df_base,
      df_model = df_model,
      target_col = target_col,
      missing_pos = missing_pos,
      y_pred = p_lgb
    )
  }

  if ("arima" %in% selected_models) {
    arima_model <- forecast::Arima(y_imp, order = arima_order)
    y_arima <- as.numeric(
      forecast::forecast(arima_model, h = length(test_idx))$mean
    )
    p_arima <- y_observed_full
    p_arima[test_idx] <- y_arima
    arima_method_label <- paste0(
      "ARIMA(",
      paste(arima_order, collapse = ","),
      ") on MICE-completed target"
    )
    imputed_rows$arima[[1L]] <- .cgmd_real_imputed_data_rows(
      method = arima_method_label,
      df_base = df_base,
      df_model = df_model,
      target_col = target_col,
      missing_pos = missing_pos,
      y_pred = p_arima
    )
  }

  imputed_data <- lapply(imputed_rows, .cgmd_bind_imputed_model_rows)
  summary <- data.frame(
    Method = vapply(imputed_data, function(x) unique(x$Method), character(1)),
    MissingRate = missing_rate,
    MissingCount = missing_count,
    RowsUsed = n_total,
    stringsAsFactors = FALSE
  )
  rownames(summary) <- NULL

  list(summary = summary, imputed_data = imputed_data)
}

.cgmd_model_keys <- function() {
  c("mice_only", "rf", "knn", "xgboost", "lightgbm", "arima")
}

.cgmd_normalize_models <- function(models) {
  if (is.factor(models)) {
    models <- as.character(models)
  }
  if (!is.character(models) || length(models) == 0L) {
    stop("models must be a character vector.")
  }

  models <- tolower(trimws(models))
  if (any(is.na(models)) || any(models == "")) {
    stop("models cannot contain NA or empty values.")
  }

  valid_models <- c(.cgmd_model_keys(), "all")
  invalid_models <- setdiff(models, valid_models)
  if (length(invalid_models) > 0L) {
    stop(
      "Invalid models: ",
      paste(invalid_models, collapse = ", "),
      ". Valid values are: ",
      paste(valid_models, collapse = ", "),
      "."
    )
  }

  if ("all" %in% models) {
    return(.cgmd_model_keys())
  }

  unique(models)
}

.cgmd_empty_model_rows <- function(models) {
  rows <- vector("list", length(models))
  names(rows) <- models
  for (model in models) {
    rows[[model]] <- list()
  }
  rows
}

.cgmd_bind_imputed_model_rows <- function(rows) {
  out <- do.call(rbind, rows)
  if ("MaskRateNum" %in% names(out)) {
    out <- out[order(out$MaskRateNum, out$.RowID), ]
    out$MaskRateNum <- NULL
  } else {
    out <- out[order(out$.RowID), ]
  }
  out$.RowID <- NULL
  rownames(out) <- NULL
  out
}

.cgmd_imputed_data_rows <- function(
  rate,
  rate_label,
  mask_type,
  method,
  df_base,
  df_model,
  target_col,
  mask_pos,
  y_pred
) {
  engineered_cols <- setdiff(names(df_model), names(df_base))
  engineered_df <- df_model[, engineered_cols, drop = FALSE]
  observed <- as.numeric(df_base[[target_col]])

  out <- data.frame(
    MaskRateNum = rate,
    MaskRate = rate_label,
    MaskType = mask_type,
    Method = method,
    .RowID = df_base$.RowID,
    .Masked = as.logical(mask_pos),
    stringsAsFactors = FALSE
  )
  out <- cbind(
    out,
    df_base[, setdiff(names(df_base), ".RowID"), drop = FALSE],
    engineered_df
  )
  out$ObservedValue <- observed
  out$ImputedValue <- as.numeric(y_pred)
  out
}

.cgmd_real_imputed_data_rows <- function(
  method,
  df_base,
  df_model,
  target_col,
  missing_pos,
  y_pred
) {
  engineered_cols <- setdiff(names(df_model), names(df_base))
  engineered_df <- df_model[, engineered_cols, drop = FALSE]
  observed <- as.numeric(df_base[[target_col]])

  out <- data.frame(
    Method = method,
    .RowID = df_base$.RowID,
    .Missing = as.logical(missing_pos),
    stringsAsFactors = FALSE
  )
  out <- cbind(
    out,
    df_base[, setdiff(names(df_base), ".RowID"), drop = FALSE],
    engineered_df
  )
  out$ObservedValue <- observed
  out$ImputedValue <- as.numeric(y_pred)
  out
}

.cgmd_coerce_numeric_strict <- function(x, nm) {
  if (is.numeric(x) || is.integer(x)) {
    return(as.double(x))
  }
  if (is.factor(x)) {
    x <- as.character(x)
  }
  if (is.character(x)) {
    num <- suppressWarnings(as.numeric(x))
    bad <- is.na(num) & !is.na(x) & nzchar(x)
    if (any(bad)) {
      stop(
        "Column '",
        nm,
        "' contains non-numeric values; recode it before imputation."
      )
    }
    return(num)
  }
  stop("Column '", nm, "' has unsupported type for numeric coercion.")
}

.cgmd_add_time_features <- function(
  df,
  raw_time_col,
  id_col,
  time_format,
  time_unit,
  time_series_col,
  time_diff_col
) {
  time_mat <- CGManalyzer::timeSeqConversion.fn(
    time.stamp = as.character(df[[raw_time_col]]),
    time.format = time_format,
    timeUnit = time_unit
  )
  if (ncol(time_mat) < 1L) {
    stop("CGManalyzer::timeSeqConversion.fn() did not return a time series.")
  }

  df[[time_series_col]] <- as.numeric(time_mat[, 1])
  if (any(!is.finite(df[[time_series_col]]))) {
    stop("Converted TimeSeries contains non-finite values.")
  }

  dt <- data.table::as.data.table(df)
  data.table::setorderv(dt, c(id_col, time_series_col))
  diff_divisor <- if (identical(time_unit, "second")) 60 else 1
  dt[,
    (time_diff_col) := {
      ts <- get(time_series_col)
      c(0, diff(ts) / diff_divisor)
    },
    by = id_col
  ]

  as.data.frame(dt)
}

.cgmd_sort_by_id_time <- function(df, id_col, time_col) {
  dt <- data.table::as.data.table(df)
  data.table::setorderv(dt, c(id_col, time_col))
  as.data.frame(dt)
}

.cgmd_compute_lag_features <- function(
  df,
  target_col,
  id_col,
  time_col,
  lag_k,
  add_rollmean,
  roll_window
) {
  dt <- data.table::as.data.table(df)
  data.table::setorderv(dt, c(id_col, time_col))

  for (k in lag_k) {
    nm <- paste0(target_col, "_lag", k)
    dt[,
      (nm) := data.table::shift(get(target_col), n = k, type = "lag"),
      by = id_col
    ]
  }

  if (isTRUE(add_rollmean)) {
    rc <- paste0(target_col, "_rollmean_", roll_window)
    dt[,
      (rc) := data.table::frollmean(
        data.table::shift(get(target_col), n = 1, type = "lag"),
        n = as.integer(roll_window),
        fill = NA_real_,
        align = "right"
      ),
      by = id_col
    ]
  }

  as.data.frame(dt)
}

.cgmd_make_mask_pos <- function(
  n,
  rate,
  mask_type,
  seed,
  gap_bins,
  gap_probs,
  open_cap
) {
  n_mask <- as.integer(ceiling(rate * n))
  if (n_mask <= 0L) {
    return(rep(FALSE, n))
  }
  if (n_mask >= n) {
    stop("Mask size >= number of rows; reduce mask rate or provide more rows.")
  }

  set.seed(seed)

  if (mask_type == "random") {
    idx <- sample.int(n, size = n_mask, replace = FALSE)
  } else if (mask_type == "block") {
    start <- sample.int(n - n_mask + 1L, size = 1L)
    idx <- start:(start + n_mask - 1L)
  } else {
    idx <- .cgmd_gap_block_indices(
      n = n,
      n_mask = n_mask,
      gap_bins = gap_bins,
      gap_probs = gap_probs,
      open_cap = open_cap
    )
  }

  mask_pos <- rep(FALSE, n)
  mask_pos[idx] <- TRUE
  mask_pos
}

.cgmd_gap_block_indices <- function(n, n_mask, gap_bins, gap_probs, open_cap) {
  if (length(gap_bins) == 0L) {
    stop("gap_bins must contain at least one bin.")
  }
  if (length(gap_bins) != length(gap_probs)) {
    stop("gap_bins and gap_probs must have the same length.")
  }
  if (any(!is.finite(gap_probs)) || sum(gap_probs) <= 0) {
    stop("gap_probs must be finite and have a positive sum.")
  }

  probs <- gap_probs / sum(gap_probs)
  bins_eff <- lapply(gap_bins, function(b) {
    if (length(b) != 2L) {
      stop("Each gap bin must have length 2.")
    }
    lo <- as.integer(b[1])
    hi <- b[2]
    hi_eff <- if (is.na(hi)) {
      as.integer(max(lo, floor(n_mask * open_cap)))
    } else {
      as.integer(hi)
    }
    if (!is.finite(lo) || !is.finite(hi_eff) || lo < 1L || hi_eff < lo) {
      stop("Invalid gap bin: ", paste(b, collapse = ", "))
    }
    c(lo, hi_eff)
  })

  block_sizes <- integer(0)
  total <- 0L
  while (total < n_mask) {
    remaining <- n_mask - total
    b_idx <- sample.int(length(bins_eff), 1L, prob = probs)
    lo <- bins_eff[[b_idx]][1]
    hi <- bins_eff[[b_idx]][2]
    len <- if (lo > remaining) {
      remaining
    } else {
      sample.int(min(hi, remaining) - lo + 1L, 1L) + lo - 1L
    }
    block_sizes <- c(block_sizes, len)
    total <- total + len
  }

  k <- length(block_sizes)
  n_free <- n - n_mask
  splits <- sort(sample.int(n_free + 1L, size = k, replace = (k > n_free)) - 1L)
  gaps <- diff(c(0L, splits, n_free))

  masked <- integer(0)
  pos <- 0L
  for (i in seq_along(block_sizes)) {
    pos <- pos + gaps[i]
    masked <- c(masked, pos:(pos + block_sizes[i] - 1L))
    pos <- pos + block_sizes[i]
  }
  masked <- sort(unique(masked))
  masked <- masked[masked < n]
  masked + 1L
}

.cgmd_fill_missing_with_train_medians <- function(train_mat, test_mat, cols) {
  cols <- intersect(cols, colnames(train_mat))
  if (length(cols) == 0L) {
    return(list(train = train_mat, test = test_mat, fill_vals = numeric(0)))
  }

  fill_vals <- vapply(
    cols,
    function(col) stats::median(train_mat[, col], na.rm = TRUE),
    numeric(1)
  )
  bad_cols <- names(fill_vals)[!is.finite(fill_vals)]
  if (length(bad_cols) > 0L) {
    stop(
      sprintf(
        "Cannot compute finite training medians for columns: %s",
        paste(bad_cols, collapse = ", ")
      )
    )
  }

  for (col in cols) {
    train_bad <- !is.finite(train_mat[, col])
    test_bad <- !is.finite(test_mat[, col])
    if (any(train_bad)) {
      train_mat[train_bad, col] <- fill_vals[[col]]
    }
    if (any(test_bad)) {
      test_mat[test_bad, col] <- fill_vals[[col]]
    }
  }

  list(train = train_mat, test = test_mat, fill_vals = fill_vals)
}

.cgmd_assert_all_finite_matrix <- function(x, name) {
  bad_counts <- colSums(!is.finite(x))
  if (any(bad_counts > 0L)) {
    stop(
      sprintf(
        "%s contains non-finite values in columns: %s",
        name,
        paste(names(bad_counts)[bad_counts > 0L], collapse = ", ")
      )
    )
  }
}

.cgmd_fit_scaler <- function(mat) {
  mat <- as.matrix(mat)
  mu <- colMeans(mat, na.rm = TRUE)
  centered <- sweep(mat, 2, mu, "-")
  sd_pop <- sqrt(colMeans(centered^2, na.rm = TRUE))
  sd_pop[!is.finite(sd_pop) | sd_pop == 0] <- 1
  list(mean = mu, scale = sd_pop)
}

.cgmd_transform_scaler <- function(mat, scaler) {
  mat <- as.matrix(mat)
  out <- sweep(mat, 2, scaler$mean, "-")
  out <- sweep(out, 2, scaler$scale, "/")
  out[!is.finite(out)] <- 0
  out
}

.cgmd_metric_row <- function(
  rate,
  rate_label,
  mask_type,
  method,
  y_true,
  y_pred,
  masked_count
) {
  mrd <- .cgmd_mrd_full(y_true, y_pred)
  data.frame(
    MaskRateNum = rate,
    MaskRate = rate_label,
    MaskType = mask_type,
    Method = method,
    MAPE = mrd * 100,
    R2 = .cgmd_r2_full(y_true, y_pred),
    MRD = mrd,
    MaskedCount = masked_count,
    stringsAsFactors = FALSE
  )
}

.cgmd_mrd_full <- function(y_true, y_pred) {
  y_true <- as.numeric(y_true)
  y_pred <- as.numeric(y_pred)
  ok <- abs(y_true) != 0 & is.finite(y_true) & is.finite(y_pred)
  if (!any(ok)) {
    return(NA_real_)
  }
  sum(abs(y_true[ok] - y_pred[ok]) / abs(y_true[ok])) / length(y_true)
}

.cgmd_r2_full <- function(y_true, y_pred) {
  y_true <- as.numeric(y_true)
  y_pred <- as.numeric(y_pred)
  ok <- is.finite(y_true) & is.finite(y_pred)
  if (!any(ok)) {
    return(NA_real_)
  }
  sst <- sum((y_true[ok] - mean(y_true[ok]))^2)
  if (!is.finite(sst) || sst == 0) {
    return(NA_real_)
  }
  1 - sum((y_true[ok] - y_pred[ok])^2) / sst
}
