# Dataset Expression

Dataset Expression evaluates a controlled arithmetic expression over bound symbols. It uses the shared Scientific Analysis parser, Unit Registry dimensional checks, and the public `NUMERIC_API_v1` operation catalog. The Operations button lists expression functions directly from catalog metadata, including argument, shape, unit and nonfinite behavior. It can insert a function name into the Expression field. Arbitrary Octave source is not accepted.

Each binding has a unique symbol and one source kind:

| Kind | Required fields | Meaning |
| --- | --- | --- |
| `series` | Variable | Selected rows of one stable Dataset variable. |
| `literal` | Scalar, optional Unit | A finite numeric scalar. Blank Unit means dimensionless (`1`). |
| `metadata` | Metadata key, optional Unit | An exact Dataset Metadata key whose value is a finite numeric scalar. |
| `row` | Variable, one-based Source row | One scalar from the original Dataset row, read through Table Stream. |
| `selection` | Variable, Selection aggregate | Mean, median, minimum, maximum or sum over the selected rows. An enabled Selection is required. |

Variable bindings persist stable `dataset_id` and `variable_id` in the saved calculation definition. A unitless source variable requires an explicit Unit; a unit in the Dataset schema takes precedence. Arithmetic converts linear units to canonical dimensions and validates an optional requested Output unit. Semantic or nonlinear units cannot participate in strict arithmetic. Only one source Dataset is accepted; the module performs no implicit cross-Dataset alignment.

The result must be a real numeric scalar or a vector with one element per selected source row. A scalar becomes a one-row published Dataset. A vector becomes a published Dataset containing `source_row` and the named result variable. Dataset Publication records source IDs, expression, Selection and producer provenance. The source remains unchanged. The full selected vector is retained in memory.

The module writes `expression_definition.ini` alongside the report. It contains the expression and stable symbol bindings. To reuse it in another run, set **Saved definition file** to its absolute path or a path relative to the current Session root; the current source Dataset must have the same stable ID. The selected result Dataset ID and variable ID remain controlled by the current run configuration. The module configuration and binding table also persist in the Session manifest.
