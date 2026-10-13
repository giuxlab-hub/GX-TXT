# Python Script Workspace Viewer API v1

SPDX-License-Identifier: GPL-3.0-or-later

Provider: `analysis.python_script` 1.1.0. The lazy Tk **Python Script Workspace** is a separate Viewer from Octave Script Workspace. Its executable identity is the existing CORE Script Registry (`session:<id>` or `user:<id>`). The viewer adds no registry or execution engine.

The Viewer Provider uses `python_script_editor_tk` and dispatches `open` and `rerender` to `::GX::PythonScriptEditor::viewerDispatch`. Opening requires a current Session. Discovery remains headless; Tk loads only when the viewer opens.

The module adapter provides `workspaceList`, `workspaceRead`, `workspaceSave`, and `workspaceDelete`. These are viewer integration procedures, not a replacement for `SCRIPT_EXECUTION_API_v1`. `workspaceList` and `workspaceRead` accept Python registry records only. `workspaceSave` writes UTF-8 source and metadata through `scriptRegistrySave` or `scriptRegistryUpdate`, preserving stable ID, revision, and SHA-256. It accepts User or Session scope, semantic version, description, required API declarations, and the Script Registry typed parameter dictionary. Updates require the exact prior SHA-256. `workspaceDelete` checks language and SHA-256, then uses Task 004 `resourceLifecycleDeleteScript`, including dependency refusal and preservation of historical execution snapshots.

Run in the viewer opens the existing CORE registered-script run dialog; the Analysis `analysis.python_script` selector uses the same Session registry identity. The public Python `gxtxt` package is documented in [`PYTHON_SCRIPT_CLIENT_v1.md`](../../../docs/api/PYTHON_SCRIPT_CLIENT_v1.md).
