# Curve Digitalizer Manual

## 1. Purpose

Curve Digitalizer is an interactive GX-TXT Viewer for recovering numerical data from curves drawn in raster images. Typical sources include scanned electronics datasheets, historical plots, instrument screenshots, and published scientific figures.

The module is data-centric. The image is a GX-TXT Dataset, the digitization work is authoritative Session state, and the scientific result is a normal GX-TXT Dataset that can be consumed without reopening the Curve Digitalizer UI.

## 2. Architecture and normal workflow

```text
Image file
  -> GX-TXT acquisition/import
  -> Canonical Image Dataset
  -> Curve Digitalizer Viewer
  -> named Digitizer Configuration
  -> calibration + curves + points + metadata
  -> Session persistence
  -> Publish Dataset
  -> CSV scientific artifact + Canonical Dataset
```

The standalone operations `Open Image`, `Save Project`, `Load Project`, and manual `Export CSV` are intentionally not part of normal GX-TXT operation.

## 3. Supported source Image Datasets

Curve Digitalizer discovers compatible image Datasets in the current Session through the public Dataset registry and resolution APIs. A Dataset is considered compatible when it exposes the canonical `image.raster` contract or an image media type.

The `acq.image_binary` importer normally imports PNG, JPEG, BMP, and TIFF and preserves the original canonical resource. Curve Digitalizer reads that canonical resource through the public Dataset API. It does not inspect or construct private Session paths.

The desktop adapter uses Pillow to decode the resolved image resource.

## 4. Opening the viewer

Open an existing GX-TXT Session, import an image through the normal image acquisition workflow, then open:

```text
Viewers -> Curve Digitalizer
```

The Viewer Provider is discovered headlessly. Python/Tk/NumPy/Pillow are checked only when the interactive viewer is opened.

If no Session is open, the viewer reports an error instead of creating private state outside GX-TXT.

## 4.1 Dataset workspace selector and automatic updates

Select **Namespace → Select Dataset namespace...** to open the hierarchical
Dataset namespace picker. It lists GX-TXT Dataset namespaces. These are the framework's organizational groups for canonical Datasets;
they are not separate directories, and are distinct from Session Workspaces.
Choose **All namespaces** to see every compatible image in the Session. Choosing
an organizational namespace shows images stored in that namespace and its descendants.
The **Image Dataset** selector in the compact header lists matching Image Datasets.

The viewer checks the **Dataset Catalog revision** every five seconds when the
**Check Dataset changes automatically** preference is enabled. Checks use the public
Dataset Catalog API and only read a complete catalog snapshot after the revision
changes. You can also choose **Dataset → Refresh Dataset catalog**. The settings and interval are explained
in **Configuration → Viewer settings → Dataset browser**.

New, removed, renamed or relocated Datasets update the source choices. Moving
between workspace filters **does not** change a saved configuration's source
Dataset ID, even if the source is hidden by the current filter. If an image's
contents change, the viewer verifies its actual SHA-256 against the digest
recorded at original selection. A mismatch marks **STALE SOURCE** and disables
new scientific edits and publication. A deleted/renamed Dataset marks **SOURCE MISSING**.
Existing points, calibrations and metadata remain preserved, and must not be
silently reassociated with another source. Create a new configuration for a new
source rather than assuming the same image coordinates still apply. A Session
change similarly invalidates an already opened viewer.

## 5. Digitizer Configurations

A Digitizer Configuration is the authoritative scientific work object for a set of curves and a group of calibration measurements associated with one source image. It is stored in the current Session as a GX-TXT Interactive Document.

Each configuration has:

- a stable generated configuration ID;
- a user-visible name;
- one source Dataset ID;
- source resource identity and SHA-256;
- X/Y axis definitions;
- projective calibration control points;
- curves and stable curve IDs;
- ordered digitized points;
- optional family definition;
- display/snapping state;
- publication settings;
- optional notes;
- a persistent interactive document format.

Use the configuration selector at the top of the viewer to switch between configurations.

### 5.1 New

Select **New** and enter a name. Then select one of the compatible source Image Datasets from the current Session.

A source is associated with a configuration only after explicit selection.

### 5.2 Rename

Select **Rename** to change the display name. The configuration ID remains unchanged.

### 5.3 Duplicate

Select **Duplicate** to create an independent configuration containing a copy of the current state. The duplicate receives a new stable configuration ID.

### 5.4 Delete

Select **Delete** and confirm. Only that configuration's Session-persisted state is removed. Already published Datasets are not silently deleted.

### 5.5 Multiple configurations per image

The same Image Dataset can back several independent configurations. For example, one scanned datasheet page may contain plate characteristics, transfer characteristics, and grid-current curves. Each configuration can use a different calibration and publish to a different Dataset.

Changing a calibrated configuration to another source Dataset is deliberately blocked. Create a new configuration or duplicate/reset explicitly instead; calibration is pixel-coordinate-dependent.

## 6. Source Dataset information and metadata

When a source Dataset is selected, Curve Digitalizer reads Dataset Metadata through the public Dataset Metadata API.

The Source information panel displays only information actually available, such as:

- Dataset ID;
- canonical format/media type;
- image dimensions if supplied;
- source filename or document information;
- page information;
- manufacturer or datasheet metadata;
- URL/date/scan information;
- other namespaced metadata.

The module does not require specific optional metadata keys and works when optional metadata is absent.

## 7. Source integrity and stale-source protection

A calibration is meaningful only for the exact pixels from which it was created. The configuration therefore stores the source Dataset identity and source SHA-256.

Whenever the configuration is opened, Curve Digitalizer resolves the current source through the public Dataset API and hashes the bytes actually returned.

Possible states are:

- **Source Dataset verified by SHA-256**: editing and publication are allowed.
- **STALE SOURCE**: the Dataset ID still exists but the current image bytes differ. Existing calibration/curves remain preserved, but calibrated work and publication are disabled until the situation is resolved explicitly.
- **SOURCE MISSING**: the Dataset no longer exists or cannot be resolved. The digitization configuration remains authoritative Session state and is not deleted.

The module never silently applies old pixel calibration to changed source bytes.

## 8. Axis calibration

Curve Digitalizer preserves the original four-point projective/homographic calibration model.

### 8.1 Axis definitions

For each axis specify:

- display label;
- unit;
- semantic role;
- minimum value;
- maximum value;
- scale mode: `linear` or `log`.

Units are offered from the GX-TXT Unit Registry, but the field remains editable. A textual unit not recognized by the registry is preserved explicitly rather than discarded.

Semantic roles are offered from the current Semantic Registry and are not inferred from axis labels.

### 8.2 Linear and logarithmic combinations

All four combinations are supported:

```text
linear X / linear Y
linear X / log Y
log X / linear Y
log X / log Y
```

Logarithmic axes require positive scientific limits.

### 8.3 Automatic full-image calibration for photographs

The **Calibration** tab contains a **Full image (photographs)** section. After selecting a source Image Dataset, click **Auto-calibrate full image** to calibrate the entire decoded raster automatically, without manual corner clicks. It uses the actual Pillow image dimensions, not the displayed/zoomed canvas dimensions or optional metadata.

- Four calibration points are set to the pixel **centres** at the actual image corners: bottom-left `(0, H-1)`, bottom-right `(W-1, H-1)`, top-left `(0, 0)`, and top-right `(W-1, 0)`.
- The X axis becomes linear, `0` through `W-1`, with unit `px`.
- The Y axis becomes linear, with unit `px`. Choose **Upward (Cartesian)** for Y=`0` at the bottom and Y=`H-1` at the top; choose **Downward (image pixels)** for Y=`0` at the top and Y=`H-1` at the bottom.
- Custom X/Y labels and semantic roles remain unchanged. Existing digitized points are **recalculated**, not removed. Replacing a current calibration or customized axis limits requires confirmation and can be undone or redone.
- Configuration state uses the same Session Interactive Document, source SHA-256 protections, projective transform, and publication path as manual calibration. There is no independent calibration/persistence mechanism.
- If the source is unavailable or stale, automatic calibration is blocked. Images narrower than two pixels or shorter than two pixels cannot be calibrated.

The **Four-point projective calibration (manual)** section remains available below the image scaling controls for graphs, image crops, skewed plots, or arbitrary quadrilaterals. Reapplying manual calibration can override automatic corner locations. The automatic pixel bounds alone do not infer physical scale; use **Scale using an image scale bar** for calibrated SEM micrographs and photographs.

### 8.4 Scale using an image scale bar (photographs and SEM)

This feature is a second, **explicit** action after **Auto-calibrate full image**. It is not a perspective correction and does not assume a physical scale from image pixels alone.

1. Choose the canonical source image and press **Auto-calibrate full image**; select the desired Y direction.
2. Select the **Tick reference**. Default: **Center-to-center (tick centers)**. Inner/outer edges are alternatives only when the microscope's scale-bar convention is known. Click **Detect**, then click near the middle of a visually distinct scale bar on the source image (typically below the SEM micrograph). The algorithm compares the bar with nearby background and searches for a long horizontal light or dark line. It does not require the bar to be white, but does require sufficient contrast. Only bars visible in the source pixels are eligible; canvas zoom does not affect measurement.
3. Inspect the **magenta overlay**, including the two outlined endpoints. The candidate pixel length is displayed in the Calibration tab. The candidate is not applied automatically.
4. If the detection is ambiguous, incomplete or selects the wrong segment, press **Endpoints** and click the physical ends of the bar. This fallback also handles rotated bars. A line at the wrong position must never be accepted just because a detector found it.
5. Enter the actual **Actual length** of the bar and its **physical unit**, such as `10` and `µm`. Press **Apply scale**. The viewer scales X and Y equally; the measured reference is drawn over the image using a **green line with black contrast outline**, endpoint markers and an annotation. The original image is never modified.

The factor is `physical length / measured Euclidean pixel distance` in the selected unit per source pixel. Original pixel centers `(0,0)` through `(W−1,H−1)` define the image extent. For example, when a 10 µm bar spans 152 px in a 720 × 560 image, the factor is 10/152 µm/px and full-image dimensions in µm become `719×10/152` by `559×10/152`. The Y direction stays Cartesian-upward or image-downward as chosen for full-image calibration. Scale is assumed isotropic, i.e. original image pixels represent equal physical distances horizontally and vertically.

The scale reference is persisted in the **existing Session configuration** as two source-pixel endpoints, pixel distance, physical length, unit, detection mode (`detected` or `manual`) and tick reference (`center`, `inner` or `outer`). Changing the tick reference invalidates a pending preview and requires detecting/selecting the bar again. The previous applied calibration remains unchanged until the new one is explicitly applied. Digitized points retain their original source pixel positions and are recalculated in physical coordinates. Undo/redo works as with other calibration actions. Reopening the Session restores the green reference overlay. A later manual corner edit, change of physical limits/units, or new full-image autocalibration removes an invalidated previous scale reference; it can be restored with Undo where applicable. Published Datasets keep the normal output Dataset identity and the same GX-TXT Dataset Publication API, with `scale_bar` reported as the calibration type. The detailed reference remains traceable through the linked digitizer configuration document.

**Limits:** a numerical scale cannot compensate for distorted/non-square pixels, perspective, or microscope calibration errors; it assumes the raster dimensions correspond to the scale bar. Automatic line detection is intentionally conservative: complex photographic backgrounds or low-contrast/fragmented bars can require manual selection. Do not treat a detected line as ground truth before visually checking the overlay.

### 8.5 Four calibration points

After applying the axis settings, select the calibration points in this order:

```text
bottom-left
bottom-right
top-left
top-right
```

The model computes a projective homography from the image quadrilateral to normalized plot coordinates and then maps normalized coordinates through the selected linear/log axis transforms.

The status line reports calibration readiness, conditioning, and corner residual information.

### 8.6 Calibration verification

Use the verification controls on a known grid intersection or other known coordinate. Curve Digitalizer reports calculated X/Y values and, when expected values are supplied, the residuals.

Verification is diagnostic; it does not change the calibration.

## 9. Curves

The **Curves** tab uses a single full-width column for its main sections,
in the following order:

1. **Curve family:** numerical-family checkbox and parameter quantity, unit and
   semantic role.
2. **Curves:** a full-width table of curve names, family values and point counts;
   New curve, Edit, Delete and Show/Hide controls directly underneath. The
   curve table has its **own vertical scrollbar**. Point the mouse at the
   table to scroll *only the curve list*, without moving the surrounding
   Curves controls or the image canvas. Curve list scrolling is preserved
   when point counts or visibility are updated.
3. **Point interaction:** six compact click modes: **Add**, **Move**, **Delete**, **Add guide**, **Edit proposal**, and **Add correction point**. In Delete mode click the intended existing scientific point directly (the operation is Undo-able). Move selects the point by clicking and allows dragging. Scientific point operations remain Curves-only.
4. **Assisted tracing:** the **only** two-column subsection. **Trace settings** on the left provide corridor, step and image source (auto/original/processed); **Proposal** on the right provides Propose, Accept, Reject, Clear guides, segment selection and Accept segment. The long static instruction labels have been removed from this control panel; only relevant transient status is displayed.
5. **Display and snapping:** **Show point numbers**, **Snap to dark**, and Radius share a single row.
6. **Appearance (per configuration):** **Image opacity** has a compact slider next to the **Background** color swatch. Click the swatch to open the color selector. No hexadecimal field is required in Curves; settings are saved with the current configuration.

**Clear guides** removes only transient guides and proposal material, not
previously accepted scientific points. In an unusually narrow pane only the two
assistant subcolumns stack; the other sections do not move into separate
left/right work areas.

The curve list has a dedicated vertical scrollbar, independent of the page.
The mouse wheel over the list scrolls **only the list**, even when the list is
long and the surrounding page is shorter than its controls. The outer Curves
scrollbar is shown **only when those controls do not fit vertically**; when
they fit, the page remains fixed. The wheel elsewhere over the Curves controls
scrolls that page when necessary, while the wheel over the image zooms the
raster independently. These interactions do not alter any scientific data.

Each curve has a stable internal `curve_id`, a display label, and an ordered list of points.

Use **New curve**, **Edit curve**, and **Delete curve** to manage curves. Visibility can be toggled without deleting data.

Curve labels are not technical identities and may be edited.

## 10. Numerical curve families

Enable **Numerical curve family** only when one real numerical quantity parameterizes the curves.

Example:

```text
X: Anode voltage [V]
Y: Anode current [mA]
Family quantity: Grid voltage
Family unit: V
Curve values: -2, -4, -6
```

For family publication:

- every curve must have a numerical family value;
- the configured family unit is the common unit;
- a per-curve unit, when present, must agree with that configured unit;
- the family quantity has an explicit semantic role, normally `family`.

Do not enable family mode for unrelated curves that happen to be on the same image.

## 11. Point digitization and editing

### 11.1 Add points

Select a curve and enter **Add points** mode. Click the curve in the image. Each point stores pixel information and its calibrated scientific coordinates.

Point order is the user digitization order and is preserved during publication.

### 11.2 Move/edit points

Use the move/edit mode to reposition an existing point. The corresponding scientific coordinates are recomputed from the current calibration.

### 11.3 Delete points

Select a point and delete it using the viewer control or the Delete key where applicable.

### 11.4 Undo/redo

Scientific edits push complete configuration snapshots onto the viewer's undo stack. **Undo** and **Redo** restore those states and then persist the resulting authoritative configuration.

### 11.5 Point numbering

Optional point numbers can be displayed as an overlay. This changes only presentation.

### 11.6 Darkest-pixel snapping

Optional snapping searches a configurable local pixel radius for the darkest candidate. The original/manual click and the snapped/stored position remain distinguishable in the data model inherited from the original digitalizer.

Snapping is an aid, not an automatic curve recognizer.

## 12. Zoom, pan, and image transform

The reusable canvas supports:

- mouse-wheel zoom;
- middle/right-button pan;
- fit image to the available canvas.

The interactive transform is presentation state. Calibration and digitized points remain defined against image pixel coordinates, so zoom/pan do not alter scientific values.

## 13. Session persistence

Authoritative configurations are stored with GX-TXT's Session-scoped Interactive Document API.

Normal persistence is therefore:

```text
Save/keep Session state
  -> close GX-TXT
  -> reopen Session
  -> open Curve Digitalizer
  -> select the same named configuration
```

The calibration, axis definitions, curves, point order, notes, source identity, publication settings, and other configuration state are restored.

No standalone `.json` project is required.

Closing the viewer, resetting derived runtime state, or temporarily changing UI selection does not delete the authoritative configuration.

A Session token protects the viewer from writing into a different Session if GX-TXT changes Session while an external viewer process is still open.

## 14. Notes

The Notes tab stores UTF-8 configuration notes suitable for scientific context such as legend interpretation, scan distortion, or excluded dashed curves. Changes are retained in the Session Interactive Document.

When the user publishes curve Datasets or an enhanced image Dataset, nonempty configuration notes are also appended as a clearly titled section of each published Dataset's **Dataset Notes** Markdown document (`notes/datasets/*.md`). The existing Dataset Notes content is preserved, and publishing the same notes again does not duplicate the section. If the configuration text changes, a new note section preserves the earlier published record rather than silently deleting it. Empty configuration notes leave existing Dataset Notes unchanged.

These Markdown notes are distinct from structured Dataset metadata and from the short Dataset description shown in the Registry. Use the framework's Dataset Notes editor or Session Files viewer to inspect the resulting `.md` document. If a notes update fails after scientific publication, the viewer reports that the Dataset was published but its notes were not saved; the user may repeat the publication after resolving the issue.

The Notes tab is not intended as a general text-editor subsystem.

## 15. Publishing independent curves

With numerical-family mode disabled, Curve Digitalizer publishes `table.generic` data in long form. The **Publish** tab lets you select one or more accepted calibration measurements and choose **separate** or **combined** publication. See the publication layouts and naming section below.

Current stored variable IDs (not part of the consumer contract) are:

| Variable ID | Meaning |
|---|---|
| `x` | calibrated X value |
| `y` | calibrated Y value |
| `curve_id` | stable internal curve identity |
| `curve_label` | user-visible curve label |
| `point_index` | zero-based order within the curve |

X and Y carry the configured labels, units, semantic roles, value kind/dtype, and canonical unit when Unit Registry resolves one.

By default the module preserves insertion order, including non-monotonic curves. When the current configuration uses **Sort by X** or **Sort by Y**, scientific points are instead stably ordered by that calibrated coordinate after insertion, moving, accepted tracing and publication. This is a deliberate configuration policy, not an implicit global sort. Each accepted calibration realization is sorted in its own scientific coordinates during publication. The Dataset metadata records `curve_digitizer.point_ordering_source` and `curve_digitizer.point_monotonicity`.


### 15.1 Semantic column contract

`table.generic` alone does not explain the meaning of its columns. The output
therefore includes the explicit Dataset Metadata fields:

```text
curve_digitizer.curve_schema_version=1
curve_digitizer.curve_mode=independent
curve_digitizer.curve_grouping=curve_key
curve_digitizer.curve_row_dimension=row
curve_digitizer.curve_column.x=x
curve_digitizer.curve_column.y=y
curve_digitizer.curve_column.curve_key=curve_id
curve_digitizer.curve_column.curve_name=curve_label
curve_digitizer.curve_column.point_order=point_index
```

Each mapping's right-hand side is the current Variable ID, **not** its semantic
meaning. Producers may change those technical IDs in future releases without
breaking consumers that use `CURVE_DIGITIZER_DATASET_SCHEMA_API_v1`.

| Stable semantic role | Meaning |
|---|---|
| `x` | Calibrated X coordinate, with unit from Variable Schema |
| `y` | Calibrated Y coordinate, with unit from Variable Schema |
| `curve_key` | Opaque, stable curve identity; **group by this**, not by curve label |
| `curve_name` | Editable human-readable title; never use as identity |
| `point_order` | Zero-based point insertion order within `curve_key` |
| `family_parameter` | Repeated numeric family parameter, only in numerical-family mode |

Rows for different `curve_key` values are independent curves even when stored in
one Dataset. The `curve_key` is only unique within the published Dataset; it is
not an externally global identifier. A change to a curve name does not change
its curve ID. X need not be monotone and must not be used to reconstruct order.

### 15.2 Public consumer API

```tcl
set manifest [::GX::CurveDigitizerDataset::read $datasetId]
set mode [dict get $manifest mode]
set members [dict get $manifest columns curve_key]
set points [dict get $manifest columns point_order]
set xy [list [dict get $manifest columns x] [dict get $manifest columns y]]
set display [dict get $manifest columns curve_name]
# For a true family only:
if {$mode eq "numerical_family"} {
    set parameter [dict get $manifest columns family_parameter]
}
```

The manifest returns the corresponding V3 variable descriptors and textual role
meanings, verifies that every mapped variable exists, checks dimension and dtype,
and rejects malformed or inconsistent schema/contract pairs. It does not read
private Interactive Documents and does not require a running Curve Digitalizer
GUI. A convenience `column $datasetId $semanticRole` returns a single actual
Variable ID; `hasSchema` and `schema` expose availability and the public
contract. See `CURVE_DATASET_SCHEMA_API_v1.md` for the complete normative spec.

For historical published Datasets without the explicit semantic schema, the API provides a marked **legacy** mapping
only when the record is genuinely Curve-Digitizer-owned and all original
technical Variable IDs can be verified in Schema v3. It never infers scientific
meaning from a human-readable column label.


## 16. Publishing a numerical curve family

When numerical family mode is enabled, **Publish Dataset** writes the existing GX-TXT `curve_family.table` contract.

Current stored variable IDs (not part of the consumer contract) are:

| Variable ID | Meaning |
|---|---|
| `x` | independent coordinate |
| `family_value` | numerical family parameter |
| `y` | measured/dependent value |
| `curve_id` | stable internal curve identity |
| `curve_label` | user-visible curve label |
| `point_index` | zero-based order within the curve |

The default semantic roles are `independent`, `family`, and `measured`, but the user-visible configuration remains explicit.

Numerical-family metadata sets `curve_digitizer.curve_mode=numerical_family` and
adds `curve_digitizer.curve_column.family_parameter=family_value`. All five
mandatory roles are still present and points are **still grouped by
`curve_key`**. A family value does not replace the grouping key.


## 17. CSV artifact and Canonical Dataset

Each output Dataset is committed through GX-TXT Dataset Publication API v2:

```text
Publish selected calibrations
  -> verify source image SHA-256 and Session identity
  -> validate selected measurement(s), schema and Dataset names
  -> publish an individual scientific Dataset transaction
  -> CSV scientific artifact, Variable Schema and Dataset Metadata
```

When separate publication selects multiple calibrations, each Dataset is committed separately. If a later publication fails, earlier completed outputs are preserved and the viewer explicitly reports which Dataset failed. This is not an all-or-nothing multi-Dataset transaction.

The user does not export a CSV and then import it again through Acquisition.

The CSV remains a portable scientific artifact, while the Canonical Dataset is immediately available to compatible GX-TXT consumers.

## 18. Calibration selection, publication layout and Dataset names

The **Publish** tab shows a scrollable list of **accepted** measurements.
Select one or several measurements using standard multi-selection keys. The
selection is independent of the measurement currently **Active** in Calibration:
activating a measurement changes the on-screen coordinate mapping, not which
measurements are selected for publication. Draft and rejected measurements are
preserved but are not offered for publication until explicitly accepted.

Two layout policies are available:

| Layout | What is published | Compatibility |
|---|---|---|
| `separate` | One independent Dataset per selected calibration, each with X/Y calculated from its own transform; all curve points keep original raster X/Y | Recommended for ordinary Plot/Fit consumers; no calibration-key column required |
| `combined` | One Dataset with one realization of each raster point for **every** selected calibration; each row carries `calibration_key` and `calibration_name` roles | Only for consumers that understand calibration-key grouping; generic X/Y readers may accidentally mix realizations |

The default is **separate**. Choose the default under **GX-TXT → Configuration → Modules → Curve Digitalizer → Calibration publication layout**. The same choice is accessible from **Configuration → Viewer settings → Axes & output**, where Apply creates a Session override using CORE Configuration. The Publish tab may temporarily select another layout for its current configuration. Both `table.generic` and `curve_family.table` preserve their curve semantics, but combined output adds another mandatory grouping dimension for calibration-aware consumers.

### 18.1 Template-based Dataset IDs

The Publish tab's **Publication base Dataset ID** is the user-defined `[name]` token. A format string named **Dataset naming template**, edited via GX-TXT module configuration or **Viewer settings → Axes & output**, constructs the actual Dataset IDs. The default is:

```text
[name].[calibration].curves
```

Tokens are case-sensitive and enclosed in square brackets:

| Token | Substitution |
|---|---|
| `[name]` | Exact validated user-provided base Dataset ID |
| `[calibration]` | Measurement label converted to a safe ASCII Dataset-ID component (or `combined` for a combined publication) |
| `[calibration_id]` | The stable `measurement_id`, sanitized for Dataset IDs (or `combined`) |
| `[configuration]` | Human configuration label, sanitized |
| `[index]` | Position of the Dataset in the selected publication plan (starting at 1) |
| `[mode]` | `separate` or `combined` |

A naming template **must** include `[name]`; only these tokens and ASCII
letters, digits, dots, underscores and hyphens are accepted. The resulting ID
must begin with a letter and be at most 128 characters. Invalid tokens, missing
required values, and duplicate output names are rejected **before** publication.
The Publish tab shows a preview of the actual generated Dataset IDs.

For example, a base ID `sem.grooves` with two accepted measurements named
`Trial A` and `Trial B` produces:

```text
sem.grooves.trial_a.curves
sem.grooves.trial_b.curves
```

The combined layout instead produces `sem.grooves.combined.curves`. If two
measurements have the same label and the default template would collide, rename
one of them or include `[calibration_id]` or `[index]` in the template.

### 18.2 Source lineage, identities and republishing

Each output Dataset contains the complete group of calibration measurements in
its structured Dataset Metadata. A separate result identifies the calibration
that generated its X/Y columns; a combined result identifies **all** selected
calibrations and maps rows through the `calibration_key` semantic role. The
source image identity, transform fingerprints and original raster points are
preserved. This allows downstream programs to recover other realizations
without depending on the live Interactive Document.

Publishing the same naming plan again may replace the existing Dataset only
under GX-TXT's own-producer replacement rules and only when its recorded
configuration identity matches the current digitizer configuration. Publishing
never silently overwrites another configuration's scientific output. A user
may inspect or change the names in the Publish tab before executing.

Combining calibrations requires consistent units for all X variables and all
Y variables. This is verified before writing rows. Every selected calibration
must validly map **every** point; the publisher rejects a missing/out-of-domain
point rather than silently omitting it. No statistical average, uncertainty or
interpolation is manufactured by either mode.

## 19. Provenance and metadata

Published results record lineage through the normal GX-TXT mechanisms, including information equivalent to:

- producer `viewer.curve_digitizer`;
- plugin version;
- configuration Interactive Document ID;
- configuration name;
- source Image Dataset ID;
- source SHA-256;
- source Dataset relationship;
- calibration type;
- X/Y scale modes;
- X/Y labels and units;
- family label/unit when applicable;
- publication contract;
- publication timestamp.

Source image metadata remain attached to the source Dataset. Curve Digitalizer does not blindly duplicate every source metadata key into the output Dataset.

## 20. Using the result with `plot.dataset`

The published Dataset is independent of the viewer. A compatible `plot.dataset` PlotSpec can bind directly to the stable `x` and `y` variables of a generic result.

Curve Digitalizer private state is not required for plotting.

## 21. Using the result with fitting modules

For a genuine curve family, the published `curve_family.table` Dataset exposes the current GX-TXT contract plus the expected semantic roles for independent coordinate, family parameter, and measured value.

Curve-family/nonlinear fitting consumers can therefore select the published Dataset through their normal Dataset contract/binding logic. They must not read Curve Digitalizer private configuration documents.

## 22. Errors and recovery

### No open Session

Open a GX-TXT Session before opening Curve Digitalizer.

### No compatible Image Dataset

Import an image through the normal GX-TXT acquisition/image importer first.

### Desktop dependency error

Install/enable Python 3, Tkinter, NumPy, and Pillow/ImageTk. Plugin discovery remains usable without them.

### Calibration invalid

Check point order, non-degenerate plot geometry, axis limits, and positivity of logarithmic-axis limits.

### Stale source

The source image bytes changed. Do not reuse the old calibration blindly. Restore the exact source or create/reset a configuration explicitly for the new image.

### Missing source

The saved Dataset ID no longer resolves. Restore/re-import the intended source as appropriate. The configuration itself remains stored.

### Family publication rejected

Ensure all curves have numerical family values and consistent family units.

### Publication ownership error

Choose another output Dataset ID if the requested ID belongs to another producer.

### Session changed while viewer was open

Curve Digitalizer checks the authoritative CORE Session token periodically,
independently of optional Dataset catalog auto-refresh. When GX-TXT opens a
new Session while the viewer is still running, the viewer immediately blocks
edits to the previous Session and fetches fresh bootstrap state. It clears the
old curve selection, image, guide points, temporary assisted proposals,
accepted-proposal tracking, undo/redo history and queued UI operations. It
then displays only configurations and image Datasets of the new Session.
If the new Session is empty, the viewer shows an empty configuration selector
and requires a new configuration. **No old-Session data is deleted or
transferred** and no stale document is saved into the new Session.

If GX-TXT is disconnected or the refresh fails, edits remain blocked with an
explicit status rather than silently continuing in stale state.

## 23. Known limitations

- The viewer supports manual digitization and operator-guided, editable assisted proposals; it does not perform unattended fully automatic curve extraction or OCR.
- A source must already exist as a compatible Image Dataset; direct filesystem image opening is intentionally absent.
- The interactive adapter requires a working Tk display (local desktop, X11 forwarding, or equivalent).
- Optional darkest-pixel snapping is local and image-intensity-based; it does not understand curve semantics.
- Scientific downstream execution depends on the downstream module/runtime. For example, actual `plot.dataset` rendering or numerical fitting requires the runtime used by those modules (normally GNU Octave on the target GX-TXT installation).
- The plugin does not modify CORE and does not provide its own private image importer, unit registry, worker pool, or publication store.

## 24. Keyboard/mouse interaction

Core image interaction inherited from the original canvas includes:

```text
F1               Open integrated detailed user guide
Mouse wheel      Zoom
Middle drag      Pan
Right drag       Pan
F                 Fit image to window
Ctrl+Z            Undo
Ctrl+Y            Redo
Delete            Delete selected point where applicable
```

Standalone shortcuts for file/project/export operations are not part of the GX-TXT-native viewer.

## 25. Technical state format

The Session document format is:

```text
gxtxt.curve_digitizer.configuration
```

It is an implementation state contract for this plugin, not a replacement for published scientific Datasets. Downstream modules must consume the published Dataset rather than this document.


## Companion-module integration

Curve Digitalizer provides `CURVE_DIGITIZER_COMPANION_API_v1` for tightly coupled tools such as Curve Trace Assistant. The authoritative state remains the existing `gxtxt.curve_digitizer.configuration` Interactive Document. Companion modules do not create their own project file or duplicate calibration.

The API exposes stable configuration and curve identities, resolves the associated Image Dataset through public Dataset APIs, verifies the stored source SHA-256, and can append accepted pixel points to a selected curve. Pixel-to-scientific conversion is performed by the same Curve Digitalizer calibration model used by manual points.

Companion writes are guarded by both the live Session token and the expected Interactive Document SHA-256. If another window or module changed the configuration, the write is rejected and the caller must reload.

## 26. Published calibration provenance

On publishing an output Dataset, Curve Digitalizer includes the calibration manifest in the **same atomic Dataset Publication API v2 transaction** as the scientific data. Output metadata is not written after finalization. The metadata travels with the published Dataset, survives Session reopen and remains available to independent viewers.

Fields under `curve_digitizer.*` include `source_dataset_id`, `source_sha256`, `configuration_id`, `calibration_type`, `image_width`, `image_height`, `coordinate_origin`, `y_direction`, `physical_unit`, and `transform`; optional `scale_bar` and `uncertainty` are present when applicable. The transform includes an exact raster-to-normalized 3×3 homography and the linear or logarithmic scientific axis maps. For two linear axes, an additional raster-to-scientific homography is published. The physical unit is normalized to a canonical code (`µm` in the GUI becomes `um` for the manifest).

**Calibration types:** `pixel` for unmodified full-image pixel axes, `scale_bar` for uniform full-image physical scaling, `affine` for a linear affine four-corner map, and `projective` for genuinely perspective four-corner transformations. A log axis is represented by a normalized homography plus explicit non-linear axis mapping, not by a false linear scientific matrix. No uncertainty is invented if none has been supplied. The scale-bar reference records measured endpoints in original image pixels, declared physical length, canonical unit, original UI unit, and selection method.

After same-owner publication to an existing output Dataset, unrelated metadata fields are retained. Obsolete `curve_digitizer.*` fields from a previous calibration are replaced, not silently retained.

## 27. Public API for other viewers

The registered API ID `CURVE_DIGITIZER_CALIBRATION_API_v1` has its own module entrypoint and can resolve calibration **using the published output Dataset ID alone**. Its read function uses the CORE public Dataset Metadata API and Session Inspection API and does not read the viewer's private Session document.

```tcl
set manifest [::GX::CurveDigitizerCalibration::read digitized.sem_contour]
set transform [dict get $manifest transform]
set H [dict get $transform normalized_homography]
set source [dict get $manifest source_dataset_id]
set unit [dict get $manifest physical_unit]
if {[dict exists $manifest scale_bar]} {
    set measured [dict get [dict get $manifest scale_bar] pixel_length]
}
```

See `CALIBRATION_API_v1.md` for the exact contract, optional Session override, schema discovery, unit conventions, error behavior, and formulae.

## 28. Status bar visibility

The main status bar is anchored/reserved at the bottom of the viewer ahead of the resizeable central workspace. The initial window height also adapts to the screen instead of assuming that an 880-pixel client area fits on every desktop. Long Calibration panels may need available vertical space, but must not obscure status information.

## 29. Menu bar and viewer settings

The narrow top row now contains only the active **Configuration** and **Source Image Dataset** selectors, including the source integrity indicator. Viewer commands are grouped into native pull-down menus:

| Menu | Commands |
|---|---|
| **Edit** | Undo (Ctrl+Z), Redo (Ctrl+Y), New/Edit/Delete curve, Delete selected point |
| **View** | Fit image, jump to Source/Calibration/Curves/Publish tabs; show point numbers, scale overlay and calibration corners |
| **Calibration** | Auto-calibrate full image, detect bar, manually select endpoints, apply physical scale, verify and clear calibration |
| **Dataset** | Open the Publish tab or publish directly (subject to existing safety checks) |
| **Configuration** | New/Rename/Duplicate/Delete a Session configuration; **Viewer settings...** |
| **Help** | **Curve Digitalizer user guide...** (F1), About |

### 29.1 Viewer settings window

Open **Configuration → Viewer settings...**. Settings are grouped in six pages:

1. **Display** — Show point numbers; show or hide the saved scale-reference overlay and calibration-corner markings. Candidate scale-bar previews stay visible even if saved overlay display is disabled.
2. **Digitizing** — Optional snap to the darkest pixel and snap radius,
   monotonicity, point ordering and assisted trace output points. Point ordering
   and output count are preserved in the active Session configuration.
3. **Calibration** — Default scale-bar tick reference (center, inner, outer), full-image Y direction and new scale-bar measurement defaults (positive length and valid physical unit). These are preferences for subsequent calibration actions; changing them does not rescale a previously accepted measurement.
4. **Axes & output** — Displays the currently configured axis labels/units, provides a jump to the scientific axis editor, and allows changing the output Dataset ID and display name without publishing anything.
5. **Dataset browser** — The source Dataset catalog, namespace selection, automatic refresh and the manual refresh command.
6. **Configurations** — Lists all saved configurations in the current Session and highlights the active one. Switch or manage them using the main Configuration selector/menu. Deleting a configuration retains its existing confirmation workflow.

The bottom **Apply** button validates all tabs, commits changed shared
preferences through GX-TXT Configuration API and explicitly saves the current
Session Interactive Document (including monotonicity, point ordering, trace
output density, background and image opacity). The settings window remains
open and displays a saved/error status. **OK** applies and closes only after a
successful save; **Cancel** closes without applying pending edits. Apply may be
pressed multiple times in one dialog. User defaults and Session overrides
follow GX-TXT's normal precedence, while scientific settings remain owned by
the selected configuration. This operation never publishes a Dataset or edits
the source image.

### 29.2 Integrated searchable help

Open **Help → Curve Digitalizer user guide...** or press **F1**. The Help command asks the GX-TXT Tcl host to open a dedicated **rendered** manual window. The host retrieves the installed module's `MANUAL.md` through the framework Documentation Browser registry (`documentationBrowserRefresh` / `documentationBrowserRead`) and displays its Markdown/GX-Markup via the framework `markupRenderStringToWidget` renderer, not a Python source-text widget. Headings, emphasis, code blocks, lists and supported links follow GX-TXT's markup conventions. The manual remains read-only; the left contents panel jumps to chapters and **Find next** searches text without case sensitivity. The viewer-to-host request is asynchronous, so Help does not block the viewer's Tk event loop. No internet connection, external browser or CORE changes are required. If the registered manual or GX-Markup services are missing, the viewer reports the host's error instead of silently showing unformatted text.

## 30. Choosing SEM scale-bar tick geometry

A typical SEM scale bar is a horizontal shaft bounded by short vertical ticks. **The default is the distance between the centers of those two terminal ticks**. This is a convenient geometric assumption, **not a guarantee about the microscope manufacturer's convention**. A specific SEM annotation may use inner-to-inner or outer-to-outer tick edges. Consult the instrument exporter or its original metadata if the distinction materially affects precision.

Choose the tick reference in **Calibration → B · Scale bar**, or set its default in **Configuration → Viewer settings... → Calibration**:

- **Center-to-center (tick centers)**: measure the distance between the centers of the terminal marks (default for new or migrated configurations).
- **Inner edges of ticks**: measure the gap between the inner-facing edges.
- **Outer edges of ticks**: measure the full extent between outer-facing edges.

**Detect** first finds the horizontal shaft, then searches near its ends for distinct upright tick segments. The viewer refuses ambiguous or low-contrast tick geometry rather than claim a center that was not detected. For photographs with indistinct ticks, use **Endpoints** and click the desired reference points directly. The preview line must be visually inspected before **Apply scale**. Automatic measurement is a convenience; its success alone does not certify metrological accuracy.

The chosen applied convention is recorded in `scale_reference.edge_convention` within the Session configuration and in the published Dataset Metadata key `curve_digitizer.scale_bar.edge_convention`. The stable `CURVE_DIGITIZER_CALIBRATION_API_v1` exposes it as `dict get [dict get $manifest scale_bar] edge_convention`. Historical Dataset manifests lacking the field are reported as `unspecified`; never silently reinterpret historical measurements as center-to-center. The existing uncertainty metadata remains optional: choosing a convention does **not** generate a numerical uncertainty estimate.

## Compact header, namespace choice and scientific raster points

The header shows only **Configuration** and **Image Dataset**. Configuration
names and Image Dataset IDs remain visible and editable through their existing
combobox selectors. Select **Namespace → Select Dataset namespace...** for
a scrollable, canvas-based list of GX-TXT Dataset namespaces. Selecting one
filters the available image choices; it does not move, replace or relabel a
Dataset. If the current configuration references an image outside the chosen
filter, the original source reference is preserved. Use **Dataset → Refresh
Dataset catalog** when necessary; automatic checks remain enabled by default
and configurable in **Configuration → Viewer settings → Dataset browser**.
Catalog revisions and check failures are displayed there. Source changes,
missing sources and Session changes remain signaled in the bottom status bar
and continue to block unsafe publication without losing digitized points.

All newly published digitized curves contain scientific X/Y and independent
**original raster pixel** X/Y coordinates per point. Both the scientific
calibration and original pixel positions remain available after deleting the
Digitizer configuration document. The output Dataset is standalone; consumers
should query the published calibration/schema contracts instead of assuming
hard-coded Dataset variable labels.

Other viewers may use the following stable public calls:

```tcl
set cal [::GX::CurveDigitizerCalibration::read $datasetId]
set identity [::GX::CurveDigitizerCalibration::identity $datasetId]
set coords [::GX::CurveDigitizerCalibration::transformPoints \
    $datasetId {{150.5 90} {200 140}} pixel_to_scientific]
set jac [::GX::CurveDigitizerCalibration::jacobian $datasetId {{150.5 90}}]
set uncertainty [::GX::CurveDigitizerCalibration::pointUncertainty \
    $datasetId {{150.5 90}}]
set curveSchema [::GX::CurveDigitizerDataset::read $datasetId]
set points [::GX::CurveDigitizerDataset::rasterPoints $datasetId "" 0 10000]
```

The producer uses the *pixel center* convention. Unknown upstream image
preprocessing or unknown measurement uncertainty is recorded as unknown,
not as an exact scientific measurement. Further details, supported mappings,
noninvertible transformation errors and optional uncertainty propagation are
specified in `CALIBRATION_API_v1.md` and `CURVE_DATASET_SCHEMA_API_v1.md`.


## GX-TXT module configuration

The Curve Digitalizer registers its presentation, digitizing, calibration **defaults**
and Dataset catalog preferences through `CONFIGURATION_API_v1`. In GX-TXT open
**Configuration → Modules → Curve Digitalizer** to edit global **User defaults**
or **Session overrides**; inherited settings use the standard CORE precedence.
Alternatively use **Configuration → GX-TXT module configuration...** in the
viewer, which opens the standard CORE module editor. **Configuration → Viewer
settings...** writes the shared fields as Session overrides when Apply is
pressed. Invalid values and stale drafts are rejected by CORE as a whole
transaction. An open viewer checks for central configuration changes every
five seconds.

Shared preferences include point numbers, scale/corner overlays, snapping,
scale-bar conventions, Y direction, default physical scale, automatic catalog
checks, and verification marker shape/color/size/line width. The verification
marker is an X; its configurable properties are `verification_marker_size`,
`verification_marker_width` and `verification_marker_color`. Scale-bar
settings are defaults for new detections, **not** retroactive changes to an
existing scientific calibration. Scientific axes, measured scale references,
digitized points, names, publication targets and source bindings remain in
CORE Interactive Documents; they do not belong in global module preferences.
Legacy documents continue to load, but their previous UI preference snapshots
do not override the effective GX-TXT Configuration registry.


## Calibration tab: layout and scientific scope

The Calibration tab places **A · Full image** beside **B · Scale bar**.
These are two related operations: full-image calibration uses all source pixel
centers, while a scale-bar measurement converts distances to real physical units.
They are distinct from manual **four-point projective calibration**, intended for
plots with axes and possibly perspective distortion.

**B · Scale bar → Clear selection overlay** hides the saved scale-bar line,
endpoints and label from the canvas, without changing the physical calibration,
the raster points or published coordinates. Starting a new measurement replaces
an earlier candidate. The saved reference can be displayed again by reopening
the configuration; **Calibration → Reset physical scale...** explicitly resets
physical scale back to full-image pixel coordinates after confirmation.

## Repeated calibration measurements

**Calibration measurements** is a full-width, scrollable table below the
Projective calibration and verification controls. It provides independent
calibration realizations for the same source raster. The **New** control saves
the current realization, creates a new one with unchanged axes but no selected
corners, and leaves the digitized curve points untouched. Select each of the
four corners independently. You can also auto-calibrate a full image or apply a
scale bar when scientifically appropriate.

- **Activate** switches the current mathematical mapping and recomputes the
  scientific coordinates of existing source-raster curve points. Pixel positions
  and curve identities are never edited by switching calibrations.
- **Accept** checks that the selected calibration has valid corners and axes and
  marks it suitable for downstream study. Any accepted measurement may be
  selected in the Publish tab, even if it is not active.
- **Reject** retains the realization and its data while marking it unsuitable
  for the default accepted set. Rejection does not erase it.
- **Cancel draft** discards only an unfinished draft with confirmation, leaving
  accepted measurements untouched. At least one measurement must remain.
- **Rename** changes the measurement's display label without changing its
  stable measurement identity or transform fingerprint.
- **Delete** removes the selected measurement only after confirmation; at least
  one realization must remain. Published Datasets are not silently changed.

Each measurement has a stable `measurement_id` that identifies the operator's
particular realization, even if its numeric transformation is identical to
another. The group has a persistent `calibration_group_id`. A separate
`calibration_sha256` fingerprints the *mapping*, so equality of the hashes means
identical raster-to-scientific mapping, not identical measurement IDs.

The Interactive Document stores all measurements and the currently selected
one. On Dataset publication, their statuses, original corner pixels, axis
ranges and, when valid, individual transformations and fingerprints are copied
into the published Dataset metadata. Scientific X/Y columns are calculated
from the **selected** calibration, rather than necessarily from the active one.
For combined publication, each calibration generates its own numeric rows and
`calibration_key` distinguishes them. All source-raster points remain available. No automatic variance, standard deviation, or
uncertainty is fabricated from repeated clicks.

Other modules can inspect the published measurements through:

```tcl
set measurements [::GX::CurveDigitizerCalibration::replicates $datasetId]
set firstId [dict get [lindex $measurements 0] measurement_id]
set points [::GX::CurveDigitizerDataset::rasterPoints $datasetId]
set output [::GX::CurveDigitizerCalibration::transformPoints \
    $datasetId {{120 150} {210 180}} pixel_to_scientific $firstId]
```

`transformPoints` accepts either an explicit measurement ID or no ID to use
the active published mapping. For incomplete measurements it reports an error;
unknown IDs are rejected. Calibrations must refer to the same source raster
and valid scientific domain. To estimate manual calibration repeatability,
external analysis software can apply the accepted transformations to the *same*
pixel coordinates and then calculate variability. Repeated calibration cannot
by itself establish absolute instrument accuracy or systematic error.

## Calibration verification

The verification panel is beside the four projective-calibration corner buttons;
calibration measurements occupy the scrollable section underneath.

Select **Verify calibration...** to reveal the Expected X / Expected Y fields.
While in verification mode, clicking the original image places a bright red
**X** exactly at the selected pixel-center location. The marker is temporary,
with a configurable size, color and line width in *screen pixels*, independent
of zoom. The program displays the calculated scientific coordinates and, when
provided, the differences from the expected values. You may enter or change
expected values *after* selecting the image point; the residuals update
immediately and the marker remains visible.

A subsequent click moves the X instead of accumulating markers. Press **Esc**,
choose **Clear verification**, or switch to another image-editing mode to remove
it. No temporary verification marker is saved in a Dataset or Interactive
Document. A verification residual is not automatically a measurement
uncertainty estimate.

## Image Processing: non-destructive enhancement

Open **Image Processing** in the viewer's left tab bar (or **View → Image Processing...**).
The original canonical image is always preserved. ImageMagick is resolved by GX-TXT
**Configuration → Runtime → ImageMagick**, not from a hard-coded path.
The viewer remains fully usable when ImageMagick is absent; only image processing
and publication of the processed image are unavailable.

### Filter controls, processing order and preview

Image Processing presents one row for each supported filter. Enable the desired
operation with its checkbox, then adjust the numeric sliders, spinboxes or
choice selectors. A disabled filter does not participate in processing. A
numeric filter retains its value when disabled and can be enabled again.

| Filter | Controls | Intended use |
| --- | --- | --- |
| Color channel | Red / Green / Blue / Luminance | Choose an informative component |
| Grayscale | Checkbox | Remove chromatic differences |
| Median denoise | Radius slider, 1..10 | Suppress small-scale noise |
| Auto levels | Checkbox | Expand intensity distribution |
| Contrast stretch | Tail percentage slider, 0..20 | Suppress near-extreme tails |
| Brightness / contrast | Separate sliders, -100..100 | Adjust intensity and contrast |
| Gamma | Slider or numeric spinbox | Nonlinear tonal adjustment |
| CLAHE | Tile grid, histogram bins and clip value | Local contrast |
| Sharpen | Sigma slider, 0.1..4.9 | Improve perceived boundaries |
| Invert colors | Checkbox | Reverse light/dark appearance |
| Threshold | Percentage slider, 0..100 | Segment foreground/background |

The **Standard** filter-order mode applies enabled operations in the documented,
fixed order. This is a practical starting point, not a universal optimum.
Channel selection and Grayscale are mutually exclusive in Standard mode.

**Advanced** exposes the exact ordered pipeline; choose a step and use
**Move up**, **Move down**, or **Remove**. Existing repeated steps are preserved
until explicitly modified. Changes in operation order change the output and
are stored in the original order for reproducibility. Switching explicitly
from Advanced to Standard sorts operations by the standard order.

**Live preview** is available when ImageMagick is configured. Slider updates
are debounced: an obsolete processing result is discarded rather than applied
over newer settings. **Apply processing / Preview** remains available for manual
refresh. **Reset filters** clears the current processing pipeline.

### Original / processed split comparison

**Compare original and processed images** enables a two-viewport view only while
the Image Processing tab is selected. The original is on the left; the filtered
image is on the right. Drag the vertical divider to assign more space to
one viewport. Each viewport independently supports mouse-wheel zoom,
right/middle-button drag pan and its own raster position and scale.

**Synchronize pan and zoom** optionally keeps both viewports at equal zoom,
centered on the same original-raster coordinate even if the divider makes
their displayed sizes different. Disabling synchronization retains independent
navigation. On first activation, or after loading a new source
image, each panel automatically fits its complete image to its actual available
viewport area. Once initialized, switching tabs, adjusting the divider or
changing filters does not reset manually chosen pan and zoom. A saved single
viewer position is also preserved when restoring the Session. **Show digitized curve overlays** draws point markers in both
viewports as read-only indicators. The image comparison NEVER adds, moves, or
deletes curve points.

Switching from Image Processing to another tab restores the usual single
image canvas. The processed image may still be displayed for easier tracing,
but a point can be inserted, dragged or deleted **only while Curves is the
active tab**. Image Processing, Source, Calibration, Publish and Notes never
alter curve points through canvas interaction or the Delete shortcut. The
Calibration tab retains only its explicit corner/scale/verification actions.

The original Image Dataset and raster coordinate mapping remain authoritative.
The processing pipeline never changes the calibration matrix, raster dimensions
or original-image SHA-256. Switching the preview does not rewrite points.

The derived processing stream is based on the viewer's decoded RGB image; the
output is RGB PNG rather than a bit-exact copy of higher-bit-depth acquisition
channels. Keep the original canonical Dataset for quantitative image metrology.

ImageMagick may emphasize or suppress features and can alter the *apparent*
location of an edge. Inspect the original before making a final measurement.
There is no crop, resize, rotation, flip or perspective correction in this viewer.
Use a dedicated image-transformation viewer for geometry-changing operations.

### Publish processed Image Dataset

1. Select and preview at least one filter.
2. Enter the new **Image Dataset ID** and optional **Image description**.
3. Click **Publish image.raster Dataset...** and review the source and output.
4. The viewer publishes a standalone canonical `image.raster` PNG via CORE's
   `DATASET_FILE_PUBLICATION_API_v1` and refreshes the Dataset catalog.

The description is stored in the Dataset notes; the canonical Dataset ID is
the stable output identity. The original Dataset is never overwritten. An image published here can be
opened by other image-compatible viewers, including Curve Digitalizer in a
**new digitizer configuration**. No curve Dataset is created by this action;
**Publish selected calibrations** is a separate, independent operation.
Processing state is saved with the digitizer's Session Interactive Document.
The newly published Image Dataset holds its own lineage and processing manifest,
so it remains interpretable when that document is unavailable.

### Processed-image metadata and scientific traceability

The output contains the canonical parent Dataset ID, human-readable source name,
parent SHA-256, ordered processing steps with exact validated parameters,
ImageMagick version, full raster width/height, geometry-preserved assertion,
identity pixel transform and a deterministic processing fingerprint. CORE
supplies the authoritative SHA-256 for the published output bytes. Data
registration and structured metadata commit occur in the same transaction.

These structured fields are **not** intended for manual parsing by downstream
viewers or scientific scripts. Use the public API described in the Developer
Reference below.

## Developer Reference — Public APIs

These APIs are stable module-owned interfaces of the GX-TXT CORE Curve Digitalizer
plugin. Tcl viewers call registered `::GX::*` commands; user scripts use the
*same public scientific contracts* through the registered Python/Octave Script
Bridge provider operations. API ID suffixes are formal contract identifiers,
not viewer-release numbers. All methods operate on canonical Dataset IDs.

### CURVE_DIGITIZER_CALIBRATION_API_v1

Read physical calibration, original-image identity, scale-bar geometry and
calibration realizations without knowing any metadata storage key.

```tcl
set c [::GX::CurveDigitizerCalibration::read $datasetId]
set trials [::GX::CurveDigitizerCalibration::replicates $datasetId]
set xy [::GX::CurveDigitizerCalibration::transformPoints \
   $datasetId $rasterPoints pixel_to_scientific]
```

The transform also accepts `scientific_to_pixel` and a selected calibration
realization where available; invalid/invertible-domain violations produce
explicit errors. Uncertainties are returned only when measured, not invented.
See `CALIBRATION_API_v1.md` for precise argument forms and values.

### CURVE_DIGITIZER_DATASET_SCHEMA_API_v1

Resolve scientific columns using semantic roles rather than names or positions:

```tcl
set schema [::GX::CurveDigitizerDataset::read $datasetId]
set curveKey [dict get $schema columns curve_key]
set xId [dict get $schema columns x]
set yId [dict get $schema columns y]
```

Additional roles include curve label, point order, original raster X/Y and, in
combined calibration publications, calibration key/name. Independent curves
and numerical families have distinct schemas and grouping rules. Use
`CURVE_DATASET_SCHEMA_API_v1.md` for the full contract.

### CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1

The processed-image facade presents the original image, ordered filters,
processing engine, raster identity and entire verified image lineage:

```tcl
set p [::GX::CurveDigitizerImage::read $datasetId]
set steps [::GX::CurveDigitizerImage::operations $datasetId]
set parents [::GX::CurveDigitizerImage::lineage $datasetId]
set ok [::GX::CurveDigitizerImage::hasManifest $datasetId]
```

The returned `p` includes `source_dataset_id`, `source_display_name`,
`source_sha256`, `processing_operations`, `processing_engine`,
`processing_engine_version`, `geometry_preserved`, `pixel_transform`,
`image_width`, `image_height`, `processing_fingerprint` and `output_sha256`.

Python Script Bridge example:

```python
from gxtxt import gxtxt_api_call, gxtxt_api_require

gxtxt_api_require('CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1@1:viewer.curve_digitizer')
info = gxtxt_api_call('CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1', 'read', ['sem.enhanced'])
print(info['source_dataset_id'], info['processing_operations'])
```

GNU Octave Script Bridge example:

```octave
if ~gxtxt_api_has('CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1')
  error('Curve Digitalizer image provenance API unavailable');
endif
info = gxtxt_api_call('CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1', 'read', {'sem.enhanced'});
disp(info.source_dataset_id);
```

`read(dataset_id)` returns a structured manifest. `operations(dataset_id)`
returns ordered `{kind,value}` records. `lineage(dataset_id)` returns the
SHA-verified parent chain up to the untouched original. `has_manifest(dataset_id)`
is exposed by Script Bridge; its Tcl equivalent is `hasManifest`. Missing,
corrupt and incompatible metadata generate explicit errors. Consumer code must
not parse `.ini` files or rely on the names of internal metadata fields.

A full description of each operation, result, error and bridge behavior is in
`IMAGE_PROCESSING_API_v1.md`. Other viewer APIs are documented in their
respective public API references. The integrated Help window renders this
Markdown with GX-TXT's standard GX-Markup renderer.

## Session source restoration

When GX-TXT switches to another Session and later reopens a previously used
Session, Curve Digitalizer resets the old window state, reloads the current
Session configurations, then waits for the authoritative Image Dataset catalog.
If the Interactive Document arrives before the Dataset catalog, the image is
**not considered missing permanently**: after the catalog arrives and the
saved Dataset ID and SHA-256 are verified, the viewer reloads the canonical
image pixels into the canvas. This preserves saved calibration and curve points,
and does not modify either Session. A changed SHA-256 remains a stale-source
condition; no image replacement is silently accepted.

## Assisted tracing with multiple guide points

Assisted tracing is available **only on the Curves tab**. It proposes raster
points that the operator can inspect and edit before they become scientific
points. It does not open the old native C Curve Trace Assistant interface.

1. Select or create the destination curve in the curve list. Select **Add guide**
   under Point interaction. Click as many guide locations as needed (two or
   more, up to 500). With insertion ordering, place them in the intended
   traversal order; when monotonic X/Y is configured, guides are sorted
   by that scientific axis. Each orange
   G marker is an exact raster-coordinate constraint, not a committed curve
   point. Insert additional guides around bends, intersections, printed labels,
   faint curves and crossings with a grid.
2. Select the image to analyze from **Trace image**:
   - `auto` uses the current processed preview when available, otherwise the
     untouched source image;
   - `original` always analyzes the canonical source raster;
   - `processed` requires a fresh processed preview for this exact source and
     filter pipeline. If the preview is missing or stale, run Image Processing
     before making the proposal. No stale pixels are used silently.
3. Adjust **Search corridor (px)** and **Step (px)**, then click **Propose**.
   The plugin requests an optional reference from GX-TXT public
   `NUMERIC_API_v1` (`interpolate`, PCHIP). If it is not available, the
   interpreter explicitly uses local guide interpolation. Either way,
   image-based dynamic programming optimizes each guide interval using color,
   local transverse line contrast, a conservative grid penalty, distance from
   the reference and route continuity. Guides remain exact endpoints.
4. Review the dashed proposal. Cyan means proposed and not accepted; magenta
   identifies intervals with higher local image costs that may be ambiguous.
   These markings are **not** a numerical confidence probability.
5. Choose **Edit proposal** under Point interaction. You can:
   - click and drag an orange guide to move it; only its immediately adjacent
     guide intervals are recalculated;
   - click near a generated segment and drag a point toward the correct trace.
     The point becomes a locked correction guide and splits the destination
     interval. When X/Y monotonicity or explicit Sort by X/Y ordering is
     configured, **the destination is determined by the dropped point's
     scientific coordinate**, not by the segment where the drag began.
     Guide labels G1, G2, ... and Segment # are then renumbered in the
     correct sequence. This matters when placing a correction between
     existing guide points or moving a proposed point across a guide
     boundary. In insertion-order/free-form mode, the originating segment
     remains the explicit target;
   - select **Add correction point** in Point interaction. **Click anywhere
     on the real curve inside the source image**, even if the generated curve
     is hundreds of display pixels away. No distance-to-proposal threshold
     or Search corridor bound is applied to this operator input. When
     **Monotonic in X** or **Monotonic in Y** is enabled, the software
     determines the correct guide interval automatically using the clicked
     calibrated coordinate; the **Segment #** field is updated to that
     interval. Explicit Sort by X / Sort by Y ordering has the same guide
     interval behavior even when a monotonicity constraint is not declared. The click must lie strictly between two existing guides on
     the declared monotonic axis. If outside the current guide domain,
     extend the range with **Add guide** and regenerate the proposal.
     For a free-form curve (**None**), use **Segment #** to explicitly select
     the intended interval. Its maximum is the actual number of proposed
     intervals, rather than an arbitrary 500. Obsolete or out-of-range values
     are recovered using the geometry of the operator's guide points.
     The correction inserts a mandatory guide and recalculates the two
     neighboring intervals, leaving all other segments and accepted points
     untouched. The action works even for a two-vertex proposed interval.
     Success and rejection reasons appear in the bottom viewer status.
   - repeat corrections as many times as necessary. Other proposed segments
     remain unchanged. Previously accepted segments cannot be edited in
     this transient mode; edit committed scientific points using **Move**.
**Editing or correcting a proposal by right-click:**

- In the Curves tab, right-click any **orange guide marker** or a **generated
  proposal point** to open a contextual menu. Choose **Move point** to arm a
  move, then left-click its destination (or press and drag from the original
  point). The changed guide interval is recalculated; other intervals stay as
  they were. The ordinary **Move** radio mode can also act on proposal points,
  not only on accepted scientific points.
- Choose **Delete point** to remove the selected provisional point. Deleting
  the *most recently added correction guide* restores the **exact previous
  proposal**, including the original path rather than a new approximation.
  Deleting an older interior guide rejoins its two affected guide intervals
  and recalculates that interval only. Deleting a generated interior vertex
  removes that vertex from the provisional polygon without affecting the
  accepted scientific Dataset points.
- The ordinary **Delete** radio mode works on nearby proposal points as well
  as on accepted scientific points. Use **Undo last proposal edit** in the
  right-click menu to undo a provisional move or deletion. This temporary
  history is separate from scientific Undo/Redo and is cleared when a proposal
  is accepted, replaced, or the Session changes. Already accepted segments
  cannot be mutated through the provisional editor; the scientific Undo/Redo
  controls govern committed edits.
- Right-button dragging in empty canvas space still pans. The context menu
  appears only when clicking sufficiently near a point on the image.

6. Set **Output points (Accept)** in the Proposal controls to specify how
   many **new assisted scientific points this acceptance operation** must add.
   Enter `0` to keep the original candidate density. With a positive N:
   - **Accept** on an entirely unaccepted proposal adds N points across all its
     guide intervals, preserving shared endpoints only once.
   - **Accept segment** adds N new scientific points for the single selected
     interval, **not a fraction of N allocated to the entire proposal**.
   - **Accept** after previous partial acceptances adds N new points over the
     remaining intervals. Previously accepted intervals are not replaced.
   The generated points follow the reviewed candidate's arclength; guide
   locations remain exact, and no second fit changes the path. The selected
   interval set must contain enough points to retain its guide endpoints;
   the maximum requested N is 10000.
7. To commit only one interval, choose its 1-based number under **Segment #**
   and press **Accept segment**. Accepted intervals are visually distinct.
   Both commands request explicit confirmation and add `origin=assisted` points
   to the existing curve; manual points are not deleted, and adjacent
   accepted intervals share guide endpoints without duplicating them.
   Undo/Redo is supported. **The number of total points shown for a curve may
   exceed Output points because pre-existing manual or previously accepted
   points remain present.**
8. After accepting, **Resample accepted** may be used to change Output points
   without regenerating the live proposal. N is the desired total number of
   assisted points within the currently accepted set of intervals, not across
   unaccepted segments. It replaces **only the accepted
   assisted points from that live proposal**, not prior manual points or other
   unrelated assisted work. It asks for confirmation because any changes made
   directly to those accepted points would be replaced. Undo restores the
   previous scientific point set. This action requires the proposal to remain
   active and can be used before accepting additional segments; it does not
   retroactively alter older Session records when the proposal is no longer live.
9. **Reject** discards the remaining proposal while preserving guides. **Clear
   guides** removes transient guides and the transient proposal but does not
   delete already accepted scientific points. No other tab can add, move or
   accept scientific curve points through canvas interactions.

**Important:** In a crossing where two traces are indistinguishable in the
source raster, the algorithm cannot know the right continuation. Add enough
guides to remove the ambiguity and never accept an uncertain segment merely
because it looks smooth. An assisted proposal is not a measured physical fit.

### Assumptions at the official numerical API boundary

The optional fitted centerline calls `::GX::NumericAPIv1::interpolate` only
through the viewer host adapter. It requires monotonically increasing
path-length parameters, supports PCHIP when at least three guides are present,
uses `extrapolation=error`, and returns samples in the original raster units.
The adapter and fallback are described in `ASSISTED_TRACING_DESIGN.md`. The
Digitalizer uses no private `math.numeric` operation or C/X11 tracing widget;
changes to the public provider require updating the documented adapter and
its regression tests.


## Curve monotonicity and point ordering (per configuration)

Open **Configuration → Viewer settings → Digitizing**. The new controls are
**Monotonicity** and **Point ordering source**:

| Monotonicity | Point ordering source | Behavior |
|---|---|---|
| None | Insertion order | Existing free-form digitization; points follow the order entered. This is the default for existing and new configurations. |
| None | Sort by X | Stable increasing calibrated X order without declaring that the source curve is mathematically single-valued. |
| None | Sort by Y | Stable increasing calibrated Y order. |
| Monotonic in X | Sort by X | Order automatically follows calibrated X, enabling insertion between points and guide sorting by X. |
| Monotonic in Y | Sort by Y | Equivalent scientific-Y ordering and guided interval rules. |

After selecting the required monotonicity or ordering, press **Apply** at the
bottom of Viewer settings. Verify the saved confirmation before closing the
window; a selection left in an unapplied dialog is not persisted.

Choosing a monotonic axis sets the matching point ordering automatically;
changing the ordering to another axis clears monotonicity. These settings
belong to the currently selected Interactive Document, not to the CORE User
or Session defaults or any other configuration. Existing Sessions retain
insertion-order behavior until the operator explicitly changes their settings.

The sort is stable; equal coordinates preserve their previous relative order.
After moving a point, accepting complete or individual assisted segments, or
manually adding a new point, scientific point order is recomputed. Publication
applies the chosen ordering independently to each selected calibration and
publishes `point_index` accordingly. No scientific measurement positions are
changed by sorting. The setting is not evidence that measured Y is monotonic;
for an XY plot a curve can remain non-monotonic in Y while ordered by X.

In **Delete** mode, click an existing committed scientific point to remove it;
use Undo to restore the point. **Add correction point** is separate: it only
changes the *uncommitted* proposed trace, never a published scientific point.

## Automatic enhancement of a raster image

In **Image Processing**, click **Try automatic enhancement**. The plugin
examines a bounded image sample and chooses a conservative non-geometric
ImageMagick pipeline based on visible contrast, edge structure and highlight
clipping. The suggestion may use auto levels, local contrast, gentle gamma or
light sharpening. It intentionally does **not** introduce thresholding, heavy
median denoising, polarity inversion, geometric resampling or cropping.

The suggested operations are shown in the existing editable filter controls.
When ImageMagick is configured, the plugin immediately processes a new preview.
The original image Dataset is unchanged; the user must inspect the resulting
image in the split comparison, optionally change the filter order and values,
and explicitly publish a processed Dataset if desired. The procedure is a
**heuristic suggestion**, not an automatic guarantee of better curve extraction
or higher scientific accuracy.

**Restore filters before auto enhancement** restores the preceding pipeline
while working on the same source and configuration. Automatically suggested
operations are saved in the current digitizer configuration like manually
selected operations. When tracing, use `auto` or `processed` under Trace image
to analyze the enhanced pixels without altering their raster geometry.

## Canvas background and image opacity

These settings are display-only and never change the source image or
scientific coordinates:

- **Image opacity** adjusts the visible raster from 0% to 100% relative to the
  canvas background, leaving guides, curve points and overlays fully opaque.
- **Canvas background** accepts a valid `#RRGGBB` color (with common presets).

The settings are available both in **Curves** and in **Configuration → Viewer
settings → Display**. They are saved **individually for each Curve Digitalizer
configuration**, rather than shared accidentally between profiles. New
configurations take initial defaults from GX-TXT's official central module
Configuration API, which declares `image_opacity` and `canvas_background`.
Changing one configuration does not rewrite another configuration's appearance
or the central defaults. The same display-only appearance applies to split
comparison viewports. It is never used as input to the tracing algorithm.

## Published digitization quality and scientific diagnostics

Quality Schema v2 is generated **at publication time**, from the same raster
points, selected accepted calibration measurements and actual output row count
that are written to the Dataset. It is independent of the interactive viewer.

The report has per-curve and per-segment entries suitable for highlighting
suspect intervals over the original raster in GX-TXT Dataset Preview. Each
segment includes the stable curve ID, zero-based index, original pixel XY
endpoints, segment-length observations and sampled grayscale line contrast.
These observations cannot distinguish an overlapping graph grid from the desired
trace and therefore are **not** an accuracy estimate. Diagnostic counts and
truncation flags are explicit for large Datasets.

A combined multi-calibration Dataset distinguishes `unique_raster_point_count`,
`calibration_realization_count`, and the **actual** `published_row_count`.
The independent calibration records report geometry and condition, and an
optional descriptive spread across realizations (not statistical uncertainty).
Exactly constrained four-point reprojection RMS is **not** independent accuracy.
Independent calibration verification is marked as not recorded because the
current ephemeral verification marker is not an authoritative persisted record.

The API and its report layout were replaced outright, without compatibility
with old Quality Schema v1. Republish old Dataset outputs to obtain v2.

### CURVE_DIGITIZER_QUALITY_API_v2

```tcl
::GX::modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_QUALITY_API_v2
set quality [::GX::CurveDigitizerQuality::read $datasetId]
set present [::GX::CurveDigitizerQuality::hasReport $datasetId]
set report_json [::GX::CurveDigitizerQuality::reportJson $datasetId]
```

The result includes source integrity, row/curve/calibration counts, detailed
report JSON, observational image evidence and explicit metrology limits.
The same provider is registered for Python and Octave Script Bridge with
`diagnostics`, `issue_report` and `has_quality`. The complete schema, coverage,
field semantics and examples are in `QUALITY_API_v2.md`.

The other Calibration, Dataset Schema and Image Processing APIs are unchanged.
Together they provide what Dataset Preview needs to render source-image
background, calibrated curves and located diagnostics without reading private
Curve Digitizer configuration documents. Display rendering belongs to GX-TXT.


## Reviewed pixel and calibration uncertainty

The **Publish** tab contains an **Uncertainty...** button next to **Publish selected calibrations**. It opens the **Pixel and calibration uncertainty** dialog. This declaration is scientific information saved in the current GX-TXT configuration, not a cosmetic rendering preference and not an automatically estimated quality score.

Choose an error model:

- **none** (default): publication is unchanged apart from the stable `point_id` variable. No standard uncertainty is inferred from raster resolution, snapping or Quality API scores.
- **pixel_calibration**: explicitly select either `rectangular_full_width` or `normal_standard_uncertainty`; provide the two pixel error widths/standard uncertainties, twelve calibration input standard uncertainties (the eight image corner coordinates and the X/Y minimum/maximum), and written evidence or rationale. Rectangular *full width* `w` represents a uniform interval and becomes a standard uncertainty `w/√12`.
- **physical_override**: supply independent standard uncertainties along scientific X/Y axes, in their respective units, together with explicit evidence. This replaces the pixel/calibration model, without claiming that the original physical uncertainty has been measured.

Press **Apply and save declaration** to persist the assumptions in the selected configuration. Changing the scientific points, calibration or source afterward invalidates the review and requires applying the declaration again before publishing. The dialog reports whether the declaration has been accepted. The raster image, curve coordinates and the current calibration are not altered. When publishing separate calibrations, the declaration is independently evaluated for each accepted mapping. A Combined Dataset with **multiple** calibrated realizations and an enabled uncertainty declaration is rejected explicitly: shared original pixel-point error correlations across realizations require a separate validated model. Disable uncertainty or publish them as separate Datasets.

If the declaration is enabled, published Datasets also contain `sigma_x`, `sigma_y` and `covariance_xy` and a compressed low-rank representation of shared calibration factors. These quantities are standard uncertainties/covariance in physical units, not estimates of visual fidelity. Calibration-common effects can correlate distinct points; do not treat marginal sigmas as independent weights when shared terms exist. Consult the actual scientific metadata and the public **Uncertainty API**, not the GUI state.

**SEM note:** A scale-bar length error and the center/inner/outer convention are not equivalent to the twelve generic homography corner input uncertainties. If the SEM source has a physical scale-bar calibration, this implementation refuses nonzero corner uncertainties. Use a justified physical override until a specific measurement model for scale-bar length and endpoint localization is available.

**Limits:** the reviewed output is limited to 4096 rows per Dataset; full covariance matrices are materialized only for up to 512 rows. Larger datasets retain compact factors without materialization where the metadata bound permits it. When uncertainty is declared, propagation and publication require the dev097 Numeric/CORE owner. The public Fitter binding is validated by CORE Statistical Semantics; a separate managed full response covariance must be published to use an eligible GLS route. The plugin refuses to silently fall back to local calculations when those services are missing. See [Uncertainty API](UNCERTAINTY_API_v1.md) for the actual public reader, formulas and scientific qualifications.


### Core-reviewed uncertainty and covariance for Fitter

In GX-TXT dev097, an explicitly declared uncertainty is processed by **`::GX::NumericAPIv1::callOperation`** through the **public Numeric API** and validated by the **public Statistical Result Semantics API**. The original point IDs, exact scientific row order, calibration identity, saved declaration, numerical result and source SHA-256 remain bound to the published Dataset. Do not interpret marginal `sigma_x/sigma_y` as independent errors when calibration terms correlate different points. For eligible response-only GLS, publish an original-order full covariance through the public Uncertainty/Companion APIs; this ignores predictor uncertainty, as the Fitter qualification reports. No implicit statistical error model is created when the uncertainty field is disabled.

The operator may explicitly enter **0** for either or both pixel-localization uncertainties, with an evidence/rationale. The plugin does not silently use one pixel, half a pixel, resolution or any other lower bound as a standard uncertainty. Calibration corner/axis uncertainties can remain strictly positive and are propagated independently through CORE. A zero statistical variance may make some fitting methods inapplicable; the CORE scientific fit plan, not the GUI, decides admissibility. The integrated GX-TXT Numeric provider supports explicitly declared zero pixel-localization uncertainty through the public numerical contract.

The initial dialog does **not** propose any numeric pixel, calibration or physical uncertainty value. All must be supplied intentionally together with a rationale. The editor's absence of a number is not interpreted as 0 or 1. Inability to activate the required dev097 Numeric CORE prevents an uncertainty-enabled publication, without affecting ordinary publication with `none`.

See [UNCERTAINTY_API_v1.md](UNCERTAINTY_API_v1.md) and [the public Numeric API](../math.numeric/NUMERIC_API_v1.md) for the supported operations and covariance contracts.

### Scientific publication consistency (2.0.3)
With explicitly enabled uncertainty, CORE Numeric is authoritative. The Digitalizer compares the complete independent and calibration-shared factor arrays with the local preflight model before scientific publication. This detects cross-point covariance differences invisible to marginal standard deviations. A mismatch prevents publication.

The published `covariance_xy` variable carries the physical product unit X*Y in Variable Schema v3 and matching Dataset metadata. Atomic units use product notation (e.g., `V*mA`); compound axis expressions are parenthesized to avoid changing their meaning. A parenthesized or custom unit symbol can be opaque to the Unit Registry: do not assume a conversion without a CORE-approved conversion plan.

The public Numeric API validates exact zero localization and shared calibration factors. Fitter GLS/ODR consumers apply their independent covariance eligibility checks.
