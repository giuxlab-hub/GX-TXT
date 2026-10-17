# GX-TXT

GX-TXT is a desktop scientific workbench for working with **experimental measurements from import to interpretation**. It brings oscilloscope CSV captures, spectra, tables, audio, images, documents and geometric data into persistent Sessions as canonical Datasets, preserving variable IDs, units, metadata and provenance.

Within the same Session you can inspect and compare measurements, perform numerical, statistical and spectral analyses or curve fitting, run registered Python and GNU Octave scripts through the Script Bridge, and create scientific 2D/3D plots and interactive viewers. Derived results stay connected to their source Datasets, while independent modules extend the workflow through public CORE APIs.

**Source version:** 0.9.8.10-dev-099  
**License:** GNU GPL-3.0-or-later (see [LICENSE](LICENSE)). Third-party packages and assets retain their applicable licenses.

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

Available capabilities depend on the installed modules and their optional runtime dependencies.

For scientific workflows and current controls, see the [integrated scientific guide](docs/guides/INTEGRATED_dev097.md), [Workspace and Viewer controls](docs/guides/WORKSPACE_AND_VIEWER_CONTROLS.md) and [public tutorials](docs/guides/tutorials_dev097/index.html).

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
