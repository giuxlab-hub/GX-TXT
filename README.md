# GX-TXT scientific workspace

The distribution identity is in `VERSION.txt`. Acceptance evidence, current limits and release handoffs are under `docs/reports/`.

GX-TXT organizes Projects, Experiments and Sessions around canonical scientific Datasets, explicit analysis recipes, native graphical views and persistent Workspaces.

Start the Debian desktop application from this directory:

```sh
wish gxtxt_pipeline.tcl
```

Use Acquisition to import source data, Dataset to inspect Variables and metadata, and the grouped Viewers catalog to open scientific tools. Configuration → Modules separates scientific services from optional Viewer presentation. Dataset Preview prepares standard native representations asynchronously and keeps disposable results under the Session's Preview Cache page. Explicit Render preserves chosen axes, filters, grouping and calibration; controls alone retain the previous successful frame.

Projects provide logical Project namespaces and per-Project Session groups,
with hierarchical search, drag-and-drop and keyboard Cut/Paste. Organization keeps
scientific Session directories and Dataset identity in place.

The existing Print / PDF tab assembles a reviewed multi-page PDF from canonical
tables, Graphs, original images/PDF/text and declared metadata representations.
Its page canvas and thumbnails render that same PDF. CUPS discovery/options are
asynchronous; Save PDF stays usable while a printer query is pending or fails.
See the [Print Studio guide](docs/api/PRINT_DOCUMENT_API_v1.md).

Open **Viewers → Viewer Interface Builder** for its native Designer and Preview.
Edit public CORE components, import a declared Viewer, compare real interfaces,
record/replay finite GUI tests and generate installable Viewer packages while
preserving independent handwritten handlers. See the
[Builder manual](plugins/modules/viewer.interface_builder/MANUAL.md) and
[design/laboratory API](docs/api/VIEWER_GUI_DESIGN_v1.md).

Builder compiles new or changed C++ source and retains its compiled artifact.
Installable Viewers distribute that binary; installed startup and ordinary
interface events execute it without a development compiler. Local tool selection
takes effect before the next Canvas action. See the
[development lifecycle](docs/api/VIEWER_DEVELOPMENT_API_v1.md).

The scientific tools include the graphical
[Circuit Workbench](plugins/modules/viewer.circuit_workbench/MANUAL.md),
[3D CAD Workbench](plugins/modules/viewer.scientific_3d_workbench/MANUAL.md),
and [Electromagnetics Studio](plugins/modules/viewer.electromagnetics_studio/MANUAL.md).
Circuit and Electromagnetics appear under Simulation & Modeling. The CAD successor
retains the original scientific document owner and the deprecated legacy Viewer.
Electromagnetics supports linear static planar 2D electric and magnetic models
using the managed Gmsh/GetDP providers. Its illustrated scientific guide and the
CAD illustrated guide are separate downloads, outside the framework archive.

Configuration → Execution registers authenticated compute nodes and chooses local, automatic or explicit-node execution. Remote scientific Jobs use the same public execution API and node-local Supervisor. Remote canonical Dataset handles support bounded typed consultation; a complete local import is explicit.

Start with the [scientific workflow guide](docs/guides/SCIENTIFIC_STUDIO_WORKFLOWS.md), [Dataset Preview API](docs/api/DATASET_PREVIEW_API_v1.md), [Replicate manual](plugins/modules/viewer.replicate_curve_analysis/MANUAL.md), [Worksheet manual](plugins/modules/viewer.scientific_worksheet/MANUAL.md), and [compute-node operation](docs/api/SCIENTIFIC_EXECUTION_API_v1.md). Viewers expose rendered Help through their Help menu and F1.

Public contracts are documented under `docs/api/`; CORE ownership is recorded in `docs/architecture/AUTHORITY_CATALOG.yaml`. Read `SCRIPT_CATALOG.md` before running validation or deployment scripts. Validation recipes require fresh isolated output directories and identify their own version scope and side effects. `VERSION.txt` identifies the installed distribution; release reports and exact acceptance limitations live under `docs/reports/`. Chronological distribution notes are preserved in `DISTRIBUTION_RELEASE_HISTORY.md` and `CHANGELOG.md`.
