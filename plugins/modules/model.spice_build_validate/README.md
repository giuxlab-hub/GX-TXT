# model.spice_build_validate

Analysis plugin for building and validating SPICE-oriented model artefacts using canonical datasets and the shared GX-TXT graphics/runtime APIs.

Version 4 accepts qualified Analysis Source bindings such as `primary.X_V` and resolves the source CSV column `X_V`. Version 3 published verification and optional measured-validation graphs as six persistent Plot.dataset variants. The module retains the mathematical model's SPICE Adapter API and runs actual ngspice sweeps; it does not fit parameters. A no-validation run produces the three verification graphs, while a validation Dataset enables the other three. Generic RMSE, MAE, R², and relative-error summaries use the discovered public `math.numeric` `residual_metrics` operation; SPICE-specific grouping and pass thresholds remain here.

See `module.ini` for declared bindings, outputs and graph capabilities. Public framework contracts are documented under `docs/api/`.

On Linux, the default `ngspice_executable=ngspice` follows the executable
selected in Configuration > Runtime > SPICE. A nondefault module executable
or path remains an explicit override. The selected path is passed to Octave
in the module runtime configuration, without shell interpolation.
