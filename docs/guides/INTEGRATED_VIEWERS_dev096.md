# Dataset and Viewer workflows

SPDX-License-Identifier: GPL-3.0-or-later

## Sessions and Dataset consultation

The Sessions **Jobs** menu opens the Script Jobs Manager even when no job is
running. Open details to inspect the selected historical run. Running a registered
script and rerunning a historical job are explicit actions. Review the recorded
bindings and current registered script before confirming a rerun; it creates a
new Job and leaves the original run and its logs available. Session Files shows
the script name, registered ID and execution time without renaming run directories.

The Dataset browser's **Print / Export current view** control exports the active
section. Select Notes, Metadata, Variables, Technical Details or Temporal Sets,
then choose an external TXT or PDF destination. Export includes the complete
section, including content below the visible scroll area. If an editor contains
an unsaved draft, the confirmation distinguishes the displayed draft from saved
content. Exporting a draft does not save it back to the Dataset. PDF output is
suitable for printing; actual printing needs a configured printer.

**Metadata** displays ordinary user metadata, matching Edit Metadata. Explicit
**Technical Details** displays read-only storage, registry and provenance fields.
Private metadata is excluded from ordinary consultation/export.

Activate another Dataset with the existing activation command. A clean editor
closes immediately. A changed editor, including unapplied Metadata field edits,
offers discard-and-switch or cancel-and-keep-editing.

## Choosing a curve workflow

**Interactive Curve Builder** remains the quick workflow: select Dataset axes,
add source rows, select the whole curve, a range or highlighted points, Preview,
and explicitly publish a new Dataset. It supports several source Datasets and
the existing 2D and 3D interpolation/fitting methods. Family and Member have
separate enabled/value/Variable controls; enabled predicates combine with AND.
An enabled empty text key is distinct from a disabled filter.

The existing middle action row contains **Options** and **Workspace**. Under
Options, Full Dataset and Selected Subset independently control the source graph.
Full Dataset shows real Family/Member curves as separate series. Neither choice
changes selected training rows or turns on ordering.

**Auto-order points (non-temporal)** is factory OFF. OFF preserves the established
processing order, including the original 2D X sorting for suitable numerical
methods. Turn it ON deliberately to review original and proposed connectivity.
The candidate retains original point values and reversible source-row identities.
Ambiguous neighbors, crossings and possible disconnected segments are reported.
An explicitly repeated closing endpoint remains last; open paths are not
automatically closed. A candidate is not proof of a physical traversal. Temporal
sources retain chronological observation order and disable automatic ordering.
Keep original / OFF cancels the proposed ordering without changing selected rows.

Builder Workspace is optional and stores the working bindings, rows, settings
and choices. Ordinary use does not require a saved Workspace. Builder has no
History menu, timeline or Clear History. Target sampling retains original knots
as well as the requested uniform samples, so output count can exceed that request.

## Dataset Curve Fit

Dataset Curve Fit provides the richer multi-source modeling workflow. **Fit →
Preview fit** and **Accept fit** are in its single top action row; factory keys
are F5 and F6. Preview does not publish a Dataset. Accept retains a local physical
curve, and Results provides explicit CSV export or Dataset publication.

**Input translation / shift positive** offers Auto, Manual and Off independently
for the two fitted axes. Auto is the default. The report states the resolved
constants, units, fit-space model and physical-space formula. For X=f(Y), the
independent fitted axis is physical Y. Accepted/previewed/exported/published
coordinates are restored to physical space once; the original Dataset is unchanged.
Changing model, orientation, translation or selected training points invalidates
an incompatible Preview. Previously accepted curves retain their own geometry
and provenance.

View → Panels / Configuration controls eight panel categories as visible,
collapsed or hidden. These choices use the same User defaults and Session
overrides as central Configuration → Modules. Hiding panels preserves source,
Preview and accepted data. Restore default panel layout removes the Session
override and inherits User defaults. Source counts describe canonical finite
observations; the plot can use fewer display points while fitting all exact rows.

Cancel loading or fitting with Escape, Sources → Cancel operation, or the visible
Cancel button. Closing during loading cancels the owned operation. Errors retain
previous accepted results; a missing or changed source needs explicit recovery
and reload. A Viewer belonging to a different Session can be closed safely and
reopened in its original Session.

## Shared presentation, shortcuts and History

Curve Viewer remains scientifically read-only. Legend entries select their exact
curve identity even when labels repeat. Context actions affect labels, style,
visibility and the local view. They do not modify canonical values. Workspace is
the last menu, and OS titles follow the actual Workspace name.

Curve Viewer uses an optional managed display cache for faster reopening. Missing,
corrupt or stale cache data is rebuilt from the canonical source. Exact Dataset
Preview and publication continue to use scientific rows, independently of the
display sample.

Viewer shortcut settings appear in the same central/local module Configuration
editor. Conflicting and reserved text-editing keys are rejected. Existing Curve
Workbench preferences remain in effect. Shortcuts apply to their own Viewer and
respect text-entry focus and disabled commands.

Curve Workbench, Curve Viewer and Dataset Curve Fit provide scientific History.
Undo/Redo restore local working state. Browsing an older step is read-only;
Return to latest retains the future, while Restart here explicitly confirms a
new branch. External exports and published Datasets remain independent artifacts.
The compact Description/History selector shares the footer.

Workspace → Clear History preserves the current scientific state and offers a
protected external backup. The complete-history limits remain 4096 steps and
8 MiB. At capacity, an edit is rejected and the previous state is restored;
explicitly save/export or clear History before continuing. Old steps are not
silently removed. Builder is intentionally outside this History workflow.

## HDF5 Dataset 3D plots

Plot Dataset reads canonical CSV and HDF5 XYZ through the same provider-neutral
Dataset interface. The existing surface, mesh, contour3, heatmap, line3, scatter3
and trisurf modes retain their documented grid/scattered requirements and saved
Plot Variants. Select the canonical X/Y/Z Variable IDs and optional Family/Color
bindings. Invalid duplicate/missing grid cells are diagnosed instead of filled
or interpolated implicitly. No HDF5-to-CSV conversion is required.


Builder source traces preserve exact measured row adjacency, including gaps;
they are not display-decimated. Full Dataset graphs therefore use memory
proportional to the finite source rows. Selected-subset display limits that
context independently of the fitting input. Ordinary Plot Dataset series retain
their configured reduction behavior.
