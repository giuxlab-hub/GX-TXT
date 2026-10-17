# Official dev098 plugin packages

`official_dev098/` contains separately identified Linux candidates for supplied
Curve Digitalizer2.0.3 and optional Scientific Image Inspector0.4.1, with SHA-256
sidecars. The original user archives remain unchanged outside the distribution.
Source provenance and the narrowly necessary Digitalizer adapter correction are
documented in `docs/reports/DEV098_INTEGRATION_AND_EVIDENCE.md`.

Inspector remains core=0/default_enabled=0 and uses the existing Plugin Manager.
Digitalizer retains its supplied bundled CORE descriptor. Exactly the two retired
Viewer IDs have no installed modules or installable ZIP in this distribution.
Other earlier package inventories below are retained historical documentation;
the installed module directories and official_dev098 candidates identify current
sources for the two supplied products.

# Managed plugin packages included with GX-TXT v0.9.3

GX-TXT modules are defined under `plugins/modules/`; the installed descriptors and source files are the authoritative module implementations.

This directory contains selected distributable plugin packages or platform-specific bundles. Plugin installation, validation and upgrades follow the public [Plugin Install API](../docs/api/PLUGIN_INSTALL_API_v1.md) and [Plugin Bundle API](../docs/api/PLUGIN_BUNDLE_API_v1.md).

For package structure and versioning, see the [Plugin Packaging Guide](../docs/guides/PACKAGING_PLUGIN.md).

All three packages use `plugin-package.ini` / Plugin Install API v1 and require
GX-TXT v0.9.3 or newer.

A same-version ZIP is intentionally rejected by **Update selected...** because
an update must have a newer plugin version. After uninstalling a plugin, use
**Install plugin...** and select the corresponding ZIP from this directory.

GX-TXT v0.9.3.2 also supports atomic multi-plugin ZIPs through Plugin Bundle API
v1. The standalone packages in this directory remain ordinary Plugin Install API
v1 packages and do not need to be converted.

## v0.9.4 plotting packages

`plot.dataset` is now bundled as the CORE scientific dataset plotter and does not require a separate install. `plot.dataset_xy` v3 is legacy/deprecated and is retained only as an optional standalone package under `deprecated/plot.dataset_xy_v3_gxtxt093_DEPRECATED.zip`. New development must target `plot.dataset`.

## 0.9.8.10-dev external plugin state

`external_plugins.tsv` records the installed, managed external modules in this development tree only. Historical ZIP inventories remain historical and may include superseded versions. Blank registry timestamps and package filenames for adopted modules mean their original Plugin Install provenance is unknown; the registry records current identity and management status.

`current_dev/` contains the corrected X-01 through X-04 packages and the reviewed 0.9.8.10-dev plugin integration packages. These ZIPs use the flat root layout documented by Plugin Install API v1. The Curve Digitalizer ZIP records the coherent 1.2.1 CORE module source; other new/update ZIPs were installed through Plugin Install API. The installed module directories are the current package sources for the other catalog entries. These are development packages, not GX-TXT release archives.

The post-3D development tree includes `plot.dataset_3.9.0.zip` and
`viewer.native_3d_0.8.0_linux_x86_64.zip` with SHA-256 sidecars. These are
source-matched development copies of bundled modules, not entries in
`external_plugins.tsv` (which records managed external plugins). The Native
3D ZIP carries Linux binaries and is not a Windows package.
`acq.geometry_3d_1.1.0.zip` is the source-preserving STL/OBJ/STEP/VTU/VTP/VTI
Acquisition package. Historical `acq.geometry_3d_1.0.0.zip` is retained unchanged.

## 0.9.8.10-dev API completion packages

`current_dev/` also contains source-matched update ZIPs and SHA-256 sidecars
for the modules changed by API completion, including `plot.dataset_3.10.0.zip`
and Linux `viewer.native_3d_0.9.0_linux_x86_64.zip`. Earlier version ZIPs
remain historical and unchanged. Updated external-plugin registry rows point
to the new version where a managed ZIP is the installed package source.

## Registered Script Analysis integration

`current_dev/analysis.octave_script_1.2.0.zip` introduced the Session
registered-script Analysis workflow. The 1.1.2, 1.1.3 and 1.2.0 ZIPs remain
historical.

## Multi-language Script Analysis integration

`current_dev/analysis.octave_script_1.2.1.zip` and
`current_dev/analysis.python_script_1.0.0.zip` are the current development
packages for the shared Script Library. Both are normal Plugin Install API v1
packages. The earlier Octave packages remain historical.

## Linux STEP cold-import performance

`current_dev/viewer.native_3d_0.9.1_linux_x86_64.zip` is the source-matched
development package for the OCCT 7.8.1 STEP transfer lookup optimization.
Earlier Native 3D ZIPs remain historical. The package retains the Linux
runtime dependency and RUNPATH model described in the module documentation.

## Script Module Builder official tool

`current_dev/tool.script_module_builder_1.0.1.zip` is the source-matched package for the protected official Modules-page Builder tool. Its module descriptor and package version are 1.0.1. The 1.0.0 ZIP remains historical. The runnable Builder is in `plugins/modules/tool.script_module_builder/runtime/builder.py`; the root `tools/gxtxt_module_builder.py` is a command-line entry point. Generated test-only Analysis ZIPs stay under `validation/gxtxt_module_builder/packages/` and are not part of the public scientific plugin catalog.

## Task 003 P1/P2 and scientific viewer packages

`current_dev/` contains flat Plugin Install ZIPs for `analysis.octave_script_1.3.0`, `plot.dataset_3.11.0`, Linux `viewer.native_3d_0.9.3_linux_x86_64`, `viewer.interactive_curve_builder_1.0.0`, `viewer.section_profile_1.0.0`, and `acq.touchstone_1.0.0`, each with a SHA-256 sidecar. Matching ordered `external_plugins/archives` and `expanded` copies have byte-identical members. Plot Dataset and Native 3D remain bundled providers despite source-matched install ZIPs; the other four modules are listed in `external_plugins.tsv`. Historical packages remain unchanged.

## Official dev102 packages

`official_dev102/` contains Numeric 1.62.0, Plot 4.2.0, Replicate 16.0,
Worksheet 2.1.0 and CORE Replicate Viewer 1.0.0, all requiring dev102.
Their module source/checksum manifests match the framework; historical packages remain.

## Official dev102 packages

`official_dev102/` contains Numeric 1.62.0, Plot 4.2.0, Replicate 16.0,
Worksheet 2.1.0 and CORE Replicate Viewer 1.0.0, all requiring dev102.
Their module source/checksum manifests match the framework; historical packages remain.
