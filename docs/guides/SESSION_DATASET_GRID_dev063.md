# Session, Dataset and Workbench navigation — dev-063

The existing **Sessions** framework page has a left internal menu: Session
files, Session scripts, Workspaces, and Configuration / Manifest. Choose an
item to use the main content area. Existing file inspection, script open/run,
workspace open/import/export/notes and read-only Manifest inspection are retained.
Configuration export/load remains in the page toolbar. No new top-level page
or persistence model is introduced.

The existing **Dataset** page keeps its shell and right namespace navigator
when the active Dataset changes. The old Dataset combobox is removed. Click a
row label to highlight it without changing the active Dataset; click its pointer
glyph, or right-click and choose Activate Dataset, to activate it explicitly.
The active Dataset name is shown above the content. Namespace expansion, browser
scroll position and the selected internal tab survive ordinary activation.

Internal tabs use the large content area: **Variables**, **Metadata**, **Notes**,
**Temporal Sets**, and **Variables help**. Variables retain the scrollable schema
editor, provenance and Save schema operation. Metadata and Notes retain their
existing editors; Temporal Sets retains its existing definition tools. The
**Active Dataset actions** menu offers preview/inspection, table pages, metadata,
notes, Temporal Sets, move to namespace, rename, delete and ZIP export for the
active Dataset. ZIP import and namespace management are also reachable there.
The browser context menu acts on its highlighted Dataset, even when another
Dataset is active. Ordinary metadata views continue to exclude private metadata.

New Curve Workbench Workspaces show a square Native2D grid. A 20-unit vertical
extent gives useful construction room with unit-spaced cells; Native equal-aspect
fitting expands horizontal room to the canvas. Existing saved Workspaces retain
their saved view and presentation. The operation and coordinates are beside each
other on one row. Aspect overrides are host/module API policy, not a toolbar,
form or Script Bridge option.

Click an interior Spline knot with Select to show its two tangent arms. After
joining that Spline into a Path, select the same knot: the same arms remain.
Dragging an arm edits only its exact retained Spline constituent while the Path
remains one top-level object. Separate is not required.
