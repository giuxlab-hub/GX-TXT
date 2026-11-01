## 1.8.3 — DEV111-P033

Add optional in-editor Project creation and management through the existing
Script Registry, plus whole-project provided and consumed API inspection with
exact source navigation. Preserve standalone scripting and the shared Runner.

## 1.8.2 — DEV111-P030

Per-file canonical Markdown Notes, image-preserving source copy/project transport, primary menu editing and retained Notes layout.

# 1.8.1

- Primary Project menu, File Save All and keyboard shortcuts replace the duplicated source toolbar and selector.
- Native source tabs have separate close targets, qualified duplicate identities and overflow navigation; inactive dirty close preserves focus and revision guards.
- Queued tree selections follow the active source; Focus source uses its actual shared Source Surface.

# 1.8.0

- Existing Script Registry now supports whole-project source manifests, atomic Save All, frozen Session/Job copies and native helper-file debugging.
- Shared source tabs retain independent buffers, Undo/search/dirty identity, an actual project tree and read-only historical snapshots.
- The common Runner supports typed invocation-only Add/Edit/Remove and optional mixed-schema parameter Datasets; source declarations are statically inspected and runtime-safe.

# 1.7.2

- Shared reviewed Runner supports independent input namespaces and typed canonical parameter Dataset Save/Load.
- View Parameters independently controls declaration visibility while retaining debugger state.

## 1.7.0 — dev108

Canonical Help About, comprehensive illustrated manual and bounded public argument binding; shared source editing and library refresh corrections. Asynchronous Octave Pause remains explicitly unsupported.

# 1.6.0 — 2026-10-18

Shared independently controlled panes, repaired physical gutter, genuine GNU Octave native frames/steps and honest unsupported asynchronous Pause, no-Session authoring and illustrated examples/manuals.

# 1.5.0 — Debian dev106

Unified public source/document, managed execution and scientific Viewer integration. See the module manual and dev106 acceptance ledger for exact tested scope and remaining limits.

## 1.4.1 — 2026-10-17

Declare distinct native-resolution scientific catalog artwork, short title and semantic group through the existing Viewer Provider descriptor.

# Changelog

## 1.4.0 — dev097

- Shared CORE editor controls and Runner integration.
- Reconciled module, package and current producer identities for this release.

## Framework dev097 — 2026-10-13

- Replaced two toolbar rows with File/Edit/Run/Help using CORE menu layout.
- Added focus-local UTF-8 selection and atomic paste/undo through shared CORE text controls; property edits track actual values.
- Reused CORE Runner from both languages with explicit dirty-buffer revision choice, no automatic Job submission and a stale-Session guard.

SPDX-License-Identifier: GPL-3.0-or-later

## 1.3.0 — 2026-10-01

- Unified new Workspace scripts with Script Registry identities used by Script Library and normal Analysis.
- Added explicit registration of readable legacy Interactive Documents while retaining their sources.
- Verified create, run, edit, revision/SHA, reopen and rerun through production controls.

## 1.2.1 — 2026-09-30

- Kept Octave Session scripts compatible with the shared multi-language Script Registry and language-filtered Analysis selector.
- Recorded source provenance alongside registered execution metadata while retaining the existing Octave runner and external `.m` mode.

## 1.2.0 — 2026-09-30

- Made Session-owned registered scripts selectable in the normal Analysis configuration by stable `session:<id>` reference.
- Routed registered Analysis runs through CORE Script Execution, with SHA-256 verification, immutable run snapshots, registry metadata, required-API preflight and preserved provenance.
- Restored normal Analysis activation while keeping the optional CORE Script Workspace separate.
- Retained standalone `.m` execution as explicit `external_file` compatibility mode and migrated old path-only Session configurations.
- Exposed complete Session script metadata in the Analysis selector and Session Script Explorer.
- Surfaced the real Octave diagnostic in the Analysis error dialog.

## 1.1.3 — 2026-09-30

- Use public Session Inspection for editor Session context.

## 1.1.2 — 2026-09-28

- Aligned the package and installed Script Workspace replacement metadata.

## 1.1.1 — 2026-09-26

- Added the required CORE Octave I/O search path to the packaged runner so generic bridge calls resolve in a normal Session.
- Validated a real packaged-module script against registered `CANONICAL_DATASET_API_v2` operations, including structured Dataset description and range transport.
- Raised the required framework to GX-TXT 0.9.8.06, which supplies `OCTAVE_SCRIPT_BRIDGE_API_v1`.

## 1.1.0 — 2026-09-25

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

## 1.0.0 — 2026-09-25

- Added the first `analysis.octave_script` module.
- Added user-selected `.m` execution through the generic `OCTAVE_SCRIPT_BRIDGE_API_v1` contract.
- Added standard Analysis Source aliases for optional Dataset context.
- Added exact script snapshot and SHA-256 provenance in the run report.
- Added explicit failure when the required CORE bridge is unavailable or incompatible.
