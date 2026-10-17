# Workspace and Viewer controls

Use **Move to Project…** on the selected Experiment to change its organization.
Creating or browsing a Project does not move the open Session. The explicit
**Move open Session here** command acts on the currently open Session.

Plugin Manager filters installed entries by their actual identifiers, names and
types. Reset restores the list. Its update receipt distinguishes installed code
from code already active in the process. A provider may explicitly certify safe
activation while quiescent; otherwise restart is required. Live native code,
workers and scientific Jobs are not forcibly unloaded. Configuration → Modules
contains the initial plugin-package chooser directory. Configuration → Scripts
contains **Show Script Workspace in Analysis**; this changes the optional surface,
while registered scripting services retain their own availability.

Session Workspaces and Viewer Workspace menus use the same saved Workspace
records and actions. Save stores the current owner state. When unsaved changes
need review, Save commits them, Discard restores the saved state, and Cancel
leaves the current editor open. The manager offers filtered provider discovery,
notes, previews, duplicate, export, import, rename and delete through the existing
Workspace authority. Unavailable providers and stale revisions are reported.

Curve Workbench supports a common known proportional coordinate unit on both
axes, including voltage, mass and compound units. Select or enter a common
working unit on its toolbar. Converting an existing Workspace opens a review
before Apply. Area uses the square of that unit, such as V² or (m/s)². Mixed
physical dimensions and affine coordinate origins cannot define this Euclidean
metric frame. Scientific axes may retain independent units where supported;
physical Native3D geometry retains its length requirements.

Choose **Help → User Manual…** or F1 in a supported Viewer to open its independent
read-only manual. Manuals have separate Find, scrolling and navigation state.
Back and Forward follow validated documentation links within that window.
Closing the manual leaves the Viewer open. A missing manual is reported
explicitly. The main Help page remains available.

Registered Viewer developers can discover and request one supported Standard
Analysis module through the public Module API. The request uses the existing
queue, progress, cancellation and Session publication lifecycle. Guided Signal
forms obtain their operation-specific typed fields and conditions from the
provider. Scripts use the existing durable Script Job service for long numerical
operations; no additional scheduler is required.
