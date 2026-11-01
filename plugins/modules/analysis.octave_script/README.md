# GX-TXT Octave Script 1.8.1

SPDX-License-Identifier: GPL-3.0-or-later

Octave Script Workspace edits ordinary registered `.m` Scripts and complete
multi-file Script Projects in User or Session scope. Shared Source Surface tabs
retain independent source, Undo/search/dirty state and historical read-only
sources. Script Library owns creation, copy, Session assignment and portable
Project import/export through the existing CORE Script Registry.

The same Runner accepts literal native source declarations, editor definitions
and manual invocation-only typed parameters, with optional canonical Parameter
Datasets. Managed Jobs freeze the complete project and execute actual `.m`
entrypoints and filename-correct helper functions. Native debugging retains
helper-file breakpoints and call stacks; asynchronous Octave Pause remains
explicitly unsupported. No separate Registry, scheduler or scientific API engine
is introduced.

Obsolete Interactive Document source Workspaces cannot be restored/converted by
this editor; their existing metadata/resource-safe inspection/deletion owner is
unchanged. User authoring works without a Session. Scientific execution requires
the intended reviewed Session and existing Script Bridge/Publication authorities.

See [manual](MANUAL.md), [editor API](OCTAVE_SCRIPT_EDITOR_API_v1.md),
[Project contract](../../../docs/api/SCRIPT_PROJECTS_v1.md) and
[source parameter declarations](../../../docs/api/SCRIPT_PARAMETER_DECLARATIONS_v1.md).
