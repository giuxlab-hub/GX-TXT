# demo.numeric.smoothing

`demo.numeric.smoothing` is an external GX-TXT numerical reference plugin for
GX-TXT 0.9.8.10-dev-097. It demonstrates Dataset-native smoothing through the public
`math.numeric` `NUMERIC_API_v1` service.

The plugin uses the public `dataset_smooth` operation with the methods actually
advertised by GX-TXT 0.9.8.10-dev-097:

- moving mean;
- moving median;
- Savitzky-Golay;
- local polynomial smoothing.

This release also supplies the corresponding portable Session Generator API v1
package:

```text
gxtxt_numerical_examples_smoothing_1.0.0.zip
```

Import that generator into the existing `GX-TXT Numerical Examples` library.
It appears as `Mathematics` → `Smoothing` and creates the deterministic ordinary
Session used by the tutorial. An identical copy is bundled under
`session_generators/`.

The generated Session contains `raw/smoothing_demo.csv` and
`metadata/ground_truth.txt`. Import the CSV through normal Acquisition as the
canonical `table.generic` Dataset, bind X, measured Y and reference Y, then run
the module. The analysis publishes one derived comparison Dataset and
automatically renders four scientific graphs.

See `MANUAL.md` for the complete reproducible GUI workflow and scientific
interpretation.

License: GNU GPL v3 or later.


Version 1.1.0 uses CORE `STATISTICAL_RESULT_SEMANTICS_API_v1` to interpret and
report existing pointwise errors. The result metadata records physical units,
applicability and comparison/subset identities. These descriptive errors do not
establish regression parameter uncertainty or sampling-inference claims.
