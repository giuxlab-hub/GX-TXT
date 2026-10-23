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
# Trusted source maintenance for existing Viewers

Use **File → Maintain installed Viewer…**, select an approved registered Viewer
and choose the parent of a fresh private maintenance project. The same route is
available from **Viewer Interface Builder → Import Existing Viewer → Maintain
original source…**. Both use the existing Development Workspace, Source Surface,
managed request broker and standard package owner. Original installed files are
read-only input; the editable browser shows only CORE-approved opaque targets
and their source bounds. Reopen a saved maintenance project with Open project.
Only Workbench's exact eight Tcl units and Replicate's one Tcl unit are admitted.
Digitizer is absent from this policy and remains its protected AS-IS package.
Replicate additionally exposes two exact Markdown IDs: existing MANUAL.md and
the optional DIGITIZER_INTEROPERABILITY_API_v1.md. The same Source Surface uses
the CORE-returned Tcl/Markdown language; no private editor or arbitrary path is
accepted. Every source/document remains within64KiB.

Save checks the inspected SHA256 before atomic replacement and advances the
editor baseline only after an accepted backend response. Failed, stale or
cancelled requests preserve unsaved text. Validate reports lexical completeness,
source inventory and unchanged preserved files; no Tcl is evaluated. Export
creates a reviewable preserved-payload candidate with a patch-version bump and
checksum/readback receipt. Its status explicitly leaves real GUI/scientific
validation untested. This is trusted maintainer source access, not arbitrary
source-file import or a new restricted Tcl runtime.
An optional document absent from the original is visibly marked not authored.
Its inspection carries genuine absence/null SHA. Save creates only that exact
approved document without replacement; a concurrent creation or stale SHA fails.
Existing document/source modes are preserved; a new document has CORE-fixed0644.
Schema-v2 records the original absence and rechecks it on reopen/save/export.
Old prototype projects/evidence remain preserved and require fresh staging.
Markdown validation means inert bounded UTF-8 only, not Tcl or document semantics.
MAIN retains descriptor/public-contract changes and final candidate acceptance.
Choose a parent folder: initialization reserves a new absent project path and
does not adopt or delete an existing empty folder. A persistent owned mode0600
derived lock serializes same-project cooperative requests; another active owner
returns busy without waiting. This is not a hostile-process CAS guarantee.
Source/lock checks use opened FDs and path identities. Save readback must confirm
bytes/mode before accepting the editor baseline. A lost response means inspect
first, not blind retry. If standard ZIP publication succeeds but checksum
publication collides, both the ZIP and competing sidecar remain for inspection;
no crash-atomic pair, automatic rollback or cleanup success is claimed.

C++ Build, Run, Preview, Test and Debug are unavailable in this mode. Use the
normal owner-approved candidate promotion and real GUI verification route.
Builder declaration/import remains truthful about unrepresented controls;
source editing alone does not prove original controls adopted a changed layout.
Ordinary restricted C++ projects retain their existing editable source targets,
limits, build/debug workflow and runtime policy.
