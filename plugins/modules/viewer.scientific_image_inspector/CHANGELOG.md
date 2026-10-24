## DEV111-P017 — CORE native History integration

- Preserves the manually developed image/figure/annotation architecture while moving general and per-domain Undo state to CORE's shared native service.
- Replaces private 80-checkpoint and figure Undo trimming with complete bounded CORE retention, asynchronous journals and explicit Save/Close projection.
- Reuses shared bounded History controls, navigation, menus, grouping, Clear and recovery; retains independent image and figure Undo behavior and Restore Original rollback.
- Reads prior Workspace timeline data and saves compatible optional scientific/domain History records without changing canonical Dataset ownership.

## 0.4.2 — 2026-10-17

Declare distinct native-resolution scientific catalog artwork, short title and semantic group through the existing Viewer Provider descriptor.

## 0.4.1 — Complete user manual and consistent plugin release metadata

- Rewrote `MANUAL.md` as a complete, workflow-oriented English reference (installation, image modes, interface/menu map, every Basic preset and parameter, Advanced catalog, preview transactions, ROI context actions, Native2D annotation tools, Figure Studio, image/color analysis, History, Workspace persistence, canonical Dataset publication, manifests, troubleshooting, scientific integrity and practical tutorials). Removed obsolete Operations-menu directions, global sidebar-save claims, duplicate numbering and misleading descriptions of incomplete features.
- Added a search bar to the Viewer-local F1/Help manual window with Find next, F3, Ctrl+F and matched-text highlighting; still uses the existing GX-TXT markup renderer and does not invoke the framework-wide Help tab.
- Fixed the packaging discrepancy: `plugin-package.ini` was incorrectly still at `0.3.9` while `module.ini` and the public API said `0.4.0`. All three release declarations, About GUI test expectation and delivered ZIP now identify **0.4.1**. CORE API protocol versions and Workspace schema versions are unchanged.
- Removed a non-functional `Export` button in the technical image report (it invoked an undefined `exportReport` procedure). `Full metadata` and `Copy` remain available; the only raster output is canonical Dataset publication.
- Added `tests/documentation_version.tcl` to prevent version divergence, removed menu references and stale documentation of the preset inventory. Extended GUI smoke coverage for in-window manual search. Updated the current Workspace contract description in `docs/API.md`.
- Verified headless ImageMagick, 15 presets, multi-panel figures, manifest/Workspace models and Native2D/Tk smoke tests on disposable Debian/Xvfb/dev088 references. This is not a claim of a live GX-TXT dev096 Windows installation test. No active Session, Dataset, CORE or other Viewer was modified.

## 0.4.0 — Workspace sidebar, contextual ROI and image/figure switching

- Removed redundant top-level Operations menu while retaining the complete operation catalog inside Image → Advanced Editor.
- Visible sidebar sections dialog now has Apply/Close; Apply updates the stack immediately and persists `sidebar_sections` to the exact current CORE Session Workspace payload. No global User-default commit occurs; separate Workspace layouts remain independent.
- Added context-aware right-click on the working canvas. A selected ROI exposes crop, statistics, histogram, inspect pixel, compatible presets, categorized ROI-safe operations with generic validated parameter dialogs, Advanced Editor and Clear ROI. Pending image edits expose Accept/Discard instead.
- Added Edit source image to the composed-figure context and Image menu. A filter invoked on a figure now offers to switch to the individual image while preserving panels, figure annotations and current Workspace history. Missing `canvas_mode` on earlier alpha projects no longer infers figure mode merely from saved panels.
- Expanded Debian/Xvfb Native2D regression tests for Workspace sidebar persistence, ROI context/preview and figure-to-image handoff. No CORE or active Session modifications. Full Native2D layer compositing is deferred until CORE support is available.

## 0.3.9 — Basic/Advanced Editor tools and descriptive presets

- Split the Editor sidebar into Basic Editor and Advanced Editor without adding a second working image canvas or altering Workspace, History, source lineage, or explicit Dataset publication.
- Replace four near-identical fixed buttons with 15 task-oriented presets (Photo, Color, Scan, Microscopy, Diagram), each with readable purpose and the actual ImageMagick operation sequence before preview.
- Move the validated, searchable operation catalog and generated parameter forms into the Advanced Editor tool pane. Keep old Operations navigation as a backwards-compatible redirect to that pane.
- Reuse the same validated ImageMagick processing pipeline and acceptance/discard behavior for Basic presets and Advanced steps; no extra stores or processing adapters.
- Add focused UI regression and preset-validation tests. All text remains English.

## 0.3.8 — Native2D invalid geometry and History recovery

- Reproduced the reported `invalid input` in the actual Native2D C adapter: zero-length lines and zero-area rectangles are invalid sketch definitions. Validate those shapes before editing History or the Workspace.
- Recover independently from each invalid annotation in a restored or legacy project. Only its transient Native2D drawing is suppressed; valid annotations and the stored recipe remain available. Show object-specific diagnostics in the status strip and on stderr without a large application dialog.
- An explicit drawing/select tool activation returns from read-only History inspection to Latest; the future history is not discarded. Pending image-filter previews still require Accept/Discard.
- Limit History context clicks to real step boxes and guard its context/menu actions against Tcl background errors.
- Regression tests use the real Native2D binary to exercise invalid definitions, rejected gestures, recovery and the History popup.

## 0.3.7 — viewport tooltip placement, nonmodal tool errors, bottom History popup

- Keeps this Viewer's ViewportHost tooltip windows under its own toplevel; delays display until hover and positions the popup after measuring it, clamped to Viewer/screen bounds. Other GX-TXT Viewers and CORE code remain unchanged. The underlying CORE tooltip behavior may require a separate framework-wide review.
- Replaces the bottom-edge Description / History combobox with an upward-opening two-item selector. The compact scrollable History timeline and Workspace recipe checkpoints are unchanged.
- Corrects annotation toolbar dispatch: a mode change or popup opening no longer forces a redundant Native2D scene redraw via ViewportHost's generic changed callback. Zoom, pan, geometry, pivots and transforms still use GX-TXT Native2D.
- Guards the Viewer's toolbar and canvas pointer event callbacks so unsupported input does not escape as a GUI-wide Tcl background exception. A rejected gesture leaves the work in place, prints the full Tcl diagnostic to stderr, and reports its context in the Viewer status line instead of displaying a large modal window.
- Moves History observation inside the Workspace save error boundary. Failed automatic Workspace saves now report inline rather than interrupting annotation drawing. The original Dataset and previously committed Workspace are not overwritten by rejected tool events.
- Adds regression checks exercising real Tk icon commands and canvas event delivery, including an injected `invalid input` error, popup direction and tooltip ownership. GUI regressions run with the read-only Native2D engine from dev088; the end-user Windows/dev096 environment still requires confirmation.

## 0.3.6 — explicit startup, exclusive toolbar modes and Curve Workbench-style bottom History

- Opens a blank working canvas with an unselected Dataset chooser unless an explicit Dataset ID or Workspace was requested. Merely enumerating Registry images does not begin an editing Session or auto-open an arbitrary source.
- Adds Help → About Scientific Image Inspector with the activated module version (0.3.6) and license; F1 remains the standalone viewer manual.
- Makes Select and Transform tool highlighting exclusive, preserving Native2D ViewportHost state and a compatible Ttk fallback for older host implementations. Pan and Draw retain separate active states.
- Adds the bottom Description / History switch, with the same short strip layout, scrollable checkpoint timeline, pointer inspection, context menu and explicit confirmed Restart design used by Curve Workbench. No extra floating History window, Dataset Registry or Workspace authority.
- Persists bounded recipe-level History checkpoints in the existing Workspace payload. Historical inspection is read-only and leaves the registered Workspace unchanged; returning to Latest restores editability. Editing-domain Undo/Redo remains unchanged pending a later history unification.
- Improves Native2D stroke-picking tolerance at the displayed canvas pixel scale to keep thin annotations selectable after viewport layout changes.
- Adds GUI regression tests for blank startup, About version, exclusive toolbar selection, chronological History strip, history read-only behavior and Workspace timeline restoration, alongside unchanged image-processing and publication checks.

## 0.3.5 — canvas selection modes, optional annotation panel and Editor settings

- Removes the dependency of the active annotation on the optional sidebar list. The active object is identified by its stable annotation ID, so selecting directly on the canvas works even when Annotations is hidden. Entering annotation editing no longer reveals that panel.
- Reuses the Native2D `selection_pick` and `selection_region` operations to implement Object / Window / Polygon modes accessible by right-clicking the shared Select icon, following Curve Workbench's semantic selection pattern. Explicit image ROI mode continues to address processing pixels, not vector annotation objects.
- Keeps Tk canvas hit testing only for transient edit handles and text presentation. Native2D handles retained vector picking, scene transforms and selection geometry.
- Adds Edit menu (Select All Annotations, Select None, Copy/Paste annotations, Undo/Redo) with keyboard shortcuts that respect focused text fields. Pasted annotations get new stable IDs. Group transforms remain disabled; transforms target one object.
- Groups Viewer-specific controls into Configuration → Viewer settings (Interface / Annotations / Processing). Visible sidebar sections stays directly accessible; exact coordinates and ImageMagick capabilities move to the settings dialog. No second preference registry is introduced.
- Corrects resize-handle hit priority, selection highlighting, modal filter lock on Edit, stale active selection across source/Workspace changes, and the ROI-to-operation-scope behavior for compatible adjustments.
- Tests actual Native2D GUI object click with Annotations hidden, Window/Polygon selection, pixel ROI separation, annotation clipboard Undo and semantic settings on isolated Debian/Xvfb; existing regression suite still passes.

## 0.3.4 — unified creation tools and inline text typography

- Fixes repeated Native2D gizmo overlays after annotation redraw; the previous `native_gizmo` tagged items are removed before the CORE presenter draws the current selection.
- Unifies **Add Text**, Draw Arrow, Draw Line, Draw Rectangle and Draw Ellipse in the same canvas icon menu. Removes the separate Text icon.
- Adds image-space drag-to-size text placement, a dashed editable bounding box and a compact toolbar above it (or below when no room): GX-TXT UI Field color chooser, ImageMagick-discovered font selector, configurable pixel/point size, Apply/Cancel.
- Uses the configured plot font-unit default where available; point sizes are resolved against the explicitly configured graphic-output DPI (fallback 72 DPI), never EXIF/scientific pixel calibration.
- Keeps the editable font family, original size/unit, resolution assumption and text box dimensions in the Workspace, the JSON overlay API and published Dataset manifest; full-resolution ImageMagick output uses the selected verified font.
- Adds real Native2D GUI regression coverage for nonduplicating gizmos and in-canvas text controls. No CORE changes.

## 0.3.3 — named annotations, on-canvas text and native transform gizmos

- Adds user-editable object names and human-readable defaults separate from the stable annotation ID; preserves names in Workspace, published manifest and `annotations_json` API output.
- Moves creation, rename, editing, style and transform tools to the Native2D canvas context menu; adds a temporary inline text editor at the image position (Apply/Cancel).
- Reuses the same CORE Native2D gizmo contract as Curve Workbench: selected retained object tokens, `gizmo_hit`, `gizmo_parameters`, `drag_begin`, `drag_translate`, `drag_rotate`, `drag_commit` and the shared gizmo presenter. The selected text uses an invisible Native2D selection proxy; Tk remains the glyph presenter.
- Adds a dedicated Native2D Pan icon with exclusive pointer mode, independent of annotation editing. Transform icon supports a right-click Translate/Rotate menu.
- Replaces the floating annotation tool panel with Native2D ViewportHost Text and Shapes icons plus a context menu; reduces the annotation sidebar to a named object list and guidance. Exact coordinates stay opt-in.
- Adds GUI tests on a real Native2D binary for Free-handle translation, Rotate-handle rotation, Pivot-handle relocation, pan-mode gesture, and names in JSON. No CORE modifications.

# Changelog

## 0.3.2 — explicit annotation mode and Native2D context transforms

- Reuses the Curve Workbench pattern: framework-generated Native2D viewport glyphs (pointer and transform), shared ViewportHost annotation tool panel, and Native2D context menu integration.
- Makes annotation editing an explicit enter/exit mode. Exiting preserves visible overlays, hides selection handles, and restores ordinary ROI gestures. Filter preview locking remains independent.
- Adds per-object rotation and an editable pivot; numeric and mouse rotation, +90/-90 shortcuts, and mouse context actions for move, pivot, text editing and deletion. Vector shapes are displayed through retained Native2D affine sketches; text uses the Tk canvas glyph presenter.
- Records rotation/pivot in Workspace recipes and the public JSON projection/derived Dataset manifest. Publication applies the validated transforms to raster overlays.
- Hides pixel-coordinate controls by default and exposes them only through a Configuration-backed User preference.
- Adds isolated tests for mode lifecycle, Native2D viewport icons/context adapter, rotation, pivot, JSON and final figure raster.


## 0.3.1 — editable Native2D overlays and exclusive adjustment preview

- Adds immediate overlay feedback while drawing shapes and selecting/moving/resizing annotations directly on the working canvas. Shapes and drag feedback use Native2D geometry/presentation; Tk paints the retained text glyph overlay at Native2D-scaled positions.
- Introduces persistent per-annotation IDs, clickable selection and resize handles; selected properties can be edited in the inspector and text can be edited on double-click.
- Adds a validated JSON projection of annotation layer objects to the Workspace payload and Dataset publication manifest, with `apiCall annotations_json dataset_id` for headless consumers. The CORE Workspace and Dataset Metadata remain the sole storage authorities.
- Makes pending ImageMagick preview exclusive: disables editor/Workspace commands and source selection, rejects other modifications, and re-enables controls only after Accept or Discard.
- Adds gesture and modal locking tests on the Native2D Debian/Xvfb GUI.


## 0.3.0 — single working canvas, explicit approval, Dataset manifest

- Single main canvas shows accepted working image; optional right-hand pane is exclusively a pending adjustment preview. Accept/Discard controls manage operation commits.
- Editable text/shapes/notes placed on working image without first composing a figure; distinct image/figure annotation layers.
- Working/Source/Preview analysis targets and separate Working ROI selection; read-only channel preview.
- Restoring original clears recipe and active annotation/composition state with short-term Undo recovery.
- Viewer File menu no longer contains image or report file export. Publish only via canonical GX-TXT Dataset File Publication.
- Headless `manifestGet`/`manifestSummary` API exposes a structured, versioned transformation manifest from CORE Dataset Metadata.
- F1 opens the plugin manual in its own rendered viewer-only window.


## 0.2.2 — single stacked scrollable inspector

- Removes the separate vertical section navigator and hidden Notebook page stack, which wasted canvas width. The selected sections now appear simultaneously, one after another, in a single scrollable sidebar.
- Preserves Configuration-backed panel visibility (Editor + Figures by default) and gives temporary access to hidden sections from the existing application menus without persisting that one-off selection.
- Adds sidebar mouse-wheel scrolling and keeps the splitter adjustable; reorganizes Figure Studio buttons into two rows to avoid clipping in the narrower panel.
- Extends Tk GUI smoke tests for geometry, scrolling, selection, preferences, and hidden-panel menu navigation.

## 0.2.1 — compact navigation, adaptive display and Session Workspaces

- Replaces the wide horizontal Inspector tabs with a compact vertical section list and resizable sidebar (Editor/Figures visible initially); Configuration user defaults control visibility of other sections.
- Adds pointer-anchored mouse wheel zoom for Windows/macOS and X11 and asynchronous full-source, Native2D-aligned viewport image tiles (Lanczos resampling), replacing nearest-neighbour-only enlargement after movement settles.
- Registers the Session Workspace provider through the existing CORE API; adds the standard Workspace menu, named projects, Manager, Save/Open/New/Duplicate/Rename/Close/Delete, and stable identity/sha verification on reopen.
- Stops reopening the most recent recipe implicitly by source Dataset; independent workspaces for the same image remain isolated. Provides compatibility with prior recipe documents.
- Adds workspace provider model tests plus GUI checks for wheel zoom, LOD pixels and independent named workspaces.

## 0.2.0 — article figure editor and Native2D viewport

- Reorients the Viewer toward practical image editing and article figure preparation, with Simple and Advanced workflows.
- Integrates the public shared Native2D ViewportHost, controls, pixel-coordinate pan/zoom, optional grid and Native2D retained sketch geometry for text-independent vector shapes.
- Adds read-only Open Image File, simple image corrections and task presets, two-pane comparison with optional navigation synchronization.
- Adds multi-source grid/horizontal/vertical article figures with independent panel recipes, adjustable output size/margins/gutters and non-destructive text, arrow, line, rectangle and ellipse annotations.
- Adds figure edit history, editable annotation coordinates, full-resolution PNG/TIFF/JPEG/WebP export and purpose presets with effective print PPI.
- Extends Interactive Document recipes and derived Dataset publication with article figure source hashes, composition geometry and annotation lineage.
- Includes new headless figure tests and Debian/Xvfb Native2D GUI workflows, without changing GX-TXT CORE or existing Sessions.

## 0.1.0 — initial independent plugin

- Implements Viewer Provider / public headless Tcl API and ImageMagick runtime resolution via Configuration.
- Adds 69 categorized ImageMagick operations, typed validation, runtime discovery and a single controlled execution adapter.
- Adds a resizable Tk Viewer, Image Info, channel statistics, 8-bit binned histograms, ROI and full-resolution pixel inspection.
- Adds non-destructive, ordered processing recipes, Undo/Redo and Interactive Document state, independent original/processed zoom/pan, and explicit canonical image Dataset publication.
- Adds English manual, focused headless tests, Xvfb/Tk smoke test and technical implementation report.
