# model.spice_build_validate

Analysis plugin for building and validating SPICE-oriented model artefacts using canonical datasets and the shared GX-TXT graphics/runtime APIs.

Version 5 keeps the existing SPICE adapter, ngspice sweeps and frozen parameters.
Numeric still computes each error summary once; the public CORE statistical API
now supplies its interpretation, units and statuses. The legacy CSV `r2` column
retains the centered prediction score `1 - SSE/SST`, explicitly identified as
`centered_comparison_score`; no regression fitting or independence claim follows.
Constant reference values and empty subsets have undefined scores. Relative
errors exclude zero reference denominators and values below the recorded floor;
no eligible denominator produces an undefined result. CSV columns gain status,
quantity, unit and reason fields. The portable `spice_statistics.tcldict` artifact,
render cache and all generated graph Datasets retain validated CORE records.
SPICE-specific grouping and numerical agreement tolerances remain module-owned.

Version 4 accepts qualified Analysis Source bindings such as `primary.X_V` and
resolves the source CSV column `X_V`. Version 3 published verification and optional
measured-validation graphs as six persistent Plot.dataset variants. No parameters
are fitted. A no-validation run produces three verification graphs, while a
validation Dataset enables the other three.

See `module.ini` for declared bindings, outputs and graph capabilities. Public framework contracts are documented under `docs/api/`.

On Linux, the default `ngspice_executable=ngspice` follows the executable
selected in Configuration > Runtime > SPICE. A nondefault module executable
or path remains an explicit override. The selected path is passed to Octave
in the module runtime configuration, without shell interpolation.

The model selector requires a callable mathematical model. Data-only scalar
expression cards are consumed by Numeric composition and do not imply a SPICE
adapter. Existing model-specific SPICE capability checks still apply.
