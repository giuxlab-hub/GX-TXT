# GX-TXT Architecture

**Reference source:** GX-TXT 0.9.8.10-dev-095  
**Framework license:** GPL-3.0-or-later

GX-TXT is a modular desktop framework for scientific acquisition, Dataset management, numerical analysis, scripting and visualization. It is not a CFD solver, data-acquisition instrument or generic execution service.

## Major components

| Component | Responsibility |
| --- | --- |
| `gxtxt_pipeline.tcl` and `app/` | Tcl/Tk entry point, Session navigation, workflow controllers and GUI |
| `core/tcl/` | Framework-owned APIs, module discovery, Dataset/Session authorities, publication and workflow orchestration |
| `core/python/`, `core/octave/`, `core/script_bindings/` | Language-facing services, scientific execution and Script Bridge bindings |
| `core/native2d/`, `core/native3d/`, `core/nativegui/` | Shared native geometry, graphics and host integration |
| `plugins/modules/` | Independently discoverable acquisition, analysis, numerical, plotting and viewer modules |
| `plugins/models/`, `plugins/instruments/`, `plugins/analysis_definitions/` | Model, instrument and declarative-analysis descriptors |
| `services/` | Shared supporting services |
| `session_generator_libraries/` | Optional deterministic scientific teaching/session generators |
| `docs/api/` | Published public contracts, not private implementation interfaces |
| `examples/` | Source examples and non-destructive sample workflows |

## Scientific data flow

```text
Instrument/file/synthetic fixture
  -> Acquisition Handler
  -> Canonical Dataset + Variable Schema + Metadata + provenance
  -> Analysis Source / Dataset selection
  -> scientific module + shared numerical services
  -> Dataset Publication + associated artifacts
  -> plot.dataset / Graph Provider / Viewer Provider
  -> persistent Session and optional export
```

The canonical Dataset identity consists of stable Dataset and Variable IDs, not display labels or CSV headers. Source inputs and scientific lineage must remain distinguishable from derived datasets, plots and presentation caches. Projects organize Experiments/Sessions without replacing the Dataset authority.

## Public API and extension boundaries

- Scientific modules discover and use public CORE APIs instead of opening internal Dataset storage paths.
- Reusable numerical operations belong to `math.numeric` / the public NUMERIC API. Analysis modules own scientific methods and domain-specific meaning.
- Static scientific plots use `plot.dataset` and the Graph Provider. Interactive 2D/3D applications use the corresponding native/viewer contracts where appropriate.
- Scripts use registered Python/Octave Script Bridge interfaces and the normal Dataset/publication mechanisms.
- Module installation and packaging use the declared plugin contracts; a Session generator is independent of the module it demonstrates.
- Session state and original scientific data are not redistributed as part of the public framework source.

Starting references: [Module API](docs/api/MODULE_API_v1.md), [Canonical Dataset API](docs/api/CANONICAL_DATASET_API_v2.md), [Dataset Publication](docs/api/DATASET_PUBLICATION_API_v2.md), [NUMERIC API](plugins/modules/math.numeric/NUMERIC_API_v1.md), [Plot Dataset API](docs/api/PLOT_DATASET_API_v3.md), [Python Script Bridge](docs/api/PYTHON_SCRIPT_CLIENT_v1.md), [Octave Script Bridge](docs/api/OCTAVE_SCRIPT_BRIDGE_API_v1.md), and [Plugin Install API](docs/api/PLUGIN_INSTALL_API_v1.md).

## Platforms and builds

The accepted release is primarily validated on a Debian/Linux scientific runtime with Tcl/Tk, Python, GNU Octave and optional scientific libraries. The source tree also contains platform-specific native artifacts, build configurations and runtime dependency notices; a bundled Linux shared object is **not** a Windows executable.

Use the local `CMakeLists.txt` and native component documentation for builds of `core/native2d/`, `core/native3d/` and relevant viewer modules. CMake, a compatible C/C++ compiler and development headers for the selected backend are needed when rebuilding native components. Python, Octave and third-party packages are external prerequisites, not embedded in the framework.

An example out-of-tree build of the platform-independent Native2D library is:

~~~sh
cmake -S core/native2d -B build/native2d -DBUILD_TESTING=OFF
cmake --build build/native2d --config Release
~~~

Native3D additionally requires compatible VTK 9 and OpenSSL development packages; OCCT is optional for selected B-Rep/STEP capabilities. Its native test option `GX3DE_BUILD_TESTS` is OFF by default; enabling it in this public source checkout requires adding independently redistributable validation fixtures because private release-evidence sources are deliberately omitted. The Native2D build already skips missing optional validation files.

Opening the Tcl/Tk GUI, running scientific jobs and verifying native rendering require a configured target machine. Static source checks alone are not evidence of successful execution on Linux or Windows.

## State, testing and contribution rules

Scientific Sessions, Projects, imported instruments, source data and workspace paths remain outside this source release. Public examples must be synthetic or redistributable with proper attribution. Tests that create Sessions or modify configuration should run in a disposable workspace, never against researchers' active data.

Before changing a public API, review the current contract and compatibility requirements. Preserve input data, units, numerical semantics and provenance. See [module authoring](docs/guides/SCIENTIFIC_ANALYSIS_AUTHORING_GUIDE.md), [plugin packaging](docs/guides/PACKAGING_PLUGIN.md), and [third-party notices](THIRD_PARTY_NOTICES.md).
