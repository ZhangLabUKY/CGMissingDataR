# Example dataset with missing glucose values

A small multi-subject CGM dataset intended for real missing-value
imputation examples. It has the same structure as `CGMExampleData`, but
`LBORRES` contains deterministic missing glucose values.

## Usage

``` r
CGMExampleData2
```

## Format

A data frame with 500 rows and 5 variables:

- USUBJID:

  Numeric subject identifier.

- LBORRES:

  Laboratory Observed Result for Glucose (numeric), with deterministic
  missing values.

- Time:

  Raw timestamp in `yyyy:mm:dd:hh:nn` format.

- AGE:

  Synthetic age in years.

- hba1c:

  Synthetic HbA1c value.

## Examples

``` r
data("CGMExampleData2")
```
