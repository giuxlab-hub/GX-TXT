# Covariance and Correlation

Select at least two numeric variables from one canonical Dataset. Optional
Dataset Selection limits the rows before missing-data handling. Choose
`pairwise` to omit nonfinite values independently for each pair, or `listwise`
to require every selected variable finite on a shared row set. Set NaN / Inf
policy to `error` to reject nonfinite selected observations instead.

The result Dataset contains one row for every ordered variable pair, with
sample covariance, Pearson correlation, Spearman correlation, the pair's
valid/input/excluded counts, and a covariance-unit string. Correlations are
dimensionless. A constant variable yields an undefined correlation (NaN) with
its status recorded; fewer than two valid paired observations yield undefined
covariance/correlations. Source rows and source Dataset remain unchanged.

When enabled, the module creates a persistent Plot Dataset heatmap of Pearson
correlation. Analysis configuration, source Dataset and stable variable IDs,
Selection ID, missing-data policy and module version are recorded in result
provenance. The full selected matrix is retained in memory for this analysis;
Table Stream chunking bounds I/O, not the matrix size.
