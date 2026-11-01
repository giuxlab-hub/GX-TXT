# Workbench and Dataset organization — dev-059

Select objects on the canvas or in the object list. Ctrl adds; Shift subtracts.
Incompatible objects may remain selected together: the chosen command explains
whether that combination is usable. Right-click an object row for bulk actions.
Delete, duplicate, visibility, locking and traversal reversal operate on the
selection where applicable. Dataset sources remain immutable; use an explicit
conversion before editing them.

The arrow icon selects geometry. Right-click it for rectangle or polygon
selection. The four-way icon activates transforms; right-click it for Translate
or Rotate. Drag the gizmo center to place a custom pivot, then drag a translation
handle or rotation ring. Pivot and geometric edits participate in Undo/Redo.
The current action appears beside the live coordinates above the canvas.

Primitive tools stay active after each completed object. Line creates one retained
straight Path through successive vertices; Line, Polyline and Spline finish with
Enter or Finish. Escape cancels an unfinished construction or returns to Select.
Right-click empty canvas for creation and other canvas commands.

Shortcuts appear in menus and tooltips. Defaults include `j` for Join Path,
`Shift+j` for Combine / Compound, Delete, Ctrl+d, Ctrl+z/Ctrl+y and Ctrl+s.
Settings > Keyboard shortcuts changes bindings; Restore default shortcuts resets
them. Text editing fields keep their normal editing keys. Conflicting or reserved
bindings are rejected without installing partial changes.

Join Path creates an exact heterogeneous path when the complete selection is one
unbranched endpoint-connected chain. Review endpoint tolerance before applying.
Line, Arc, Spline and Bézier constituents keep their defining geometry. Sources
remain available. Closed primitives, gaps or branches cannot be invented into a
single traversal: use Combine / Compound, including Rectangle plus Spline.
Compound preserves independent parts and their real topology; it is not a Boolean
union. Separate exact constituents creates editable copies while preserving the
composition. Split divides a heterogeneous Path at a reviewed constituent junction.
Editing a constituent currently uses Separate; nested defining handles are not
exposed on a composition.

When Join/Combine encounters a Dataset-backed curve, it offers a reviewed retained
copy. Verified primitive publication can reconstruct the exact original definition;
other finite ordered data becomes an explicitly derived spline through its knots.
The Dataset and other selected objects remain unchanged. Select the desired
retained objects again and apply the composition command.

Publish a Path after reviewing the new Dataset ID, ordering variable, curved
samples per constituent and closed-endpoint policy. Straight sections retain their
exact vertices. A Compound opens a separate-output review with one Dataset per
constituent and explicit curved sampling; it does not fabricate a global traversal.
Sampling creates finite Dataset values without replacing the retained definition.
Publication keeps units, source identity, direction and conversion provenance.

For constraints, select the intended geometry or defining handles, then choose
Constraints. For Line/Arc Tangent, select the Line segment and Arc with Ctrl and
choose Connections > Tangent. Moving a defining handle keeps the relationship
when a valid solution exists. Dimensions use a placed annotation and an editable
value. Fix prevents edits; Unfix removes the relationship. Conflicting operations
are rejected atomically and report the reason in the status area.

The Dataset tab has a namespace tree on the right. Selecting a Dataset there
selects the existing inspection/preview target. Its context menu opens Metadata,
Notes, namespace movement, rename, deletion and ZIP export. Current namespace
controls where user imports are placed. Old Datasets without an explicit namespace
follow that current namespace. Module outputs receive `module/<module identity>`
automatically. Moving an output outside that namespace prevents its producing
module from replacing it until the user moves it back. Ordinary Metadata hides
reserved private fields; moving or editing a Dataset preserves those fields.
