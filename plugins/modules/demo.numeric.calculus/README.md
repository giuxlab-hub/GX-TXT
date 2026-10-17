# demo.numeric.calculus

`demo.numeric.calculus` is an external GX-TXT 0.9.8.10-dev-097 reference plugin demonstrating Dataset-aware numerical differentiation, definite integration and cumulative integration through the public `math.numeric` `NUMERIC_API_v1` interface.

The canonical input is the existing Session Generator:

```text
Library:   GX-TXT Numerical Examples
Category:  Mathematics
Generator: Calculus
```

The generated `raw/calculus.csv` contains `x`, `f`, `df_dx` and `F`. The plugin computes calculus only from the bound `x` and `f` variables, compares the results with the separately bound analytical references, publishes `demo.numeric.calculus.result`, and automatically renders five scientific graphs.

The plugin does not read `metadata/ground_truth.txt` and therefore works when generator metadata have not been imported into Dataset Metadata. Future public metadata import can enrich provenance/reporting without becoming a numerical dependency.

See `MANUAL.md` for the complete GUI workflow, mathematics, output schema, graphs, validation and troubleshooting.


Version 1.1.0 publishes CORE statistical interpretation for the full derivative,
its endpoints and interior, and the cumulative integral comparison. Error
statistics use the public pointwise comparison profile; they establish no
regression or sampling-inference claim. Existing Dataset and report identities
remain stable, with additional status/reason/quantity fields. A two-point input
has an empty derivative interior and an explicitly undefined interior error.
