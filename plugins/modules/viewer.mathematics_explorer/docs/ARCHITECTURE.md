# Mathematics Explorer architecture

The independent Viewer owns formulas, parameter controls, domain choices and
presentation routing. Its original bounded data-only parser validates the GUI's
small formula grammar. Numerical evaluation uses one provider-owned public
`NUMERIC_API_v1/expression_evaluate` call, whose authoritative CORE parser and
Unit Registry reject unsupported syntax and dimensions. No Viewer evaluates
user text as code or implements a numerical solver.

`expression_analyze` uses the same evaluator with public Numeric `root_find` and
`minimize_1d`. Bounded sampling locates candidates, not a completeness proof.
Array calculus continues through the existing Numeric differentiation/integration
owners. Physical arithmetic/conversions use the public Unit Registry.

The native plot widget owns disposable device geometry, hit testing and
zoom/pan. The Viewer supplies evaluated samples, exact sample indices and full
sample extrema. Missing/invalid model results never replace the scientific
capture. Separate derivative panels avoid mixing unlike Y dimensions.

The existing Interactive Document stores the inert mathematical state and
numerical viewport. Session tokens guard saves, loads, analyses and publication.
Native widget destruction releases its native model; window destruction cancels
pending debounce callbacks. Source code and scientific formula input are never
interchangeable.

Explicit publication uses Dataset Publication v2 and creates new canonical
Dataset/Variable identities. A retained Graph uses public Plot Dataset v4 and
existing Graph Metadata/Variant/Session owners. Formula and Document provenance
remain attached to the published values; downstream rerendering reads the
canonical source. There is no private Dataset, Workspace or rendering store.

The original optional prototype source archive is immutable. Its adaptation
ledger is in INTEGRATION_PROVENANCE.md; historical source audit material is not
current functional guidance.
