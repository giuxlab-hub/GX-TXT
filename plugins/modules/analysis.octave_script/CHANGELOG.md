# Changelog

SPDX-License-Identifier: GPL-3.0-or-later

## 1.3.0

- Unified new Workspace scripts with Script Registry identities used by Script Library and normal Analysis.
- Added explicit registration of readable legacy Interactive Documents while retaining their sources.
- Verified create, run, edit, revision/SHA, reopen and rerun through production controls.

## 1.2.1

- Kept Octave Session scripts compatible with the shared multi-language Script Registry and language-filtered Analysis selector.
- Recorded source provenance alongside registered execution metadata while retaining the existing Octave runner and external `.m` mode.

## 1.2.0

- Made Session-owned registered scripts selectable in the normal Analysis configuration by stable `session:<id>` reference.
- Routed registered Analysis runs through CORE Script Execution, with SHA-256 verification, immutable run snapshots, registry metadata, required-API preflight and preserved provenance.
- Restored normal Analysis activation while keeping the optional CORE Script Workspace separate.
- Retained standalone `.m` execution as explicit `external_file` compatibility mode and migrated old path-only Session configurations.
- Exposed complete Session script metadata in the Analysis selector and Session Script Explorer.
- Surfaced the real Octave diagnostic in the Analysis error dialog.

## 1.1.3

- Use public Session Inspection for editor Session context.

## 1.1.2

- Aligned the package and installed Script Workspace replacement metadata.

## 1.1.1

- Added the required CORE Octave I/O search path to the packaged runner so generic bridge calls resolve in a normal Session.
- Validated a real packaged-module script against registered `CANONICAL_DATASET_API_v2` operations, including structured Dataset description and range transport.
- Raised the required framework to GX-TXT 0.9.8.06, which supplies `OCTAVE_SCRIPT_BRIDGE_API_v1`.

## 1.1.0

- Added the Session-persistent **Octave Script Workspace** Viewer.
- Added named research-script documents through Interactive Document API v1.
- Added UTF-8 source editing, line numbers, undo/redo, scrolling, search, go-to-line and syntax-oriented highlighting.
- Added `.m` import/export and save-copy workflows.
- Added bridge snippets and in-editor generic API quick reference.
- Added optional working-directory configuration for real research scripts that use relative resources.
- Added optional source-script-directory insertion into the Octave search path for helper `.m` functions.
- Added semicolon/comma-separated required-API preflight before user code runs.
- Expanded the run report with GNU Octave version, bridge transport version, registered API IDs, source aliases, arguments and execution-directory information.
- Preserved exact executed-source snapshots and SHA-256 provenance.
- Kept editing/persistence separate from execution: the Workspace exports normal `.m` files consumed by the standard analysis runner.

## 1.0.0

- Added the first `analysis.octave_script` module.
- Added user-selected `.m` execution through the generic `OCTAVE_SCRIPT_BRIDGE_API_v1` contract.
- Added standard Analysis Source aliases for optional Dataset context.
- Added exact script snapshot and SHA-256 provenance in the run report.
- Added explicit failure when the required CORE bridge is unavailable or incompatible.
