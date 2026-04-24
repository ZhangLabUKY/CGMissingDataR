#' Example dataset for CGMissingData
#'
#' A small multi-subject CGM dataset intended for benchmark examples and tests.
#'
#' @format A data frame with 500 rows and 5 variables:
#' \describe{
#'   \item{USUBJID}{Numeric subject identifier.}
#'   \item{LBORRES}{Laboratory Observed Result for Glucose (numeric).}
#'   \item{Time}{Raw timestamp in `yyyy:mm:dd:hh:nn` format.}
#'   \item{AGE}{Synthetic age in years.}
#'   \item{hba1c}{Synthetic HbA1c value.}
#' }
#' @examples
#' data("CGMExampleData")
"CGMExampleData"

#' Example dataset with missing glucose values
#'
#' A small multi-subject CGM dataset intended for real missing-value imputation
#' examples. It has the same structure as `CGMExampleData`, but `LBORRES`
#' contains deterministic missing glucose values.
#'
#' @format A data frame with 500 rows and 5 variables:
#' \describe{
#'   \item{USUBJID}{Numeric subject identifier.}
#'   \item{LBORRES}{Laboratory Observed Result for Glucose (numeric), with
#'   deterministic missing values.}
#'   \item{Time}{Raw timestamp in `yyyy:mm:dd:hh:nn` format.}
#'   \item{AGE}{Synthetic age in years.}
#'   \item{hba1c}{Synthetic HbA1c value.}
#' }
#' @examples
#' data("CGMExampleData2")
"CGMExampleData2"
