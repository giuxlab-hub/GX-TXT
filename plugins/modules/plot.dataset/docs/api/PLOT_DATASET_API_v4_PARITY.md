# Plot Dataset API v4 finite parity and evidence

Version scope: official GX-TXT dev100. The finite baseline is the actual accepted dev099 runtime inventory in `plot-inventory-01/inventory.tcldict`: **68 v3 operations,13 companion operations,66 capabilities,10 registered2D kinds and7 registered3D kinds**. This matrix distinguishes reused unchanged owners from new native behavior. A declaration/availability PASS is not an individual scientific or GUI PASS.

The protected v1/v2/v3/3D API and original Script binding bytes are verified unchanged in `plot-parity-01/result.tcldict`. Existing persistence/specification acceptance is reused. New native rendering, bounds, identities, units, captures and GUI flows have the focused receipts named below. Historical failed attempts are retained and are not substituted for final acceptance.

## All68 public v3 operations

| Operation and accepted signature | Actual v4 owner / equivalent | Evidence / disposition |
|---|---|---|
| `activateInteractive representationId` | Native v4 `plot_dataset_v4_native3d.tcl` | plot-remaining-gui-03 native retained Open button; rejects foreign module/provider; independent resources retained |
| `addPanel plotRef panelId` | Unchanged public `PlotDatasetAPIv2::addPanel` | plot-crosscuts-03 real public edit/configuration and native effect; unchanged persistence owner |
| `apiInfo ` | Native v4 `plot_dataset_api_v4.tcl` | plot-parity-01 + actual Python/Octave plot-bridge-03 |
| `applySpec plotRef spec` | Native v4 `plot_dataset_api_v4.tcl` | plot-selection-01 fresh-binding capture |
| `artifacts plotRef` | Native v4 `plot_dataset_api_v4.tcl` | plot-public-04 and graph-workflow-05 actual canonical/native artifacts |
| `buildScene plotRef {representationId {}}` | Native v4 `plot_dataset_v4_native3d.tcl` | plot-gui-04 all7 kinds; plot-remaining-gui-03 real Native3D Create button/public rank2 grid |
| `capabilities ` | Native v4 `plot_dataset_api_v4.tcl` | plot-parity-01 (all66 actual accepted capabilities) |
| `captureForArtifact artifact destinationDir` | Native v4 `plot_dataset_v4_snapshots.tcl` | plot-public-04 complete Dataset ZIPs; plot-selection-01 explicit read-only legacy intake; worksheet-model/legacy-plot-04 |
| `createPlot graphId {kind base} {sourceVariant {}}` | Native v4 `plot_dataset_api_v4.tcl` | existing v1 creation retained, additive owner marker checked plot-public-04 / Worksheet retainPlot legacy-plot-04 |
| `createPlotFromSpec spec {kind base} {sourceVariant {}}` | Native v4 `plot_dataset_api_v4.tcl` | plot-public-04; plot-gui-04; plot-bridge-03 |
| `deletePlot plotRef` | Unchanged public `PlotDatasetAPIv1::deletePlot` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `deriveSpec plotRef` | Native v4 `plot_dataset_v4_native3d.tcl` | existing v2 XY owner retained; native3D explicit public Variant resolution used plot-remaining-gui-03 |
| `getConfig plotRef key` | Unchanged public `PlotDatasetAPIv1::getConfig` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `getSeries plotRef seriesId` | Unchanged public `PlotDatasetAPIv1::getSeries` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `interactiveRepresentations ` | Native v4 `plot_dataset_v4_native3d.tcl` | plot-remaining-gui-03 actual existing representation chooser before/after source deletion |
| `interactiveSourceInfo plotRef` | Native v4 `plot_dataset_v4_native3d.tcl` | plot-remaining-gui-03 actual X/Y/Z/C role bindings and source hash |
| `interactiveSources ` | Native v4 `plot_dataset_v4_native3d.tcl` | plot-remaining-gui-03 unavailable-source eligibility rejection |
| `interactiveStatus representationId` | Native v4 `plot_dataset_v4_native3d.tcl` | plot-remaining-gui-03 truthful SOURCE MISSING after disposable source deletion; exact accepted status strings |
| `listSeries plotRef {includeDisabled 1}` | Unchanged public `PlotDatasetAPIv1::listSeries` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `loadSpec plotRef {deriveIfMissing 1}` | Native v4 `plot_dataset_v4_native3d.tcl` | plot-public-04; plot-crosscuts-03 effective controls; plot-selection-01 fresh source binding |
| `movePanel plotRef panelId delta` | Unchanged public `PlotDatasetAPIv2::movePanel` | plot-crosscuts-03 real public edit/configuration and native effect; unchanged persistence owner |
| `moveSeries plotRef seriesId direction` | Unchanged public `PlotDatasetAPIv1::moveSeries` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `multiPanelEnabled plotRef` | Unchanged public `PlotDatasetAPIv2::multiPanelEnabled` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `newSpec args` | Unchanged public `PlotDatasetAPIv2::newSpec` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `openEditor plotRef` | Native v4 `plot_dataset_api_v4.tcl` | byte-identical existing v2 editor reused; source inspection confirms Add/update/remove/move/Close only, no Render callback or legacy render redirection |
| `openInteractive plotRef` | Native v4 `plot_dataset_v4_native3d.tcl` | plot-gui-04; plot-remaining-gui-03 actual Native3D graph chooser/Create button |
| `openPlot graphId {variantId {}}` | Unchanged public `PlotDatasetAPIv1::openPlot` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `panelIds plotRef` | Unchanged public `PlotDatasetAPIv2::panelIds` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `panelIdsForArtifact path` | Unchanged public `PlotDatasetAPIv2::panelIdsForArtifact` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `panelInfo plotRef panelId` | Unchanged public `PlotDatasetAPIv2::panelInfo` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `plotRefForArtifact path` | Unchanged public `PlotDatasetAPIv2::plotRefForArtifact` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `previewCompatibility plotRef` | Native v4 `plot_dataset_api_v4.tcl` | current public source/spec validation; exact supported/plot_ref receipt restored, actual Native3D preview intake plot-remaining-gui-03 |
| `previewExportCommand plotRef output` | Native v4 `plot_dataset_v4_native3d.tcl` | plot-gui-04 genuine read-only native preview worker; plot-remaining-gui-03 HDF5 grid intake |
| `readPlot plotRef` | Native v4 `plot_dataset_api_v4.tcl` | plot-bridge-03; plot-remaining-gui-03 source-info binding receipt |
| `reconcilePersistentPlots ` | Unchanged public `PlotDatasetAPIv2::reconcilePersistentPlots` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `refreshInteractive plotRef` | Native v4 `plot_dataset_v4_native3d.tcl` | actual same-document Sync button, source freshness/status and unchanged science: chart-selection-sync-gui-03 PASS9 / chart-selection-sync-accepted.json PASS16 |
| `removePanel plotRef panelId` | Unchanged public `PlotDatasetAPIv2::removePanel` | plot-crosscuts-03 real public edit/configuration and native effect; unchanged persistence owner |
| `removeSeries plotRef seriesId` | Unchanged public `PlotDatasetAPIv1::removeSeries` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `removeSpec plotRef` | Unchanged public `PlotDatasetAPIv2::removeSpec` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `render plotRef` | Native v4 `plot_dataset_api_v4.tcl` | plot-public-04 all10 2D kinds; plot-gui-04 all7 3D kinds; plot-remaining-gui-03; plot-bridge-03 |
| `renderCommand plotRef {operation render}` | Native v4 `plot_dataset_api_v4.tcl` | graph-workflow-05 real queued native worker |
| `renderSnapshot cloneDir graph` | Native v4 `plot_dataset_v4_snapshots.tcl` | plot-public-04; graph-workflow-05; worksheet-model/legacy-plot-04 post-import live validation |
| `renderTransientCurve3D xValues yValues zValues label destinationDir` | Native v4 `plot_dataset_v4_native3d.tcl` | plot-transient3d-02 PASS: actual public native render, independently inspected exact ordered VTK vertices, invalid-input rejection and no canonical publication |
| `renderTransientCurves2D xValues series label destinationDir {xUnit {}}` | Native v4 `plot_dataset_v4_snapshots.tcl` | plot-grid-04 original values argument/result contract |
| `renderTransientIndependentCurves2D series label destinationDir` | Native v4 `plot_dataset_v4_snapshots.tcl` | plot-grid-04 original x_values/y_values contract including single-point series |
| `renderTransientOverlay artifact xValues yValues label destinationDir` | Native v4 `plot_dataset_v4_snapshots.tcl` | plot-selection-01 changed-spec fresh native overlay; original owner/PNG/source SHA unchanged; worksheet-model/legacy-plot-04 real legacy source |
| `requireCapability capability` | Native v4 `plot_dataset_api_v4.tcl` | plot-parity-01 |
| `rerender plotRef` | Native v4 `plot_dataset_api_v4.tcl` | plot-bridge-03 actual Python/Octave; existing Plots queued native worker graph-workflow-05 |
| `saveSpec plotRef spec` | Native v4 `plot_dataset_api_v4.tcl` | existing v2 persistence retained; actual Script binding normalizes its result; native Graph Metadata presentation covered graph-workflow-05 |
| `setConfig plotRef key value` | Unchanged public `PlotDatasetAPIv1::setConfig` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `setMultiPanel plotRef state` | Unchanged public `PlotDatasetAPIv2::setMultiPanel` | plot-crosscuts-03 real public edit/configuration and native effect; unchanged persistence owner |
| `setPanelAxis plotRef panelId axis fields` | Unchanged public `PlotDatasetAPIv2::setPanelAxis` | plot-crosscuts-03 real public edit/configuration and native effect; unchanged persistence owner |
| `setPanelTitle plotRef panelId title` | Unchanged public `PlotDatasetAPIv2::setPanelTitle` | plot-crosscuts-03 real public edit/configuration and native effect; unchanged persistence owner |
| `setPlotEnabled plotRef state` | Unchanged public `PlotDatasetAPIv1::setPlotEnabled` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `setSeries plotRef seriesId fields` | Unchanged public `PlotDatasetAPIv1::setSeries` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `setSeriesEnabled plotRef seriesId state` | Unchanged public `PlotDatasetAPIv1::setSeriesEnabled` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `setSeriesOrder plotRef orderedIds` | Unchanged public `PlotDatasetAPIv1::setSeriesOrder` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `setSeriesPanel plotRef seriesId panelId` | Unchanged public `PlotDatasetAPIv2::setSeriesPanel` | plot-crosscuts-03 real public edit/configuration and native effect; unchanged persistence owner |
| `setSeriesPresentation plotRef seriesId fields` | Unchanged public `PlotDatasetAPIv2::setSeriesPresentation` | plot-crosscuts-03 real public edit/configuration and native effect; unchanged persistence owner |
| `setTitle plotRef title` | Unchanged public `PlotDatasetAPIv1::setTitle` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `sharedXAxisGet plotRef` | Unchanged public `PlotDatasetAPIv2::sharedXAxisGet` | plot-crosscuts-03 real public edit/configuration and native effect; unchanged persistence owner |
| `sharedXAxisSet plotRef fields` | Unchanged public `PlotDatasetAPIv2::sharedXAxisSet` | plot-crosscuts-03 real public edit/configuration and native effect; unchanged persistence owner |
| `sourceFingerprint plotRef` | Native v4 `plot_dataset_v4_native3d.tcl` | existing effective spec + Dataset identity; plot-remaining-gui-03 source deletion; chart-selection-sync-gui-03 actual OUT OF SYNC → Sync → same-ID SYNCED/current fingerprint |
| `supports capability` | Native v4 `plot_dataset_api_v4.tcl` | plot-parity-01 |
| `syncInteractive representationId` | Native v4 `plot_dataset_v4_native3d.tcl` | chart-selection-sync-gui-03 PASS9: actual Sync button, same ID, exact current fingerprint, unchanged four scientific payloads/XY PNG |
| `upsertPlotFromSpec producerModuleId providerKey spec` | Native v4 `plot_dataset_api_v4.tcl` | existing provider-key Variant authority retained; Worksheet retainPlot legacy-plot-04 actual native publication |
| `validateSpec spec` | Unchanged public `PlotDatasetAPIv2::validateSpec` | REUSED accepted dev099 owner; all5 protected hashes unchanged (`plot-parity-01`) |
| `writePointIndex artifact destination` | Native v4 `plot_dataset_v4_snapshots.tcl` | plot-selection-01 exact accepted7-column TSV, actual CORE reader, canonical family-series ID, raw source coordinates/exact rows |

## All13 dedicated3D companion equivalents

| Accepted companion operation | Explicit v4 equivalent | Evidence / disposition |
|---|---|---|
| `activateRepresentation representationId` | `activateInteractive` | plot-remaining-gui-03 native retained Open button; rejects foreign module/provider; independent resources retained |
| `apiInfo ` | `apiInfo` | plot-parity-01 + actual Python/Octave plot-bridge-03 |
| `buildScene plotRef {representationId {}}` | `buildScene` | plot-gui-04 all7 kinds; plot-remaining-gui-03 real Native3D Create button/public rank2 grid |
| `openInteractive plotRef` | `openInteractive` | plot-gui-04; plot-remaining-gui-03 actual Native3D graph chooser/Create button |
| `previewCompatibility ref` | `previewCompatibility` | current public source/spec validation; exact supported/plot_ref receipt restored, actual Native3D preview intake plot-remaining-gui-03 |
| `previewExportCommand plotRef output` | `previewExportCommand` | plot-gui-04 genuine read-only native preview worker; plot-remaining-gui-03 HDF5 grid intake |
| `refreshInteractive plotRef` | `refreshInteractive` | actual same-document Sync button, source freshness/status and unchanged science: chart-selection-sync-gui-03 PASS9 / chart-selection-sync-accepted.json PASS16 |
| `representations ` | `interactiveRepresentations` | plot-remaining-gui-03 actual existing representation chooser before/after source deletion |
| `sourceFingerprint plotRef` | `sourceFingerprint` | existing effective spec + Dataset identity; plot-remaining-gui-03 source deletion; chart-selection-sync-gui-03 actual OUT OF SYNC → Sync → same-ID SYNCED/current fingerprint |
| `sourceInfo plotRef` | `interactiveSourceInfo` | plot-remaining-gui-03 actual X/Y/Z/C role bindings and source hash |
| `sources ` | `interactiveSources` | plot-remaining-gui-03 unavailable-source eligibility rejection |
| `syncInteractive representationId` | `syncInteractive` | chart-selection-sync-gui-03 PASS9: actual Sync button, same ID, exact current fingerprint, unchanged four scientific payloads/XY PNG |
| `syncStatus representationId` | `interactiveStatus` | plot-remaining-gui-03 truthful SOURCE MISSING after disposable source deletion; exact accepted status strings |

## All66 accepted public capabilities

| Capability | Native owner / exact retained authority | Focused evidence / disposition |
|---|---|---|
| `annotations_reference_line` | C++ panel data annotations at their actual left/right/X coordinates | plot-properties-03 and real GUI plot-properties-gui-01 PASS: exact right-axis position/dash/color, clipped regions and text |
| `annotations_reference_region` | C++ panel data annotations at their actual left/right/X coordinates | plot-properties-03 and real GUI plot-properties-gui-01 PASS: exact right-axis position/dash/color, clipped regions and text |
| `annotations_text` | C++ panel data annotations at their actual left/right/X coordinates | plot-properties-03 and real GUI plot-properties-gui-01 PASS: exact right-axis position/dash/color, clipped regions and text |
| `artifact_panel_discovery` | Unchanged public v1/v2 canonical Graph Series/Variant/PlotSpec authority | REUSED accepted dev099 owner, exact source hashes plot-parity-01; representative actual native lifecycle plot-public-04 / plot-bridge-03 |
| `artifacts` | Unchanged public v1/v2 canonical Graph Series/Variant/PlotSpec authority | REUSED accepted dev099 owner, exact source hashes plot-parity-01; representative actual native lifecycle plot-public-04 / plot-bridge-03 |
| `axes_config` | Existing PlotSpec/CORE Axes/Legend/graphics authorities → native model | plot-crosscuts-03; parent graph-workflow-05; parent worksheet-chart-features-02; plot-remaining-gui-03 (font/layout/grid/restore) |
| `axis_config_extension` | Existing PlotSpec/CORE Axes/Legend/graphics authorities → native model | plot-crosscuts-03; parent graph-workflow-05; parent worksheet-chart-features-02; plot-remaining-gui-03 (font/layout/grid/restore) |
| `axis_custom_ticks` | Existing PlotSpec/CORE Axes/Legend/graphics authorities → native model | plot-crosscuts-03; parent graph-workflow-05; parent worksheet-chart-features-02; plot-remaining-gui-03 (font/layout/grid/restore) |
| `axis_direction` | Existing PlotSpec/CORE Axes/Legend/graphics authorities → native model | plot-crosscuts-03; parent graph-workflow-05; parent worksheet-chart-features-02; plot-remaining-gui-03 (font/layout/grid/restore) |
| `bar_x_bounds` | Existing PlotSpec/Curve Source typed schema and native C++ scientific model | plot-public-04 + plot-gui-04; exactint64 grouping; independent-unit displacements plot-crosscuts-03; plot-properties-03 / plot-properties-gui-01 PASS independent bar-X/band-Y, optional confidence bounds, kind-aware markers, histogram physical/count axes |
| `base_graph` | Unchanged public v1/v2 canonical Graph Series/Variant/PlotSpec authority | REUSED accepted dev099 owner, exact source hashes plot-parity-01; representative actual native lifecycle plot-public-04 / plot-bridge-03 |
| `box_whisker_outliers` | Existing PlotSpec/Curve Source typed schema and native C++ scientific model | plot-public-04 + plot-gui-04; exactint64 grouping; independent-unit displacements plot-crosscuts-03; plot-properties-03 / plot-properties-gui-01 PASS independent bar-X/band-Y, optional confidence bounds, kind-aware markers, histogram physical/count axes |
| `build_scene` | Native3D C++/VTK and existing Viewer Scene/Layer/Interactive Document | plot-gui-04 all7 kinds; plot-grid-04 full rank2 HDF5; plot-remaining-gui-03 real Create/Open, source-deleted independent resources/owner/status |
| `cartesian_2d` | Native2D C++/Cairo and Native3D same VTK target | plot-public-04; plot-gui-04; plot-remaining-gui-03; actual supervised Python/Octave plot-bridge-03 |
| `cartesian_3d` | Native3D C++/VTK and existing Viewer Scene/Layer/Interactive Document | plot-gui-04 all7 kinds; plot-grid-04 full rank2 HDF5; plot-remaining-gui-03 real Create/Open, source-deleted independent resources/owner/status |
| `detached_scientific_capture` | Native snapshot/transient adapter; existing portable Dataset ZIP/Session authority | plot-public-04; plot-grid-04; plot-selection-01; worksheet-model/legacy-plot-04 |
| `detached_scientific_render` | Native snapshot/transient adapter; existing portable Dataset ZIP/Session authority | plot-public-04; plot-grid-04; plot-selection-01; worksheet-model/legacy-plot-04 |
| `dual_y` | Existing PlotSpec/Curve Source typed schema and native C++ scientific model | plot-public-04 + plot-gui-04; exactint64 grouping; independent-unit displacements plot-crosscuts-03; plot-properties-03 / plot-properties-gui-01 PASS independent bar-X/band-Y, optional confidence bounds, kind-aware markers, histogram physical/count axes |
| `errorbar_asymmetric` | Existing PlotSpec/Curve Source typed schema and native C++ scientific model | plot-public-04 + plot-gui-04; exactint64 grouping; independent-unit displacements plot-crosscuts-03; plot-properties-03 / plot-properties-gui-01 PASS independent bar-X/band-Y, optional confidence bounds, kind-aware markers, histogram physical/count axes |
| `errorbar_x` | Existing PlotSpec/Curve Source typed schema and native C++ scientific model | plot-public-04 + plot-gui-04; exactint64 grouping; independent-unit displacements plot-crosscuts-03; plot-properties-03 / plot-properties-gui-01 PASS independent bar-X/band-Y, optional confidence bounds, kind-aware markers, histogram physical/count axes |
| `errorbar_y` | Existing PlotSpec/Curve Source typed schema and native C++ scientific model | plot-public-04 + plot-gui-04; exactint64 grouping; independent-unit displacements plot-crosscuts-03; plot-properties-03 / plot-properties-gui-01 PASS independent bar-X/band-Y, optional confidence bounds, kind-aware markers, histogram physical/count axes |
| `graph_config_extension` | Existing PlotSpec/CORE Axes/Legend/graphics authorities → native model | plot-crosscuts-03; parent graph-workflow-05; parent worksheet-chart-features-02; plot-remaining-gui-03 (font/layout/grid/restore) |
| `graph_series` | Unchanged public v1/v2 canonical Graph Series/Variant/PlotSpec authority | REUSED accepted dev099 owner, exact source hashes plot-parity-01; representative actual native lifecycle plot-public-04 / plot-bridge-03 |
| `gridded_3d_streaming` | Native3D C++/VTK and existing Viewer Scene/Layer/Interactive Document | plot-gui-04 all7 kinds; plot-grid-04 full rank2 HDF5; plot-remaining-gui-03 real Create/Open, source-deleted independent resources/owner/status |
| `histogram_normalization` | Existing PlotSpec/Curve Source typed schema and native C++ scientific model | plot-public-04 + plot-gui-04; exactint64 grouping; independent-unit displacements plot-crosscuts-03; plot-properties-03 / plot-properties-gui-01 PASS independent bar-X/band-Y, optional confidence bounds, kind-aware markers, histogram physical/count axes |
| `idempotent_plot_publication` | Unchanged public v1/v2 canonical Graph Series/Variant/PlotSpec authority | REUSED accepted dev099 owner, exact source hashes plot-parity-01; representative actual native lifecycle plot-public-04 / plot-bridge-03 |
| `independent_representation` | Native3D C++/VTK and existing Viewer Scene/Layer/Interactive Document | plot-gui-04 all7 kinds; plot-grid-04 full rank2 HDF5; plot-remaining-gui-03 real Create/Open, source-deleted independent resources/owner/status |
| `interactive_sources` | Native3D C++/VTK and existing Viewer Scene/Layer/Interactive Document | plot-gui-04 all7 kinds; plot-grid-04 full rank2 HDF5; plot-remaining-gui-03 real Create/Open, source-deleted independent resources/owner/status |
| `interactive_sync_status` | Native3D C++/VTK and existing Viewer Scene/Layer/Interactive Document | plot-gui-04 all7 kinds; plot-grid-04 full rank2 HDF5; plot-remaining-gui-03 real Create/Open, source-deleted independent resources/owner/status |
| `manual_interactive_sync` | Explicit native same-document manual sync | chart-selection-sync-gui-03 PASS9 actual existing Sync button and source freshness; accepted combined continuation PASS16 |
| `multi_dataset` | Unchanged public v1/v2 canonical Graph Series/Variant/PlotSpec authority | REUSED accepted dev099 owner, exact source hashes plot-parity-01; representative actual native lifecycle plot-public-04 / plot-bridge-03 |
| `multi_panel` | Existing PlotSpec/CORE Axes/Legend/graphics authorities → native model | plot-crosscuts-03; parent graph-workflow-05; parent worksheet-chart-features-02; plot-remaining-gui-03 (font/layout/grid/restore) |
| `multi_panel_toggle` | Existing PlotSpec/CORE Axes/Legend/graphics authorities → native model | plot-crosscuts-03; parent graph-workflow-05; parent worksheet-chart-features-02; plot-remaining-gui-03 (font/layout/grid/restore) |
| `open_interactive` | Native3D C++/VTK and existing Viewer Scene/Layer/Interactive Document | plot-gui-04 all7 kinds; plot-grid-04 full rank2 HDF5; plot-remaining-gui-03 real Create/Open, source-deleted independent resources/owner/status |
| `panel_assignment` | Existing PlotSpec/CORE Axes/Legend/graphics authorities → native model | plot-crosscuts-03; parent graph-workflow-05; parent worksheet-chart-features-02; plot-remaining-gui-03 (font/layout/grid/restore) |
| `panel_order` | Existing PlotSpec/CORE Axes/Legend/graphics authorities → native model | plot-crosscuts-03; parent graph-workflow-05; parent worksheet-chart-features-02; plot-remaining-gui-03 (font/layout/grid/restore) |
| `panel_titles` | Existing PlotSpec/CORE Axes/Legend/graphics authorities → native model | plot-crosscuts-03; parent graph-workflow-05; parent worksheet-chart-features-02; plot-remaining-gui-03 (font/layout/grid/restore) |
| `panels_schema` | Unchanged public v1/v2 canonical Graph Series/Variant/PlotSpec authority | REUSED accepted dev099 owner, exact source hashes plot-parity-01; representative actual native lifecycle plot-public-04 / plot-bridge-03 |
| `persistent_graph_source` | Native3D C++/VTK and existing Viewer Scene/Layer/Interactive Document | plot-gui-04 all7 kinds; plot-grid-04 full rank2 HDF5; plot-remaining-gui-03 real Create/Open, source-deleted independent resources/owner/status |
| `plotspec` | Unchanged public v1/v2 canonical Graph Series/Variant/PlotSpec authority | REUSED accepted dev099 owner, exact source hashes plot-parity-01; representative actual native lifecycle plot-public-04 / plot-bridge-03 |
| `readonly_native3d_preview_export` | Native3D C++/VTK and existing Viewer Scene/Layer/Interactive Document | plot-gui-04 all7 kinds; plot-grid-04 full rank2 HDF5; plot-remaining-gui-03 real Create/Open, source-deleted independent resources/owner/status |
| `refresh_interactive` | Explicit native same-document manual sync | chart-selection-sync-gui-03 PASS9 actual existing Sync button and source freshness; accepted combined continuation PASS16 |
| `render` | Native2D C++/Cairo and Native3D same VTK target | plot-public-04; plot-gui-04; plot-remaining-gui-03; actual supervised Python/Octave plot-bridge-03 |
| `rerender` | Native2D C++/Cairo and Native3D same VTK target | plot-public-04; plot-gui-04; plot-remaining-gui-03; actual supervised Python/Octave plot-bridge-03 |
| `series_editor_extension` | Unchanged public v1/v2 canonical Graph Series/Variant/PlotSpec authority | REUSED accepted dev099 owner, exact source hashes plot-parity-01; representative actual native lifecycle plot-public-04 / plot-bridge-03 |
| `series_family_grouping` | Existing PlotSpec/Curve Source typed schema and native C++ scientific model | plot-public-04 + plot-gui-04; exactint64 grouping; independent-unit displacements plot-crosscuts-03; plot-properties-03 / plot-properties-gui-01 PASS independent bar-X/band-Y, optional confidence bounds, kind-aware markers, histogram physical/count axes |
| `series_kind_band` | Existing PlotSpec/Curve Source typed schema and native C++ scientific model | plot-public-04 + plot-gui-04; exactint64 grouping; independent-unit displacements plot-crosscuts-03; plot-properties-03 / plot-properties-gui-01 PASS independent bar-X/band-Y, optional confidence bounds, kind-aware markers, histogram physical/count axes |
| `series_kind_bar` | Existing PlotSpec/Curve Source typed schema and native C++ scientific model | plot-public-04 + plot-gui-04; exactint64 grouping; independent-unit displacements plot-crosscuts-03; plot-properties-03 / plot-properties-gui-01 PASS independent bar-X/band-Y, optional confidence bounds, kind-aware markers, histogram physical/count axes |
| `series_kind_box_whisker` | Existing PlotSpec/Curve Source typed schema and native C++ scientific model | plot-public-04 + plot-gui-04; exactint64 grouping; independent-unit displacements plot-crosscuts-03; plot-properties-03 / plot-properties-gui-01 PASS independent bar-X/band-Y, optional confidence bounds, kind-aware markers, histogram physical/count axes |
| `series_kind_errorbar` | Existing PlotSpec/Curve Source typed schema and native C++ scientific model | plot-public-04 + plot-gui-04; exactint64 grouping; independent-unit displacements plot-crosscuts-03; plot-properties-03 / plot-properties-gui-01 PASS independent bar-X/band-Y, optional confidence bounds, kind-aware markers, histogram physical/count axes |
| `series_kind_histogram` | Existing PlotSpec/Curve Source typed schema and native C++ scientific model | plot-public-04 + plot-gui-04; exactint64 grouping; independent-unit displacements plot-crosscuts-03; plot-properties-03 / plot-properties-gui-01 PASS independent bar-X/band-Y, optional confidence bounds, kind-aware markers, histogram physical/count axes |
| `series_kind_line` | Existing PlotSpec/Curve Source typed schema and native C++ scientific model | plot-public-04 + plot-gui-04; exactint64 grouping; independent-unit displacements plot-crosscuts-03; plot-properties-03 / plot-properties-gui-01 PASS independent bar-X/band-Y, optional confidence bounds, kind-aware markers, histogram physical/count axes |
| `series_kind_line_marker` | Existing PlotSpec/Curve Source typed schema and native C++ scientific model | plot-public-04 + plot-gui-04; exactint64 grouping; independent-unit displacements plot-crosscuts-03; plot-properties-03 / plot-properties-gui-01 PASS independent bar-X/band-Y, optional confidence bounds, kind-aware markers, histogram physical/count axes |
| `series_kind_scatter` | Existing PlotSpec/Curve Source typed schema and native C++ scientific model | plot-public-04 + plot-gui-04; exactint64 grouping; independent-unit displacements plot-crosscuts-03; plot-properties-03 / plot-properties-gui-01 PASS independent bar-X/band-Y, optional confidence bounds, kind-aware markers, histogram physical/count axes |
| `series_kind_step` | Existing PlotSpec/Curve Source typed schema and native C++ scientific model | plot-public-04 + plot-gui-04; exactint64 grouping; independent-unit displacements plot-crosscuts-03; plot-properties-03 / plot-properties-gui-01 PASS independent bar-X/band-Y, optional confidence bounds, kind-aware markers, histogram physical/count axes |
| `series_style` | Unchanged public v1/v2 canonical Graph Series/Variant/PlotSpec authority | REUSED accepted dev099 owner, exact source hashes plot-parity-01; representative actual native lifecycle plot-public-04 / plot-bridge-03 |
| `shared_x_panels` | Existing PlotSpec/CORE Axes/Legend/graphics authorities → native model | plot-crosscuts-03; parent graph-workflow-05; parent worksheet-chart-features-02; plot-remaining-gui-03 (font/layout/grid/restore) |
| `source_row_point_index` | Native bounded display sample + exact raw source IDs; unchanged CORE complete-source selection | plot-selection-01 actual CORE reader and calibrated native raster; no full-source-export claim |
| `stable_variable_identity` | Unchanged public v1/v2 canonical Graph Series/Variant/PlotSpec authority | REUSED accepted dev099 owner, exact source hashes plot-parity-01; representative actual native lifecycle plot-public-04 / plot-bridge-03 |
| `standalone_v2_editor` | Unchanged public v1/v2 canonical Graph Series/Variant/PlotSpec authority | REUSED accepted dev099 owner, exact source hashes plot-parity-01; representative actual native lifecycle plot-public-04 / plot-bridge-03 |
| `transient_2d_curves` | Native snapshot/transient adapter; existing portable Dataset ZIP/Session authority | plot-public-04; plot-grid-04; plot-selection-01; worksheet-model/legacy-plot-04 |
| `transient_2d_overlay` | Native snapshot/transient adapter; existing portable Dataset ZIP/Session authority | plot-public-04; plot-grid-04; plot-selection-01; worksheet-model/legacy-plot-04 |
| `transient_independent_2d_curves` | Native snapshot/transient adapter; existing portable Dataset ZIP/Session authority | plot-public-04; plot-grid-04; plot-selection-01; worksheet-model/legacy-plot-04 |
| `uncertainty_band` | Existing PlotSpec/Curve Source typed schema and native C++ scientific model | plot-public-04 + plot-gui-04; exactint64 grouping; independent-unit displacements plot-crosscuts-03; plot-properties-03 / plot-properties-gui-01 PASS independent bar-X/band-Y, optional confidence bounds, kind-aware markers, histogram physical/count axes |
| `variants` | Unchanged public v1/v2 canonical Graph Series/Variant/PlotSpec authority | REUSED accepted dev099 owner, exact source hashes plot-parity-01; representative actual native lifecycle plot-public-04 / plot-bridge-03 |
| `vector_export` | Native2D C++/Cairo and Native3D same VTK target | plot-public-04; plot-gui-04; plot-remaining-gui-03; actual supervised Python/Octave plot-bridge-03 |

## Registered scientific kinds

| Kind | Actual native owner | Focused evidence |
|---|---|---|
| `auto` | Native2D C++ typed projection + shared native Cairo/Tk painter | plot-public-04 headless actual canonical source; plot-gui-04 real native widget; affected optional-band/distribution properties: plot-properties-03 and real plot-properties-gui-01 PASS |
| `line` | Native2D C++ typed projection + shared native Cairo/Tk painter | plot-public-04 headless actual canonical source; plot-gui-04 real native widget; affected optional-band/distribution properties: plot-properties-03 and real plot-properties-gui-01 PASS |
| `scatter` | Native2D C++ typed projection + shared native Cairo/Tk painter | plot-public-04 headless actual canonical source; plot-gui-04 real native widget; affected optional-band/distribution properties: plot-properties-03 and real plot-properties-gui-01 PASS |
| `line_marker` | Native2D C++ typed projection + shared native Cairo/Tk painter | plot-public-04 headless actual canonical source; plot-gui-04 real native widget; affected optional-band/distribution properties: plot-properties-03 and real plot-properties-gui-01 PASS |
| `step` | Native2D C++ typed projection + shared native Cairo/Tk painter | plot-public-04 headless actual canonical source; plot-gui-04 real native widget; affected optional-band/distribution properties: plot-properties-03 and real plot-properties-gui-01 PASS |
| `errorbar` | Native2D C++ typed projection + shared native Cairo/Tk painter | plot-public-04 headless actual canonical source; plot-gui-04 real native widget; affected optional-band/distribution properties: plot-properties-03 and real plot-properties-gui-01 PASS |
| `band` | Native2D C++ typed projection + shared native Cairo/Tk painter | plot-public-04 headless actual canonical source; plot-gui-04 real native widget; affected optional-band/distribution properties: plot-properties-03 and real plot-properties-gui-01 PASS |
| `bar` | Native2D C++ typed projection + shared native Cairo/Tk painter | plot-public-04 headless actual canonical source; plot-gui-04 real native widget; affected optional-band/distribution properties: plot-properties-03 and real plot-properties-gui-01 PASS |
| `histogram` | Native2D C++ typed projection + shared native Cairo/Tk painter | plot-public-04 headless actual canonical source; plot-gui-04 real native widget; affected optional-band/distribution properties: plot-properties-03 and real plot-properties-gui-01 PASS |
| `box_whisker` | Native2D C++ typed projection + shared native Cairo/Tk painter | plot-public-04 headless actual canonical source; plot-gui-04 real native widget; affected optional-band/distribution properties: plot-properties-03 and real plot-properties-gui-01 PASS |
| `line3` | Native3D C++/VTK geometry and same native scientific figure/target | plot-gui-04 real native consultation; changed sparse labels/palette/retained host plot-remaining-gui-03; canonical rank2 grid plot-grid-04 |
| `scatter3` | Native3D C++/VTK geometry and same native scientific figure/target | plot-gui-04 real native consultation; changed sparse labels/palette/retained host plot-remaining-gui-03; canonical rank2 grid plot-grid-04 |
| `surface` | Native3D C++/VTK geometry and same native scientific figure/target | plot-gui-04 real native consultation; changed sparse labels/palette/retained host plot-remaining-gui-03; canonical rank2 grid plot-grid-04 |
| `mesh` | Native3D C++/VTK geometry and same native scientific figure/target | plot-gui-04 real native consultation; changed sparse labels/palette/retained host plot-remaining-gui-03; canonical rank2 grid plot-grid-04 |
| `contour3` | Native3D C++/VTK geometry and same native scientific figure/target | plot-gui-04 real native consultation; changed sparse labels/palette/retained host plot-remaining-gui-03; canonical rank2 grid plot-grid-04 |
| `trisurf` | Native3D C++/VTK geometry and same native scientific figure/target | plot-gui-04 real native consultation; changed sparse labels/palette/retained host plot-remaining-gui-03; canonical rank2 grid plot-grid-04 |
| `heatmap` | Native3D C++/VTK geometry and same native scientific figure/target | plot-gui-04 real native consultation; changed sparse labels/palette/retained host plot-remaining-gui-03; canonical rank2 grid plot-grid-04 |

## Public Python and Octave bindings

The separate real v4 registration retains the exact34 accepted v3 operation argument/result metadata. `plot-parity-01` compares the actual registrations and lists all34 names; `plot-bridge-03` contains actual supervised **Python COMPLETED and Octave COMPLETED** with native create/read/render/panel-edit/rerender/delete and an unchanged v3 inspection. There is no hidden legacy rendering fallback. The original binding remains byte-identical.

## Scientific and operational limits

- A point index contains the actual bounded rendering sample. Region publication scans the complete source through the existing CORE services. Statistical bins/boxes and contour intersections are derived presentation objects and do not claim invented canonical row IDs.
- Rank-two canonical surfaces use declared Y/X dimensions and bounded hyperslabs. As in accepted v3, a rank-two grid has one surface and cannot carry a family binding; no rank3 or inferred transposition is introduced.
- Nonlinear coordinate/level transforms remain explicitly noninvertible to the existing Region Selection API v1. They are never described as an affine inverse. Multiple-source selection retains the existing per-source-unit compatibility limits.
- Graph Series alignment modes remain declarative. As accepted v3 requires, materialize alignment before combining incompatible time origins. No new alignment algorithm or scientific data rewrite is introduced.
- Native Point-vector capacity receipts exclude allocator bookkeeping,row-string heaps,Tcl input models and painter display lists. Actual process RSS/worker peaks are recorded separately by the dense-source campaign.
- Figure-normalized Graph Annotations retain the existing separate CORE compositor; native base rendering does not burn them twice. Canonical PlotSpec data annotations use native geometry.

## Protected accepted source hashes

- `plot_dataset_api_v1.tcl`: `acdaabbf3a1d68c8ee99435ad7ee28b69e2eb695b83bc8f0cbc7d7f0220f78d7`
- `plot_dataset_api_v2.tcl`: `02dc0265416438924e26641ac8733c6aaa29345febc7f6e7fdd43beab5e1bbc1`
- `plot_dataset_api_v3.tcl`: `af7919d83161111c525407665ec5bd199ebb8487cdb54d2fdcc4067061f1eadd`
- `plot_dataset_3d_api_v1.tcl`: `7a1c239d54de9631f2c92a38a37b69c2c7fd1357704743b5f73ab773ac6738b6`
- `script_bridge_binding.py`: `fa05a05587e5d50be89d0fdc923cf609604d3cf3b3b29880563cd9e68c823c63`


## New native interaction acceptance

| Required selection | Actual owner and identity | Evidence |
|---|---|---|
| Point | Native typed displayed point; exact source-row string and canonical source-series ID take priority | plot-object-hits-02 and real pointer-event plot-object-hits-gui-02 PASS; uint64 `9007199254740993` preserved |
| Series | Same painted polyline/marker/polygon geometry; series identity only | Same focused headless/GUI receipts; no fabricated source row |
| Axis | Same painted tick/axis text geometry or actual panel spine | Same focused headless/GUI receipts; real `x/left/right` axis identity |
| Legend | Same painted legend text/sample/background geometry | Same focused headless/GUI receipts |
| Annotation | Same clipped line/region/text primitive and current panel annotation ordinal | Same focused headless/GUI receipts; data annotation ordinal is a presentation identity |
| Panel / chart / title | Actual panel rectangle, background and Cairo text extents | Same focused headless/GUI receipts; no scientific row identity |

The bounded painter display list is the hit-geometry authority; no secondary hit registry or full scientific point copy is introduced. Text hit testing uses the same Cairo font metrics, anchor and rotation as painting. Hidden or clipped primitives do not supply hits. A changed viewport rejects the stale hit frame until redraw. Native11 affects these interaction receipts only; earlier immutable native06 dense-source and native10 scientific-property receipts retain their original binary hashes.
