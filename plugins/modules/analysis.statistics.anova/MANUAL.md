# One-way ANOVA

Choose a numeric measurement and a text or numeric group variable from one Dataset, optionally restricted by a Dataset Selection. Ordinary one-way ANOVA assumes a common within-group variance. Welch one-way ANOVA uses group-specific variances and requires at least two observations and positive variance in every group. The method is never chosen automatically. Missing labels or nonfinite measurements follow the explicit `error` or `omit` policy.

The public `NUMERIC_API_v1` operation computes group counts, means and variances, between/within/total sums of squares, degrees of freedom, F and p-value. Ordinary ANOVA also reports eta-squared and omega-squared. These effect sizes are marked undefined for Welch's heteroscedastic test. Post-hoc comparisons are not part of this module.

Two `table.generic` Datasets are published: `<prefix>.groups` contains stable first-seen group indices, labels, counts, means, variances and standard deviations; `<prefix>.test` contains the method, observation counts, sums of squares, degrees of freedom, F, p-value and effect sizes/status. An optional group-mean graph is a persistent public Plot Dataset variant. Provenance records stable source Dataset and variable IDs, Selection, method and nonfinite policy. The source Dataset remains unchanged.

## CORE interpretation (dev097)

Group and test Datasets retain the same versioned CORE result records. Group
summary estimates are selected from Numeric's existing ANOVA results; no second
calculation is made. Welch results state approximate F inference and do not
claim classical eta/omega effects. Estimated omega squared may be negative and
is not silently clamped. Zero within-group variation does not establish a
nondegenerate estimated F distribution: reported inference is undefined while
descriptive sums of squares remain available. Existing group/variable IDs persist.
