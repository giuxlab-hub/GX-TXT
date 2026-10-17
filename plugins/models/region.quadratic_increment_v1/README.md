# Quadratic regional increment

Independent data-only descriptor `region.quadratic_increment_v1`. Use public
`NUMERIC_API_v1.fit_region_catalog` and `fit_region_compose`.

The increment is `slope*t+quadratic*t^2`; its derivative with respect to regional span
`t` is `slope+2*quadratic*t`. It contributes zero at its start. The builder clamps
completed increments and sums them with the global physical level. C0 shares
the junction value; C1 also substitutes the previous endpoint derivative for
this region's starting slope. All remaining parameters share one optimization
and one covariance. The first region's level is anchored at the recipe origin.

Observation windows select actual training rows separately from finite ordered
breakpoint search windows. Equality belongs to the region on the right. Gaps
and extrapolation contain model predictions, not observed regime evidence.

Initial values require physical units and review. An exponential rate of zero
uses the analytic linear limit through `exprel`. Local covariance requires
identification and appropriate error assumptions; it does not certify a unique
breakpoint or replace profile/score inference. Explicit multistart may reveal
multiple minima. See the Numeric public API and Fitter guide.

