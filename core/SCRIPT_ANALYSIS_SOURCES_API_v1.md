# Script Analysis Sources declaration API v1

Python and Octave scripts can declare the Dataset sources they require with one
UTF-8 comment line. Discovery reads the source as text and parses JSON; it does
not import, evaluate, or execute the researcher script.

Python uses `#` and Octave uses `%` before the same marker and JSON object:

```python
# GX-TXT-ANALYSIS-SOURCES-V1: {"api_version":1,"sources":[{"id":"primary","label":"Measured series","required":true,"contracts":["timeseries.table"],"purpose":"Data to analyze"},{"id":"reference","label":"Reference spectrum","required":false,"contracts":["spectrum.scientific"],"purpose":"Optional comparison"}]}
```

The equivalent Octave source starts that line with `%`. JSON booleans are
lowercase. The declaration is a single line anywhere in a `.py` or `.m` source.
There must be at most one declaration. A script without the line retains its
existing behavior.

Each source requires a unique `id`, a visible `label`, a JSON Boolean
`required`, and a nonempty `contracts` array. `purpose` and
`preferred_dataset` are optional strings. The preferred Dataset is a canonical
Dataset ID and is used only when it is registered and contract-compatible.
`primary` must be present and required, matching Analysis Source Map API v1.
Source IDs use letters, digits, and underscore, beginning with a letter.

The declaration governs source selection in the normal Analysis Source Map.
At runtime `analysis_source.<id>` contains the selected canonical `dataset_id`,
Dataset `kind`, and public metadata and variable access. Optional unselected
sources have an empty Dataset ID. No source is identified by a private storage
path. The Module Builder imports this declaration automatically and emits its
ordinary `[analysis_sources]` and `[analysis_source.<id>]` sections. Any manual
Builder definition that differs requires an explicit resolution in Builder.

The authoritative parser is `core/python/script_source_declaration_v1.py`.
`discover(path)` returns validated data or `None`; the CLI emits JSON or
validated tab-separated rows with `--tsv` for CORE Tcl integration. Invalid
declarations fail discovery with a line-specific error. The maximum script size
is 16 MiB and the metadata line is limited to 16 KiB.
