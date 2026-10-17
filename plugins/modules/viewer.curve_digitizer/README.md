# GX-TXT Curve Digitalizer

`viewer.curve_digitizer` is a GX-TXT-native interactive viewer for digitizing scientific curves from canonical Image Datasets.

It is designed for scanned datasheets, plots, legacy figures, and other raster sources that have already been imported into the current GX-TXT Session. The module preserves the scientific calibration and interactive behavior of the original standalone Curve Digitizer while replacing standalone file/project/export workflows with GX-TXT Dataset, Session, Metadata, Variable Schema, Publication, provenance, and Viewer Provider APIs.

## Identity

- Plugin ID: `viewer.curve_digitizer`
- Display name: `Curve Digitalizer`
- Version: `2.0.3`
- GX-TXT source release: `0.9.8.10-dev-098`
- Workspace: `Viewers`
- License: GPL-3.0-or-later

## Proposal editing and Session image restoration

Right-click guide markers or generated proposal points on the **Curves** canvas
for **Move point**, **Delete point** and (after an edit) **Undo last proposal
edit**. The ordinary Move and Delete modes also work on provisional points.
The last accidental correction can be removed with an exact candidate rollback;
other local edits have an independent, transient proposal-only undo history.
Scientific Dataset points are never changed before explicit acceptance.

When a Session is reopened, an authoritative Image Dataset catalog may arrive
after the Session's saved Interactive Documents. The viewer now restores the
canonical source raster as soon as the catalog and SHA-256 verify it, and
recreates the Tk image item after canvas resets. No document or source bytes
are changed by this restoration.

## Settings and trace output density

The Viewer settings dialog has a permanent bottom row of **Apply**, **OK**
(Apply and close), and **Cancel**, with an explicit save status. All edited
shared GX-TXT settings are committed through the CORE Configuration API;
monotonicity, point ordering, output-point count and appearance are saved in
the selected Session Interactive Document. Repeated Apply operations correctly
advance the optimistic CORE commit baseline. Failed saves are reported.

The assisted Proposal panel has **Output points (Accept)**: `0` retains
candidate density and positive N applies to the particular acceptance action.
**Accept segment** now adds N new points to that segment instead of allocating
just a fraction of N over the entire unaccepted proposal; **Accept** spreads
N across the intervals it commits. The sampling preserves exact guides and
existing scientific points, and `Resample accepted` applies N only to intervals
already committed from the active proposal. Undo remains available.

The viewer now **automatically follows CORE Session changes**: an independent
three-second Session identity check triggers a clean, read-only rebootstrap,
clears all old-Session transient state and undo history, and selects only the
new Session's configurations. It does not change or delete the previous Session.

## Correction guides far from an incorrect proposal

In **Point interaction → Add correction point**, click anywhere on the real
curve inside the source raster. The distance to the wrong proposed trace does
not matter. With per-configuration **Monotonic in X/Y**, the correct interval
is selected automatically from the calibrated coordinate; otherwise use the
bounded **Segment #** selector. Status explains rejected corrections. Only
unaccepted intervals are recalculated; committed scientific data is unchanged.

## Curves workspace controls

Curves keeps the original full-width, single-column workflow. The compact
**Point interaction** section has Add, Move, Delete, Add guide, Edit proposal
and Add correction point. Only the assisted-tracing subsection uses two
internal columns. The old long instructions were removed from this tab.
Point-number visibility and snapping share one row; opacity and the clickable
background color swatch share another row.

The **Configuration → Viewer settings → Digitizing** page stores a
per-configuration ordering policy: None/Monotonic X/Monotonic Y and
Insertion order/Sort by X/Sort by Y. Existing configurations default to
insertion order. When enabled, scientific points are stably sorted after all
edits and separately for each accepted calibration during publication.

**Add correction point** inserts a mandatory guide in the selected proposal
segment without any required proximity to the proposed path; it only
recalculates adjacent unaccepted segments.

## Curves workspace layout

The **Curves** tab retains its familiar **single-column** organization: family
settings, full-width curve table, curve controls, point interaction, Assisted
tracing, display/snapping and per-configuration appearance are in that order.

**Only Assisted tracing** has two internal columns. The left subcolumn contains
Search corridor, Step and Trace image. The right subcolumn contains Propose,
Accept, Reject, Clear guides, the segment selector and Accept segment. When the
user drags the control pane exceptionally narrow, only those two internal
assistant subcolumns stack; the remainder of Curves never becomes a two-panel
layout.

The curve list has its **own vertical scrollbar** (reserved ahead of the
expanding Treeview). Mouse-wheel events over that list can never scroll the
surrounding Curves page, including wheel events redirected through the main
window by Windows/Tk. The outer scrollbar appears only if the control sections
actually exceed the viewport height; if not, an obsolete page scroll offset is
reset. Wheel events over the raster continue to zoom its image. Curve-list
refreshes preserve the scroll position when point totals or visibility change.
These changes only affect presentation, never points or calibration.

## Image Processing interface

The Image Processing tab includes checkbox-driven filters, parameter sliders,
Standard/Advanced ordered processing and a resizable Original/Processed
comparison. Each comparison viewport fits to its measured Tk geometry when
first displayed or on source change, without resetting subsequent navigation. Pan and zoom are independent by default; they can optionally be
synchronized. Curve-point additions, movement and deletion are restricted to
the Curves tab, including keyboard Delete and read-only comparison overlays.
The derived image remains publishable as a standalone `image.raster` Dataset
through the existing CORE publication and public provenance APIs.


## Reviewed physical uncertainty in current viewer

The Publish tab now offers **Uncertainty...** next to the publication action. It saves an explicit uncertainty declaration in the current GX-TXT Interactive Document, independent of Quality API v2. If no declaration is supplied, **no uncertainty columns are fabricated**. For an enabled, validated declaration, every individually published calibration is propagated against its exact ordered rows; multi-calibration uncertainty in a single Combined Dataset is explicitly rejected. Output variables `sigma_x`, `sigma_y`, `covariance_xy`, stable `point_id` and compact cross-point covariance factors are available through `CURVE_DIGITIZER_UNCERTAINTY_API_v1` and Script Bridge. This uses the analytic sensitivity equations from the dev097 Digitizer implementation.

Declarations are fingerprinted to the scientific point/calibration/source state; changed inputs require re-review before publication.

The **direct Fitter/GLS managed-HDF5 covariance binding introduced in dev097 is not yet transplanted**: compact factors and a bounded covariance matrix are exposed to consumers, but direct model-fitting integration must be validated against the active dev097 CORE/Fitter provider. The current algorithm applies its propagation in the plugin's isolated NumPy adapter; see `UNCERTAINTY_API_v1.md` for exact limitations and semantics. SEM physical scale-bar uncertainty requires a separate measurement model; an explicit physical override is available.

## Native workflow

```text
Image file
  -> GX-TXT image acquisition/import
  -> Canonical Image Dataset
  -> Viewers / Curve Digitalizer
  -> named Session-persistent configuration
  -> calibration + curves + ordered points
  -> Publish Dataset
  -> CSV scientific artifact + Canonical Dataset
```

The normal workflow does not use an image file picker, standalone project file, or manual CSV re-import.

## Main capabilities

- Compact native menus (Edit, View, Calibration, Dataset, Configuration, Help), with Configuration immediately followed by Help.
- Centralized **Configuration → Viewer settings...** dialog: display, snapping, tick convention, full-image direction, scale defaults, publication names, and Session configuration profile overview; Apply/Cancel avoids accidental changes.
- Searchable, fully **rendered** user guide via **Help → Curve Digitalizer user guide...** or F1. The Python viewer requests the guide over its existing Tcl host RPC channel. The GX-TXT host reads the installed, registered `MANUAL.md` using `documentationBrowserRead` and formats it using `markupRenderStringToWidget` (GX-Markup v1), inside a dedicated Help window. The viewer does not render Markdown itself and does not modify CORE.
- Center-to-center SEM tick calibration by default; selectable inner/outer tick references with conservative automatic detection and explicit manual fallback. Published calibration manifests expose the applied `edge_convention` through the existing Tcl calibration API.
- Current-Session Image Dataset selector filtered by CORE Dataset namespaces ("Dataset workspace" dropdown). Selecting a parent namespace also displays its children. The Dataset ID remains globally stable; the filter never moves data.
- Read-only `DATASET_CATALOG_v1` revision checks every five seconds (configurable on/off in Viewer settings) with an immediate manual Refresh. A complete snapshot is only requested when the Catalog revision or Session token changes.
- Detects committed additions, deletions/renames, namespace moves and changes; re-verifies a linked source by SHA-256. A replaced or missing source blocks digitization/publication without discarding scientific state. Existing linked sources stay selected when switching the browser filter.
- Multiple named digitizer configurations, including multiple independent configurations for one source image.
- Stable configuration and curve identities.
- Four-point projective/homographic calibration.
- Full-image pixel autocalibration with configurable Y direction, followed by optional physical scale-bar measurement (conservative one-click detection of light/dark bars or manual two-endpoint selection).
- Magenta pre-application scale preview and permanent green overlay after physical scale confirmation. Isotropic X/Y conversion to physical units; scale-reference metadata stored in the existing Session Interactive Document.
- Linear or logarithmic X and Y axes in all four combinations.
- Axis display labels, units, and semantic roles.
- Unit Registry and Semantic Registry integration.
- Multiple curves, optional numerical curve-family mode, ordered digitized points.
- Add, move, and delete points.
- Undo/redo.
- Zoom, pan, fit-to-window, overlays, optional point numbering, and optional darkest-pixel snapping.
- Calibration verification against expected coordinates.
- Session persistence through Interactive Document API v1.
- Source-image integrity checks using the currently resolved source bytes and SHA-256.
- Dataset Metadata readout and output lineage/provenance.
- Atomic publication of the complete calibration manifest (source identity, image dimensions, origin/Y orientation, physical units, exact transform, optional scale bar and uncertainty).
- Public `CURVE_DIGITIZER_CALIBRATION_API_v1` resolves typed calibration using only the published curve Dataset ID.
- Direct publication as `table.generic` or `curve_family.table`.
- Stable output Dataset identity with safe same-owner republishing.
- CSV artifact and Canonical Dataset generated by the same Publish action.
- Lazy desktop backend activation; plugin discovery does not load GUI libraries.

## Requirements

The interactive desktop adapter requires:

- Python 3.10 or newer
- Tkinter/Tcl-Tk
- NumPy
- Pillow with ImageTk

The plugin checks these dependencies only when the viewer is opened. Headless GX-TXT operations such as plugin discovery, validation, installation, and Dataset inspection do not require GUI imports.

## Dataset workspace browser and revision monitoring

GX-TXT Dataset workspaces in the source selector are **Dataset namespaces** from `DATASET_NAMESPACE_API_v1`, not Session Workspace documents. `All namespaces` preserves the previous all-Session behavior. The combobox lists CORE-provided namespaces, and a selected ancestor includes descendants. Existing source associations are independent of this display filter.

The host uses public `datasetCatalogSnapshot`/`datasetCatalogRevision` and `datasetNamespaceList` (dev096, read-only). The Python UI sends nonblocking `CATALOG_REV` requests and fetches a full `CATALOG` snapshot only after a revision change or user Refresh. No client filesystem watcher or plugin-private Dataset index is introduced. When a linked image changes, the host remeasures its SHA-256: no automatic rebinding or recalibration occurs. A linked source that is renamed or deleted remains recorded in the configuration as missing, with its existing digitized points retained.

The check interval is five seconds when enabled in **Configuration → Viewer settings → Dataset browser**; the option can be disabled. **Dataset → Refresh Dataset catalog** and the Refresh button perform an immediate check. Filter and automatic-check preferences are saved per configuration in the existing Interactive Document, and do not change the scientific source identity.

## Source images

The plugin consumes compatible Image Datasets already present in the Session. With the GX-TXT 0.9.7.78 `acq.image_binary` importer, the normal source formats are PNG, JPEG, BMP, and TIFF. The viewer itself relies on the canonical resource exposed by the public Dataset API rather than on private Session paths.

## Publication and stable curve semantics

Independent curves publish as `table.generic`; genuine numeric families publish as
`curve_family.table`. Both are **long tables**, with one row per point, and a
stable public role mapping independent of the variable names or CSV headers.

For a newly published Dataset, use the public `CURVE_DIGITIZER_DATASET_SCHEMA_API_v1`:

```tcl
set spec [::GX::CurveDigitizerDataset::read $datasetId]
set columns [dict get $spec columns]
set keyVariable [dict get $columns curve_key]
set xVariable [dict get $columns x]
set yVariable [dict get $columns y]
set mode [dict get $spec mode] ;# independent | numerical_family
```

`curve_key` is the opaque identity used to group points; `curve_name` is a
changeable label; `point_order` is the zero-based order *within each curve*.
`family_parameter` exists **only** for numerical families. Other viewers must
read role mappings using the public API, not assume `curve_id`, `curve_label`,
column positions or human display labels are permanent.

For transparency/interoperability the same role map is stored in canonical
Dataset Metadata as `curve_digitizer.curve_column.<role>` with version and
mode. The corresponding physical Variable Schema v3 semantic roles are also
registered by the plugin. See `CURVE_DATASET_SCHEMA_API_v1.md`.

## Installation

Install the packaged ZIP through the GX-TXT Plugin Install interface/API. Do not copy files manually into CORE.

Package name:

```text
viewer.curve_digitizer_1.2.9.zip
```

See `MANUAL.md` for complete operation, `CALIBRATION_API_v1.md` for calibration and `CURVE_DATASET_SCHEMA_API_v1.md` for public column semantics.

Version 1.2.1 normalizes LF and CRLF messages from the Python adapter, keeps
the startup window responsive while Session state loads, and lets a second
Open request focus an idle viewer. Host and Python startup diagnostics are
appended under the current Session's `logs/` directory. The scientific model,
Session document format and published Dataset formats are unchanged.


## Companion modules

Version 1.2.0 exposes `CURVE_DIGITIZER_COMPANION_API_v1`. Companion tools can enumerate digitizer configurations, resolve a selected curve and its calibrated source context, verify the Image Dataset SHA-256, and commit accepted pixel points back into the same authoritative Session Interactive Document. The commit path reuses the Curve Digitalizer calibration model.

Writes use optimistic document SHA-256 checks. If the configuration changes after a companion loaded it, the companion must reload rather than overwriting newer scientific state.

## Full-image automatic calibration

Open the Calibration tab and select **Auto-calibrate full image** to use all pixels of the current Image Dataset, with source dimensions W x H and coordinates from 0 to W-1 / 0 to H-1. Select Cartesian upward or native image downward Y orientation. Manual four-point calibration remains available; existing points are recalculated and the operation participates in Undo/Redo and Session persistence. See MANUAL.md, section 8.3.

## Published calibration contract (v1)

Curve Digitalizer 1.2.8 publishes calibration fields in the canonical Dataset Metadata resource in the same Dataset Publication v2 transaction as curve coordinates. Consumers should use `::GX::CurveDigitizerCalibration::read <published_dataset_id>` rather than inspect plugin configuration or deserialize domain-specific metadata. See `CALIBRATION_API_v1.md` for the public manifest, matrix conventions and examples.

The bottom status strip is reserved ahead of the expanding notebook/image workspace so tall Calibration controls cannot force it below the window edge.

## New in 1.2.10

The active configuration and source Image Dataset now share one compact header.
Choose the Dataset namespace with **Configuration → Select Dataset namespace...**
(Canvas picker); inspect catalog revision and automatic monitoring in **Viewer
settings → Dataset browser**, or refresh manually under **Dataset**.

The calibration and published-Dataset semantic contracts keep their existing API
IDs, with additive methods and persistent raster coordinates. Consumers may call
`CurveDigitizerCalibration::transformPoints`, `identity`, `jacobian`,
`pointUncertainty` and `CurveDigitizerDataset::rasterPoints` by published Dataset
ID, without depending on UI state or technical column names. Every new curve
Dataset stores its exact original raster pixel coordinates with its scientific
X/Y values, curve membership and point order. Consult `CALIBRATION_API_v1.md`
and `CURVE_DATASET_SCHEMA_API_v1.md` for contracts, metadata and errors.

Compatibility: older outputs remain readable but cannot claim raster positions
or fingerprints that were not published. Core framework files are read-only.


### CORE Configuration API v1 integration

The module descriptor declares ten typed `[config]` fields with
`persistent_default=1` and `application=immediate`. CORE owns persisted
User defaults, Session overrides, inheritance, validation and conflict
rejection. The Python viewer consumes resolved settings via its existing
trusted host RPC and updates automatically every five seconds; the local
settings dialog commits through `::GX::configurationCommit`. The native
GX-TXT module configuration dialog is also available through Configuration.
No duplicate settings files, CORE patches, or private Manifest writes.

## Calibration measurements and verification

Calibration tab supports repeated independent corner measurements within one
Interactive Document. The active accepted mapping determines main published
scientific X/Y; all realizations and their states are published in Dataset
Metadata and exposed through the existing calibration API. The temporary red
verification X is configurable through GX-TXT central module preferences.
The Namespace menu owns the Dataset namespace picker. Refer to MANUAL.md for
functional usage; version history remains only in CHANGELOG.md.

## Calibration-selectable publishing

The Publish tab selects one or more accepted calibration measurements and offers
**separate** (one Dataset per measurement) or **combined** (one Dataset with a
calibration-key semantic column) output. The default layout and Dataset-name
template are ordinary GX-TXT Configuration API v1 User defaults / Session
overrides, with no independent settings store. A preview validates generated
names before publication. Full user instructions and substitution tokens are
in `MANUAL.md` under **Calibration selection, publication layout and Dataset names**.
The Dataset Calibration API continues to enumerate every published calibration
measurement; the Dataset Schema API adds optional calibration grouping roles.


## Image Processing

The viewer includes an optional geometry-preserving ImageMagick enhancement
workflow and publishes processed PNG images as separate `image.raster` Datasets
using `DATASET_FILE_PUBLICATION_API_v1`. The original Dataset, its SHA-256 and
all original raster coordinates are preserved. The public read-only
`CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1` is exposed to Tcl viewers and
Python/Octave Script Bridge. See `IMAGE_PROCESSING_API_v1.md` and the integrated
`MANUAL.md` for the complete user/developer contracts.

Dataset Notes integration uses the framework Dataset Notes API v1 (`datasetUserNotes`/`datasetUserNotesSave`) after publication. Existing user-authored Markdown remains intact; identical exports are idempotent. Numeric or image publication is reported as successful even if the separate Markdown update fails; a specific warning identifies the notes error.

## Multi-guide tracing, editable proposals, image quality and canvas appearance

The Curves tab provides proposal-only multi-guide image tracing with per-segment
pixel-path optimization and optional GX-TXT public numerical fitting. The
matcher combines grayscale/RGB signatures, transverse-line contrast,
conservative printed-grid penalties and path continuity. Guides remain exact;
operators can drag a guide or add a correction to regenerate only the affected
intervals. A segment can be accepted independently or together with all
remaining segments; no accepted points change until an explicit operation.

The matcher can analyze the untouched source or the current ImageMagick processed
preview (source/pipeline fingerprint verified). Image Processing offers **Try
automatic enhancement** to recommend and preview safe non-geometric filters,
with an operation to restore the previous pipeline. Enhancement is heuristic,
not a guarantee of tracing accuracy.

Curve publication carries versioned, non-destructive calibration and geometry
diagnostics through the established `CURVE_DIGITIZER_QUALITY_API_v2` and Script
Bridge. Each digitizer configuration now stores its own opacity and canvas
background in the Session Interactive Document, with module CORE Configuration
providing initial defaults for newly created configurations.

The old standalone Curve Trace Assistant C/X11 frontend and standalone
Digitization Quality viewer are **not** imported, linked or required by this
plugin. Retirement of their separate CORE descriptors in the framework
release belongs to the framework maintainer; this package does not modify
or delete either installed CORE plugin.

## Published Quality Schema v2

Newly published curve Datasets now contain Quality Schema v2: unique raster
points versus actual publication rows, selected calibration realizations,
per-curve statistics, located per-segment findings, bounded source-image
line-contrast evidence and explicit metrological limitations.
The public provider is `CURVE_DIGITIZER_QUALITY_API_v2`; v1 is not installed.
See `QUALITY_API_v2.md`. No GUI controls were changed in this release.

## dev097 scientific uncertainty integration

An enabled uncertainty declaration now requires the actual dev097 Numeric/Statistical Semantics CORE services; its physical columns are calculated by CORE and verified against the saved point/calibration identity. Managed covariance resources and dev097-compatible Fitter/GLS bindings are supplied through public APIs. Numeric uncertainty fields start blank. For precise integration requirements, limitations and the necessary installed-host acceptance test see `NUMERIC_CORE_INTEGRATION.md` and `INTEGRATION_STATUS_v2.md`.

## Public Numeric execution and zero pixel uncertainty

In 2.0.2, a zero pixel-localization contribution may be declared explicitly,
without invented resolution-based precision. The plugin routes uncertainty
propagation and covariance to public `NUMERIC_API_v1` operations and uses
GX-TXT Interactive Document resource writers for retained scientific output.
Module-specific Python/Octave subprocesses and scratch files are no longer in
the uncertainty execution path. The dev097 Numeric provider requires the
separately supplied zero-input correction; framework Fitter/GLS acceptance is
intentionally outside this plugin task. See `NUMERIC_CORE_INTEGRATION.md`.

### Version 2.0.3
Scientific consistency: the entire preflight local/shared uncertainty factor representation must agree with retained public CORE Numeric factors, not merely the marginal standard deviations and XY covariance. The Dataset Variable Schema v3 unit for `covariance_xy` is now an explicit X*Y product and must match published metadata. No change is made to the declared-uncertainty default (`none`), existing viewers, calibrations or tracing controls.
