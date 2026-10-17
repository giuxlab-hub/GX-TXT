# Projects and Session organization

The left navigator groups Projects in Project namespaces and Sessions in
Project-local Session namespaces. Ungrouped Projects and each Project's
Ungrouped group preserve older entries. Default / Unassigned remains protected.
These groups organize membership; moving a Session keeps its directory,
Datasets, Graphs, Workspaces and scientific identity.

Use the Logical namespace editor to create a Project namespace, or select a
Project and choose Session namespace. Select a named group to Rename or Remove
it. Removing a group returns its members to Ungrouped. Names must be unique
within their parent; an equal name in another Project is a separate group.

Drag a Project onto a Project namespace. Drag a Session onto a Project or one
of its Session groups. The highlighted destination and inline message identify
the actual drop target. Hover expands a target; holding at an edge scrolls the
list. Invalid or stale moves are refused without changing membership.

For the keyboard alternative, select a Project or Session and press Ctrl+X,
search/select the destination, then press Ctrl+V. Escape cancels. Cut, Paste
and Cancel are also available in the toolbar and context menu. Moving to a
bare Project chooses its Ungrouped destination. No automatic Undo is promised;
an inverse move is another guarded operation.

Search names, stable IDs, tags and descriptions. Results retain their ancestor
path. Sort A–Z, expand/collapse with the arrows, and use Enter to open the
selected Session. Your selected group, expansion and scroll state are retained.
Choose Identity / breadcrumb from the context menu for a group's stable ID.
Selecting a Session shows a quick summary; Info opens scientific details.

Import Experiment into this Project does not need an existing Experiment selection.
Choose a valid Portable ZIP and unused destination name. Export selected Experiment
exports one explicitly selected scientific Session losslessly. Both reuse Session →
Tools transport. Missing modules/references are reported; existing destinations are
never overwritten. Duplicate Experiment in Session → Session is a separate operation:
it retains safe preparation and private profiles, but starts without scientific data.

Info opens in the same right canvas without switching the open Session. Overview shows
counts and metadata; Datasets shows contracts/formats and guarded availability; Modules
& Scripts distinguishes saved configuration/enabled/Run selection from Dataset-derived
actual-use evidence. Documents groups notes and module documentation snapshots, renders
a verified note by default, and offers Document details for full paths/hashes. A Session
without Markdown says so. Origin & Technical reports declared creator, parent/import
events and technical IDs/paths. Use Back to Experiments; each panel scrolls independently.

Delete requires explicit destructive confirmation. Scientific Session deletion retains
a recovery directory. Default cannot be deleted. Deleting a named Project reassigns
its members to Default and keeps scientific Sessions.
