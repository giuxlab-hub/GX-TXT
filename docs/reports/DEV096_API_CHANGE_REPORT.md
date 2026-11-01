# dev096 CORE ownership and compatibility report

SPDX-License-Identifier: GPL-3.0-or-later

This report describes the integrated candidate, based on the accepted dev095
archive SHA-256 `95e93f9b5f69238205a269ec764facb1bef13e336c9ca4819925ae11bae5e3fe`.
Release acceptance and archive publication are tracked separately. Additions use
the existing public authorities below; they do not introduce a parallel Dataset
reader, numerical solver, renderer, Workspace registry or History persistence.

| Required capability / demonstrated gap | Existing authority and additive implementation | Compatibility and reason for public reuse |
| --- | --- | --- |
| Commands and scoped shortcuts were tied to a particular Viewer rather than reusable module contributions | `CONFIGURATION_API_v1`, `configuration_viewer_commands.tcl`: catalog registration, validation/typed fields, window attach/detach, enablement/invocation, key dispatch and live menu accelerators | Module IDs/command IDs are data. The synthetic unknown Viewer proves there is no plugin-name branch. Same User/Session transactions and central/local editor; existing Workbench command identities and saved overrides are preserved. A common service avoids divergent key/conflict rules in each plugin. |
| Fitter and read-only Curve Viewer need meaningful reversible state, without copying CAD snapshots | `SCIENTIFIC_RECIPE_API_v1`, `scientific_recipe_history.tcl`: pure state/append/navigation/branch functions and host callbacks for capture/restore/commit/guard; shared browse/clear/strip/details projection | Uses existing inert Recipe patches, registered host validation, Interactive Document persistence and managed resources. Complete retention keeps the existing 4096-step/8 MiB limits. Failed commits restore previous live state. Built-in Fitter inline residuals and Dataset-backed residual resources use their original host representations. External publications are never deleted by Undo. |
| Titles could remain stale after lifecycle operations or external rename | `SESSION_WORKSPACE_API_v1`, `session_workspace_viewer_gui.tcl`: subscribed title adapter, shared lifecycle menu/action/name form | Name comes from the existing authoritative Workspace ID; refresh does not write a new name store. Draft/none/Session-token cases are explicit. Close unregisters the window. Cancel is a normal Tcl return, not an empty error dialog. |
| Legend text cannot identify one of several identically labeled curves | `NATIVE_2D` presentation host: stable object tags and `native2DLegendHit` | Hit resolution returns logical/native identity independently of label text. Existing native geometry and rendering remain authoritative; context actions mutate presentation only. |
| A saved Viewer previously had to repeat expensive display preparation | `CURVE_SOURCE_API_v1`: `curveSourceDisplayCacheStore/Restore`, existing content-addressed managed-resource authority and native buffer loading | Cache is an optional bounded float64 display resource, validated against owner/namespace/generation, schema/source SHA and exact request. Missing/invalid data rebuilds through existing cancellable Curve Source jobs. Scientific publication opens canonical rows. No cache value becomes scientific input. |
| Complete contextual Dataset section export needed a shared canonical document | `SESSION_INSPECTION_API_v1`: `datasetInspectionSectionDocument`; existing Notes, ordinary Metadata, schema and Temporal owners; `FILE_PUBLICATION_API_v1` external text/PDF publication | Ordinary Metadata comes exclusively from the ordinary Metadata authority; registry provenance has an explicit technical section. Draft source is explicit and does not write back. Existing registered export-directory role is reused. No second metadata parser/store or private publication path. |
| Builder graph scope needs exact selected row identity while retaining genuine Family/Member partitions | `GRAPH_SERIES_API_v1` and existing Plot Dataset PlotSpec facade: additive selected-row ordinals and row continuity on series | Existing calls/specs without the optional selection fields preserve their behavior. CORE expands real observed grouping keys and retains breaks/row lineage. Builder chooses Full/Selected independently of numerical input. The optional fields belong to authorized Builder work, not the HDF5 fix. |
| Optional reversible positive translation should work independently of model selection | Bundled CORE `math.numeric`, existing `NUMERIC_API_v1`: `positive_translation`; Fitter applies mapping around existing solvers | Existing public fit calls that omit new options retain zero-offset behavior. UI defaults are Auto; manual/off are explicit. Forward/inverse mapping, original/transformed bounds, physical axes/units and coefficient space are retained. Inverse is applied once before retained/output geometry; accepted historical curves are not refitted. |
| Optional point-order proposal must be reusable geometry work rather than a private Builder fitter | Bundled CORE `NUMERIC_API_v1`: `point_sequence_order` | Finite 2..4096 XY/XYZ points, stable monotone or guarded nearest-neighbor proposal, zero-based permutation/inverse, unchanged point values, ambiguity/gap/crossing diagnostics. Algorithm v2 retains an explicitly repeated closing endpoint when starting at ordinal zero. It does not close an open path or infer physical ground truth. This new operation has an Octave/typed-host binding; no new direct Python binding is claimed. |
| Builder needs an optional saved context while remaining simple | Existing Session Workspace/Interactive Document provider `curve_builder`, schema `gxtxt.interactive_curve_builder.context` 1.0 | No compulsory document on ordinary launch. Saves exact Dataset/Variable/row identities, source/schema fingerprints, method/options and selected rows. Restore validates sources; stale writes are guarded. No History fields/adapter/UI are accepted. |
| HDF5 3D was incorrectly opened by CSV-only file APIs | Existing Table Stream v3, consumed by Plot Dataset's existing 3D preparation owners | Uses Session, Dataset and canonical Variable IDs, row-based progress and `unwind_protect` cleanup. Preserves public PlotSpec/render/Variant contracts. Family formatting retains streamed int64 grouping identity. No new reader, CSV conversion, Script Job change or unrelated plot-module modification. See dedicated ISSUE-021 report. |
| Dense menu rows and nested scroll controls need shared layout behavior | Existing UI Field/Menu/Native2D viewport owners; `uiMenuRowAttach` and host clipping ancestry corrections | Native overflow delegates the original menu/button command and retains final Workspace menus. Builder retains both middle-row menus. Configuration remains the same typed schema. Scientific state is independent of visibility, fonts and clipping. |

## Persistence and failure behavior

History belongs to the existing Workspace document and its resource graph.
Portable export/import remaps managed ownership through existing CORE operations.
The original complete History remains intact on rejected edits and failed writes.
Tests exercise real read-only directory failure, bounded-History rejection, exact
rollback, branch cancellation and subsequent deliberate Clear History/Undo/Redo.

Curve Viewer remains read-only with respect to canonical science. Fitter's
selection invalidates a Preview only when selected points are the training scope;
all-source fitting is not invalidated by presentation selection. The source
table reports the exact finite population instead of the reduced display count.
In-flight cancellation keeps the Sources Cancel menu accessible while other
commands remain guarded. Closing a Fitter from a different Session releases
its live handles without saving or collecting resources in the wrong Session.

Builder OFF behavior was compared directly with an immutable dev095 process for
all seven 2D methods and both existing 3D parameter modes. ON never permutes
temporal observations or crosses selected Family/Member identities. Publication
keeps original and chosen row mappings, algorithm version, warnings and source
fingerprints in the normal Dataset metadata authority.

Public manuals are updated under `docs/api/` and the contributing modules.
The Script Bridge inventory describes the new registered host operations using
the existing dispatcher; it does not advertise unavailable language bindings.
Original public API version IDs remain stable; module/release implementation
versions are listed below; public API family/version IDs remain compatible.

## Evidence and limits of this report

Final overlay checks also required serializing `source_row_ordinals` through the
existing CORE Plot Variant runtime writer and retaining `source_row_continuity`
in the PlotSpec presentation whitelist. The selected disjoint rows now reach the
actual renderer exactly; Full/Selected display still does not change fit inputs.
Native Builder publication checks compare every cached XY coordinate and row ID.

The existing Plot Dataset 3D facade now delegates directly to its existing render
authority: its redundant temporary primary-Dataset override conflicted with base
template bindings when opening a newly published Dataset. CORE Variant runtime
projection already owns that selection. Removing the duplicate override preserves
the base bindings and public PlotSpec contract; no unrelated plot provider changed.

Prepared versions are framework `0.9.8.10-dev-096`, bundled `math.numeric 1.17.0`,
`plot.dataset 3.14.0`, `viewer.curve_viewer 0.3.0`,
`viewer.curve_workbench 2.15.2`, `viewer.dataset_curve_fit 0.5.0` and
`viewer.interactive_curve_builder 1.1.0`. Five external package descriptors require
dev096. Bundled math.numeric remains part of CORE.

The issue ledger, progress report, numerical receipts and GUI logs distinguish
executed checks from pending final-package verification. Native C compatibility,
Script Bridge/Supervisor, Configuration, constrained Workbench History, exact
publication and legacy Fitter checks have recorded development results.

The accepted 536-row `built_curve` and completed Sylvania evidence meet the user's
clarified fixture requirement. A separately named Eridiana identity is not
claimed. No original Dataset, Workspace, historic Job or prior release was
intentionally modified. Final source/archive inventories must be verified again
before publishing the integrated release and removing completed TODO entries.


Large exact source traces: the existing Plot Dataset preparation paths now
resolve `source_row_continuity` to unreduced data. Sampling gaps must not be
misidentified as physical disconnections. The ordinary and filtered-batch paths
agree; the incompatible grouped reduction optimization is bypassed for that
explicit option. Other series keep their existing reduction behavior. The cache
fingerprint already includes the resolved reduction policy, so old reduced data
are not reused for the exact request. Builder Full/Selected backend caches verify
all 12287/8191 finite ordinals and coordinates in the large/gap regression.

Builder's existing error presenter ignores a disposed window after cooperative
source cancellation. Native Restart and window-close tests verify no partial
source rows, stale preview, or unclosed Table Stream. No new cancellation owner
or background job implementation was introduced.
