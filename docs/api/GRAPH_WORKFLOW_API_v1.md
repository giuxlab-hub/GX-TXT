# Graph Workflow API v1

## dev109 read-only scientific 3D resolution

`::GX::graphWorkflowScientific3DSource reference` separates the exact
`original_reference`, any verified `representation_reference`, owning exporter
and `source_info`. Producer-backed preparations also carry `prepared_source`
and a fingerprint. Compact Plots preview uses this resolver for eligibility,
activation, retained-source checks and preparation. Captions and exported
provenance preserve the selected graph's identity.

Resolution uses the selected producer output's explicit public bridge and
declared geometry contract. It never creates/reconciles a Plot Variant, edits
bindings, reruns a module or infers a mesh from PNG pixels. Missing registration
alone is not a geometry rejection. Canonical Dataset identity, stable Variable
IDs, units, coordinate revision and effective presentation must match the
retained preparation. The existing exporter worker verifies actual MAT geometry.
Positive and negative installed GUI acceptance remains open.

## Scope

Graph Workflow API v1 provides three CORE services around the stable graph
identity: module_id + graph_id + variant_id. variant_id is empty for a base
graph. The API does not create another graph, axis, or variant registry.

## Deterministic public API activation

    ::GX::modulePublicApiIds module_id
    ::GX::modulePublicApiDocumentation module_id api_id
    ::GX::modulePublicApiActivate module_id api_id

A descriptor declares public APIs in [public_apis] and their entrypoints in
[public_api.<id>]. Activation resolves the entrypoint inside the module
directory, sources it once, and caches only successful activation.

`modulePublicApiDocumentation` reads optional provider-owned `public_contract`
data in the existing `[public_api.<id>]` descriptor section. It returns the
validated dictionary or an empty value when the provider has not declared one.
It does not activate source, execute operations, require a Session or change
Script Bridge/restricted C++ authorization.

The schema is `gxtxt.public_api_documentation.v1`, with nonempty `purpose`, an
`operations` dictionary and optional overall `context`. Each logical operation
declares a literal qualified `command`, exact Tcl formal `arguments` (including
optional default pairs), `parameters` keyed by those formal names, a `result`
and its actual `context`. Each parameter has a meaningful `type` and
`description`; result has the same two fields. An optional `example` is trusted
host documentation only. Callbacks and standalone entrypoints must retain their
actual different contexts. This is explicit public-owner metadata, not a scan of
implementation procedures or a new callable registry.

The normal Development API catalogue carries these contracts and the shared
Octave/Python/C++ Browser displays signatures, parameter/result types and context
in its own reference pane. It labels them trusted host documentation; only the
existing Script registration or finite SDK policy establishes those languages'
callability. Missing/invalid documentation is reported without inventing a
signature or invoking the provider. API manuals resolve through the existing
Documentation service to the actual common/provider path.

When writing `public_contract` through an INI descriptor, use the existing
`putKV`/`iniEscape` owner. A nested Tcl dictionary may contain backslashes and
default values; writing an unescaped Tcl serialization changes it when the
normal `parseIni` reader unescapes it. The ordinary dictionary and INI roundtrip
must both preserve the declared contract.

Before Series Editor extension lookup, CORE activates each declared public API
whose capabilities contain series_editor_extension. Activation is
provider-neutral and independent of earlier GUI actions. Repeated lookup and
multiple editor opens do not register duplicate callbacks. A load error remains
retryable and the Series editor shows an explicit unavailable provider area.

## Graph-addressed Axes editor

    ::GX::graphAxisConfigOpen module_id graph_id ?variant_id?
    ::GX::graphAxisConfigSnapshot module_id graph_id ?variant_id?

graphAxisConfigOpen opens the standard CORE Axes dialog for an explicit stable
graph reference. The Plots window and Analysis Configure entrypoints call the
same editor and use the existing axisOverride state. graphAxisConfigSnapshot
returns a read-only dictionary for inspection and tests.

The operation supports base graphs and existing variants. Unknown graph or
variant IDs are errors. X, Y-left, Y-right, Z, grid, display unit, level scale,
view and color controls retain their existing validation and behavior.

The established [plot.axis.overrides] manifest sections persist 2D base and
variant state. Existing 3D axis sections remain additive. There is one CORE axis
authority.

## Stable USE / NON USE

    ::GX::graphUseStateGet module_id graph_id ?variant_id?
    ::GX::graphUseStateSet module_id graph_id variant_id value
    ::GX::scheduledModuleGraphIds module_id

The default is USE for backward compatibility. State is persisted in
[graph_use.*] entries and is projected into the Plots tree after every rebuild,
so row IDs and display order are not identities.

| Control | Meaning |
| --- | --- |
| Graph Provider enabled | The base graph offering is enabled for the module. |
| Plot Variant enabled | The persistent variant is available for execution. |
| USE / NON USE | Whether that stable base graph or variant participates in later graph work. |

For base graphs, the effective runtime set is the intersection of Graph Provider
enabled and USE. For variants, CORE preserves the existing Plot Module rule: the variant is
independent from the base Graph Provider enabled flag and is scheduled when
Plot Variant enabled and USE are both true.

The standard runtime [graph_provider] section exposes provider_enabled,
use_enabled, effective_enabled, and enabled. enabled remains the
backward-compatible renderer input and equals effective_enabled. A NON USE base
graph is removed before renderer graph preparation and is not an expected graph
artifact. A NON USE variant is removed before plotVariantCommand, so its dataset
scan, series preparation, provider preparation, rendering, and artifact
regeneration are not started.

## Public Session plot deletion

`::GX::graphLifecycleDelete path` is the public CORE lifecycle entry point
used by the Plots page. It accepts an existing Session-owned PNG under the
current Session's `analysis/` tree and returns `1` after deletion. It requires
an open Session and rejects missing files, paths outside that tree, and
non-PNG paths. The path identifies the exact artifact; a graph ID alone is
not a deletion request. A recognized Clone or Variant must also pass its
own ownership checks; deletion of a symlinked Clone or Variant directory is
rejected.

- A recognized detached Clone is removed with its owned Clone directory,
  including its rendered and captured presentation files. Its source plot
  remains intact.
- A Plot Dataset Variant is deleted through public
  `::GX::PlotDatasetAPIv3::deletePlot`. This removes its PlotSpec and, via the
  normal Plot Variant lifecycle, its Graph Series, configuration, axis,
  legend, level-scale, region/USE state, and owned render directory.
- Another provider's Plot Variant is deleted through the public Plot Module
  Variant lifecycle, which clears that Variant's persistent state and owned
  render directory.
- A recognized descriptor-backed base graph cannot be deleted as a graph
  offering. The operation disables it, clears its owned axis/legend/level,
  region and USE state, and removes the selected PNG and its annotation and
  plot-metadata sidecars. For a Plot Dataset base graph it also removes the
  persisted PlotSpec and that base graph's Graph Series. An unrecognized
  Session PNG has only its PNG and matching sidecars removed.

Scientific Datasets shared by plots and registered scripts are preserved.
Artifact files are removed immediately. Graph and Variant state changes are
made in the current Session and enter the saved Manifest when the Session is
saved; `graphLifecycleDelete` itself does not write `manifest.ini`. After that
save, reopening the Session does not restore the deleted Variant or enabled
base graph. `graphLifecycleDelete` is host-only in Script Bridge coverage:
the Bridge does not register this path-based filesystem deletion operation.

## Graph configuration extensions

Graph Workflow API v1 now hosts the public [Graph Configuration Extension API v1](GRAPH_CONFIG_EXTENSION_API_v1.md). A module public API advertising `graph_config_extension` is activated before lookup; its provider-owned controls are appended to the normal base Graph configuration window and to the Variant editor Plot tab with the exact graph/variant identity. Generic graph fields remain CORE-owned.

## Script Bridge operations

The Bridge exposes state for stable module/graph/Variant identities. Empty or omitted `variant_id` addresses the base graph where the Tcl API permits it. `use_set` requires an explicit `variant_id`, including the empty string for the base. USE state persists in the Session Manifest and affects later scheduled work. Both Octave/MATLAB and Python call these names through `gxtxt_api_call(API_ID, operation, arguments)`. Arguments are positional and are passed to the named public Tcl procedure.

| Script operation | Public Tcl mapping | Positional arguments | Result |
| --- | --- | --- | --- |
| `axis_snapshot` | `::GX::graphAxisConfigSnapshot` | `module_id`, `graph_id`, `variant_id` (optional) | axis struct |
| `use_get` | `::GX::graphUseStateGet` | `module_id`, `graph_id`, `variant_id` (optional) | integer `0` or `1` |
| `use_set` | `::GX::graphUseStateSet` | `module_id`, `graph_id`, `variant_id`, `value` | integer `0` or `1` |
| `scheduled_graph_ids` | `::GX::scheduledModuleGraphIds` | `module_id` | cell of IDs |

`graphAxisConfigOpen` opens the GUI and remains host-only. The path-based
`graphLifecycleDelete` is also host-only; scripts can use the separately
registered Plot Dataset v3 `delete_plot` operation for a Plot Dataset Variant.
Nested Tcl dictionaries and lists returned by these registered state calls
are normalized for script clients.

## Public aspect and background mutation

`::GX::graphAxisPresentationSet module_id graph_id variant_id changes` validates all changes before changing the existing CORE Axes authority. Allowed fields are `xy_aspect_mode` (`inherit`, `auto`, `xy_equal`), 3-D `aspect_mode` (`inherit`, `auto`, `xy_equal`, `data_equal`, `manual`), `aspect_ratio` (three positive values for manual), and `background` (`inherit`, `#RRGGBB`, `transparent`). Empty values mean inheritance. This does not change camera/view or scientific values. Invalid identities, ratios, colors and unsupported fields fail without partial mutation.

Both Octave/Python Script Bridge expose `presentation_set`, `axis_snapshot`, `use_get`, `use_set` and `scheduled_graph_ids`; require `GRAPH_WORKFLOW_API_v1@1:graph_workflow`. Example:

```python
gxtxt_api_call('GRAPH_WORKFLOW_API_v1', 'presentation_set',
               ['plot.dataset', 'plot.dataset.xy', '',
                {'xy_aspect_mode': 'xy_equal', 'background': 'transparent'}])
```

The GUI Axes dialog accepts `transparent` beside inherited/opaque backgrounds. Static 2-D/3-D Octave rendering writes real RGBA PNG alpha through GNUplot pngcairo at the requested pixel dimensions; axes/figure margins are transparent. Explicitly filled objects can remain opaque. Annotation composition, full-size viewer, Save image, clipboard image and HTML use the same alpha-bearing PNG. This changes the shared static PNG path; it does not claim transparent native interactive 3-D scenes. Effective background/aspect appear in plot metadata and persist through Session save/reopen.

## Public API activation lifetime

The existing `modulePublicApiActivated` cache describes commands installed in
the Tcl interpreter. Defaults, configuration loading and Session changes reset
Session state while preserving this cache. Clearing it cannot unload commands;
re-sourcing established wrapper APIs causes duplicate rename targets. Activation
continues to use declared module entrypoints and trusted module execution scope.
This is an internal lifecycle correction to the existing host/admin loader, not
a new Script Bridge operation or a hot-reload mechanism.

## Declared native rendering owner

Native Plot Dataset graphs use existing Graph Metadata to declare their renderer. Existing Plots controls retain the same stable Graph/Variant identity and configuration authorities. CORE projects global, enabled module, Variant, Axes, Legend and layout settings into an ephemeral effective native PlotSpec; it does not rewrite canonical source data or the saved PlotSpec. Rerender uses the existing Analysis queue and a captured Session worker invoking public Plot Dataset API v4. Historical unmarked graphs keep their established routing. Unknown owner markers are errors, never silent fallback.

The same owner dispatch supplies exact source-row point indices for the existing Select data dialog. Distribution aggregates remain ineligible for individual source-point selection. Host queue construction and effective configuration projection are host adapters, while reusable scientific rendering and capture operations are exposed by Plot Dataset API v4 and its Script Bridge.
