# Principal Component Analysis

Choose at least two numeric variables from one Dataset and optionally restrict rows by a Dataset Selection. The missing-data rule is explicit: fail on any nonfinite value or remove complete rows listwise. Removed rows are counted and never imputed. The score Dataset carries the original one-based source-row identity for every retained observation.

Centering subtracts each variable mean when enabled. `standardize` divides by its sample standard deviation and requires positive spread. `none` keeps source units and requires all variables to have compatible linear units; values are converted to the first variable's unit before decomposition. Standardization permits mixed linear units. Uncentered PCA uses the uncentered second-moment SVD; explained variances still use singular-value squares divided by `n−1`, and the report records that choice.

The public `NUMERIC_API_v1` matrix SVD provides singular vectors and values. Components are chosen either by an explicit count or by the smallest number reaching the requested cumulative explained-variance fraction. Singular-vector signs are oriented deterministically so each loading's largest-magnitude element is positive.

Published `table.generic` Datasets are `<prefix>.scores`, `.loadings`, `.components`, and `.scaling`. They contain scores, loadings, eigen/explained variance and ratios, singular values, variable means/scales and stable source variable IDs. Scree, PC1/PC2 score and loading graphs are persistent public Plot Dataset variants when enabled. Provenance records Selection, preprocessing, component policy and missing-data rule. The selected matrix and SVD are retained in memory.
