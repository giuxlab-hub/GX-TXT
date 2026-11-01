# GX-TXT dev-062 — pivot state and editable mixed Path

Only the two requested behaviors are corrected, from published dev-061.
Transform activation and its mode menus no longer require a selected curve.
Pivot placement uses the existing Native2D scene state and workspace history;
changing target selection does not discard a custom pivot. Empty-canvas clicks
place the pivot; the existing gizmo center remains draggable.

Endpoint-attached canvas construction adopts compatible exact retained parts
through the existing Native2D composition operation in the same creation/history
transaction. The object list contains one logical Path. Native2D now maps
constituent defining controls to stable flattened control ordinals on that
object, transforms their coordinates through the existing root/leaf matrices,
and produces deep-owned exact edit candidates. Preview and commit use the
existing public control-definition/control-edit operations. Editing a shared
junction updates incident endpoints; Native topology validation rejects an
incompatible coupled edit atomically. Display samples never become controls.
Unrelated constrained attachments are not silently consumed by automatic
adoption. Compound and the pre-existing manual constrained-Join limitation
remain outside this correction.

The additive C owned-candidate/release pair addresses nested definition lifetime;
it is used beneath existing Tcl/Python/Octave interfaces, with no new script API
or duplicate geometry/store. All three shipped Native adapters were rebuilt
from the same CORE source. Curve Fit changes only adapter parity and version.

## Minimal decisive validation

Exactly one Pivot smoke and one editable mixed-Path smoke ran with real local
X11 pointer/keyboard input on giu's normal Linux XFCE/Xorg `:1` desktop,
seat0/tty2, Remote=no. No forwarded display or broad regression campaign was
used. The private fixture's recovery prompt was dismissed before either smoke.

Pivot: create an empty workspace, activate Transform, place a custom pivot,
create two curves, select the first curve and Rotate through the icon menu.
A real gizmo drag changes that curve's exact definition while preserving the
earlier pivot. Path: draw one multi-vertex Line and a Spline attached to its
endpoint, finish construction without invoking Join, observe one exact Path,
then drag the line interior vertex and spline interior control directly. Its
two exact retained leaves change and one object-list row remains. The final
object-list screenshot was inspected with the utility panel shown.

Evidence: `_evidence_dev062_smoke02`, three inspected screenshots and exact
state/definition receipts; final host `_evidence_dev062_host01` with source
stamp and empty controller-error log. No additional unit/API regression suite
was run. Previous published releases and canonical user Sessions are preserved.
