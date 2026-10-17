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

GX-TXT 0.9.7.78 `acq.image_binary` normally imports PNG, JPEG, BMP, and TIFF and preserves the original canonical resource. Curve Digitalizer reads that canonical resource through the public Dataset API. It does not inspect or construct private Session paths.

The desktop adapter uses Pillow to decode the resolved image resource.

## 4. Opening the viewer

Open an existing GX-TXT Session, import an image through the normal image acquisition workflow, then open:

```text
Viewers -> Curve Digitalizer
```

The Viewer Provider is discovered headlessly. Python/Tk/NumPy/Pillow are checked only when the interactive viewer is opened.

If no Session is open, the viewer reports an error instead of creating private state outside GX-TXT.

## 5. Digitizer Configurations

A Digitizer Configuration is the authoritative scientific work object for one calibration and one set of curves. It is stored in the current Session as a GX-TXT Interactive Document.

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
- a state format/version.

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

### 8.3 Four calibration points

After applying the axis settings, select the calibration points in this order:

```text
bottom-left
bottom-right
top-left
top-right
```

The model computes a projective homography from the image quadrilateral to normalized plot coordinates and then maps normalized coordinates through the selected linear/log axis transforms.

The status line reports calibration readiness, conditioning, and corner residual information.

### 8.4 Calibration verification

Use the verification controls on a known grid intersection or other known coordinate. Curve Digitalizer reports calculated X/Y values and, when expected values are supplied, the residuals.

Verification is diagnostic; it does not change the calibration.

## 9. Curves

Each curve has a stable internal `curve_id`, a display label, and an ordered list of points.

Use **New curve**, **Edit curve**, and **Delete curve** to manage curves. Visibility can be toggled without deleting data.

Curve labels are not technical identities and may be edited.

## 10. Numerical curve families

Enable **This configuration is a numerical curve family** only when one real numerical quantity parameterizes the curves.

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

The Notes tab stores a small plain UTF-8 note inside the configuration. It is suitable for short scientific context such as legend interpretation, scan distortion, or excluded dashed curves.

It is not intended as a general text-editor subsystem.

## 15. Publishing independent curves

When family mode is disabled, **Publish Dataset** writes a `table.generic` Dataset in long form.

Stable variables are:

| Variable ID | Meaning |
|---|---|
| `x` | calibrated X value |
| `y` | calibrated Y value |
| `curve_id` | stable internal curve identity |
| `curve_label` | user-visible curve label |
| `point_index` | zero-based order within the curve |

X and Y carry the configured labels, units, semantic roles, value kind/dtype, and canonical unit when Unit Registry resolves one.

The module does not sort X globally. Non-monotonic curves remain non-monotonic.

## 16. Publishing a numerical curve family

When numerical family mode is enabled, **Publish Dataset** writes the existing GX-TXT `curve_family.table` contract.

Stable variables are:

| Variable ID | Meaning |
|---|---|
| `x` | independent coordinate |
| `family_value` | numerical family parameter |
| `y` | measured/dependent value |
| `curve_id` | stable internal curve identity |
| `curve_label` | user-visible curve label |
| `point_index` | zero-based order within the curve |

The default semantic roles are `independent`, `family`, and `measured`, but the user-visible configuration remains explicit.

## 17. CSV artifact and Canonical Dataset

Publishing is one operation:

```text
Publish Dataset
  -> Dataset Publication API v2
  -> CSV scientific artifact
  -> Dataset registry entry
  -> Variable Schema
  -> Dataset Metadata/provenance
```

The user does not export a CSV and then import it again through Acquisition.

The CSV remains a portable scientific artifact, while the Canonical Dataset is immediately available to compatible GX-TXT consumers.

## 18. Output Dataset identity and republishing

The Publish tab allows an output Dataset ID and display name. A deterministic default is derived from the configuration name.

Configuration identity and output Dataset identity are separate.

Publishing the same configuration again after editing points requests same-owner replacement through Dataset Publication API v2. The intended Dataset ID remains stable, while the numerical artifact and SHA-256 are updated.

GX-TXT ownership rules prevent this module from silently overwriting a Dataset owned by another producer.

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

Close the stale Curve Digitalizer window and reopen it from the intended current Session.

## 23. Known limitations

- The viewer is manual/semi-assisted; it does not implement automatic curve tracing or OCR.
- A source must already exist as a compatible Image Dataset; direct filesystem image opening is intentionally absent.
- The interactive adapter requires a working Tk display (local desktop, X11 forwarding, or equivalent).
- Optional darkest-pixel snapping is local and image-intensity-based; it does not understand curve semantics.
- Scientific downstream execution depends on the downstream module/runtime. For example, actual `plot.dataset` rendering or numerical fitting requires the runtime used by those modules (normally GNU Octave on the target GX-TXT installation).
- The plugin does not modify CORE and does not provide its own private image importer, unit registry, worker pool, or publication store.

## 24. Keyboard/mouse interaction

Core image interaction inherited from the original canvas includes:

```text
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
version 1.0
```

It is an implementation state contract for this plugin, not a replacement for published scientific Datasets. Downstream modules must consume the published Dataset rather than this document.


## Companion-module integration

Curve Digitalizer provides `CURVE_DIGITIZER_COMPANION_API_v1` for tightly coupled tools such as Curve Trace Assistant. The authoritative state remains the existing `gxtxt.curve_digitizer.configuration` Interactive Document. Companion modules do not create their own project file or duplicate calibration.

The API exposes stable configuration and curve identities, resolves the associated Image Dataset through public Dataset APIs, verifies the stored source SHA-256, and can append accepted pixel points to a selected curve. Pixel-to-scientific conversion is performed by the same Curve Digitalizer calibration model used by manual points.

Companion writes are guarded by both the live Session token and the expected Interactive Document SHA-256. If another window or module changed the configuration, the write is rejected and the caller must reload.

## Pixel and calibration uncertainty

Open **Publish → Pixel / calibration uncertainty**. Choose an explicit pixel
distribution and X/Y scales, or independent physical standard uncertainties as
an override. Supply the twelve calibration standard uncertainties in the order
shown and explain the evidence or override. Zero fixes that calibration input.
Save and review before publishing; changes to points, calibration or declaration
require a fresh review. Historical configurations default to no uncertainty.

The common report explains first-order propagation, shared calibration and X/Y
correlation. Publication adds stable point IDs, sigma_x, sigma_y and covariance_xy
without changing x/y/curve/point_index identities. Standard uncertainty columns
use the physical axis units. A pixel width is never silently called sigma.

Fitter can use response sigma or actual both-axis ODR when the public CORE plan
allows it. Shared calibration requires correlated covariance; diagonal ODR cannot
represent within-point X/Y correlation. The dialog can publish an original-order
full X or Y covariance Dataset (up to512 points). Select its covariance Variable
in Fitter's full-covariance settings. This response-only GLS ignores predictor
uncertainty; its report preserves that qualification. A physical override is an
explicit replacement model. It does not erase the original calibration.

Review supports up to4096 original points and retains shared factors without
quadratic storage. Calibration, image hash, point order and numerical state remain
owned Session resources through publication, save/reopen and Script consumers.
See [the versioned API contract](../../../docs/api/DIGITIZATION_UNCERTAINTY_v1.md).
