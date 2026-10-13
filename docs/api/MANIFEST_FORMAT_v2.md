# GX-TXT Pipeline Manifest Format 2

SPDX-License-Identifier: GPL-3.0-or-later

Manifest Format 2 is the native configuration format used by GX-TXT Pipeline v0.6.x. It removes the historical ProvaTelecomando-specific IR/HOLD/LED/channel/probe schema from newly written manifests and stores only descriptor-driven module state.

## Design rules

- The manifest stores configuration and provenance, not algorithm code.
- Acquisition, experiment notebook, instrument instances, canonical variables, analysis modules, input bindings, plot configuration, generic graphics and print settings are separate concepts.
- No real instrument is inserted automatically. Instruments are explicit instances of an installed **Instrument Module API** descriptor.
- Variables inherit CSV headers by default but may be renamed and associated with instruments/channels.
- Analysis modules declare the roles they require; the framework binds canonical variables to those roles.
- Module-specific plot controls come from the analysis module descriptor, not from hard-coded GUI panels.
- Stable IDs are used instead of GUI labels.

## `[pipeline]`

```ini
[pipeline]
format=2
application_version=0.6.9
module_api_version=1
instrument_api_version=1
```

The manifest schema, Standard Module API and Instrument Module API are versioned independently.

## `[runtime]`

```ini
[runtime]
octave_cmd=/usr/bin/octave-cli
cpu_count=16
worker_file=/path/to/gxtxt_csv_worker.m
```

Runtime/toolchain configuration is separate from scientific module configuration.

## `[acquisition]`

```ini
[acquisition]
module_id=acq.generic_csv
input_csv=/data/VG_X.csv
session_root=/data/GXTXT_sessions
session_name=6BX7_GE_fit
```

`module_id` selects exactly one installed acquisition module.

## `[session]`

```ini
[session]
mode=analysis_only
```

Typical values are `analysis_only` for generic tables and `measurement` for instrument acquisitions.

## `[experiment]`

The Experiment page is a lightweight laboratory notebook. Multiline values are escaped as `\n` in the physical INI file and restored on load.

```ini
[experiment]
name=6BX7 characteristic extraction
project=Vacuum tube SPICE models
date=2026-09-10
operator=Giuseppe
tags=6BX7;triode;SPICE
notes=General free-form notes
objective=Build and validate a reusable triode model
procedure=Digitize characteristic curves and fit them globally
observations=Fit quality and anomalies observed during the run
```

Instrument-specific information belongs to instrument instances; measured quantities and CSV mappings belong to Source Variables.

Since GX-TXT 0.9.7.66, `experiment.project` is retained as a backward-compatible display snapshot / historical free-text field. Persistent Project identity is stored separately:

```ini
[project_link]
api_version=1
experiment_id=experiment-...
project_id=project-...
legacy_project=
```

`experiment_id` is stable for the Experiment and `project_id` refers to Project API v1. The Project association is logical and does not move or duplicate Session/Dataset content. A legacy manifest without `[project_link]` remains valid; its old `experiment.project` value is preserved as recoverable legacy text and is not automatically converted into a persistent Project.

See [Project API v1](PROJECT_API_v1.md).

## `[instrument_modules]` and `[instrument_module_instance.N]`

An experiment may contain zero instruments:

```ini
[instrument_modules]
api_version=1
count=0
```

To record an instrument, the user first loads an installed instrument module from the **Instrumentation** tab. The descriptor defines which fields appear. Loading the descriptor creates an editable instance; it does not claim that any particular physical device exists or was used.

Example oscilloscope instance:

```ini
[instrument_modules]
api_version=1
count=1

[instrument_module_instance.1]
enabled=1
module_id=instrument.oscilloscope
id=scope_main
display_name=Bench oscilloscope
field.role=Acquisition
field.manufacturer=Rigol
field.model=DS1104Z-S
field.serial=
field.firmware=
field.bandwidth=100 MHz
field.sample_rate=
field.memory_depth=
field.coupling=DC
field.notes=Probe and setup notes can span multiple lines.
```

Framework-owned fields are `enabled`, `module_id`, `id`, and `display_name`. All `field.*` entries are declared by the selected instrument descriptor.

The stable `id` is what Source Variables use to reference the instrument.

## `[source_variables]` and `[source_variable.N]`

```ini
[source_variables]
count=3

[source_variable.1]
enabled=1
source_column=1
source_channel=
original_header=X_V
canonical=Va_V
unit=V
semantic_role=independent
instrument_id=scope_main
instrument_channel=CH1
```

Fields:

- `source_column`: 1-based column in the imported CSV;
- `source_channel`: optional source name present in the acquisition format;
- `original_header`: header found in the source file;
- `canonical`: variable name exposed to datasets and modules;
- `unit`: engineering/scientific unit;
- `semantic_role`: optional generic hint such as `independent`, `family`, `measured`;
- `instrument_id`: optional reference to an instrument instance stable ID;
- `instrument_channel`: optional channel/terminal on that instrument.

For generic CSV import, aliases are written into the canonical dataset header; they are not merely display labels.

## `[module_state]`

```ini
[module_state]
enabled=curvefit.family_global
run=curvefit.family_global
```

`enabled` means that the analysis module belongs to the experiment. `run` means it is selected for the next PHASE 2 execution. Removing `run` does not delete existing results.

Acquisition selection belongs to `[acquisition]` and is not duplicated here.

## `[module_config.<module-id>]`

These keys are generated from the module descriptor.

```ini
[module_config.curvefit.family_global]
dataset_id=curve_family.primary
model_id=triode.koren_v1
solver=auto
max_iter=2000
tolerance=1e-8
plot_dpi=200
```

The core GUI does not know these field names in advance.

## `[module_binding.<module-id>]`

Analysis modules declare semantic input roles. The manifest stores the user binding for each role:

```ini
[module_binding.curvefit.family_global]
x=auto
family=auto
y=auto
```

Explicit example:

```ini
x=Va_V
family=Vg_V
y=Ia_mA
```

Resolution order is:

```text
explicit binding
→ model-preferred variable
→ matching semantic role
→ error if a required role remains unresolved
```

The module therefore knows **what** it needs without hard-coding **where** the data came from.

## `[module_plot.<module-id>.<plot-id>]`

Every plot exposed by a scientific module may have descriptor-generated configuration. Example:

```ini
[module_plot.curvefit.family_global.curvefit.family.overlay]
title=6BX7-GT characteristic curves
x_label=Anode voltage [V]
y_label=Anode current [mA]
show_measured=1
show_fitted=1
marker_size=4
line_width=1.6
legend_mode=family_only
x_min=
x_max=
y_min=0
y_max=
```

These values are copied into the runtime INI as `[plot.<plot-id>]` and are consumed by both the first render and rerender. Adding a plot option therefore requires a descriptor/renderer change, not a new hard-coded Tcl GUI branch.

## `[graphics]`

`[graphics]` is the global renderer profile shared by every native module: dimensions, DPI, font sizes/units, toolkit, grid defaults, legend defaults and background. It is intentionally distinct from module-specific plot semantics. In v0.7.4 it is the first layer of the graphics inheritance model.

## `[module_graphics.<module-id>]`

Optional common presentation override for all graphs generated by one module. It is disabled by default. Blank or `inherit` values fall back to `[graphics]`. Plot-specific presentation controls such as `[plot.legend.<graph-id>]` remain the final layer.

```ini
[module_graphics.curvefit.family_global]
enabled=1
dpi=300
font_unit=pt
font_size=9
legend_font_unit=px
legend_font_size=10
grid_mode=inherit
background=
```

Resolution order:

```text
[graphics]
 -> [module_graphics.<module-id>] when enabled
    -> per-plot overrides
```

The resolved environment is also written to runtime.ini under `[graphics_effective]` for reproducibility.

## `[print]`

`[print]` contains PDF composition, page layout, export and printer configuration.

## Backward compatibility

v0.6.9 can open v0.6.0/v0.6.1/v0.6.2/v0.6.3/v0.6.4 Manifest Format 2 files. Fixed instrument records from those versions are migrated in memory to `instrument.generic` instances when opened. New manifests are written only with the Instrument Module API structure.

Removed ProvaTelecomando analysis modules do not reappear because their descriptors are not present in the native-only package.


## Per-plot legend editor state

Plots declaring `legend_editor=standard` store the common legend editor state independently from `[module_plot.*]`, because module plot configuration controls semantic content while the common editor controls presentation.

```ini
[plot.legend.overrides]
keys=curvefit.family.overlay

[plot.legend.curvefit.family.overlay]
enabled=1
placement=below
layout=wrapped
alignment=center
location=northeast
columns=4
background=#FFFFFF
border=0
border_color=#808080
font_size=10
external_margin_px=12
manual_x=0.75
manual_y=0.85
```

These values are restored when a session is reopened and are forwarded to both calculation rendering and rerendering.

### Legend placement vs layout (v0.6.9)

Legend geometry is intentionally orthogonal:

- `placement`: `inside`, `above`, `below`, `left`, `right`, `manual`, `none`;
- `layout`: `row`, `stacked`, `wrapped`, `auto`;
- `alignment`: `start`, `center`, `end` for external bands;
- `location`: inside preset only;
- `columns`: used by `wrapped`;
- `manual_x`, `manual_y`: normalized figure-center coordinates used only by `manual`.

For backward compatibility, old `mode` and `orientation` keys are accepted as aliases when the new keys are absent. New manifests write the new fields and may retain aliases only for migration compatibility.


## Native runtime presentation state (v0.6.4)

For a native plot, the runtime generated immediately before calculation or rerender contains the effective plot-specific legend state, for example:

```ini
[legend.curvefit.family.overlay]
enabled=1
placement=below
layout=wrapped
alignment=end
location=northeast
columns=4
background=none
border=0
font_size=9
external_margin_px=17
manual_x=0.40
manual_y=0.25
```

These runtime sections are execution state derived from the current GUI/manifest. They are regenerated for every native rerender; an old `runtime.ini` is never treated as authoritative presentation state.


## Plot annotation references (v0.7.0)

Annotation object payloads do not belong in the INI manifest. Manifest Format 2 stores only references to the UTF-8 JSON documents:

```ini
[plot_annotations]
api_version=1
count=1

[plot_annotation.1]
plot_id=curvefit.family.overlay
plot_path=analysis/curvefit.family_global/01_curve_family_fit.png
file=analysis/curvefit.family_global/annotations/01_curve_family_fit.json
enabled=1
api_version=1
```

The JSON is authoritative and survives a scientific plot rerender. Derived annotated PNGs used for export/print are not configuration state and are not required in the manifest.

## Graph Provider API v1 (v0.7.1)

Modules can declare several graph offerings and the experiment chooses which ones are generated:

```ini
[graph_provider_api]
version=1
model=module-declared graph types; optional persistent plot variants

[module_graphs.curvefit.family_global]
offered=curvefit.family.overlay,curvefit.family.residuals
enabled=curvefit.family.overlay
```

The module-specific graph configuration remains in `[module_plot.<module>.<graph>]`. The framework copies the enabled list into runtime.ini under `[graph_provider]` and dynamically appends enabled graph files to the checked module output contract.

### Global graphics DPI and font units

```ini
[graphics]
analysis_png_dpi=200
plot_font_unit=px
```

`analysis_png_dpi` is the global native-plot raster DPI. `plot_font_unit` may be `px` or `pt`. `plot_legend_font_unit` may be `inherit`, `px` or `pt`; `inherit` follows `plot_font_unit`.

A per-plot legend can override the unit independently:

```ini
[plot.legend.curvefit.family.overlay]
font_unit=pt
font_size=9
```

Blank `font_unit` inherits the global plot unit.

## v0.7.8 descriptor file/path fields

`type=file` and `type=path` are UI/validation semantics only. Their values are persisted through the existing `[module_config.<module-id>]` or graph configuration sections exactly like other descriptor-generated fields. Manifest Format remains version 2.

`model.descriptor_path`, `model.plugin_dir`, `[progress]` and `[job]` are generated **runtime.ini execution state**, not new persistent manifest sections.

## v0.8.1 Scientific Analysis Definition API marker

Manifest Format remains version 2. GX-TXT v0.8.1 adds a backward-compatible capability marker:

```ini
[scientific_analysis_api]
version=1
```

A module's selected analysis definition remains normal module configuration state (for example `analysis_definition_id=...`) and is therefore persisted through the existing module-config sections. Absolute descriptor paths are **not** stored as portable manifest identity; they are resolved again by plugin discovery and written into the generated runtime configuration.

This is intentionally separate from mathematical Model Plugin API state.


## Framework API markers in v0.8.3

Manifest Format 2 remains unchanged in version number. Current manifests advertise additive framework APIs:

```ini
[scientific_analysis_api]
version=1

[render_cache_api]
version=1
```

The Render Cache API marker means the framework provides the optional helper contract; it does **not** imply that every installed module has migrated its historical `render_cache.mat` format. Module opt-in is declared separately in `module.ini` under `[render_cache]`.

## v0.8.4 Documentation API marker

Manifest Format remains version 2 and advertises Documentation API availability/policy:

```ini
[documentation_api]
version=1
policy=required_for_plugins
enforcement=v084_backward_compatible_warning
```

This marker describes framework policy. Individual plugin documentation remains in each plugin descriptor, not copied into the portable session manifest.

## v0.8.4 Analysis Definition parameter persistence

Descriptor-generated Analysis Definition parameter values are persisted additively without changing Manifest Format version:

```ini
[analysis_parameters.<module-id>.<config-key>]
definition_id=my.analysis_v1
target=0.005
method=linear
```

On runtime generation the effective values are emitted to the module's `runtime.ini` as:

```ini
[analysis_parameters]
target=0.005
method=linear
```

Definition IDs, not absolute descriptor paths, remain the portable identity. Absolute paths are rediscovered at runtime.

## v0.8.4 compatibility

Older Format 2 manifests that omit `[documentation_api]` or `analysis_parameters.*` load normally. Defaults from the selected Analysis Definition are used when no persisted parameter override exists.

## v0.9.3.3 scientific plotting additions

The additions are optional and backward compatible:

```ini
[scientific_plot_framework_api]
version=1

[unit_selector_api]
version=1

[graphics_3d]
plot_3d_azimuth=-37.5
plot_3d_elevation=30
plot_3d_projection=orthographic
plot_colormap=viridis
plot_colorbar_visible=0
plot_colorbar_label=
plot_color_unit=auto
plot_color_min=
plot_color_max=

[plot.axis3d.<graph-id>]
z_unit=inherit
z_label=
z_min=
z_max=
z_step=
z_format=inherit
z_scale=inherit
zgrid=inherit
view_azimuth=
view_elevation=
projection=inherit
colormap=inherit
colorbar_visible=inherit
colorbar_label=
color_unit=inherit
color_min=
color_max=
```

The historical plot-axis sections and fields are not removed. The runtime folds these additive fields into the existing `[axis.<graph-id>]` section so renderers receive one final per-graph presentation record.

## GX-TXT 0.9.7.11 plot variants

Opted-in Plot Module graphs add plot_variant_api, plot_variant_counter, plot_variant and plot_variant_region sections. Graph Series entries may carry variant_id; Dataset Selection resources may carry producer_variant and variable IDs. Omitted variant fields retain the base behavior. See [Plot Module API v1](PLOT_MODULE_API_v1.md) for lifecycle and artifact ownership.


## GX-TXT 0.9.7.12 additive fields

Base Standard Module `[module_binding_variable_id.<module>]` entries now
store `source_id|dataset_id|variable_id`. Older two-part entries load
conservatively and are migrated only when unambiguous. A source remap
does not silently change a stored variable identity.

Level Scale API v1 also persists Z in
`[level_scale.<graph_id>.z]`, including variant graph keys; absent Z
sections retain the linear default.

## Graph resources and resource ZIPs (dev-051)

Manifest Format 2 adds `[graph_notes]` / `[graph_notes.N]` and `[graph_metadata]` / `[graph_metadata.N]` resource references with stable provider/Variant or Clone identity and Session-relative files. The Markdown note and namespaced metadata remain authoritative separate resources; annotation object payloads remain in the existing JSON layer. Descriptor fields `supports_annotations`, `annotation_editor`, `annotation_types` and `annotation_coordinate_spaces` declare graph capability; they are not Manifest payloads. CORE public Graph Notes, Graph Metadata and Plot Annotation APIs own writes and lifecycle. Variant duplicate and Clone creation copy resources; deletion cleans them up. Portable Resource ZIP has its own transport manifest and restores these references through the same authority. See [Portable Resource](PORTABLE_RESOURCE_API_v1.md), [Graph Notes](GRAPH_NOTES_API_v1.md), [Graph Metadata](GRAPH_METADATA_API_v1.md) and [Plot Annotation](PLOT_ANNOTATION_API_v1.md).
