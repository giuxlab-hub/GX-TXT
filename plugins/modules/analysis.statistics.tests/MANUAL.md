# Hypothesis Tests

The method is explicit: one-sample t, independent pooled-variance t, Welch t, paired t, Mann-Whitney/Wilcoxon rank-sum, or Wilcoxon signed-rank. The second variable is required except for one-sample t. Independent tests use the two columns as separate samples; paired tests align the two values in each selected source row. Missing values are handled by the selected `error` or `omit` policy inside public `NUMERIC_API_v1`. The alternative is two-sided, greater or less, with the first sample or first-minus-second difference defining direction.

The null mean or mean difference applies to t-tests only. Rank tests require zero null shift. Two-variable tests require compatible units; the second variable is converted to the first variable's unit through the Unit Registry. T-tests publish mean or mean-difference confidence intervals and Cohen's d where defined. Welch's test does not invent a standardized effect. Rank tests publish rank-biserial effect size; their location-shift confidence interval is explicitly undefined. Rank p-values are exact conditional permutation/sign values for at most 20 relevant observations; larger samples use a tie-corrected normal approximation with continuity correction.

The result `table.generic` Dataset publishes method, statistic, degrees of freedom, input and valid counts, p-value, alternative, confidence level and bounds, effect size/name, null value, estimate, nonfinite policy and approximation method. The report and summary carry stable source Dataset/variable IDs and configuration provenance. The source Dataset remains unchanged.

## CORE interpretation (dev097)

Results now carry public CORE statuses, units, reasons and conditional test
assumptions through reports and Dataset metadata. Original output variable IDs
remain unchanged. One-sided intervals retain their unbounded endpoint.
Constant samples/differences have no nondegenerate estimated t distribution:
p-values and confidence intervals are explicitly undefined, while the observed
mean/difference remains available. Rank tests do not report mean confidence
intervals. Choosing a test states assumptions; it does not verify them from data.
Welch probabilities and intervals use approximate degrees of freedom.
