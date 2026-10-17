# Resampling Inference

Choose a stable numeric Dataset variable and an optional Selection. Bootstrap resamples the finite first sample with replacement and reports a percentile confidence interval for its mean, median or sample standard deviation. At least two finite values are required. This is a basic percentile interval; it does not claim bias correction or guaranteed coverage for dependent observations.

Independent permutation compares the difference in group means using two variables as separate samples. Nonfinite values are removed independently; each variable may have a different number of observations. Paired permutation uses rows where both variables are finite, converts the second variable to the first unit, and randomly flips the sign of each paired difference. Permutation p-values use the finite Monte Carlo correction `(extreme + 1)/(replicates + 1)`; the alternative is explicit. The null distribution and observed difference have the first variable's unit. For independent samples, the grouping labels are the two chosen variables.

The explicit positive seed uses the public NUMERIC_API Park–Miller generator. Batches continue from its returned `next_seed`, so the result does not depend on global random state. Iterations are bounded to ten million generated indices and at most 100,000 replicates. The module emits determinate progress after each batch. The framework's standard run cancellation terminates the module process; no partial Dataset is published until all requested iterations finish. Parallel execution is not used for these bounded sequential batches.

The `.distribution` Dataset contains every replicate and the `.summary` Dataset contains counts, estimate, interval or p-value, seed, method and configuration. Both carry source Dataset and stable variable IDs, Selection ID, unit and complete run provenance. The source Dataset is immutable. Invalid units, missing bindings, nonfinite policy violations and unsupported settings fail explicitly.

## CORE interpretation (dev097)

The public Numeric `resampling_summary` operation owns percentile endpoints
and plus-one permutation probabilities. Both output Datasets carry the same
versioned CORE record, with conditional sampling assumptions, statuses, reasons
and units. Percentile intervals are approximate empirical-bootstrap intervals;
constant or single-replicate distributions do not establish uncertainty coverage.
The alternative selector applies to permutation tests. Bootstrap percentile
intervals are explicitly two-sided. Finite Monte Carlo plus-one probabilities
are positive even when no generated replicate is as extreme as the observation.
The original random generator, seed sequence, full distributions and output
scientific IDs are preserved.
