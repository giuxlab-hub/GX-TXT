# Module Builder module inventory — GX-TXT 0.9.8.10-dev

| ID | Version | Role | Location |
|---|---:|---|---|
| `tool.script_module_builder` | 1.0.1 | Protected official Modules-page development tool | `plugins/modules/tool.script_module_builder/`; source-matched `plugin_packages/current_dev/tool.script_module_builder_1.0.1.zip` |
| `validation.generated.octave_analysis` | 0.1.2 | Test-only generated Octave Analysis fixture | `validation/gxtxt_module_builder/packages/` |
| `validation.generated.python_analysis` | 0.1.0 | Test-only generated NumPy Analysis fixture | `validation/gxtxt_module_builder/packages/` |
| `validation.generated.python_file_output` | 0.1.0 | Test-only generated STEP file-publication fixture | `validation/gxtxt_module_builder/packages/` |

The three generated Analysis modules are installed only into disposable framework copies during acceptance. They are absent from the production scientific module catalog. Error, missing-API and optional public-API validation ZIPs share the same test-only directory. Normal module discovery and Plugin Install own the generated modules; no module-specific CORE registration is needed.

Dev109 ongoing CAD integration: `plugins/modules/viewer.3d_workbench/api/workbench_3d_builder_forms_v1.tcl` is the original scientific owner's finite
purpose-form router. Host32 in the shared Builder bridges to its public
`guiCommand`; it does not expose buildPanel, callbacks, paths or geometry
payloads. Existing native geometry, structural History, measurement/constraint,
organization/comparison, Recipe/Extension and planar-return owners remain sole
authorities. Actual metadata admission covers44 new commands and7 negative
boundaries; installed scientific/CAD/all45 acceptance remains pending.

### Dev109 compiled Viewer artifact ownership

| Existing owner | Responsibility |
|---|---|
| `core/python/gxtxt_viewer_development.py` | Development validation, explicit Build, source-bound artifact reuse and ordinary compiled-package Export |
| `core/tcl/viewer_development_api_v1.tcl` | Public Builder/Workspace operations and installed Viewer dispatch; installed execution does not enter development Build |
| `core/python/gxtxt_viewer_native_worker.py` | Execute the admitted distributed native binary through the existing process and Session lifecycle |
| `core/tcl/plugin_install_api_v1.tcl` | Normal package inspection and install/update, including the packaged binary and interface/provenance records |

Build dependency identity uses the five existing framework-relative SDK,
adapter, policy, compiler and toolchain-manifest roles with their exact content
hashes. Historical absolute receipt prefixes resolve to those same roles;
checkout relocation alone does not require compilation. Flags, build recipe,
validation owner and recorded included-header hashes remain checked. Source,
binary or semantic callback-contract changes still invalidate artifact reuse.

An unchanged callback contract also permits package-version and presentation
updates. Export retains the genuine compilation receipt in
`review/original-build.json` and records the current source/interface/project
admission separately. Plugin Manager installs that compiled package. Installed
startup and GUI events execute `native/viewer.so` without requiring a compiler;
missing or incompatible binaries report an error through the existing owner.
No second build, runtime, scientific storage or presentation service is added.

The public contract and exact reuse boundaries are documented in
[Viewer Development API v1](../api/VIEWER_DEVELOPMENT_API_v1.md).
The focused component regression is registered in
`validation/build_artifact352/CATALOG.md`; ordinary public Export and the cold
installed EM0.3.3 Help workflow have separate independent receipts. These scoped
checks do not grant acceptance to the entire integrated release.
