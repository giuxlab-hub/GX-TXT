# Octave Script Workspace Viewer API v1

SPDX-License-Identifier: GPL-3.0-or-later

Provider `analysis.octave_script` 1.8.0 uses the existing Script Registry,
Source Surface, shared file-aware tab controller and managed Script Job owner.
The lazy Tk `octave_script_editor_tk` Viewer dispatches `open`/`rerender` through
`::GX::OctaveScriptEditor::viewerDispatch`. User authoring works without a Session;
Session operations require the reviewed Session lifetime.

Trusted host operations are `workspaceList`, `workspaceRead reference`,
`workspaceSave reference expectedSha scope scriptId name description code ?arguments? ?properties?`
and `workspaceDelete reference expectedSha`. Reads return verified UTF-8
entrypoint source plus full Project metadata when applicable. Compatible one-file
Save properties accept `version`, `required_apis`, typed `parameters` and
`expected_revision`; the UI pins the revision to protect same-source metadata
edits. Arguments remain inert text. Delete uses the existing resource lifecycle,
including active-dependency refusal and preserved historical Jobs.

Project Save All calls `::GX::scriptRegistryProjectUpdate` once for all admitted
buffers. Creation/copy/import/export/assignment remains in that Registry;
see [Project contract](../../../docs/api/SCRIPT_PROJECTS_v1.md). Native Octave
executes real `.m` files/functions and retains their stack/breakpoint identities.
The common tab controller preserves per-file source, Undo, find/caret and dirty
state, including separate read-only historical source tabs.

The existing shared Runner accepts source/editor declarations plus typed manual
invocation rows and optional canonical Parameter Dataset presets. Native Debug
uses the same managed Job owner. Asynchronous native Octave Pause remains
unsupported; genuine breakpoints and Into/Over/Out remain available.

Obsolete Interactive Document Workspace body reads/writes, registration and
conversion remain unsupported. Metadata-only inspection and explicitly confirmed
resource-safe deletion remain with their existing Workspace owner. See the
[manual](MANUAL.md) and [source parameter declaration contract](../../../docs/api/SCRIPT_PARAMETER_DECLARATIONS_v1.md).
