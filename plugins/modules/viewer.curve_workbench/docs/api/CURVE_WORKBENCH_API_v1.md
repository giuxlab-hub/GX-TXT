# Curve Workbench comparison display contract

Owner: `viewer.curve_workbench`, public family `CURVE_WORKBENCH_API_v1`.


## Source-bound numerical comparison presentation

`comparisonDisplaySource w` returns a binding to the live enabled comparison's actual window/incarnation, Session token, Document identity/generation, explicit reference/target/method and unchanged comparison record. Source provenance is sampled at admission; cached editable geometry does not assert that its original canonical Dataset remains current.

`comparisonDisplayValidate binding record` returns `valid=1` only while the same owner, active definition, exact record/receipt, geometry fingerprints, coordinate signature, Document generation and referenced resources remain valid. Otherwise it reports a precise stale/closed/inactive condition. Neither operation evaluates geometry, saves a Workspace or publishes data. Both are trusted host APIs; Script Bridge and C++ SDK grants are unchanged.

The residual display uses public Plot v4 `comparisonModel` and its existing native widget. Numerical/statistical authority remains the original comparison receipt, including evaluation indices, maximum and sampling policy. Display points are derived comparison samples, never canonical Dataset row identities. Editable main geometry remains under Native2D. Closing or invalidating its owner retires the residual controller and child surface. A stale comparison requires the ordinary Compare action to refresh. Saving an authorized Workspace may rebind its presentation; display failure does not undo a committed scientific save.

The dev109 implementation is integrated separately from focused runtime/GUI acceptance; see `docs/development/plot_comparison418/IMPLEMENTATION.md` in the framework.
