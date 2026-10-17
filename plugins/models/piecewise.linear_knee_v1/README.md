# Continuous linear knee

For `d = x - breakpoint`, the response is
`level + left_slope*min(d,0) + right_slope*max(d,0)`.
Native branch selection avoids subtracting large terms in a flat outer regime.
The two regimes meet at `(breakpoint, level)`. The right branch owns the junction.
One joint fit estimates the breakpoint, level and slopes; continuity is exact.

Choose an initial breakpoint with observations on both sides and physically
reviewed search bounds. Start from different breakpoints when the shape suggests
more than one possible transition. Equal slopes reduce the model to a line and
make its breakpoint unidentifiable. Active breakpoint bounds, insufficient
support and rank deficiency require explicit uncertainty qualifications.

The covariance contains all free parameters and their correlations. A local
normal/Student approximation is not a profiled breakpoint interval and can be
unreliable for weak changes in slope. The distinction is discussed by the author
of [R segmented](https://search.r-project.org/CRAN/refmans/segmented/html/confint.segmented.html).
Use public CORE interpretation for availability and units. Both coordinates stay
in their original physical frame; this model forbids additive coordinate translations.
The outer straight lines extrapolate mathematically beyond the fitted support.
