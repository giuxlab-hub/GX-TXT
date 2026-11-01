# GX-TXT dev-067 — scoped correction report

Baseline is the published, tabs-only corrected dev-066. Four requested
corrections are delivered; the reported independent Spline invalid-input error
remains unresolved because it did not reproduce in the available Sessions.
The affected Session was requested from the user; no generic error was hidden.

A valid version-2 Workspace may omit cad_workspace. The base loader accepts it,
but the recipe wrapper unconditionally read it, causing an incomplete restore.
Recipe restoration now defaults the optional CAD/recipe block. A real local GUI
negative control failed before this fix; the final runtime restores both exact
saved curves. Failed restores now skip automatic view saves and initial
parameter recalculation. Explicit Save still refuses to overwrite their saved
payload; the original restore cause remains visible.

Spline instructions appear once, beside live coordinates. The legacy feedback
row is hidden only for Spline, and status remains available for results/errors.
Path/Polyline point addition commits on an existing defining control once it
has at least two placements, including another line or branch. Native2D still
owns attachment and topology. The creation tool remains ready until Escape.

The loaded Session name reuses ui(sessionPath) to the right of the existing
Workspace selector and its controls on the same top row. All original controls
and tabs are preserved. No science/CORE/API/native binary, Session format,
Curve Fit, other plugin or Session Generator was changed.

GUI validation used only giu's local XFCE/Xorg :1 desktop, seat0/tty2,
Remote=no, GDM authority. Real mouse/keyboard input and inspected screenshots
cover menu and s Spline creation, one Spline instruction row, two existing lines
joined by a new Path, attachment to another branch, top-row Session identity,
legacy restore, protected failure, and fresh-process exact geometry/unit/identity
reopen. No remote X11, forwarding, VcXsrv or remote display was used.

Final source receipts: _evidence_dev067_gui03, _evidence_dev067_gui04 and
_evidence_dev067_gui05 (completed protected-save journey).
GUI03 contains exactly two expected trace errors (_cadRestoreState and _load)
from the intentionally invalid private gizmo fixture. GUI04 errors are empty.
GUI01 legacy failure and earlier harness failures are diagnostic only. A Ctrl+s
negative-control assertion initially missed keyboard focus; the actual Save
button correctly refused, and the corrected negative journey was repeated.
Screenshot review rejected GUI01's still-duplicated instruction and occluded
main capture; final GUI03 screenshots show the actual corrected surfaces.

Coverage is focused on the requested corrections, not every screen size or
plugin. Canonical user Sessions are unchanged. Dev-066 archive, expanded source,
restore archive and versioned handoff remain immutable. The Spline failure is
not claimed fixed merely because tested creation paths pass.
