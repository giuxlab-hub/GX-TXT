# GX-TXT

GX-TXT is a desktop scientific workbench for working with **experimental measurements from import to interpretation**. It brings oscilloscope CSV captures, spectra, tables, audio, images, documents and geometric data into persistent Sessions as canonical Datasets, preserving variable IDs, units, metadata and provenance.

Within the same Session you can inspect and compare measurements, perform numerical, statistical and spectral analyses or curve fitting, run registered Python and GNU Octave scripts through the Script Bridge, and create scientific 2D/3D plots and interactive viewers. Derived results stay connected to their source Datasets, while independent modules extend the workflow through public CORE APIs.

**Source version:** 0.9.8.10-dev-108  
**License:** GNU GPL-3.0-or-later (see [LICENSE](LICENSE)). Third-party packages and assets retain their applicable licenses.

**Project website:** [GX-TXT on GitHub Pages](https://giuxlab-hub.github.io/GX-TXT/) · [Italian version](https://giuxlab-hub.github.io/GX-TXT/it/).
**Official developer website:** [Giux-Lab](https://giux-lab.it/).
**Online documentation:** [GX-TXT handbook](https://gxtxt.giux-lab.it/).

## Features

- Acquisition and import of tabular, instrument, audio, image, document and geometric data
- Typed canonical Dataset variables with stable IDs, units, metadata, provenance and supported HDF5 storage
- Numerical, statistical, spectral and curve-fitting workflows
- Registered Python and GNU Octave scripts using public GX-TXT API bindings
- Configurable scientific 2D/3D plotting, Viewers and curve workspaces
- Saved Sessions and Projects, portable exchange and modular extension points
- Shared statistical-result interpretation across numeric modules, fitting, scientific viewers and Python/Octave scripts
- Physical model fitting with covariance, resampling, constrained/profile inference, multi-response, surface and spline methods
- Explicit scientific units and coordinate presentation without modifying canonical input data
- Managed exact integer and real/complex numerical transport with preserved shapes and scientific identities
- Interactive digitization with explicitly declared pixel/calibration uncertainty and traceable derived results
- Reproducible public example workflows for large data, STFT, 3D terrain and residual validation
- Typed scientific Dataset Preview predicates and independent grouping that preserve full int64 values, curve identities and metadata provenance
- Integrated Curve Digitalizer 2.0.3 and optional Scientific Image Inspector 0.4.1, using public CORE services for calibration, uncertainty and image publication
- Viewer-requested single-module Analysis through the existing queue and guided Signal forms backed by public operation schemas
- Unified Session Workspace and Viewer controls with guarded Save, Discard and Cancel, independent searchable Viewer manuals and persisted package/script preferences
- Curve Workbench support for shared proportional coordinate dimensions without changing Native3D physical length requirements
- Session Script Jobs with inspected job history, reviewed reruns and paged logs
- Complete Dataset Notes, Metadata, Variables, Technical Details and Temporal Sets export to TXT/PDF
- Shared Viewer commands, shortcuts, named Workspaces, History and optional disposable display caches
- Curve fitting with reversible positive input translation, configurable panels and scientific provenance
- Interactive Curve Builder with Family/Member filtering, independent Full/Selected source graphs and optional point-order review
- Plot Dataset 3D with backend-neutral Table Stream access to HDF5 and CSV scientific data
- Scientific Worksheet 2.0: native virtual-grid editing, exact Dataset identities, formulas, named ranges, saved Workbook documents and canonical publication
- Additive Plot Dataset v4: Native2D/Native3D plots, typed source selection, scientific Graphs/Clone and viewer-safe generated snapshots
- Editable Worksheet scientific charts with exact data lineage, immutable derived Datasets and managed plot representation
- Native2D view-scoped scientific axis labels, intervals and unit-aware presentation without modifying source values
- CORE same-owner automatic replacement provider retention, without bypassing Dataset Publication ownership or immutable source guards
- Per-field/per-key Dataset Metadata contributor provenance and actual source-contributor groups
- Retained Native2D scientific Preview curve visibility without recomputing original numeric bounds or reallocating plot buffers
- Public Viewer GUI Integration Manifest v1 for shared action toolbar, inspector, Workspace, History and contained selectors
- Scientific Worksheet 2.1 with guided canonical Dataset binding, spreadsheet-style navigation/fill/presentation and synchronous bounded Filter Views
- Worksheet-managed Script Jobs, saved script sources, guarded proposal Apply and portable original-Session resources
- Registered remote compute-node execution with mutual TLS, trusted provider allowlists, Script Job ownership, bounded verified resource staging and controlled result import
- Remote canonical Dataset consultation via bounded typed binary ranges without automatically downloading whole scientific files
- Background Dataset Preview preparation with progress/cancellation, retained visibility, exact source guards and disposable SHA-verified cache; modified settings require explicit Render
- A grouped Viewer catalog with distinct scientific SVG/PNG artwork, persisted enablement and dependency checks independent of Analysis membership
- Reusable Viewer GUI host and source-dialog ownership shared with Curve Workbench and Replicate, including guarded History, Workspace, focus and mapped popups
- Viewer Interface Builder: native UI design, preview, reversible edits and deterministic installable Viewer packages with independent handwritten scientific handlers
- Project groups and hierarchical Session navigation with authority-guarded move, drag/drop and source preservation
- Scientific Print/PDF studio with exact Dataset tables, native graph/annotation composition and managed CUPS discovery/submission
- Official Signal Analysis and Statistical Analysis Viewers, with independent public Viewer APIs and GUI-disabled scientific service paths
- Built-in HTML document viewing and rendered Markdown/XML access with inactive scripting, remote resources and restricted document presentation
- Shared source-code editor services, syntax presentation, structural import and exact tracked dirty/Undo/Redo state for Session Python and Octave scripts
- Native Python and GNU Octave debugging with managed Jobs, bounded stack/variable observations, source revision checks and explicit cancellation
- Python environment and import assistance, canonical source publication and read-only Dataset source previews
- Independent Program output/stderr and diagnostic streams, exact byte-preserving export and Results checkbox-based consultation
- Shared Script Workspace layout and debugger pane controls across Python and GNU Octave, with session-aware editing and preserved user libraries
- Native 3D GUI Host v2 with independently owned Viewer components and retained native scientific renderer
- Temporary RAM-only Native2D and Plot v4 displays for Viewer design and interactive previews, without creating scientific Datasets
- Restricted C++ Viewer Development API v1 with fixed SDK, Clang policy checks and managed out-of-process native execution under bounded project-write grants
- Official Viewer development workspace and bounded native example Viewers, retaining separate public API contracts and explicit execution limitations
- Circuit Workbench for integrated native 2D electronic diagrams, typed component properties, public scientific netlist/sweep services and source-aware plots through CORE
- Reusable public icon catalogs, Viewer component profiles, visibility and structured scientific controls for Interface Builder and installable Viewers
- Managed restricted-C++ debugger and reproducible viewer GUI tests with bounded public API capability checks
- Updated Python/Octave Script Workspace manuals, canonical Help/About and script-source life-cycle handling
- Numeric 1.63 managed captured expressions and split-complex outputs, Plot Dataset 4.2.2 retained native frames and source cursor/axis behavior
- Managed registered local scientific solver Jobs and authorized scientific source I/O with Session-bound publication, cancellation and complete retained provenance
- Planar static electromagnetic FEM using Gmsh/GetDP and native 2D/3D field plotting with exact mesh and source identities
- Fitter panel configuration, shared documentation browsing and bounded unit-aware mathematical functions through public Numeric operations
- Optional Mathematics Explorer Viewer for real functions, roots, intersections and extrema; no claim of completeness from finite numerical sampling
- Managed native image-local ROI, layers, masks and transparent appearance; native planar profiles can return to their original 3D Workspaces
- Replicate Curve Analysis 16.1 and the Replicate / Consensus Curves Viewer 1.1 build on shared CORE Numeric/statistical services, with real Dataset/Variable source identities and scientifically qualified repeatability studies. Unsupported covariance-aware/interval estimators remain unavailable.

Available capabilities depend on the installed modules and their optional runtime dependencies.

For current scientific workflows and controls, start with [Circuit Workbench manual](plugins/modules/viewer.circuit_workbench/MANUAL.md), [Viewer GUI design](docs/api/VIEWER_GUI_DESIGN_v1.md), [Viewer Development](docs/api/VIEWER_DEVELOPMENT_API_v1.md), [Native3D GUI Host v2](docs/api/NATIVE_3D_GUI_HOST_API_v2.md), [Native Plot display](docs/api/NATIVE_PLOT_DISPLAY_API_v1.md), [Script Workspace GUI Host](docs/api/SCRIPT_WORKSPACE_GUI_HOST.md), [Source/Script editor API](docs/api/SOURCE_SURFACE_API_v1.md), [Python environments](docs/api/PYTHON_ENVIRONMENT_API_v1.md), [XML documents](docs/api/XML_DOCUMENT_API_v1.md), [dev-106 user workflows](docs/DEV106_USER_WORKFLOWS.md), [Viewer Interface Builder](docs/api/VIEWER_GUI_DESIGN_v1.md), [Project organization](docs/api/PROJECT_ORGANIZATION_v1.md), [Scientific Print/PDF](docs/api/PRINT_DOCUMENT_API_v1.md), [Scientific Studio workflows](docs/guides/SCIENTIFIC_STUDIO_WORKFLOWS.md), [Scientific Execution and compute nodes](docs/api/SCIENTIFIC_EXECUTION_API_v1.md), [Dataset Preview](docs/api/DATASET_PREVIEW_API_v1.md), [Replicate / Consensus Curves](plugins/modules/viewer.replicate_curve_analysis/MANUAL.md), [Replicate scientific API](docs/api/CURVE_REPLICATE_ANALYSIS_API_v1.md), [Worksheet 2.1 public extensions](docs/api/SCIENTIFIC_WORKSHEET_DEV102.md), [Viewer GUI Integration Manifest](docs/api/VIEWER_GUI_HOST_API_v1.md), [Plot Dataset v4 API](docs/api/PLOT_DATASET_API_v4.md) and [public tutorials](docs/guides/tutorials_dev097/index.html).

## Getting started

On a system with the required Tcl/Tk and scientific runtimes:

```bash
wish gxtxt_pipeline.tcl
```

Create or open a Session; import inputs with Acquisition; inspect data under Datasets; configure scientific modules and Script Bridge jobs; view results using Plots and Viewers.

See the [Getting Started guide](docs/help/getting_started.md) for the basic workflow.

## Requirements and platform notes

- A Tcl/Tk installation providing `wish` is required for the desktop interface.
- Python 3 and GNU Octave are required for the respective Script Bridge and scientific-module workflows; NumPy, SciPy, Matplotlib and other optional dependencies depend on the enabled modules.
- Bundled Linux native libraries and executables target compatible Linux installations. Native components are **not** portable Windows binaries; rebuild and validate them for any different platform/ABI. See the component `CMakeLists.txt` files and [Native 3D runtime dependencies](plugins/modules/viewer.native_3d/LINUX_RUNTIME_DEPENDENCIES.md).
- This repository is a source distribution, not an installer with all scientific runtimes included. Configure system dependencies and use a disposable test Session before processing real data.

See the [architecture overview](ARCHITECTURE.md) for subsystem boundaries, extension points and build guidance.

## Source layout

| Path | Purpose |
| --- | --- |
| `app/` | Application GUI and workflow controllers |
| `core/` | CORE services, data interfaces and language bindings |
| `plugins/` | Scientific modules, acquisition providers and model descriptors |
| `plugin_packages/` | Plugin package distributions |
| `session_generator_libraries/` | Scientific Session generator definitions and resources |
| `docs/api/` | Public API contracts |
| `docs/help/` and `docs/guides/` | User and developer documentation |
| `examples/` | Examples and reusable resources |

## Public API documentation

- [Canonical Datasets](docs/api/CANONICAL_DATASET_API_v2.md)
- [Dataset publication](docs/api/DATASET_PUBLICATION_API_v2.md)
- [Table Stream](docs/api/TABLE_STREAM_API_v3.md)
- [Plot Dataset](docs/api/PLOT_DATASET_API_v3.md)
- [Module API](docs/api/MODULE_API_v1.md)
- [Python scripting](docs/api/PYTHON_SCRIPT_CLIENT_v1.md)
- [GNU Octave Script Bridge](docs/api/OCTAVE_SCRIPT_BRIDGE_API_v1.md)
- [Plugin packaging](docs/guides/PACKAGING_PLUGIN.md)
- [Numerical API](plugins/modules/math.numeric/NUMERIC_API_v1.md)
- [Architecture and developer orientation](ARCHITECTURE.md)
- [Release history](CHANGELOG.md)

## License and scientific data

GX-TXT's own framework sources are licensed under GNU GPL version 3 or later. Independently licensed third-party software and scientific data retain their respective terms; see [third-party notices and source attribution](THIRD_PARTY_NOTICES.md) and nested package license files.

Scientific Sessions, HDF5 Datasets, experiment logs and private configurations are separate from this source repository and require their own backups. The public source distribution intentionally excludes internal development documents, original user data, validation evidence and non-redistributable teaching assets.

Contributions should preserve API contracts, numerical behavior, provenance, and applicable licenses. Start with the [module authoring guide](docs/guides/SCIENTIFIC_ANALYSIS_AUTHORING_GUIDE.md) and [plugin packaging guide](docs/guides/PACKAGING_PLUGIN.md).
