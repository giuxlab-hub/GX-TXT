# Nonlinear fit integration demo

`demo.numeric.nonlinear_fit` is an external GX-TXT analysis plugin for the
`GX-TXT Numerical Examples / Nonlinear Fitting` generated Session.

The module uses the shared `plot.dataset` graphics service and public Analysis Source Map and Dataset Publication interfaces:

- it no longer requires a hard-coded Dataset ID `demo.nonlinear.source`;
- the input Dataset is selected normally from the GX-TXT Analysis panel;
- X and Y variables are selected through normal module bindings;
- the expected parameters are read from the generated Session's
  `metadata/ground_truth.txt`;
- the fit result is published as `demo.nonlinear.fit`;
- the graph is produced automatically by the module's Graph Provider.

The generator's `raw/nonlinear_fitting.csv` must be imported as a Canonical Dataset through `acq.generic_csv` before it can be selected by this analysis. The module does not require any particular Session name.

See `MANUAL.md` for the exact GUI procedure.


## Dataset and variable bindings

Select the imported nonlinear fitting Dataset as Analysis Source `primary`, then bind `primary.x` and `primary.y` using the public Analysis Source Map API v1.


## Binding identity note

GX-TXT binding labels such as `primary.x` identify a canonical variable by its
source/name in the GUI. The module resolves those tokens through Analysis Source metadata and passes stable Dataset `variable_id` values to `NUMERIC_API_v1`.
