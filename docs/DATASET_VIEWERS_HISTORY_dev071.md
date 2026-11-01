# Dataset consultation and Workbench History — dev071

The Dataset page contains Variables, Metadata, Notes, Temporal Sets, Preview
and Variables Help. The navigator remains available. Its icons, left to right, are
Refresh, Save Schema, Namespace manager, Open Dataset and contextual Edit. Click an item's pointer
glyph to activate it; highlighting a row alone does not activate it. Click
`Current: …` for Active Dataset Actions. Use namespace context actions or the
manager to select Current and move canonical Datasets without changing their IDs.

`base` is the fallback namespace. `pending` contains acquisition sources until a
successful import; failed imports remain available for correction. Modules publish
inside their own namespaces independently of Current. Legacy `current` metadata
projects to `base`; Namespace manager → Migrate legacy creates a portable Session
backup before an explicit migration. Recover by importing that backup into a new
directory, preserving both copies.

Preview shows canonical content. For ambiguous scientific axes, choose X/Y and
Render. Optional Family/Group, Trace, Replicate and declared source categories
use actual CORE profile values. No selection keeps the original unfiltered one
series; explicit family selections enable separate curves. See
`DATASET_PREVIEW_CONTROLS_dev073.md` and `api/DATASET_SCIENTIFIC_PROFILE_API_v1.md`. Open gives
a larger read-only scientific plot, separate member/variable selections, canonical
table pages, and explicit array planes. The plot shows units and original source
rows; gaps remain gaps. Display reduction never rewrites the Dataset. Overlay
variables must declare the same unit. Use separate plots for different units.

Mesh Open provides actual Native3D rendering, Fit and standard views, left-drag
orbit, middle-drag Pan, wheel zoom, representations, scalar arrays and field
isosurfaces. Available bounds/counts/arrays appear below the canvas. Units are
shown as undeclared when absent. Structural datasets use fixed source-aware atom,
cell/bond and density-plane displays with camera controls and scrollable details.
PDF, raster image, text and audio open their CORE consultation surfaces. Unsupported
or corrupt formats produce a diagnosis; no external application is substituted.

Notes, Metadata and Temporal Sets edit inside their sections. Existing search,
markup preview, bulk metadata and Temporal controls remain. Switching sections
preserves drafts; save/cancel before changing Dataset or Session. Variables Help
has a 24-topic English navigation index and worked examples.

## Workbench

The original bottom strip now offers Description or History without increasing
its height. Settings can hide/show it; recording continues while hidden. Click a
step to reconstruct geometry, topology, constraints/dimensions and named parameters.
Future steps remain dimmed and retained. Historical browsing does not save changes.
Right-click a group to expand individual operations, inspect constraints, or return
to Latest. Edit constraints at Latest or after a confirmed restart; historical
views reject writes. Expanded constraint steps expose direct identity inspection
and confirmed restart-then-edit/remove actions. Existing CORE dependency/solver
checks still apply. The complete Workbench MANUAL.md explains the workflow.

`Restart editing here; discard future…` is the only truncation operation and asks
for confirmation. It restores the chosen state before persisting the shortened
history. Diverged shared Session parameters require explicit reconciliation; they
are never silently overwritten in other Workspaces. Undo/Redo remain available;
while browsing, they navigate retained history. Workspace Save preserves the
complete timeline. The policy admits up to 4096 steps/8 MiB; exceeding it rejects
an edit rather than silently erasing old steps. Prior already-rebased histories
cannot recover steps removed by an older release.

Sketch import reconstructs atomically. A post-commit Workspace-save failure is
reported accurately: the canonical revision stays committed, and the message
instructs retrying Workspace Save or reopening. Sketch export reports included
objects, conversion of scientific curves, source Dataset lineage and omitted
constraints in a scrollable report. Workspace Save and canonical Commit remain
separate actions. Opening another Sketch protects existing unsaved work with
Save/Discard/Cancel.

Retained spline display now evaluates exact definitions adaptively in screen space.
Stored compatibility samples no longer determine visible tessellation. This does
not smooth, refit or replace any saved geometry. Existing Native geometry limits
and explicit rejection of unsupported constraints/conversions still apply.
