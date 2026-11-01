# DEV111-P031 presentation correction0.1.5

P0310.1.5 is a separately versioned presentation correction of the retained
owner0.1.4 input: two control-character caption separators become em dashes,
and the readonly Dataset identity wraps without taking half the curve-list
width. The runtime api/preview.tcl and all scientific/schema/Plot operations
remain byte-identical to0.1.4. Original ZIP SHA256 c07ae52b27dd81737eb2f95acaf842eb56e6c48f6eccdc6722b41d854335cfac.
Independent final P031 acceptance is required; the original historical
validation below is not claimed as acceptance of this corrective package.

# Curve Digitalizer Dataset Preview

Open the published Curve Digitalizer Dataset in the ordinary Dataset
Preview. The module contributes three additional tabs:

1. Curves — Click Load curves to discover curve/calibration pairs from
   the published Curve Dataset Schema, then display their filtered canonical
   X/Y points using Plot Dataset API v4. Select a curve and Show/Hide;
   Show all resets presentation visibility only. Use Fit/Zoom on native Plot.
2. Calibration & Quality — Read-only canonical publication metadata
   and Quality Report v2. Missing values are explicitly marked.
3. Canonical Data — Original published rows with Curve and Calibration IDs,
   point order, scientific X/Y and original raster pixel coordinates,
   using the CORE Dataset Preview table.

The chart groups by (curve_key, calibration_key) for Combined publication
and curve_key for Separate publication. Labels are presentation only.
This version scans at most 20,000 canonical rows for display-group
discovery; larger datasets receive a clear refusal, not partial analysis.
Full data remains registered in CORE.

Limit: The CORE table tab is unfiltered. Curve visibility in the Plot does
not change canonical table rows. The current public table-page contract
offers ranges and variable projection but no filtered subset keyed by
curve and calibration. No private CSV/HDF5 parser is introduced.

No local C++ library is needed: Plot API v4 uses GX-TXT's existing C++
renderer. The Builder Preview-target handlers are Tcl host integration,
not an unrelated compiled Viewer process or standalone window.

## Diagnostic and implementation (0.1.4)

The module reads bounded, immutable canonical pages through the installed
DATASET_PREVIEW_API_v1, resolves curve and calibration Variable IDs using
the published Curve Dataset Schema v1, then passes a disposable nine-series
model to PLOT_DATASET_API_v4 with prepared_model=1.
No separate renderer, data writer, Dataset Transform, CSV reader or
private Session path is involved. The Plot is destroyed with the Preview
host, and every source read checks the current Session and canonical identity.

A maximum of 20,000 original Dataset rows, 256 groups and 4,096 points per
individual curve/calibration group is supported in this version for a
complete, non-reduced graphical preview. Out-of-bounds data refuses
rather than silently dropping points; the full canonical Dataset is unchanged.


### GUI responsiveness (0.1.4)

Select **Load curves** once. The button returns immediately; the status line
reports how many canonical rows have been read. Every bounded page yields
to the Tk event loop before proceeding. A second Load cancels the prior
request; closing the Preview cancels unfinished work and releases the
module-owned Plot. Plot v4's native C++ renderer owns the actual drawing.

This is *cooperative* source preparation, not an independently threaded
C++ viewer. It cannot eliminate a slow individual CORE Dataset page call
or change the framework's own periodic Preview observer; those remain
subject to the standard owner and the work-copy performance correction.

### 0.1.4 — Controls

Open Curves and press **Load curves**. The previously empty white list
fills with the available curve/calibration groups. Select one item and
use Show/Hide, or Show all. Native Plot v4 renders the source data.
The initial list is empty until Load curves has completed.

### 0.1.4 — Visible Curves list

The Curves tab initially displays a single non-data instruction:
"Select here or press Load curves to display the available curves".
Selecting that row or clicking **Load curves** starts the identical
bounded cooperative read. Successful loading replaces the instruction
with the actual curve/calibration groups. The module does not fetch
scientific data while the parent GUI mounts.

### Persistent cache limitations

The framework **already caches its standard prepared Dataset Preview** in
the Session via DATASET_PREVIEW_API_v1, and exposes
datasetPreviewCacheRequest/Subscribe/Read. This module does not create a
private cache or modify the standard CORE cache's serializer.

A cached **300-row** representation with a single selected calibration
must not be reused as the **900-row** nine-group presentation: that would
silently omit two physical calibration realizations. Any future reuse
must request its own exact unfiltered scientific selection, validate the
source/renderer identity and prove the resulting cached model includes
every requested (curve, calibration) group before rendering.


## 0.1.6 — Preview for two logical Y axes

Curve Digitalizer curve schema 2 adds a text y_axis_id for each canonical
point. The Preview resolves it through the producer's public Dataset
Schema API rather than decoding private JSON or assuming fixed variable
names. Its bounded canonical page reader preserves curve, calibration
and logical-axis associations, including a shared X axis.

The Curves list identifies (Y1) or (Y2). The native Plot Dataset API v4
displays Y1 on the left and Y2 on the right; these are Preview presentation
choices only and do not establish where the printed axes are located in
the source raster. Each axis retains the scientific physical unit and
uses its declared log/linear transformation where valid. An actual Y1/Y2
plot can be composed from the same-unit canonical Dataset. If the units
are different, independent canonical datasets remain separate; a Dataset
Group may link them without replacing either original scientific payload.

Legacy schema 0/1 Preview and existing controls retain their behavior.
The 20,000-row bounded Preview, stale Session guards, native plot lifecycle
and no-private-file-read rules remain in effect. No CORE or Dataset mutations
are performed by Preview.

## 0.1.7 — Scientific and traceability table

The Canonical Data tab now uses a read-only GUI table rather than a preformatted text dump. It has separate Scientific values and Point traceability views, original-row paging (50 rows per page), 6/10/full-precision presentation, horizontal/vertical scrollbars and selected-row Ctrl+C. The table reads only public Dataset Preview pages on an explicit Load/Next/Previous/precision action. It uses public CURVE_DIGITIZER_DATASET_SCHEMA_API_v1 for Variable IDs and public PREVIEW_COMPONENT_GUI_API_v1 tables for presentation. The source Dataset and scientific values are unchanged.

The Numeric precision selector affects only displayed numeric cells. The full-precision option returns the original canonical text from the public page. UUIDs and point identity are never shortened in the traceability view. The old standard CORE Plot/Table remain available. Legacy and dual-Y Dataset output are both supported; unavailable optional fields display "Not published".

## 0.1.8 — Compact Canonical Data toolbar

The Canonical Data top row contains natural-width **Load**, **Prev**, and **Next** buttons, then a flexible spacer and a compact **Precision** selector. The read-only selector supports 6 digits, 10 digits and Full precision; it does not include an unnecessary Reset button. Paging and scientific rows are unchanged. Controls use public UI_FIELD_API_v1 layout and combobox components. No private Tk widget adjustments are needed.

## 0.1.9 — Point ID traceability

The point ID is an optional producer-declared canonical Variable, not a role required by the version-1 Curve Dataset Schema reader. The table looks for the exact published curve_digitizer.curve_column.point_id metadata mapping, validates the mapped current canonical Variable against public Variable Schema v3, and requests it by ID in the ordinary bounded Dataset Preview Page. If a publication lacks that optional mapping, the field explicitly displays Not published. A broken mapping is a visible error, never replaced silently by a false absence.

## 0.1.10 — Scientific uncertainty and verified page reuse

The Canonical Data Scientific values table displays Sigma X, Sigma Y and Cov XY from the actual published canonical Variable Schema v3 semantic roles. Their units are shown beside the dataset's canonical X/Y units. The display is presentational and does not recompute the Numeric uncertainty results. When a Dataset does not publish these roles, the cells say Not published. Malformed or incomplete uncertainty Variable Schemas are refused explicitly.

Within one live, source-bound Preview pane the last two canonical pages (maximum 50 rows each) are retained as disposable presentation pages. Changes of numeric precision reformat the same verified original numeric page without a new public Dataset page read. Back/forward uses a retained page if available; eviction forces an ordinary public Dataset page read. The existing CORE Preview Cache, Job, source invalidation, native Plot v4 and scientific provenance remain authoritative and unchanged.

## 0.1.12 — Persistent CORE cache for all Preview content

Curves: Load curves requests the CORE verified native representation through the additive public PREVIEW_COMPONENT_GUI_API_v1 adapter. A hit is taken from the same Session Preview cache and uses the existing native Plot Dataset API v4 to present the correct scientific axes. A miss queues the existing CORE cache worker asynchronously. The plugin does **not** construct another persistent cache.

Canonical Data: requests exact canonical 50-row pages through the same CORE cache namespace, with an immutable key bound to Session/Dataset/variables/range. Cached pages persist across Preview/Session reopen; a miss uses an asynchronous CORE worker. Precision changes only reformat cached values. Uncertainty and Point ID columns retain their schema-v3 bindings.

CORE Source image and Calibration & Quality remain CORE-cached; neither requires additional user-module cache files. Changing a real scientific source, version or shared CORE rendering implementation invalidates a cache entry.
