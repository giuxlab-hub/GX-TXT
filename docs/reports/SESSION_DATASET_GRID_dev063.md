# GX-TXT dev-063 — Session/Dataset navigation, grid and Spline arms

Baseline is immutable published GX-TXT 0.9.8.10-dev-062. Scope follows
`GXTXT_DEV063_SESSION_DATASET_NAVIGATION_GRID_TASK.md`, including its section 8.
Existing Session/Dataset/Native2D authorities provide all operations and state.
No new top-level framework page, backend store or geometry engine is introduced.

The Session page's internal menu maps existing file, script, Workspace and
Manifest widgets into one large content area. Existing operation/widget paths
and Session subscriptions remain. Script action space is reserved before its
table takes the remaining width.

Dataset initialization replaces the legacy channel form once. Subsequent
activation keeps the shell, namespace browser, notebook, summary, schema canvas,
Metadata table and Notes widget alive. Schema rows are rebound inside their
existing scrollable container when the active Dataset changes. Metadata/Notes/
Temporal content updates in place; namespace rows remain when the catalog has
not changed. Selection highlight remains distinct from explicit glyph/context
activation. The old Dataset combobox is removed from the current page, while
framework choice/selection authority remains. Large internal tabs organize
Variables, Metadata, Notes, Temporal Sets and help. The active-Dataset menu
reuses preview/table inspection, editors, namespace move, rename/delete and ZIP
operations; browser context actions still target the highlighted Dataset.

Native2D scenes initialize equal visual unit scale through the existing C view
setter. The established `xy_equal` API spelling implements `x_equal_y`; explicit
host aspect APIs remain. No UI aspect toggle or Script Bridge override is
exposed; non-default mutating view-state requests reject at the Bridge boundary.
New Workbench Workspace bounds span -10 to 10 vertically with unit grid spacing;
Native equal-aspect expansion supplies useful horizontal drawing room. The grid
is visible at creation. Saved Workspaces retain their stored presentation.
Operation and live coordinates share one row, with explicit stacking for sibling
widgets managed inside descendant containers.

Existing Native2D Spline tangent get/edit calls resolve a Path's defining-control
ordinal to its Spline leaf. Queries compose root/leaf affine frames and edits
invert them, update exact leaf offsets in a deep candidate and adopt through the
existing topology/constraint authority. Leaf side semantics survive reversed
Path traversal. Tcl asks CORE for handles on any selected retained control;
non-Spline controls and missing endpoint sides reject normally. One Path owns
its internal geometry throughout; Separate and display flattening are unnecessary.
The same existing Tcl/Python/Octave endpoints expose the extended capability.
All three Native adapters are rebuilt from the same CORE sources; Workbench is
2.10.0 and Curve Fit 0.3.8 changes only adapter/version parity.

## Focused real GUI acceptance

The decisive workflows use actual local X11 pointer/keyboard input on giu's
normal XFCE/Xorg `:1` desktop, seat0/tty2, Remote=no. No forwarded X11, broad
regression, unit or API test campaign is used. A copied private Session isolates
all GUI writes from canonical user Sessions.

Final page evidence: `_evidence_dev063_pages06`, host08. All four Session
sections switch into the main area. Dataset glyph activation, pure highlight
and context activation work; shell/content widget IDs remain identical across
activation. The old combobox is absent. Variables, Metadata, Notes and Temporal
Sets are visibly available, and the active-Dataset action menu is inspected.
Final Workbench evidence: `_evidence_dev063_workbench05`, host07. A new Workspace
shows square grid cells at useful scale and visible live coordinates beside the
operation. Clicking the standalone Spline's interior knot exposes two arms;
endpoint-attached Line construction joins it into one retained Path. The same
knot exposes arms with identical world positions. A real arm drag changes only
the exact Spline leaf and leaves one object-list row. The line leaf is unchanged.

Twelve final screenshots are explicitly inspected. Both final controller logs
are empty. Source receipts bind the final surfaces independently: only the two
page layout files changed after the successful Workbench check, and the later
page run checks those corrections. Early private diagnostic attempts are excluded:
Tk parent/stacking issues, legacy channel remnants, a misplaced candidate adapter
and harness-only offscreen/read-query issues were resolved before acceptance.
Scientific fit/layout features and the pre-existing manual Join non-coincidence
constraint policy are outside this task. API policy is checked by source review,
without claiming an additional runtime API campaign.

The package/release receipt records exact byte parity and preserves dev-062.
Installed acceptance is `docs/reports/ACCEPTANCE_dev063.json`; the current UI
manual is `docs/guides/SESSION_DATASET_GRID_dev063.md`. Stop after handoff for
manual user review.
