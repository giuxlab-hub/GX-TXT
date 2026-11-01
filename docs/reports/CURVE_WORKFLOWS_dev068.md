# GX-TXT dev-068 — Curve Workbench workflow corrections

All six requested workflow areas are corrected from the immutable published dev-067.
The user clarified the original S report as missing command-context guidance and
large generic errors. Small explanatory canvas notices address that report; there
is no separate unresolved Spline geometry claim. Valid Spline creation also passes.

Creation commands S/L/C/R/A/B cancel previous interactions before enabling the new
tool. D clears unsupported previews and explains compatible selections. Rejected
commands and insufficient/degenerate construction show a small non-modal canvas
notice without taking focus. An incomplete Spline remains editable after Enter.
Only one construction instruction row is visible; the existing shared tool and
live-coordinate readout is preserved.

Native semantic selection remains authoritative. Selected points paint above
coincident handles and other geometry, including retained/composed/current geometry.
Individual straight and curved constituent segments use a checked read-only Native
render query. Ctrl adds and Shift subtracts. Constraint tools clear Native selection
on start and incompatible-pair retry. Parallel, Perpendicular, Coincident and
Arc-Line Tangent use the existing supported Native equations with visible selection.
Dimension picks share semantic feedback. Composed Arc constituents infer radius.

Construction accepts controls, straight segments and retained curved branches in
the existing placement layout. Native finite-edge projection or the existing exact
closest-point kernel resolves the connection. The existing point-on-line or
point-on-curve equation enforces interior attachments. Controls retain snap priority
across crossing edges. Same-start, other-line, other-branch and curved-branch
connections finish the placement transaction. Shared controls still compose retained
networks; interior attachments keep primitives linked by actual persistent Native
equations. No new constraint type, topology store, persistence schema or math kernel.
Existing Python/Octave construct_attached and placement_points operations support
these references. The additive device render query is host presentation only.
Workbench 2.11.3 and Curve Fit 0.3.11 contain the identical CORE adapter. Curve Fit
has no UI or scientific behavior changes. Existing Session selector/controls,
top-row Session name and saved-Workspace restore protection are preserved.

Acceptance used actual keyboard/mouse input on local Linux XFCE/Xorg :1, giu,
seat0/tty2, Remote=no with GDM authority. No remote X11, forwarding, VcXsrv or
remote-display testing. GUI05 covers constraints, tangency and composed selection;
GUI06 covers final incomplete-Spline continuation and a copied existing Workspace;
GUI07 repeats curved/straight connections, keyboard and constraints on the final
adapter. Final fresh processes restore frozen exact definitions, logical IDs,
working units and relationships. Screenshots were inspected and normal controller
logs are empty. Canonical Sessions were copied and never opened for writes.
25 Native compatibility tests and focused attachment/render/inference/atomicity
checks pass. Python and Octave straight/curved attachment bridge checks pass.
These supplement the real GUI acceptance. Coverage is scoped to the requested
workflows, rather than every Session or desktop configuration.

Earlier naming/menu/coordinate/camera/foreground harness failures and a composition
attempt following an unrelated tangency fixture are diagnostic only. Acceptance uses
isolated fixtures, activated actual windows and real wheel input for saved camera
bounds. Final source hashes match the GUI07 runtime. Ordered framework/plugin pairs,
restore, active runtime, alias and checksums match. Dev-067 and earlier releases and
versioned handoffs remain immutable. Session Generators and unrelated modules are
unchanged. Completed items are removed from the unfinished-only TODO.
