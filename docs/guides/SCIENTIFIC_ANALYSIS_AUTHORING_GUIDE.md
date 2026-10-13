# Authoring a Scientific Analysis plugin - GX-TXT v0.9.8.01

SPDX-License-Identifier: GPL-3.0-or-later

This guide is intended to be sufficient for writing a new analysis module **without reading GX-TXT source code**.

## Mandatory numerical architecture prerequisite

Before implementing or modifying any scientific analysis module, read **[GX-TXT architecture overview](../../ARCHITECTURE.md)**. It is normative. Generic reusable mathematics belongs in `math.numeric` / `NUMERIC_API`; analysis modules retain scientific workflow and domain semantics. If a required generic primitive is missing, extend the public numerical API first rather than implementing a private copy in the consumer.

## Standard scientific renderer (GX-TXT 0.9.7.17+)

For every graph representable by the standard GX-TXT renderer, a new analysis module **must prefer** the public `PLOT_DATASET_API_v2` service. The module calculates and publishes canonical datasets or results, configures Graph Series through the API using stable `dataset_id + variable_id` references, requests rendering, and retrieves artifacts from the API. The API is available with the user-facing `plot.dataset` module Enabled=0.

Use the standard renderer for supported line plots, one or more Graph Series, multiple datasets, dual-Y axes, variants, and Level Scale presentation. Configure Level Scale through the public CORE Level Scale API; it is not an extra PlotSpec field. API v1 remains stable for existing consumers. Check `supports` or `requireCapability` before optional features. An unsupported capability must produce an explicit error; do not silently substitute legacy X/Y bindings, another interpretation, or a private renderer.

For production scientific result plots, an unsupported standard visualization is **not** permission to create a private renderer. Extend `plot.dataset` / its public API with the smallest generic capability required, test it centrally, and then consume it from the module. Historical private renderers are migration targets, not precedent. See [PLOT_DATASET_API_v2](../api/PLOT_DATASET_API_v2.md) for discovery, Enabled behavior, PlotSpec, rendering and artifact retrieval. For supported Series editor capabilities, consult the public Plot Dataset API and current plugin documentation.

Normative specifications:

```text
docs/api/MODULE_API_v1.md
docs/api/PLOT_DATASET_API_v1.md
docs/api/PLOT_DATASET_API_v2.md
docs/api/SCIENTIFIC_ANALYSIS_DEFINITION_API_v1.md
docs/api/RENDER_CACHE_API_v1.md
docs/api/DOCUMENTATION_API_v1.md
docs/api/UNIT_DIMENSION_API_v1.md
docs/api/UNCERTAINTY_POLICY_v1.md
ARCHITECTURE.md
```

## 1. Mandatory plugin documentation

Every new/updated plugin must implement Documentation API v1:

```ini
[documentation]
api_version=1
guide=README.md
api_refs=MODULE_API_v1;SCIENTIFIC_ANALYSIS_DEFINITION_API_v1;RENDER_CACHE_API_v1
examples=
changelog=
```

v0.8.4 keeps older undocumented plugins loadable, but this is a compatibility window. Future releases may silently enforce the documentation requirement.

## 2. Keep the executable module thin

A normal Scientific Analysis module should primarily:

```text
read runtime.ini
resolve canonical dataset source(s)
resolve selected Analysis Definition descriptor_path
call gxtxt_analysis_run()
optionally save a standard render cache
perform only module-specific artifacts that the generic engine cannot express
```

Do not copy framework implementations of:

```text
expression evaluation
dependency sorting
crossing/interpolation
alignment/join/resampling
generic statistics/regression
masks/grouping
status propagation
feature-table export
legend
axes/grid
PNG finalization
```

## 3. Declare semantic bindings

Example `module.ini`:

```ini
[bindings]
roles=x;y;family;sigma_y

[binding.x]
label=X
required=1
role=independent

[binding.y]
label=Y
required=1
role=measure

[binding.family]
label=Family / group
required=1
role=group

[binding.sigma_y]
label=Y uncertainty
required=0
role=uncertainty
```

The Standard Module API writes resolved values into runtime `[bindings]`.

## 4. Use those bindings in `analysis.ini`

```ini
[variable.x]
source=primary
binding=x
type=numeric
role=independent
unit=V
```

Do not hard-code application column names in a generic module.

Optional input:

```ini
[variable.sigma_y]
source=primary
binding=sigma_y
type=numeric
role=uncertainty
required=0
```

## 5. Add an Analysis Definition selector

```ini
[config]
fields=dataset_id;analysis_definition_id

[config.analysis_definition_id]
type=analysis_definition
label=Analysis definition
required=1
scope=all
kind=curve_family
capabilities=expression;crossing;mask;plot;export
```

GX-TXT generates:

```text
Analysis definition [selector] [Parameters...] [Preflight...]
```

Do not write a module-specific parameter panel.

## 6. Declare scientific parameters in the definition

```ini
[parameters]
ids=negative_target;positive_target

[parameter.negative_target]
type=numeric
label=Negative target
default=-0.01
min=-1
max=0

[parameter.positive_target]
type=numeric
label=Positive target
default=0.005
min=0
max=1
```

Types supported by v0.8.4:

```text
numeric
string
bool
choice
```

The GUI, manifest persistence and runtime `[analysis_parameters]` are framework-owned.

## 7. Multiple sources with different grids

Declare them explicitly:

```ini
[sources]
roles=primary;chemistry
```

Do not assume rows correspond. Align them:

```ini
[operation.nh3_fast]
type=resample
target_x=time_fast
source_x=time_chem
value=nh3
extrapolation=forbid
output=nh3_fast
```

For exact metadata joins:

```ini
[operation.sample_label]
type=join
left_key=sample_id
right_key=metadata_sample_id
value=metadata_label
output=sample_label
```

## 8. Reusable features

Crossing:

```ini
[operation.zero]
type=crossing
x=x
y=y
target=0
group=family
interpolation=linear
extrapolation=forbid
output=X0
```

Derived coordinate:

```ini
[operation.delta]
type=expression
expression=x - X0
depends=zero
output=DeltaX
```

Reusable domain:

```ini
[operation.negative]
type=mask
value=x
operator=le
target_series=X0
depends=zero
output=negative_domain
```

Feature failures are local data states, not necessarily job failures:

```text
unavailable / target_not_reached
unavailable / dependency_unavailable
```

## 9. Spectral/general feature examples

Peak:

```ini
[operation.peak]
type=peak
x=wavenumber
y=absorbance
group=sample
mode=max
return=x
output=peak_position
```

Window + area:

```ini
[operation.band]
type=window
value=wavenumber
min=1300
max=1500
output=band_domain

[operation.area]
type=integrate
x=wavenumber
y=absorbance
group=sample
domain=band_domain
depends=band
output=band_area
```

`domain=` is non-destructive: the window mask restricts the points participating in the calculation while the original source rows remain available to other operations and plots. The framework never silently reorders curve traversal.

## 10. Correlation/regression/model fit

```ini
[operation.r]
type=correlate
x=energy
y=nh3
group=experiment
output=r_energy_nh3
```

```ini
[operation.cal]
type=regress
x=band_area
y=concentration
output=concentration_hat
```

Use `fit` only when the module/runtime already selects a Mathematical Model Plugin resource. The Scientific Analysis API does not replace Model Plugin API.

## 11. Units

Normal definitions may keep units as metadata.

For strict arithmetic:

```ini
[operation.power]
type=expression
expression=voltage * current
strict_units=1
unit=W
output=power
```

For explicit conversion:

```ini
[operation.current_A]
type=convert_unit
value=current_mA
to_unit=A
output=current_A
```

Read `UNIT_DIMENSION_API_v1.md` before relying on supported unit syntax.

## 12. Exports

```ini
[export.transformed]
type=csv
file=transformed.csv
columns=x;y;family;X0;DeltaX;negative_domain

[export.features]
type=feature_table
file=features.csv
features=X0

[export.summary]
type=text_summary
file=summary.txt
```

## 13. Generic grouped/domain plots

```ini
[plot.normalized]
type=line
file=03_normalized.png
x=DeltaX
series=y
group=family
domain=negative_domain
title=Normalized family
```

The framework creates one curve per group and applies the mask.

Grid/Axes are framework-owned. Do not put `grid on/off` workarounds in the plugin. Legends must use shared graphics APIs.

## 14. Minimal runtime skeleton

```octave
thisdir=fileparts(mfilename('fullpath'));
root=fileparts(fileparts(fileparts(fileparts(thisdir))));
addpath(fullfile(root,'core','octave','analysis'));
addpath(fullfile(root,'core','octave','io'));
addpath(fullfile(root,'core','octave','graphics'));
addpath(fullfile(root,'core','octave','cache'));

cfg=gxtxt_ini_read(config_path);
outdir=gxtxt_ini_get(cfg,'runtime.output_dir','');
source_path=gxtxt_ini_get(cfg,'dataset.path','');
def_path=gxtxt_ini_get(cfg,'analysis_definition.analysis_definition_id.descriptor_path','');

sources=struct();
sources.primary=source_path;
opts=struct('runtime_cfg',cfg);
r=gxtxt_analysis_run(def_path,sources,outdir,opts);
```

For multiple source roles, obtain each trusted canonical path from standard runtime/dataset metadata and populate the corresponding `sources.<role>` field. Do not search arbitrary files by filename.

## 15. Standard Render Cache API

Recommended for a new thin module:

```octave
meta=gxtxt_render_cache_standard_meta( ...
    module_id,module_version,def_path,sources,r.context.parameters);
cache=gxtxt_render_cache_from_analysis(r,meta);
gxtxt_render_cache_save(outdir,cache);
```

A historical plugin may continue using its own `render_cache.mat` structure.

## 16. Validate before/during Run

GUI users can use **Preflight...**.

Tests/tools should also call:

```octave
rep=gxtxt_analysis_validate_definition(def_path);
if(!rep.valid)
  error('invalid definition: %s',strjoin(rep.errors,', '));
endif
```

## 17. Generate installation reference

```bash
tclsh tools/generate_framework_reference.tcl
```

Read:

```text
docs/reference/INSTALLED_PLUGIN_REFERENCE.md
```

for the installed contracts/modules/models/definitions. This generated file does not replace normative API documentation.

## 18. Uncertainty

Preserve optional uncertainty series and declare them with `role=uncertainty`. Do not add private propagation formulas to a generic plugin. Read `UNCERTAINTY_POLICY_v1.md`.

## 19. Intentionally deferred after v0.8.4

See `TODO_v085.md`. In particular, generalized uncertainty propagation, richer fit/optimizer backends, advanced alignment policies, full dimensional-unit coverage, and additional scientific primitives should be added to the framework rather than implemented as competing plugin-local engines.

## Using multiple canonical datasets in one module (v0.8.5)

Do not create a private file selector or a second column-mapping system when an analysis needs several datasets. Declare Analysis Source Map API v1 in the module descriptor:

```ini
[analysis_sources]
api_version=1
ids=primary;uncertainty
dynamic=1

[analysis_source.primary]
required=1
contracts=curve_family.table

[analysis_source.uncertainty]
required=0
contracts=table.generic
```

GX-TXT generates the source table in the Analysis GUI. The user selects canonical Dataset IDs, then the normal binding chooser exposes qualified variables such as:

```text
primary.Vg1_V
primary.Ig1_mA
uncertainty.sigma_total
```

The module runtime normally needs only:

```octave
cfg = gxtxt_ini_read(config_path);
opts = struct('runtime_cfg', cfg);
result = gxtxt_analysis_run(definition_path, struct(), output_dir, opts);
```

The empty source map is filled from the runtime by the framework. You may also call `gxtxt_analysis_source_map_from_runtime(cfg)` explicitly.

Do not align sources in module code merely because they have different row counts. Declare `align`, `join`, `resample`, or `interpolate` in the Analysis Definition when scientifically required.

Full contract: `docs/api/ANALYSIS_SOURCE_MAP_API_v1.md`.


## Dataset inspection and canonical names (v0.8.6)

When a module consumes datasets through Analysis Source Map API v1, bindings refer to canonical variables. Original CSV headers are provenance metadata, not analysis identifiers.

Users can inspect `Original header -> Canonical variable` mappings in the framework-owned CSV Preview and Variables workspaces. Analysis plugins should not reopen RAW files to infer headers.

For example:

```text
primary      -> 2d21-cal7
uncertainty  -> uncertainty_profile

x=primary.Vg
sigma_y=uncertainty.sigma_total
```

The import/inspection layer does not align these datasets. Use explicit Scientific Analysis operations when alignment is scientifically required.

## Extending the standard Series editor

When a graph provider needs per-series controls beyond Dataset, X/Y stable
variable IDs, Axis, Label, Enabled and Order, use
[Series Editor Extension API v1](../api/SERIES_EDITOR_EXTENSION_API_v1.md).
Register provider callbacks for the relevant module/graph IDs and build controls
only in the supplied parent container.

The callback context identifies the base graph or exact variant and selected
`series_id`, and supplies a read-only generic Graph Series snapshot. Keep
provider properties in provider-owned persistent state keyed by graph, variant
and series. Validate before save and make provider persistence atomic. Do not
add renderer-specific fields to Graph Series, inspect CORE widgets, or create a
separate Series editor.

## Graph workflow services in GX-TXT 0.9.7.22

Providers may advertise series_editor_extension on a descriptor public API;
CORE activates the module's declared public APIs in descriptor order before
the first Series editor lookup. Providers should keep registration idempotent.

Use graphAxisConfigOpen for an explicit module, graph, and optional variant
instead of reading framework axis storage. Use graphUseStateGet only when a
consumer needs to inspect selection; standard CORE scheduling already removes
NON USE base graphs and variants from graph-specific work.
## Large dataset reads in GX-TXT 0.9.7.23

New large-data-aware consumers open the logical Dataset ID through Canonical
Dataset API v2 and query capabilities before choosing a range, chunk, or
hyperslab operation. Keep stable variable IDs in module configuration. Do not
open HDF5 objects, import h5py, inspect provider locators, or branch on file
extensions in plugin code.

CSV and HDF5 use the same consumer operations. A provider with
`random_access=0` may satisfy a row-range request by sequential scanning, so a
consumer that requires bounded late access must explicitly require that
capability. Multidimensional variables require `hyperslab_read`; do not flatten
them into table rows implicitly.

Existing modules may continue to use Analysis Source paths and Table Stream v2.
Migration of plot.dataset, Graph Series, FFT, audio and dataset.extract is not
part of this foundation release.

## Backend-neutral dataset writes in GX-TXT 0.9.7.24

New CORE-aware producers that need bounded or multidimensional output use
[Dataset Publication API v2](../api/DATASET_PUBLICATION_API_v2.md). Declare the
logical Dataset ID, contract, dimensions, stable Variable IDs, Schema v3
metadata, and required capabilities. Write through the generic publication
commands and let CORE select or validate the storage provider.

Use append with bounded chunks for extendible output and hyperslabs for array
regions. Declare uniform coordinates by origin and step when no stored payload
is needed. Keep scientific meaning in Schema v3 and the Semantic Registry;
storage provider, HDF5 groups, CSV delimiter, and private locators do not define
scientific identity.

Do not import h5py, construct HDF5 paths, write registry entries, or build an
intermediate CSV in a plugin. Abort an incomplete writer. Finalize performs
provider validation, SHA-256, atomic placement, and registry commit.

Existing producers may continue using Dataset Publication API v1. This patch
does not require migration of any scientific module.

## Table-shaped large-data reads in GX-TXT 0.9.7.25

Use [Table Stream API v3](../api/TABLE_STREAM_API_v3.md) when selected
variables are rank-1 columns on one shared row dimension. Open by Dataset ID or
the Analysis Source runtime descriptor, select stable Variable IDs, choose a
bounded chunk size, and optionally declare a start/count range.

Request `require_direct` when an algorithm cannot accept prefix scanning.
HDF5 satisfies direct row ranges; CSV reports a sequential fallback. Inspect
capabilities and diagnostics instead of branching on file extensions.

Use Canonical Dataset API v2 directly for matrices, fields, and general
n-dimensional objects. Do not flatten them to fit Table Stream. Keep legacy
bare-path calls only for compatibility code. New large-data-aware code should
not use `gxtxt_read_csv_table()` because it materializes the whole table.

This release does not migrate any existing scientific module.


## Capability-based storage access in GX-TXT 0.9.7.26

Call datasetAccessRequest with hard capabilities and optional characteristics. Keep provider names out of scientific logic. Use an explicit storage override only when requested by the user or producer. Inspect datasetAccessDiagnostics for the effective provider and cache decision. Legacy flat-table executables may call datasetCompatibilityCsv; CORE rejects objects without a lossless table representation.

## Graph resources and scientific result publication (dev-051)

Use `GRAPH_WORKFLOW_API_v1/presentation_set` for `xy_aspect_mode`, 3-D `aspect_mode`/`aspect_ratio`, and blank/inherit, `#RRGGBB` or `transparent` background. Rerender through the graph provider. Notes and metadata use stable provider/Variant/Clone references; annotations use module/graph/Variant identity and enforce descriptor capabilities. See [Graph Notes](../api/GRAPH_NOTES_API_v1.md), [Graph Metadata](../api/GRAPH_METADATA_API_v1.md) and [Plot Annotation](../api/PLOT_ANNOTATION_API_v1.md).

Public `NUMERIC_API_v1` curve-model operations fit and reconstruct arc/Bézier/PCHIP/smoothing-spline/Fourier state. Use `DATASET_PUBLICATION_API_v2/publish_series` for explicit scientific X/Y results and `DATASET_FILE_PUBLICATION_API_v1/publish_auto` for completed files. Python/Octave examples are `examples/scripts/combined_stabilization.*`.

## Experiment Duplication Policy authoring (dev080)

New or substantially updated GX-TXT modules MUST declare an Experiment Duplication Policy using the public CORE contract when they introduce module-owned Session-persistent state. Modules with no additional privately owned persistent state SHOULD use the minimal explicit empty policy supported by the API.

This MUST is an authoring requirement, not an installation or execution gate. Existing and third-party modules without a policy remain installable and runnable. Their custom configuration may be completely reset in a duplicate; safe omission and fresh configuration are intentional outcomes.

```ini
[experiment_duplication]
api_version=1
```

The minimal policy authorizes no custom configuration copies. Only explicitly classified, independently reusable preparation is eligible. CORE controls mandatory Dataset, Workspace, graph, observation, output and cache exclusions, validates dependencies/ownership and handles transactions. Existing Dataset, Metadata, Publication, Provenance, Script Registry, Interactive Document and Managed Resource APIs remain authoritative. Standard registries provide coarse legacy ownership; arbitrary private keys, filenames and source code are not classification authorities.

Do not implement private filesystem copying or ask CORE to recognize a module by name. Use capability/version discovery and the public `EXPERIMENT_DUPLICATION_POLICY_API_v1` validation contract. Generic scientific field types and declared bindings are excluded even when named `input`. Unlisted configuration resets; selectors and paths start empty. Module execution is explicitly reconfigured on fresh data.

See [Experiment Duplication Policy API](../api/EXPERIMENT_DUPLICATION_POLICY_API_v1.md) and runnable `examples/experiment_duplication_policy/` Python/Octave Builder projects. Builder 1.2.0 uses the same flat descriptor policy contract, preserves schema-version-1 A/B/W project fields and unchanged script bytes, and supplies a minimal policy on rebuild. Old generated ZIPs remain valid without rebuilding.
