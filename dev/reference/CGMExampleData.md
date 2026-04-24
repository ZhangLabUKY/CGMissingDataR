# Example dataset for CGMissingData

A small multi-subject CGM dataset intended for benchmark examples and
tests.

## Usage

``` r
CGMExampleData
```

## Format

A data frame with 500 rows and 5 variables:

- USUBJID:

  Numeric subject identifier.

- LBORRES:

  Laboratory Observed Result for Glucose (numeric).

- Time:

  Raw timestamp in `yyyy:mm:dd:hh:nn` format.

- AGE:

  Synthetic age in years.

- hba1c:

  Synthetic HbA1c value.

## Examples

``` r
data("CGMExampleData")
```
