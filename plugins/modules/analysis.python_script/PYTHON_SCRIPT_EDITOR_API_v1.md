# Python Script Workspace Viewer API v1

SPDX-License-Identifier: GPL-3.0-or-later

Provider `analysis.python_script` 1.6.0 uses the existing Script Registry,
Source Surface, shared file-aware tab controller and managed Script Job owner.
The lazy Tk Viewer dispatches `open`/`rerender` through
`::GX::PythonScriptEditor::viewerDispatch`. User authoring works without a Session;
Session persistence and execution require the reviewed Session lifetime.

The module's trusted host operations are:

- `workspaceList`: language-filtered Registry Scripts/Projects.
- `workspaceRead reference`: verified metadata plus UTF-8 entrypoint `code`;
  Projects also expose their full admitted manifest/source identities.
- `workspaceSave reference expectedSha scope scriptId name version description requiredApis parameters code ?expectedRevision?`:
  compatible one-file create/update through the Registry. Optional revision pins
  same-source metadata edits; ordinary UI callers supply it.
- `workspaceDelete reference expectedSha`: language/SHA guarded removal through
  the existing resource lifecycle, including active-dependency refusal.

Project Save All uses `::GX::scriptRegistryProjectUpdate`, never a loop of
one-file writes. Project creation/copy/import/export/assignment uses the same
Registry owner. See [Project API](../../../docs/api/SCRIPT_PROJECTS_v1.md).
The common tab controller retains independent source, Undo, find/caret, dirty
baseline, exact source/composite identity and read-only historical snapshots.

Run opens the shared Runner for the selected saved identity. It does not submit
or start a separate process. Native Debug retains real helper-file frames and
frozen source identity. Literal source parameters and typed manual invocation
rows use the common Registry/Bridge/Job schema; see
[parameter declarations](../../../docs/api/SCRIPT_PARAMETER_DECLARATIONS_v1.md)
and [Python client](../../../docs/api/PYTHON_SCRIPT_CLIENT_v1.md).
