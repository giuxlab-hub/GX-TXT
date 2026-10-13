# demo.numeric.uncertainty

`demo.numeric.uncertainty` is an external GX-TXT 0.9.7.82 reference plugin demonstrating uncertainty-aware numerical processing through the public `math.numeric` / `NUMERIC_API_v1` service.

It has two explicit interpretations:

- **Standard uncertainty** — the auxiliary Dataset variable is a measurement standard uncertainty. The plugin obtains the arithmetic mean through public `statistics` and propagates the independent input standard uncertainties through public `propagate_uncertainty`.
- **Explicit statistical weight** — the auxiliary variable is an already-defined statistical weight. The plugin uses public `weighted_statistics`; with `inverse_variance` semantics it also uses public `least_squares` to obtain the estimate standard error.

The plugin never silently converts an uncertainty column into a weight. It publishes a result Dataset and a measurement-series Dataset, writes `uncertainty_report.txt`, and provides `01_uncertainty_measurements.png` through a persistent public Plot.dataset variant. Both graph modes can be adjusted through framework plot controls.

A portable `Measurement Uncertainty` Session Generator is bundled under `session_generators/`.

License: GNU GPL v3 or later.
