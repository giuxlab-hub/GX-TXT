# Post-release future work

These ideas are deferred until after the current GX-TXT release and freeze. They do not block the current release.

## Dataset Curve Fit — custom analytical models

Dataset Curve Fit should eventually let users define a custom analytical model or function with fitted parameters.

This is intentionally deferred because the current data-only Numerical worker does not provide clean binding for arbitrary model callbacks. Do not expand `NUMERIC_API` solely for this feature during stabilization or the current release cycle.

Revisit it after the current release and freeze work, when execution-scoped numerical model callbacks can be supported cleanly through the public architecture.
