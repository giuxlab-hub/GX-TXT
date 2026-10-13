# Standard Module API v1 — native profile used by GX-TXT Pipeline v0.6.1

## Central and local Configuration contributions (dev094)

Every installed descriptor participates in CORE Configuration discovery, including
disabled, nonselectable, CORE and ALWAYS modules. `[config] fields=...` and
`[config.<key>]` remain the existing Session module configuration authority.
`persistent_default=1` explicitly adds a saved User-default scope. Session-only
fields remain configurable without silently manufacturing global preferences.

Optional field metadata: `configuration_id` for a stable legacy registry ID,
`application=immediate|next_invocation|restart`, constraints/help/visibility/read-only
policy, typed choices, and module-owned validator/structured-field callbacks.
`[configuration] entrypoint=api/settings.tcl` sources only a safe lightweight
schema contribution inside the installed module root, never its scientific Viewer.
Formally registered fields carry stable `module_id` and `module_key`; they also
participate in existing Manifest save/load, even if registered after GUI startup.

Both settings surfaces consume the public
[Configuration API contract](CONFIGURATION_API_v1.md). See the installable
[`module_configuration` example](../examples/module_configuration/README.md)
for typed User defaults, Session inheritance and a repeatable table without CORE
or global GUI edits. Catalog loading notifies existing projections; discovery
alone does not enable/reset modules or import scientific runtime data.

GPL-3.0-or-later

## Rule

A module is available only if it has a descriptor at:

```text
plugins/modules/<stable-id>/module.ini
```

v0.6.1 does not use compatibility descriptors. A module without a conforming descriptor is not discovered, shown in the GUI, saved as enabled, or placed in a queue.

## Required descriptor structure

```ini
[meta]
api_version=1
id=curvefit.family_global
kind=analysis
name=Curve Family Fitting
version=1
runner=standard_octave
selectable=1
default_enabled=0

[inputs]
contracts=curve_family.table

[outputs]
files=fit_parameters.csv;fit_summary.txt;fit_predictions.csv;render_cache.mat;01_curve_family_fit.png

[graphs]
ids=curvefit.family.overlay

[config]
fields=dataset_id;model_id;solver

[config.dataset_id]
type=dataset
label=Input dataset
default=curve_family.primary
required=1
```

Supported configuration widget types currently include `string`, `integer`, `double`, `choice`, `boolean`, `dataset`, `model`, `file`, `path`, and `analysis_definition`.

`analysis_definition` is the v0.8.1 selector for Scientific Analysis Definition API v1 resources. It is separate from `model`: mathematical models remain mathematical resources, while analysis definitions describe reusable data-flow through framework operations.

## Acquisition modules

Acquisition modules use `kind=acquisition`, `runner=standard_tcl`, and declare a native handler:

```ini
[runner]
handler=generic_csv
```

or:

```ini
[runner]
handler=rigol_csv
```

The acquisition module receives configuration from its descriptor. The Rigol module may reuse the proven Octave CSV worker internally, but legacy GX-TXT experiment fields are not part of its public contract.

## Analysis modules and bindings

An analysis module declares what it needs by semantic input role, not by hard-coded source column position:

```ini
[bindings]
roles=x;family;y

[binding.x]
label=Independent X
required=1
preferred_model_field=x_column
semantic_role=independent
```

Resolution order is:

1. explicit user binding in the manifest/GUI;
2. preferred variable declared by the selected mathematical model;
3. a canonical variable carrying the requested semantic role;
4. failure if the role is required and cannot be resolved.

The analysis module therefore knows **what role it needs**, while the framework decides **which dataset variable supplies it**.

## Runner contract

`standard_octave` receives a generated `runtime.ini`, containing:

- module ID;
- session and output directory;
- dataset ID/path/contract/columns;
- selected model;
- resolved variable bindings;
- module configuration.

New analysis modules must not require edits to `buildAnalysisQueue`. The queue is generated from enabled/runnable descriptors.


## Output contract enforcement (v0.6.1)

For `standard_octave`, `[outputs] files=` is executable contract data, not documentation only. The standard wrapper runs Octave and then verifies that every declared relative output file exists. A non-zero Octave status or a missing required output makes the module run fail. This prevents a generated `runtime.ini` from being mistaken for a completed analysis.

Module-specific environment variables must not be injected globally. The standard queue exports only generic graphics/runtime settings; settings belonging to a module must travel through its descriptor-generated `runtime.ini`.

## v0.6.2: module-owned plot configuration

Analysis modules may declare one or more graphs in `[graphs]` and describe each graph through `[graph.<plot-id>]` plus `[graph.<plot-id>.config.<key>]` sections. The GUI builds the module plot controls from those sections, persists them as `[module_plot.<module-id>.<plot-id>]`, and copies them into the runtime INI as `[plot.<plot-id>]`.

This keeps plot semantics inside the module contract. The core only supplies generic graphics, artifact/rerender and print infrastructure. See `PLOT_MODULE_API_v1.md`.

Instrument metadata uses a separate schema because an instrument is an experiment resource, not an acquisition or analysis job. See `INSTRUMENT_MODULE_API_v1.md`.


## v0.6.3: standard legend editor capability

Native plot descriptors may declare `supports_legend=1` and `legend_editor=standard`. The core resolves the plot graph ID from the module descriptor and enables the shared legend editor without hard-coded knowledge of the module or PNG filename. A renderer declaring this capability must use `gxtxt_plot_legend(...)`; direct calls to Octave `legend(...)` are not conformant because they bypass saved overrides.


## v0.6.4: current presentation state on rerender

A native module with descriptor-defined plots must not assume that the `runtime.ini` created during the numerical analysis is still current. The framework regenerates the runtime before each rerender. Per-graph legend settings are exported as `[legend.<graph-id>]` sections. A native renderer using the standard legend editor passes its parsed runtime configuration to `gxtxt_plot_legend(..., graph_id, runtime_cfg)`. This makes the module runtime the authoritative path while retaining the historical TSV environment override as a fallback.


## Plot annotations

Plot annotation support is a plot capability, not an analysis-module special case. A graph descriptor may opt into `supports_annotations=1` and `annotation_editor=standard`. The module does not parse annotation JSON and does not alter its base PNG. See `PLOT_ANNOTATION_API_v1.md`.

## Graph providers

A Standard Module API analysis module may implement Graph Provider API v1. The module descriptor declares the plot types it can offer; the core handles experiment selection, Manifest Format 2 state, runtime delivery and output-contract checking. The scientific renderer decides how each enabled graph is calculated from the module's results/cache.

See `GRAPH_PROVIDER_API_v1.md` and `PLOT_MODULE_API_v1.md`.


## Graph Provider API

An analysis module may expose arbitrary stable graph IDs through `[graphs]` and `[graph.<id>]`. The graph list is module-owned; the framework discovers it and provides selection, descriptor-generated configuration, manifest persistence, runtime delivery, output validation, legend/annotation services and plot discovery. See `GRAPH_PROVIDER_API_v1.md`.

A module does not require a core Tcl change to add another graph.


## Common graphics inheritance

Common presentation is intentionally separate from module-specific scientific configuration. Effective values resolve as:

```text
Global graphics -> optional module graphics override -> plot-specific override
```

This preserves a homogeneous publication style across modules by default. A module-specific override is opt-in and individual blank/inherit fields keep the global value.

## v0.7.8: full model-plugin location

For a selected mathematical model, `runtime.ini` now publishes `model.descriptor_path` and `model.plugin_dir` in addition to the existing model function/script/parameter metadata. A consumer may inspect additional sections in the model descriptor itself. The core does not interpret optional model-specific capability sections.

## v0.7.8: descriptor-driven file/path fields

Module and graph configuration may use `type=file` or `type=path`. The common GUI creates an Entry + `Browse...` control. Optional metadata:

```ini
must_exist=1
extensions=.csv;.txt
path_kind=file|directory
dialog_title=Choose file
```

`type=string` remains unchanged. Path existence is validated before standard runtime generation when `must_exist=1`.

## v0.7.8: shared scientific-support helpers

Plugin authors should use `gxtxt_read_parameter_set` / `gxtxt_validate_parameter_set` for `parameter,value` files and `gxtxt_read_model_domain` / `gxtxt_validate_model_domain` / `gxtxt_classify_model_domain` for convex-hull model domains. See `PARAMETER_SET_API_v1.md` and `MODEL_DOMAIN_API_v1.md`.

## v0.7.8: Plugin Progress API v1

Long-running plugins may use the public, optional Progress API. `standard_octave` jobs receive framework-owned module/run identity and may call the `gxtxt_progress_*` helpers. The core consumes the reserved structured protocol separately from ordinary logging and renders determinate/indeterminate status without blocking Tk. See `PROGRESS_API_v1.md`.


## v0.8.1: Scientific Analysis Definition API v1

Modules may select a global or module-local analysis definition with `type=analysis_definition`. Optional descriptor filters are `scope=all|global|local`, `kind=...`, and `capabilities=...`. The standard runtime publishes the selected definition ID, descriptor path, plugin directory, scope and capabilities. See `SCIENTIFIC_ANALYSIS_DEFINITION_API_v1.md`.

## v0.8.2+: framework-owned final Axes/Grid application

Native renderers use the shared graphics APIs and export through `gxtxt_print_png_atomic(...)`. The common PNG finalizer resolves the Graph Provider ID and applies final per-plot/per-panel Axes/Grid overrides centrally. `gxtxt_plot_apply_graph_axes(...)` remains a supported helper/compatibility API, but a plugin does not need a graph-specific workaround merely to receive GUI Grid/Axes state. Legend handling remains independent through `gxtxt_plot_legend(...)`.

## v0.8.3: Scientific Analysis binding bridge

Scientific Analysis Definition variables may use `binding=<role>` to resolve a Standard Module API binding from runtime `[bindings]`. Optional variables use `required=0`. This is the supported bridge between module semantic roles and declarative analysis variables; modules should not create a second column-mapping mechanism. See `SCIENTIFIC_ANALYSIS_DEFINITION_API_v1.md`.

## v0.8.3: optional Render Cache API v1

A module may declare:

```ini
[render_cache]
api_version=1
rerender_from_cache=1
```

The standard runtime then exposes `[render_cache_api]` with API version, standard `render_cache.mat` path and rerender capability. This is additive: modules that omit the section keep their historical module-owned cache format and loader. See `RENDER_CACHE_API_v1.md`.

## v0.8.4: Documentation API v1 is mandatory for plugin authors

New or updated plugins MUST declare a `[documentation]` section conforming to `DOCUMENTATION_API_v1.md`. GX-TXT v0.8.4 keeps older descriptors without the section loadable with `legacy_missing` status for backward compatibility. Plugin authors must not rely on that exception; future releases may silently enforce documentation conformance during normal discovery/execution.

Minimal module declaration:

```ini
[documentation]
api_version=1
guide=README.md
api_refs=MODULE_API_v1
examples=
changelog=
```

## v0.8.4: descriptor-driven Analysis parameters and preflight

A `type=analysis_definition` configuration field automatically gains framework-owned `Parameters...` and `Preflight...` actions. Parameters are declared in the selected Analysis Definition, persisted through Manifest Format 2, and emitted as runtime `[analysis_parameters]`. Modules MUST NOT create a private Tcl parameter editor for the same contract.

Preflight uses module bindings/contracts and Analysis Definition metadata without performing scientific calculations. Octave execution also validates the definition.

## v0.8.4: Scientific Analysis operation expansion

`SCIENTIFIC_ANALYSIS_DEFINITION_API_v1.md` now documents explicit non-row-aligned alignment/join/resample, interpolation, feature extraction, correlation/regression/model fitting bridge, unit conversion, and strict dimensional expressions. Standard Module API version remains 1 because these are additive framework capabilities.

## v0.8.4: standard Render Cache provenance

Opt-in modules may use the new Render Cache API v1 provenance constructors and `gxtxt_render_cache_from_analysis()` instead of manually copying a normal `gxtxt_analysis_run()` result. Legacy module-owned cache formats remain valid.

## v0.8.5: N-source dataset map for analysis modules

Standard Module API v1 now supports an additive multi-source dataset map for analysis modules. A module opts in with `[analysis_sources]`; existing single-`dataset_id` modules are unchanged.

Minimal descriptor:

```ini
[analysis_sources]
api_version=1
ids=primary
dynamic=1

[analysis_source.primary]
required=1
contracts=curve_family.table
```

The framework owns the Analysis-panel Add/Remove source table, resolves Dataset API IDs to runtime paths, persists the map in Manifest Format 2, and emits `[analysis_sources]` / `[analysis_source.<id>]` runtime sections.

Bindings may use `source.variable`:

```text
x=primary.Vg1_V
sigma_y=uncertainty.sigma_total
```

An unqualified legacy binding remains valid and means `primary.<variable>`.

The source-map layer performs no scientific alignment. Use Scientific Analysis Definition operations such as `align`, `join`, `resample`, or `interpolate` explicitly.

Normative reference: `ANALYSIS_SOURCE_MAP_API_v1.md`.

## v0.8.8: Dataset Publication API v1

A Standard Module API analysis module that creates a reusable dataset must request framework publication instead of modifying `metadata/datasets.ini`. Runtime `[dataset_publication_api]` exposes the publication request directory. The framework validates successful module output, computes SHA-256, enforces dataset ownership, registers metadata, saves the Dataset Registry, and refreshes dataset-aware GUI controls. See `DATASET_PUBLICATION_API_v1.md`.

Working-directory profiles introduced in v0.8.8 are application/user state, not module descriptor state. See `WORKING_DIRECTORY_PROFILES_API_v1.md`.

---

## v0.8.9 addendum — pluggable `standard_tcl` acquisition handlers

GX-TXT v0.8.9 adds **Acquisition Handler Plugin API v1**. `kind=acquisition`, `runner=standard_tcl` modules are no longer restricted to the historical `generic_csv` and `rigol_csv` algorithms.

New acquisition formats MUST declare a plug-in handler through `[acquisition_handler]`; they MUST NOT add format-specific branches to the core dispatcher.

See:

```text
docs/api/ACQUISITION_HANDLER_PLUGIN_API_v1.md
docs/guides/WRITING_ACQUISITION_PLUGIN.md
```

The framework retains ownership of session lifecycle, RAW provenance, SHA-256, Dataset Registry and common Preview/Variables integration. The plug-in owns only format recognition/parsing/metadata/canonicalization.

## v0.9.5 host-independence requirement for official plugins

CORE and official scientific plugins MUST remain independent of the Tcl/Tk desktop host. Production plugin code must use public GX-TXT descriptors/runtime/APIs rather than direct Tk widgets, GUI callbacks or `gxtxt_pipeline.tcl` internals. Tcl is allowed for host-independent handlers. See `PLUGIN_HOST_INDEPENDENCE_RULE_v1.md` and `tools/check_plugin_host_independence.py`.

## Dependency public APIs in `standard_octave` runtime configuration

For a Standard Module that declares dependencies through `meta.depends`, GX-TXT exposes each dependency's declared public APIs in the generated `runtime.ini`.

For example, a module declaring:

```ini
[meta]
depends=math.numeric
```

receives a section equivalent to:

```ini
[public_api.NUMERIC_API_v1]
module_id=math.numeric
module_version=...
api_version=1
capabilities=...
octave_entrypoint=/absolute/framework-resolved/path/gxtxt_numeric_v1.m
octave_function=gxtxt_numeric_v1
```

Consumers must use these runtime fields for dependency API discovery rather than reconstructing paths such as `plugins/modules/<dependency>`. The framework validates that advertised entrypoints remain inside the dependency module and exist before writing them. Duplicate API IDs across declared dependencies are rejected as ambiguous.

This runtime metadata is discovery information. The dependency's own descriptor remains authoritative, and the consumer should still validate the API version and every capability it requires.

## Framework-owned graph resources (dev-051)

CORE registers GRAPH_NOTES_API_v1, GRAPH_METADATA_API_v1, PORTABLE_RESOURCE_API_v1 and the operational PLOT_ANNOTATION_API_v1; plugins consume these services without declaring themselves providers. A graph opts into annotations in `[graph.<id>]` with `supports_annotations=1`, `annotation_editor=standard`, `annotation_types=text;line;arrow;rectangle;ellipse`, `annotation_coordinate_spaces=figure_norm`. Public CRUD validates that declaration. Notes/metadata and presentation use stable graph/Variant identity; Manifest Format 2 stores resource references. See the dedicated API contracts and consolidated inventory. Filesystem resource import/export is host-only, while safe graph-resource operations are registered for Python and Octave.

## Optional Experiment duplication declaration

A module may add `[experiment_duplication] api_version=1` and exact provider/schema
preparation declarations, independently of Module API v1 installation and execution.
See [Experiment Duplication Policy API v1](EXPERIMENT_DUPLICATION_POLICY_API_v1.md)
and the [Experiment Duplication Policy API](EXPERIMENT_DUPLICATION_POLICY_API_v1.md).
Capability discovery is available headlessly and through Python/Octave. Missing or
invalid declarations never make a module defective: Duplicate Experiment uses disabled
selectable-module defaults, cleared Run/input bindings, and documented optional-state
omission. Numerical algorithms, Dataset/Workspace/Graph publication and normal execution
remain under their existing contracts. No plugin filesystem cloning callback is needed.

## Experiment Duplication Policy authoring (dev080)

New or substantially updated GX-TXT modules MUST declare an Experiment Duplication Policy using the public CORE contract when they introduce module-owned Session-persistent state. Modules with no additional privately owned persistent state SHOULD use the minimal explicit empty policy supported by the API.

This MUST is an authoring requirement, not an installation or execution gate. Existing and third-party modules without a policy remain installable and runnable. Their custom configuration may be completely reset in a duplicate; safe omission and fresh configuration are intentional outcomes.

```ini
[experiment_duplication]
api_version=1
```

The minimal policy authorizes no custom configuration copies. Only explicitly classified, independently reusable preparation is eligible. CORE controls mandatory Dataset, Workspace, graph, observation, output and cache exclusions, validates dependencies/ownership and handles transactions. Existing Dataset, Metadata, Publication, Provenance, Script Registry, Interactive Document and Managed Resource APIs remain authoritative. Standard registries provide coarse legacy ownership; arbitrary private keys, filenames and source code are not classification authorities.

Do not implement private filesystem copying or ask CORE to recognize a module by name. Use capability/version discovery and the public `EXPERIMENT_DUPLICATION_POLICY_API_v1` validation contract. Generic scientific field types and declared bindings are excluded even when named `input`. Unlisted configuration resets; selectors and paths start empty. Module execution is explicitly reconfigured on fresh data.

See [Experiment Duplication Policy API](EXPERIMENT_DUPLICATION_POLICY_API_v1.md) and runnable `examples/experiment_duplication_policy/` Python/Octave Builder projects. Builder 1.2.0 uses the same flat descriptor policy contract, preserves schema-version-1 A/B/W project fields and unchanged script bytes, and supplies a minimal policy on rebuild. Old generated ZIPs remain valid without rebuilding.

## dev089 Acquisition activation policy

`moduleIsAlwaysAvailable id` derives ALWAYS from descriptor `kind=acquisition`
or existing `selectable=0`. `moduleIsEnabled` and the owning implementation of
`moduleSetEnabled` use that policy. All installed acquisition providers are
invocable without Analysis membership; this does not change `core`, package
ownership, version, source or prerequisite checks. CORE / ALWAYS combines
ownership with activation; external providers show ALWAYS. Selectable Analysis
modules retain their existing explicit flags and dependency rules. No additional
activation registry or scientific Script Bridge operation is introduced.
