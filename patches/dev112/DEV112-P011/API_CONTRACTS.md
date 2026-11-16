# P011 public API contracts

These are current functional contracts. The owner withdrew the earlier
pre-implementation API inventory requirement. This document makes no temporal
inventory claim. Independent execution and source provenance belong to exact
candidate matrices and the packaged public API Catalog.

| Contract | Surface and ownership |
| --- | --- |
| CURVE_VIEWER_API_v2 | Trusted owning GUI host: nativeReceipt, Plot Dataset discovery, open/add, explicit publishPlot and workspaceSave. Source/Graph/Variant/renderer ownership remains CORE. |
| CURVE_VIEWER_API_v1 | Existing datasetIds Script Bridge heuristic retained. open/add delegate supported canonical bindings. Legacy scene snapshot reports GXTXT CURVE_VIEWER LEGACY_SNAPSHOT_UNAVAILABLE rather than fabricating a different shape. |
| PLOT_DATASET_API_v4 | Existing scientific kind/PlotSpec/Graph/Variant/widget/render/export owners. The eight additive host operations are previewSpecSource, previewSpecExportCommand, previewSpecScene, previewSpecAcquire, previewSpecReceipt, previewSpecCamera, previewSpecControls and previewSpecRelease. Camera actions include Fit/Reset. They reuse the original Native3D host and worker; acquisition does not publish. |
| PLOT_DATASET_API_v4 specEquivalent | Validates complete 2D/3D PlotSpecs and compares canonical object-key order through CORE typed codecs/JSON. The shared plot_xyz_spec shape preserves the former Viewer XYZ encoding through its existing alias. Arrays, values and ownership/source fields remain significant; no publication, mutation or Script grant. |
| CURVE_FIT API | Original public fit operations and numerical semantics retained. GUI-only unchanged Preview reuse requires exact successful receipt, settings/selection/source identity and live canonical bytes; explicit Recompute executes the original solver. |
| UI_FIELD_API_v1 | Additive trusted-host uiFieldFormNote appends read-only prose inside an existing owned contained-scroll form; no input/Apply or Script authority. Existing uiFieldInspectionColumnsFit owns measured table fonts/row heights/column widths. |
| Scientific History | Existing capture/restore/commit and auxiliary channel. Layout/view/tabs use bounded auxiliary state; scientific changes preserve full source/fit/resource receipts and existing backup/Clear guards. |
| Native2D Plot receipt | Existing NATIVE_PLOT_BACKEND_v1/API1 adds requested_axis_limits; widgetReceipt returns existing native requested_limits separately from effective aspect-expanded limits. Workspace restore/persistence uses the request, typed render manifests preserve both. No numeric/aspect algorithm or public C ABI change. |
| Native3D | Existing C ABI, geometry/topology/camera/projection/units and explicit margins retained; automatic figure text-band calculation corrected. Exact exports/build/source receipt included. |
| MCP compatibility | Inert original metadata then actual OCTAVE_SCRIPT_BRIDGE_API_v1/API1, compatible transport2/binarydescriptor2/authorized_direct runtime. Optional capabilities derive from actual API IDs/versions/operation sets, with precise missing-contract diagnostics. |

MCP adapter component0.2.0 and SDK2.3.0 are separate from the GX-TXT framework
patch. Standard MCP initialization negotiates SDK-supported handshake versions;
HTTP headers enforce that transport profile. Public framework capabilities are
then checked independently. Authentication, canonical Session grants, author/run
review, resource leases and original API restrictions remain unchanged.
See integrations/mcp/README.md for exact negotiation and supported profiles.

The public API Catalog is rebuilt by its existing trusted packaging owner using
actual declarations and binding provenance. A catalog entry documents a contract;
it does not grant host, Script Bridge or C++ execution rights. New GUI commands
have no implicit generic Script permissions. Original ORION/SII contracts remain
frozen. Complete public module contracts are adjacent to each module/API owner.
