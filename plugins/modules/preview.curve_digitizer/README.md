# DEV111-P031 presentation correction0.1.5

P0310.1.5 is a separately versioned presentation correction of the retained
owner0.1.4 input: two control-character caption separators become em dashes,
and the readonly Dataset identity wraps without taking half the curve-list
width. The runtime api/preview.tcl and all scientific/schema/Plot operations
remain byte-identical to0.1.4. Original ZIP SHA256 c07ae52b27dd81737eb2f95acaf842eb56e6c48f6eccdc6722b41d854335cfac.
Independent final P031 acceptance is required; the original historical
validation below is not claimed as acceptance of this corrective package.

# Curve Digitalizer Dataset Preview — 0.1.4

This is an independently installable kind=preview module, not a Viewer.
It adds three read-only panes inside the existing GX-TXT Dataset Preview.
It does not replace the CORE Dataset or Preview service and never writes
Session/Dataset metadata. Its Curves panel uses PLOT_DATASET_API_v4 exclusively.

Target: DEV111-r3. Package tests are isolated from the installed GX-TXT.
The preview-mount and native Plot-v4 Show/Hide test has run against
the actual published 900-row Dataset inside a hidden diagnostic host.
Normal user-facing tab switching and rendering remain to be accepted. The existing specialized Preview stays available.

## 0.1.4 performance and UI

Curves Load now returns a preparing receipt immediately. The canonical
Dataset is traversed in finite pages with an event-loop yield between pages
and strict Preview host/Session/source cancellation. Plotting remains with
the framework's public native Plot v4 C++ engine. The Preview never starts
its own native worker or copies Dataset files.

This release does not change the standard GX-TXT Dataset Preview toolbar,
axis selectors or separate Family/Curve/Calibration filter controls. Those
are owned by CORE, not this module.

### 0.1.4

The Curves list no longer appears as an unexplained blank white box:
its single metadata-only instruction can be selected to request a Load.
The CORE Preview owner in the GX-TXT work copy also avoids a 4-second
extension-tab recomposition on purely retained presentation changes.
Full scientific Dataset source and cache invalidation remain active.


## 0.1.6 — Y1/Y2 scientific Preview

The new schema-2 data remain ordinary table.generic or curve_family.table
Datasets. The public Curve Digitizer Dataset Schema API supplies row axis
bindings; Plot Dataset v4 renders Y1 on the left and Y2 on the right,
with logarithmic scales where valid. Existing monoaxis behavior remains
available. No CORE data or Session is changed by the Preview.
