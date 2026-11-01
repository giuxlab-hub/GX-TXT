# Block 3 architecture review — GX-TXT 0.9.8.10-dev

This is an implementation inventory, not a support-policy decision. Source-order replacement, absence of a GUI binding, and obsolescence are distinct. The original audit remains unchanged.

## 2026-09-30 API completion re-audit

C-03/C-04's ordinary external-module needs now have supported semantic paths:
Session Inspection v1 returns current Session, Dataset/Selection records and
verified Session resources; Canonical Dataset v2 and Variable Schema v3 resolve
stable data identities; Dataset Publication v2/File Publication v1 own output;
Session Persistence v1 commits current framework-owned state without arbitrary
Manifest editing; Plot Dataset v3 covers graph configuration, Variant identity,
rendering and interactive manual Sync; Viewer Provider v1 owns presentation.
External callers of these paths were migrated where safe. Plot Dataset v2's
remaining `moduleGraph*`, queue and registry calls are inside the protected
CORE plot-service implementation and remain necessary for that implementation;
they are not an API requirement for a normal external module. The remaining
Levoglucosan standalone bootstrap sources the framework entry point to start
the process and does not represent module-to-CORE private state access.

C-02 was rerun over all production module directories. Ten modules were
reported: `acq.geometry_3d` (the Python identifier `grid` is a checker false
positive), `analysis.digitization_quality`, `viewer.curve_digitizer`,
`viewer.pdf_ocr`, `viewer.table_extractor` (explicit Python Tk companions),
`viewer.document_extractors`, `viewer.spectral_library`, `viewer.xas_spectra`
(Tk commands are inside explicitly invoked GUI procedures),
`demo.environmental.levoglucosan_campaign` (standalone framework bootstrap),
and `viewer.native_3d` (explicit native GUI adapter). Descriptor discovery
and service activation remain headless; the native adapter remains lazily
activated. These reports do not require external scientific modules to call
private CORE state. The original historical findings below remain as audit
context; this dated section is the current disposition.

## C-01: definitions replaced without `rename`

`gxtxt_pipeline.tcl` loads `app/module_catalog.tcl` before `core/tcl/module_api_v1.tcl`; later CORE files load after both. The following 13 earlier definitions are replaced in the current load order. None was deleted: historical or programmatic compatibility and the intent of each earlier definition have not been established well enough to call it obsolete. `UNCLASSIFIED_RETAINED` describes the earlier definition, not the active command of the same name. During the rename/source-order stabilization, the active module-discovery chain was given fixed named procedures. The early `app/module_catalog.tcl` `loadModuleCatalog` now remains the transient command name until `documentation_browser_api_v1.tcl` defines the final entry point; it is still shadowed after complete framework loading and remains retained.

| Earlier procedure | Earlier source | Current disposition |
| --- | --- | --- |
| `::GX::loadModuleCatalog` | `app/module_catalog.tcl:2` | UNCLASSIFIED_RETAINED; early INI catalog loader, later descriptor catalog replaces it. |
| `::GX::moduleField` | `app/module_catalog.tcl:37` | UNCLASSIFIED_RETAINED; early catalog field reader, later descriptor-aware reader replaces it. |
| `::GX::moduleIsEnabled` | `app/module_catalog.tcl:52` | UNCLASSIFIED_RETAINED; early enabled-key semantics differ from active CORE semantics. |
| `::GX::selectedModuleIds` | `app/module_catalog.tcl:61` | UNCLASSIFIED_RETAINED; early selection traversal is replaced by CORE. |
| `::GX::moduleSetEnabled` | `app/module_catalog.tcl:71` | UNCLASSIFIED_RETAINED; early selection mutation is replaced by CORE. |
| `::GX::applyModuleSelection` | `app/module_catalog.tcl:93` | UNCLASSIFIED_RETAINED; early selection restore is replaced by CORE, then extended by a later wrapper. |
| `::GX::manifestString` | `core/tcl/module_api_v1.tcl:1713` | UNCLASSIFIED_RETAINED; superseded by a later manifest implementation. |
| `::GX::refreshNativeInstrumentationGui` | `core/tcl/module_api_v1.tcl:1777` | UNCLASSIFIED_RETAINED; the later Module API builder still shadows it and is now explicitly named `refreshNativeInstrumentationGui_before_scientific_notes_v1`. The active Instrument Library → Scientific Notes → later Module API chain no longer captures this earlier definition by rename. |
| `::GX::rebuildNativeExperimentGui` | `core/tcl/module_api_v1.tcl:1856` | UNCLASSIFIED_RETAINED; the later Experiment/notes implementation is now named directly `rebuildNativeExperimentGui_before_project_api_v1` at line 2597, and Project API defines the final entry after it. The earlier definition remains in source and is still transiently active during loading; no lifecycle removal decision has been made. |
| `::GX::rebuildNativeAnalysisGui` | `core/tcl/module_api_v1.tcl:1887` | UNCLASSIFIED_RETAINED; later Analysis UI implementation replaces it. |
| `::GX::addExperimentTextTab` | `core/tcl/module_api_v1.tcl:2570` | UNCLASSIFIED_RETAINED; `dataset_notes_api_v1.tcl` replaces the tab implementation. |
| `::GX::buildModulePlotConfigFrame` | `core/tcl/module_api_v1.tcl:2620` | UNCLASSIFIED_RETAINED; later plot controls replace it. |
| `::GX::acquisitionHandlerImportSourcesToSession` | `core/tcl/acquisition_handler_api_v1.tcl:1296` | UNCLASSIFIED_RETAINED; the later implementation adds transaction staging and rollback. |

The active definitions are `ACTIVE`; the replaced definitions are not callable by their original command names after startup. They are not classified as intentionally unbound, intentionally overridden, accidentally shadowed, or obsolete without stronger evidence. `::GX::moduleKindLabel` in the early file remains active and has GUI callers.

The rename/source-order stabilization keeps the earlier `rebuildNativeAnalysisGui` source definition intact. Its later v0.6.2, v0.7.1, v0.7.8 and v0.8.4 historical implementations are now explicitly named; a short Module API adapter exposes the current Analysis Sources builder until the final Script Workspace decorator is sourced. The earlier C-01 definition remains shadowed after startup and retains `UNCLASSIFIED_RETAINED` lifecycle status. No C-01 definition was deleted by this work.

The earlier `buildModulePlotConfigFrame` definition is also retained. Its v0.7.1 and v0.7.2 successors and common-graphics layer now have fixed names; a Module API adapter exposes common graphics until the Plot Variant source defines the final entry. The earlier definition remains shadowed after full load and retains `UNCLASSIFIED_RETAINED` status.

## C-02: host-independence findings

The checker reports nine modules. `export.session_html` now keeps its headless public `export` service in `api/` and loads its Tk dialog from `ui/` only on `guiExport`. The other findings are retained pending focused design work: `analysis.digitization_quality`, `viewer.curve_digitizer`, `viewer.pdf_ocr`, and `viewer.table_extractor` use Tk in separate Python GUI companions launched only on explicit viewer actions; `viewer.document_extractors` and `viewer.spectral_library` define desktop adapters in API files, but their inspected source does not initialize Tk during headless descriptor discovery. Spectral Library also sources two UI definition files during API activation; that source boundary deserves a separate change with its GUI and headless behavior tested. The Levoglucosan graph generator sources the desktop pipeline as a standalone runner; replacing that with a smaller public bootstrap requires an actual runtime contract. `viewer.native_3d` is frozen and was inspected only. These checker reports are real architecture follow-ups, but moving working GUI procedures mechanically would not establish host independence.

## C-03/C-04: missing public CORE capabilities

The undocumented calls remain present. Plot Dataset's private CORE dependencies include graph/module state (`modulePlotCfg`, `moduleGraphConfig*`, `moduleGraph*`, `moduleSetEnabled`, `moduleSetRunSelected`), queue construction (`buildStandardAnalysisQueue`, `buildStandardRerenderQueue`), current registry access (`loadDatasetRegistry`, `datasetField`, `datasetRegistryIds`), persistence (`putKV`, `plotVariantOutputDir`), and UI refresh/selection hooks. Its own documented Plot Dataset v1–v3 API is public to consumers, but does not grant these reverse calls to CORE. Replacing a call with another private command would only rename the violation.

The current Plot Dataset source scan found these undocumented symbols (27 names, including arrays; the audit counted 26 in its earlier tree):

| Current symbol(s) | Public API assessment |
| --- | --- |
| `analysisSourceFindRow`, `analysisSourceRowDataset`, `moduleAnalysisSource` | Analysis Source Map API exposes runtime/source contracts, but does not provide this GUI state lookup with matching semantics. |
| `buildStandardAnalysisQueue`, `buildStandardRerenderQueue` | No public queue/render request with the same module-state and lifecycle semantics. |
| `datasetField`, `datasetRegistryIds`, `loadDatasetRegistry` | Session Inspection v1 offers read-only descriptors/IDs for suitable uses; it does not expose the mutable current registry or its load side effects. |
| `graphRuntimeSelectionOverride` | No public equivalent for this runtime graph-selection hook. |
| `moduleGraphConfigField`, `moduleGraphConfigGet`, `moduleGraphConfigKeys`, `moduleGraphConfigSet`, `moduleGraphField`, `moduleGraphIds`, `moduleGraphIsEnabled`, `moduleGraphToggle`, `modulePlotCfg` | Graph Provider/Graph Configuration APIs expose selected provider contracts, but not the full base-graph config and enabled-state semantics used here. |
| `moduleOrder`, `moduleRunIsSelected`, `moduleSetEnabled`, `moduleSetRunSelected` | No public module selection/temporary render-state transaction with equivalent semantics. |
| `plotVariantExists`, `plotVariantOutputDir`, `plotVariantResetInheritedDataView` | Public Plot Dataset v1–v3 describes plots; it does not expose all CORE variant storage/inheritance operations used internally by the provider. |
| `putKV`, `refreshManifestPreview` | No generic validated PlotSpec serialization/manifest UI service with equivalent behavior. |

Other reported modules still use `loadDatasetRegistry` (IR, UV/Vis, UV/Vis Exploration, Levoglucosan, Math Numeric, Curve Digitizer), `datasetField` and `datasetResolvePath` (notably Curve Digitizer), `writeManifest` and `loadModuleCatalog` (Levoglucosan), `datasetSelectionLoadRegistry` (Math Numeric), and `sha256File` (several modules). Native 3D's uses remain frozen. Session Inspection API v1 already supplies read-only Dataset descriptors for suitable consumers, but it does not replace mutable registry loading, trusted canonical-path resolution, graph queue construction, or manifest writes. No large module was rewritten in this block.

The other C-04 reported symbols were checked individually: `loadDatasetRegistry` and `datasetSelectionLoadRegistry` need a Session-scoped read/query service; `datasetField` has a partial read-only alternative in Session Inspection v1; `datasetResolvePath` needs a safe canonical payload resolver; `writeManifest` needs a validated Session update request; `loadModuleCatalog` needs a headless descriptor bootstrap; `putKV` needs a format-specific writer owned by the relevant public API; and `sha256File` needs a generic digest contract only where integrity comparison is part of the consumer's supported operation. None has a clear, behavior-equivalent one-line replacement in the affected call sites. Native 3D is deferred without source changes.

Small generic public capabilities to design before migrating these consumers: a read-only canonical Dataset descriptor/path accessor with integrity information; a Session-scoped Dataset/Selection query that does not mutate global registry state; a sanctioned module graph state/config and render/rerender request service; a bounded Session manifest update service for generators; and a generic file-digest utility where integrity comparison is part of a public contract. Public APIs must validate ownership and Session scope rather than expose raw CORE arrays or arbitrary registry writes.

## C-05: local Octave quote helpers

The IR, UV/Vis, and UV/Vis Exploration current entrypoints call `gxtxt_shell_quote_v1`; repository search finds only the three old helper definitions and historical file inventories. Because external Octave callers and older programmatic paths cannot be excluded from current evidence, all three are retained and listed in `UNBOUND_CAPABILITIES.md` for owner review.

## C-06/C-07: explicit `standardConfigWidget` ownership after stabilization

The known caller is `::GX::buildStandardConfigFrame`, reached by descriptor-generated Standard Module configuration GUI. Source order is `module_api_v1.tcl` (pipeline line 156), `dataset_selection_api_v1.tcl` (170), `repeatable_config_api_v1.tcl` (171), `numeric_expression_browser_v1.tcl` (172), `scientific_plot_framework_api_v1.tcl` (176), then `temporal_set_api_v1.tcl` (205). Within `module_api_v1.tcl`, definitions and renames execute in file order.

Block 3's pre-change wrapper chain was, outermost first:

1. `standardConfigWidget`: Temporal Set selector (`temporal_set_api_v1.tcl`); other types delegate.
2. `standardConfigWidget_before_temporal_set_v1`: Unit selector (`scientific_plot_framework_api_v1.tcl`); others delegate.
3. `standardConfigWidget_v0933_before_unit_selector`: Numeric Expression Browser button (`numeric_expression_browser_v1.tcl`); others delegate.
4. `standardConfigWidget_before_numeric_expression_browser`: repeatable table and model selectors (`repeatable_config_api_v1.tcl`); others delegate.
5. `standardConfigWidget_v092_before_repeatable_config`: Dataset Selection selector (`dataset_selection_api_v1.tcl`); others delegate.
6. `standardConfigWidget_v091_before_dataset_selection`: Analysis Definition selector with Parameters/Preflight (`module_api_v1.tcl`); others delegate.
7. `standardConfigWidget_v083_before_analysis_parameters`: generic CSV contract selector (`module_api_v1.tcl`); others delegate.
8. `standardConfigWidget_v081_before_contract_registry`: older Analysis Definition selector (`module_api_v1.tcl`); others delegate.
9. `standardConfigWidget_v079_before_scientific_analysis`: file/path browser (`module_api_v1.tcl`); others delegate.
10. `standardConfigWidget_v077`: Boolean checkbox (`module_api_v1.tcl`); others delegate.
11. `standardConfigWidget_v060`: base choice/model/dataset/text widget (`module_api_v1.tcl`).

Block 3 left this chain unchanged. The subsequent rename/source-order stabilization replaced its ten source-time captures with a fixed-owner internal dispatcher in `module_api_v1.tcl`. The dispatcher checks the specific generic CSV module/key contract first, then selects the owner by normalized widget type. The listed historical procedures retain their implementations and internal fallback calls for direct compatibility use; ordinary configuration construction selects one owner explicitly. The Numeric Expression Browser still provides its 79 operations. Focused Xvfb widget tests and a copied real Welch DEMO GUI/Session save/reopen passed after the change; see `RENAME_SOURCE_ORDER_STABILIZATION.md` for the full before/after evidence and ordering table. This is an internal composition mechanism, not a new public API. The 13 earlier C-01 definitions remain retained with their previous lifecycle classifications.

The Linux Script Bridge hardening pass rechecked the C-01 shadows and the
unbound-capability table. Their callers and owner lifecycle policy remain
uncertain, so no definition was deleted. The current host-independence checker
still detects GUI dependencies; exact known GUI companions, provider GUI
adapters and the standalone Levoglucosan framework entry point are classified
as informational with reasons in `tools/check_plugin_host_independence.py`.
Unlisted dependencies remain failures. The Python geometry-probe `grid`
token was a false positive because Tk geometry-manager rules now apply only
to Tcl sources.

## dev109 shared scientific preview integration (acceptance pending)

`graph_workflow_api_v1.tcl` now resolves an original Graph Resource separately
from its explicit provider-backed scientific representation. The compact host
uses the same resolver for eligibility, activation and retained source identity.
`PlotDataset3DAPIv1::previewGraphExportCommand` shares the existing preparation
worker, scientific renderer and converter; its actual-cache/source/geometry
checks execute in that worker. No new renderer, Dataset store or Variant registry
was introduced. Axis and legend defaults remain in their current owners and are
also available as pure default reads for effective presentation comparison.

Molecular Dataset navigation uses the existing Dataset Viewer and Viewer dispatch
owners to open `viewer.molecule_3d` with the exact Dataset ID. The dedicated
Native3D adapter and native host own normal root shutdown and command-pipe EOF.
The molecular orphan failure and manual cleanup remain failed lifecycle evidence;
source corrections and successful builds alone do not establish GUI acceptance.
