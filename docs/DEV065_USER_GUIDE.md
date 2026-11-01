# dev-065 sketch and Session workflow

Draw a Line, Polyline or Spline and click an existing defining point to connect it.
Several curves may share the same point. Connected geometry becomes one Path;
click and drag that junction to move all incident constituents. Select individual
points or curve portions directly. Ctrl adds a target and Shift subtracts it.
Right-click the selected geometry for compatible Constraints and the inspector.
Constraint badges also provide inspection/removal. Select a Spline knot to show
its incoming/outgoing tangent arms; drag an arm without separating the Path.

Choose **Parameters...** in Workbench. Enter a name (for example `span`) and formula
(`12` or `session.base * 3`), then Create / update. The table shows evaluated values
and dependencies. Select a straight segment, choose Dimension, place the label,
and enter `span` or an expression. Changing the parameter recalculates its geometry.
Invalid expressions, dependency cycles and inconsistent geometry retain the prior
state and show an error. Numeric results use the dimension's working units; angles
use radians in formulas. Parameter unit labels are metadata, not automatic algebraic
unit conversion. Save Workspace and reopen it from Session Workspaces to restore
formulas, bindings and the automatically assigned module context.

The Session page dropdown selects Session files, Session scripts, Workspaces,
Configuration / Manifest, or Session Parameters in the large content area.
Session Parameters uses the same editor for Session-owned names. Modules read those
names explicitly as `session.name`; module-private parameters are not editable in
this Session table. The Workspaces **Actions** menu also opens the provider's
Parameters action.

The Session menu now contains New/Open, information, save and delete. Import/Export,
Configuration and Tools have their own menus. Configuration offers the existing
export `.ini` and load-configuration-only operations. The framework Workspace
profile/directory controls remain above the notebook. Configuration-only import
keeps its established scope; Session parameters are saved in the Session Manifest.
