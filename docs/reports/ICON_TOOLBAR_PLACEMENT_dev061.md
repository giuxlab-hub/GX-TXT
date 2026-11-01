# GX-TXT dev-061 — focused Curve Workbench GUI acceptance

Baseline: published GX-TXT 0.9.8.10-dev-060. This release changes only the
placement of existing Select and Transform/Pivot icon controls. The shared
Native2D viewport icon toolbar owns the buttons; existing Workbench command
handlers, menus and shortcuts still own behavior. The old upper-toolbar
widgets are absent, and the secondary sketchbar Select copy is not displayed.

Real GUI acceptance used the normal giu local XFCE/Xorg desktop on `:1`,
seat0/tty2, Remote=no. GX-TXT/Tk rendered on the Linux server. Actual local
X11 pointer actions opened a private Session copy and the packaged Workbench
viewer. Screenshots `01-icon-placement.png` and `02-transform-pivot.png` in
`_evidence_dev061_gui02` were inspected. The compact icon bar displayed both
buttons; neither upper bar displayed them. Left-click Select restored normal
click selection; right-click opened Select/Rectangle/Polygon modes and the
Rectangle action changed mode. With an actual object selected, left-click
Transform activated Translate; right-click opened Translate/Rotate, Rotate
activated the Native gizmo, and dragging its center placed a custom pivot.
The registered `v` and `m` shortcuts remained. A real hover showed the shared
tooltip. No Tk background error or traced controller error occurred.

The first private GUI run exposed a stale `pack` manager on the hidden secondary
Select button. The final candidate releases that manager before sketchbar grid
layout. That failed run is excluded from acceptance. No broad geometry, Dataset
or API regression suite was rerun for this placement-only change, per the
requested rapid scope. Dev-060 scientific behavior and its known Join
constraint limit remain unchanged.
