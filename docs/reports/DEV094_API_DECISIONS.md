# dev094 authority and API gap decisions

SPDX-License-Identifier: GPL-3.0-or-later

Verified baseline: official dev093 archive/restore/expanded/installation, 5861
files. Development uses a separate Git worktree. No new authority is justified.

| Requirement | Source-verified authority / gap | Decision |
|---|---|---|
| Exact families and filters | Scientific Dataset Filters already discover typed values and build Curve Source predicates; Curve Source streams exact rows separately from display | Reuse; add generic manual dimension binding only if necessary |
| Scientific publication | Dataset Transform supports predicate/project plans; Publication v2 provides atomic create-only commits in dev093 | Reuse in an independent extension module |
| Named viewer Workspaces | Session Workspace wraps existing Interactive Documents; viewers currently pick the first document | Register lightweight module-owned providers and make viewer opening explicit-ID; reuse lifecycle |
| History reset | Scientific Recipe Append protects complete retention but offers no explicit reset | Add owner-neutral validated rebase to the same API; Workbench captures state and commits through existing document/recovery services |
| Central/local configuration | Configuration registry supports only global values; Module owns Session moduleCfg; descriptor persistent fields alone are exposed; no draft conflict contract | Extend Configuration API with module schema discovery, scope resolution, validation, compare-before-commit transactions and generic editor adapters. Session values stay in moduleCfg/Manifest; User defaults stay in configuration.ini |
| Save failure | configurationGuiSave unconditionally dereferences late fields absent from configurationUi | Project only existing editable drafts; retain CORE values for hidden fields; validate all candidates before commit |

Generic configuration contributions load from a descriptor-owned lightweight file,
with no scientific runtime or Viewer initialization. Plugin validators and rich
field schemas stay in their packages. CORE dispatches callbacks without module-ID
branches. Editors capture authoritative starting values and reject conflicting
commits. Unknown saved keys remain preserved for unavailable optional modules.
Existing descriptor types and repeatable config controls retain their authorities.

Source-confirmed capability gap: Workbench Extension's existing CORE API
availability map omitted Dataset Publication v2 although its public implementation
is loaded. Add its existing Prepare command to that map; no registry/API is added.

Source-confirmed continuity gap: exact filtered publication can preserve original
row ordinals, but Curve Source only respected nonfinite gaps on reopening. Extend
Curve Source display to consume a declared `source_row_adjacency` continuity policy
and typed lineage variable through CORE Metadata/Schema/Table Stream. The publisher
only writes CORE-provided exact row identities; it implements no filter/gap engine.
Sampling and Native2D remain unchanged. Memory is bounded by source chunks and the
display budget, and async display schedules continuity scans at chunk boundaries.

## Final authority and compatibility matrix

| Owner/API | Change and concrete necessity | Consumers / evidence |
|---|---|---|
| CONFIGURATION_API_v1 | Add module discovery, scoped resolution, compare-before-commit transactions and subscription operations to existing registry. Existing global-only register/get/set/save could not describe Session inheritance or coordinate two editors. | Central Modules, generic local dialog, Workbench shortcuts, unknown descriptor-only example; Configuration API/real-GUI/restart suites. |
| MODULE_API_v1 | Discover all public `[config]` fields and safe lightweight contribution entrypoints at catalog load. Include formally registered module keys in existing Manifest persistence. Existing persistent-only discovery omitted legitimate Session settings and unopened Workbench shortcuts. | Entire installed catalog; source/GUI coverage TSV and late-field persistence tests. |
| UI_FIELD_API / REPEATABLE_CONFIG_API_v1 | Reuse typed scalar/choice/path/structured forms. Add validated factory/snapshot/apply operations to existing repeatable-row authority so both editors can stage whole tables without direct private-array persistence. | Unknown plugin's typed Session coefficient table; invalid values, save/reopen and central/local drafts. |
| DATASET_SCIENTIFIC_PROFILE_API / Filters | Extend dimensions/controls with optional manual family Variable ID and semantic-only discovery. Preserve defaults for existing consumers. Existing name heuristics could not safely express explicit manual binding. | Curve Viewer; text/int64, ambiguous/name-only/incomplete discovery tests. |
| CURVE_SOURCE_API_v1 | Reuse exact requests/pages/selection, fingerprints and async cancellation. Add declared original-row adjacency consumption for display; otherwise reopening an exact filtered Dataset could join separated source segments after sampling. | Publisher and normal Viewer/Preview; exact 1850/20000 fixture, all lineage/content rows, synchronous/async gap equality and cancellation. |
| DATASET_PUBLICATION_API_v2 | Unchanged authoritative prepare/writer/schema/append/finalize/abort create-only transaction. Dataset Transform predicate selection remains Curve Source's dependency. | Independent export.curve_dataset; collisions/zero rows/stale owners/Session/units do not leave partial output. |
| UNIT_REGISTRY_API_v1 | Reuse available registered-unit listing, existing intrinsic expression validation and conversion planning. Identity conversion alone cannot validate an unknown expression. No unit parser or numerical conversion is added. | Registered opaque scientific labels remain supported; unsupported-unit fixture rejects before output staging. Existing validation operations documented. |
| WORKBENCH_EXTENSION_API_v1 | Reuse discovery, typed parameters, normal enablement and common action/export dialogs. Fix its capability map to recognize the already loaded Publication v2 API. | Publisher normal install/disable/uninstall/reinstall; existing exporters stay separate. |
| SESSION_WORKSPACE_API_v1 | Add descriptor-based lightweight provider discovery, accepted schema versions and generic Viewer menu adapter. Existing registry remains authoritative. Older hardwired providers could not list new viewers without eager runtime activation. | Curve Viewer v1 and Fit v1/v2; exact IDs, A/B, promotion, notes, duplicate/export/import/delete and unavailable-provider cases. |
| INTERACTIVE_DOCUMENT / RESOURCE / RECOVERY APIs | Reuse unchanged IDs, generation/revision, atomic document/resource commits, Session lifetime and recovery checkpoint/mark-saved. Viewer adapters compare saved scientific payloads while allowing note/name metadata updates. | Viewer saves and History reset; stale writes, recovery, rich image/calibration/resource/portable checks. |
| SCIENTIFIC_RECIPE_API_v1 | Add inert owner-neutral `scientificRecipeRebase record current context` using existing host validation/encoding limits. Append cannot explicitly discard complete history; raising limits would not solve the problem. Decode owner grammar permits registered future owners rather than a two-owner whitelist. | Workbench host adapter plus unknown owner CORE unit test near 8 MiB and 4096 steps, oversized base rejection and append after reset. |
| Native2D / Numerical fitting | Unchanged compiled/native sources and numerical implementation. Fit widgets/menus call existing actions. | Exact deterministic dev093/dev094 numerical dictionaries; classical five-model/source-filter/selection/residual/publication regression; real rectangle/zoom/pan/residual GUI. |

No new public CORE API or configuration/scientific/Workspace authority exists.
`CURVE_DATASET_EXPORT_API_v1` is the one new **module-owned invocation façade**:
normal Workbench Extension modules must declare a discoverable public entrypoint
for their action. It accepts a typed extension context and frozen Curve Source
selection, returns the Publication receipt, and delegates all scientific selection,
storage, metadata and transaction responsibilities to existing CORE owners. It
does not warrant a new CORE publisher API. Its Session lifetime and Workspace
generation travel inside the plugin's selection descriptor, without changing the
generic Extension context's public signature.

## Configuration interface and source isolation

The public developer contract is `docs/api/CONFIGURATION_API_v1.md`, complemented
by Module and Repeatable Config contracts and the installable
`docs/examples/module_configuration`. Stable IDs and `module_id/module_key`
connect the existing registry to existing `moduleCfg`/Manifest keys. Factory →
saved User default → explicit Session override resolves through CORE. Inheritance
is transient projection metadata, reconstructed from key presence in the Manifest;
it is not another persisted setting store. User defaults stay in configuration.ini.

The central page and local `configurationModuleDialog` use the same descriptors,
typed/module-owned validators, expected authoritative starting values, Session
tokens, commit and notifications. Tk arrays contain drafts only. Existing module
controls still write their legitimate Session `moduleCfg` values; traces update
projections without manufacturing global defaults. Workbench command definitions
and shortcut validation live in its lightweight plugin settings file; CORE has no
conditional branch on its ID or any other installed plugin's identity/version.

The unknown example is installed normally in a disposable physical module tree,
including while disabled. Integer/choice/boolean and repeatable-table settings
work centrally and locally. The coverage runner visits every installed module and
checks every declared/formally registered field against actual editor controls,
including disabled, CORE, ALWAYS and genuinely nonconfigurable modules.
Rich-form conflicts, late fields, hidden global values, restart, next-invocation
timing, inherited Session values and live Workbench F8→F9 bindings are exercised.

The modified authoritative Manifest loader also replaces its pre-existing
hard-coded script-module migration/synchronization loop with descriptor dispatch
on the existing registered-script configuration contract. Historical external-file
mode remains compatible. Unmodified Analysis/Acquisition execution widgets elsewhere
in the large legacy Module file retain their baseline specialist dispatch; they
are outside the new Configuration interface and are not copied into it.

## Encountered Tcl ownership / rename chains

No new rename wrapper is introduced. The release gate compares added Tcl rename
lines with dev093, records every retained chain in affected files, and hashes
unchanged numerical/native owners. The changed-files manifest preserves exact
before/after evidence.

| Chain / activation | Consumers and decision | Regression |
|---|---|---|
| Fit `_saveState` v1→v2 interception in `curve_fit_workspace_v2.tcl` loaded after the original Viewer API | Consolidated into one authoritative v2 save; removed unused old v1 save and rename. All GUI changes, accept, close and explicit Workspace Save use it. A restore-in-progress guard prevents autosave of a partial restore. | Fit A/B accepted sources, resource dictionaries, duplicate/notes, exact save/reopen and legacy v1→v2 promotion without extra document. |
| Fit `_restoreState` v1→v2 interception | Removed rename. Existing v1 compatibility body has a static `_restoreLegacyState` name, called only by authoritative v2 restore for a genuine v1 record, with exact requested ID. | Legacy accepted-record restoration and promotion; no dataset-first misrouting. |
| GUI `loadManifest` Session Instrumentation wrapper | Consolidated its loading guard into authoritative Module `loadManifest`, alongside generic configuration Session reconciliation. Removed GUI rename/proc; instrumentation variables and dirty-trace suppression remain. | Configuration inheritance/reopen/late fields; real GUI startup, existing cache/Appearance/Native3D preferences; viewer and rich Workbench Session reopen. |
| `openSessionPath` / saveCurrentSessionConfig / Session-dialog chains across Dataset Viewer, storage profiles, Project API/experiment management and Session Instrumentation | Inspected, retained. These unchanged outer wrappers add different lifecycle responsibilities (save decisions, Project attachment/defaults, namespace refresh, dirty-instrument prompts). Replacing the cross-owner chain would require a separately scoped Project/Session lifecycle migration; the targeted loading guard was safely consolidated at its actual owner. | Public Session open/create/reopen and A→B→A fixtures, manifest values, stale Viewer isolation; unchanged procedure signatures. |
| Session Workspace explorer/menu wrappers around build/populate/load/save GUI | Retained unchanged. Session File Explorer integration and manager refresh consume these adapters; new viewer providers/menu use the existing public registry rather than intercepting another command. Global explorer refactoring is outside this stabilization. | Standard provider listing/manager, notes/export/import and exact-ID opening. |
| Workbench recipe `_snapshotIds`, `_load`, `_history`; Timeline guard/rebuild and Undo/Redo wrappers | Retained unchanged. Existing history guards wrap a large set of editing, constraints, selection and restore commands across retained/native bridge, CAD and interaction controllers. Clear History adds an explicit host command and CORE rebase, without changing append or those command chains. Consolidating all controllers would expand into prohibited Workbench/Native2D redesign. | Near-step/byte edit rejection, cancel/failure rollback, browsing/active-gesture rejection, exact rich current state, real constrained drag after reset, save/reopen/portable recovery. |
| Workbench interaction v1/v2 `_coordinates`, constraint forms, restoreSnapshot, units/source joins, marker/point/numeric editors, undo/redo/publish | Only duplicated constraint/command schema definitions were moved to one lightweight settings owner. Wrappers themselves are unchanged; their distinct gesture/constraint/native restoration consumers require an independent controller consolidation, not a settings or History fix. | Live shortcut central/local round trip; unchanged rich geometry/constraints/calibration and native post-reset gesture. |
| Fit numeric-source `loadSource_v1` interception | Retained byte-for-byte unchanged. It supplies the already accepted CORE exact-source adapter used by all numerical fitting/selection/publication; replacing it would risk numerical behavior beyond the requested layout. | Seven deterministic built-in fixtures exactly equal to dev093, five classical models/all filters/orientation/publication. |

Unrelated installed plugin/generator wrappers remain outside this work. The general
wrapper-remediation TODO remains; completed central-configurator and Fit-layout
items alone are removed.
