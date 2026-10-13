# Outlier Flags

Select a numeric Dataset variable, an optional Dataset Selection, and an explicit positive multiplier. The IQR rule uses type-7 Q1 and Q3, with fences Q1 − multiplier × IQR and Q3 + multiplier × IQR. Its signed score is (value − median) / IQR. The MAD rule uses the median and normal-consistency scaled MAD, with symmetric limits median ± multiplier × scaled MAD. Its signed score is (value − median) / scaled MAD. A zero scale produces score 0 at the center and signed infinity for a differing value; comparison with the finite limits still defines the flag.

The published `table.generic` Dataset contains the original one-based `source_row`, selected value, method, signed score, lower/upper limits, and a 0/1 `is_outlier` flag. All selected rows remain present. Under `omit`, nonfinite input rows have NaN score and flag 0; they are counted separately and are never silently removed from the published table. Under `error`, any nonfinite input stops analysis.

`NUMERIC_API_v1` supplies quantiles, MAD and vector comparisons. Publication records stable source Dataset and variable IDs, Selection, rule, threshold and nonfinite policy. The source Dataset remains unchanged. The full selected vector is retained in memory.
