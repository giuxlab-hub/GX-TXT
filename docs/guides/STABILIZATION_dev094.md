# GX-TXT dev094 stabilization guide

SPDX-License-Identifier: GPL-3.0-or-later

## Curve Viewer

Use **Add curve…**, choose a Dataset and its stable X/Y Variable IDs. Semantic
family variables show their exact available members. Select one or several;
each becomes an independent curve with its own style and visibility. Complete
discovery permits all members (up to 16 curves per operation). An incomplete
bounded scan requires explicit members. **Point filters / manual binding** lets
you bind a rank-one variable when family semantics are missing or ambiguous,
apply typed predicates and choose a saved Dataset Selection. Column names alone
do not determine families. With no family the compact ordinary XY dialog remains.

Select a curve and use **Source filters…** to inspect, edit or clear predicates.
Applying retains its logical identity and display style. Source Datasets are
read only. Preview reads authoritative data; bounded canvas samples remain display
proxies. Existing zoom/pan, style, visibility, grid and PNG/SVG Export remain.

**Publish Dataset…** appears when Scientific Curve Dataset Publisher is installed
and enabled. Select exactly one visible source/member. The common action dialog
shows the Dataset, variables and predicates. Enter a fresh canonical Dataset ID.
The result contains exact X/Y rows, original dtypes/units and original row lineage,
even when the canvas shows fewer points. Collisions, stale sources/documents,
unsupported units and empty selections reject without a partial Dataset. NaN/Inf
rows remain scientific values. Declared gaps survive reopening and sampling.
Published data remain independent of later view/filter/zoom changes.

## Dataset Curve Fit

The left panel groups Dataset/variables, source collection, filters, model and
parameters, selection, accepted fits, samples and presentation. Drag the divider
to resize; scroll or focus controls to reach lower groups. The existing Native2D
canvas fills the right side. Residual rows/report remain accessible below it;
hiding the residual panel retains exact data and managed resources.

**Sources**, **Fit**, **Selection**, **Results** and **View** menus call the same
existing commands and preserve their enabled states. Preview fit and Accept stay
on the toolbar. Source styles/visibility/reload/remove, parametric/radial options,
rectangle replace/add/subtract/undo, accepted-fit publication and CSV export are
retained. Ctrl+S saves the current Workspace. Model equations, solvers, defaults,
selection, acceptance and scientific output algorithms are unchanged.

## Named Workspaces in both viewers

The **Workspace** menu offers New, Open, Save, Save as / Duplicate, Rename,
Session Workspace manager, Close and Delete. Open selects an exact CORE document
ID; two Workspaces using the same Dataset remain independent. Duplicate uses
official portable export/import and resource remapping. Delete confirms removal
of its owned document and retains source/published Datasets and other Workspaces.

**Session → Workspaces** provides the standard provider listing, notes, previews
and portable transfer. Compatible legacy documents retain their IDs when promoted.
Curve Fit v1 accepted records remain readable and upgrade in place to the existing
v2 format on save. Missing source/provider states retain recoverable documents and
give explicit diagnostics. Close cancels pending source loads. Reopen after a
Session change; old windows cannot save into the new Session.

## Curve Workbench Clear History

**Workspace → Clear History…** explicitly discards prior Timeline and Undo/Redo
entries. Current scientific geometry, identities/directions, constraints,
parameters, selections, image calibration/resources, presentation, view, linked
Dataset bindings and notes remain. Cancel changes nothing; the confirmation also
offers an official portable backup. History browsing, active gestures, busy
operations, stale documents and invalid/oversized bases reject before reset.

CORE validates a new complete base with zero steps, then the existing Workspace
and Recovery services persist it. Precommit failure restores prior memory/history.
The 8 MiB/4096-step limits stay intact; this explicit operation permits subsequent
editing from a small current-state checkpoint. Recovery journals remain separate.

## Configuration → Modules

Search or filter the installed catalog, including disabled, CORE and ALWAYS
providers. Select a module to edit every setting it publicly declares. Typed
controls show constraints, effective values, origin and application timing.
Modules that genuinely declare no settings retain metadata/documentation actions.
Opening settings does not enable or reset a module.

Choose **User defaults** for persistent configuration, or **Current Session** for
supported overrides. Without an open Session the override scope is unavailable.
A missing override inherits the User default. Reset affects only its chosen field
and scope; clearing an override resumes inheritance. Session-only fields reset to
their factory value. Save scopes separately. Immediate settings notify consumers;
next-invocation and restart settings show their actual timing.

Workbench **Command shortcuts** are available centrally before its Viewer opens.
The typed structured form presents actual commands; invalid/conflicting keys reject.
The local Settings dialog uses the same schema and CORE transaction. Two open
editors preserve drafts and reject stale conflicting writes; Reload/discard is the
explicit resolution. Open structured/table forms also capture lifetime/value
preconditions and keep their draft when projection refreshes.

Late fields reconcile without dropping other drafts. Save user defaults preserves
valid unprojected values and unavailable optional-plugin keys. Appearance,
Native3D and Cache & Temporary Storage retain their existing authorities.
Plugin authors can install the descriptor-only example in
`docs/examples/module_configuration` without editing CORE or the GUI.
