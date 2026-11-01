# Scientific canvas Viewer guideline

Use the accepted Curve Workbench's separation of scientific scene, native viewport,
inspector and scoped commands as a design reference. Reuse its public authorities;
do not copy its CAD commands, private state or entire UI implementation.

Start with a registered Viewer provider. Declare the GUI integration manifest,
mount the existing public canvas, and connect the existing Workspace, Scientific
History, Documentation and Viewer Command hosts. The scientific owner retains
selection, source identities, results and revision guards. The GUI manifest only
connects them. A true missing feature belongs in its existing CORE owner first.

Place common actions at the top, scientific options in a left scrollable inspector,
and give most space to the canvas. Keep status and Description/History visible at
small window sizes. Reuse shared fields, English validation and native menus.
Use compact contextual commands, meaningful tooltips and the existing command
catalog's shortcuts. Derive applicable/enabled controls from actual cell, curve,
landmark or Plot selection. Never add a shadow selection/action registry.

Open without executing analysis. Use explicit Analyze/Run and existing supervised
Jobs, with cancellation, progress/logs, immutable source receipts and stale-result
checks. Adopt a completed scientific result as one History action. Visibility,
zoom and pan use retained native display state and preserve axes until explicit
Fit. Presentation changes do not rewrite canonical Datasets or restart science.

Persist the scientific recipe and versioned interpretation through the existing
Workspace. Put large results in its managed resources. Publish genuine canonical
Datasets and PlotSpec/Graph Variants when requested. Preserve role-to-Variable-ID
bindings, source rows and units; a PNG is an export, not scientific authority.

Test the real native desktop: resize, short inspector/selector, keyboard, source
changes, Session switch, cancellation, stale Job, Undo/Redo, save/reopen, portable
resources, Graph editing/publication and cleanup. Count source reads and geometry
rebuilds during visibility changes. Record actual latency and platform limits.
