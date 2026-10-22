# Viewer Development Workspace API v1

SPDX-License-Identifier: GPL-3.0-or-later

The installed module `viewer.development_workspace` declares this version-1
activation API in `api/workspace.tcl`, namespace
`::GX::ViewerDevelopmentWorkspace`. Its Viewer ID is `development_workspace`,
backend `viewer_development_workspace_tk`. This is the GUI client; CORE's
[Viewer Development API](VIEWER_DEVELOPMENT_API_v1.md) owns policy, compiler,
runtime, public SDK, requests, preview, packaging and debugging services.

## Public opening contract

```tcl
# Trusted host: open an existing official project, without running its code.
set window [::GX::viewerOpen viewer.development_workspace development_workspace \
    [dict create project $projectDirectory]]
```

`viewerOpen moduleId viewerId ?context?` takes a Tcl dict defaulting to `{}` and
checks installed provider/presentation enablement before lazy activation.

| Entry in `::GX::ViewerDevelopmentWorkspace` | Arguments/defaults | Result |
|---|---|---|
| `open ?context?` | dict default `{}`; optional `project` is a filesystem project directory | creates `.gxViewerDevelopment`, optionally selects the project, returns that Tk path |
| `dispatch operation scene` | lifecycle operation string and resolved scene dict | calls `open` with `scene.open_context` or `{}`; returns its result |

An already open window is raised and returned **before** inspecting a new
context: repeated `viewerOpen` is not a project-switch request. `dispatch` does
not branch on operation. Project selection requires `project.json`. In the
current UI, editable files are `handlers.cpp` and `project.json`; design,
validation/build reports and trusted adapter views are read-only. Project reads
reject a missing file, final symlink or a file larger than 4,194,304 bytes.
That read ceiling does not replace the stricter Development source/policy bound.

## GUI actions delegate to existing owners

The native File/Develop controls use New/Open, source import/save, Validate,
Build, Preview, Test, Export and cancellation through the existing Development
request owner. `save` waits for the public transfer response and accepts only
`SAVED`/`PASS`; failures retain the unsaved source rather than establish a new
baseline. Dirty source transitions use the actual native Yes/No/Cancel review.
Cancel refuses the transition; Yes must complete Save. A busy request prevents
a conflicting source transfer. Generation/project identity guards prevent stale
asynchronous responses from updating a different project.

Source editing, search and syntax services reuse
[Source Surface](SOURCE_SURFACE_API_v1.md); Debug controls use the managed
debugger owner. The left API Browser uses the same discovery owner as Python and
Octave and does not grant runtime access by selecting a catalog row. Its layout
uses the existing `scripts.editor_layout.cpp` Configuration fields.

These stateful widget callbacks are not a new headless command API. Programmatic
authors should use the documented Development service/request contract. This
family's descriptor declares activation/capabilities, not a complete typed
schema for every GUI callback, debugger state or report.

## Language and scientific authority

No Session is required just to open the workspace or author a project.
Scientific operations require their normal public owners and context. This
activation family has no registered Python/Octave Bridge operation and no typed
C++ `gx::Host` method. There is no generic C++ family/name invocation.

The current policy admits ordinary C++17/C facilities with reviewed headers,
including classes, templates, exceptions, allocation, threads and fork/wait for
local application logic. Public CORE ownership of canonical Dataset, Workspace,
History, Jobs and scientific services remains mandatory. Historical UI/profile
strings containing “restricted” do not define a ban on those ordinary language
facilities. See the actual [C/C++ support catalog](CPP_SUPPORT_CATALOG.md),
current SDK/project grants and Development manual for exact allowed integration.

Project paths, source text and component IDs have no scientific units. Result
units/schemas belong to the invoked public service. Missing project, invalid
context, disabled provider, unsupported source, busy request or failed transfer
raise/return the existing owner's explicit error. GUI `safe method args` catches
callback errors, logs them and returns `{status FAILED message ...}`; public
Viewer opening can still raise a Tcl error. This reference proves neither build,
debugger, scientific correctness nor installed release acceptance.
