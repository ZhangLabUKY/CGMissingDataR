# CGMissingDataR: Benchmark and Impute Missing Glucose Values in CGM Data

Benchmarks and imputes missing glucose values in repeated-measures
continuous glucose monitoring (CGM) data. The package can mask known
glucose values using random, contiguous block, or gap-distribution block
missingness to compare imputation performance, and can impute glucose
values that are already missing in user data. Workflows create
time-series features from raw timestamps, support model selection, and
return model-specific completed data sets. Methods include multiple
imputation by chained equations (MICE; Azur et al. (2011)
[doi:10.1002/mpr.329](https://doi.org/10.1002/mpr.329) ), Random Forest
regression (Breiman (2001)
[doi:10.1023/A:1010933404324](https://doi.org/10.1023/A%3A1010933404324)
), k-nearest-neighbor regression (Zhang (2016)
[doi:10.21037/atm.2016.03.37](https://doi.org/10.21037/atm.2016.03.37)
), XGBoost (Chen and Guestrin (2016)
[doi:10.1145/2939672.2939785](https://doi.org/10.1145/2939672.2939785)
), LightGBM (Ke et al. (2017)
<https://papers.nips.cc/paper/6907-lightgbm-a-highly-efficient-gradient-boosting-decision>),
and ARIMA forecasting with the forecast framework (Hyndman and Khandakar
(2008)
[doi:10.18637/jss.v027.i03](https://doi.org/10.18637/jss.v027.i03) ).

## See also

Useful links:

- <https://zhanglabuky.github.io/CGMissingDataR/>

- <https://github.com/ZhangLabUKY/CGMissingDataR>

- Report bugs at <https://github.com/ZhangLabUKY/CGMissingDataR/issues>

## Author

**Maintainer**: Shubh Saraswat <shubh.saraswat00@gmail.com>
([ORCID](https://orcid.org/0009-0009-2359-1484)) \[copyright holder\]

Authors:

- Hasin Shahed Shad <hasin.shad@uky.edu>

- Xiaohua Douglas Zhang <douglas.zhang@uky.edu>
  ([ORCID](https://orcid.org/0000-0002-2486-7931))
