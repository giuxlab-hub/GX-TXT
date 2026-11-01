# DEV111-P017 current History integration

The manual Viewer architecture and scientific image/figure/annotation hooks remain in the plugin. CORE owns the active C++ records, image/figure domain contexts, ordered background journals, recovery, scheduling, shared timeline/details/menus and lifecycle. Private 80-state timeline trimming, figure Undo stacks and image Redo ownership have been removed. Current and domain-cursor snapshots contain no accumulated records; complete records are materialized only for explicit Save, export/Document projection or lifecycle boundaries.

The mapped GUI validation uses actual xdotool preset acceptance, Native2D rectangle drawing, image and figure Undo/Redo, Restore Original Undo, read-only History browsing, application-bounded upper popups, explicit Save/reopen, restart/Clear and verified journal recovery. Ninety additional model-level annotation edits prove retention beyond the former 80-state bound. Canonical source SHA-256 remains unchanged. Historical plugin-only validation notes below describe the pre-P017 implementation and are retained as development evidence; their old stack/timeline descriptions are superseded by this section and the current manual.

# Scientific Image Inspector — Technical Delivery Report

SPDX-License-Identifier: GPL-3.0-or-later

## Scope

Independent Viewer plugin for accepted GX-TXT dev096 public contracts. No modifications to GX-TXT CORE, Curve Digitalizer, PDF OCR, dev097, dev098 or user Sessions. Full source package includes module and plugin descriptors, GUI, Native2D canvas host, ImageMagick operation catalog and execution adapter, Session Workspace adapter, Dataset publication and manifest API.

## 0.4.1 documentation and packaging audit

- The installed-module version, plugin-package version and public API's `::GX::SII::version` are now identical (`0.4.1`), with an executable descriptor/catalog/manual regression (`tests/documentation_version.tcl`). `Help → About` projects that one API-owned version string.
- The user manual was rewritten as the current authoritative task guide; it distinguishes accepted single-image processing, ephemeral previews, Workspace drafts, ROI, annotation objects, figure compositions, Dataset publication and metadata. The complete 15-preset reference comes from `basicPresetCatalog` and the 69-operation counts come from `catalogList`.
- Viewer-local F1/manual now offers text Find/Find next (Ctrl+F, F3) without adding a second markup engine. The unused technical-report Export button was removed because its callback did not exist; report copy and canonical image-Dataset publication are unaffected.
- Test coverage: headless ImageMagick, preset, figure, Workspace and GUI/Xvfb/Native2D dev088 smoke passed after this change. Integration into a live dev096 Session, persistent save/reopen across GX-TXT restart and Windows GUI remain unverified. CORE contracts and runtime processing algorithms were not rewritten.

## Implemented behavior

### 0.3.9 Basic/Advanced Editor, shared Native2D image canvas

- The left Editor panel has two mutually exclusive tool views: Basic and Advanced. This is strictly a GUI/navigation distinction; the same Native2D working image canvas, ordered processing recipe, Workspace ID, History, and publication path remain authoritative.
- Basic Editor exposes 15 purpose-named presets with inspectable descriptions and ordered catalog operation names before a user requests a preview. The operations are not learned, image-classified or physically calibrated. ImageMagick verification on disposable RGB images successfully executed every preset and yielded 12 distinct pixel results.
- Advanced Editor directly embeds the **existing** validated catalog/parameter-form implementation in the Editor, rather than adding a second execution adapter. Unsupported/recognized-but-not-enabled operations remain disabled with reason strings; ROI availability is catalog-driven. Legacy `Operations` sidebar requests redirect to Advanced Editor. Old saved `operations` sidebar preferences are treated as `simple` without rewriting Configuration.
- GUI regressions checked that switching editor tool views changes neither accepted steps, source identity, working image, Workspace nor pending-preview state; a Basic preset generates an uncommitted preview and Discard restores the same accepted image.
- The original user-facing image canvas and Native2D interactions (zoom/pan, annotations, pivot), History strip and Dataset publication remain unchanged. No GX-TXT CORE files have been modified.


### 0.3.8 Native2D error-state recovery

The live Native2D shared-library test confirmed that degenerate line/arrow and zero-area rectangle `sketch_create` calls return `invalid input`. The plugin rejects these shapes before changing the recipe. An invalid retained annotation is isolated during redraw and reports a stable ID, name, geometry and cause, without deleting Workspace payloads. The GUI regression exercises subsequent zoom, select and new-arrow operations as well as a right-click on History. Explicit editing-tool actions exit read-only historical inspection by restoring Latest; only a confirmed Restart truncates History.

### 0.3.7 focused GUI corrections

- The inherited CORE Native2D ViewportHost tooltip is overridden for this Viewer only, to prevent root-window positioning artifacts on Windows. A withdrawn, delayed, Viewer-child Tk tooltip is measured and clamped before mapping. No global CORE commands are overwritten.
- The Description / History selector uses an upward-opening menu to avoid Windows native combobox popups falling below the screen. History still uses CORE Workspace persistence and the existing chronological recipe, with no new registry.
- Toolbar controls continue to use the shared Native2D ViewportHost glyph/layout, but this Viewer dispatches its own mode/menu/zoom callbacks. This avoids the common host adapter's unconditional changed callback and the redundant Native2D redraw while a menu is open.
- Canvas event errors are intercepted in the Viewer: status-line report plus full stderr diagnostic instead of a host-level `bgerror` modal. Failed automatic Workspace writes are reported inline; no source Dataset bytes are touched.
- GUI tests include forced invalid input on a Native2D toolbar callback and mouse event to verify containment. The reported Windows error could not be reproduced on Debian/dev088; integration with the actual end-user dev096/Windows build remains a necessary follow-up check.


- Primary working canvas is visible alone by default, showing accepted modifications. The second canvas is a **transient pending candidate**, displayed only when an ImageMagick operation/preset is proposed. **Accept preview** commits the ordered operation recipe; **Discard preview** leaves it untouched. Candidate file and pixels remain temporary; the canonical source is never overwritten.
- Editable annotation objects with stable IDs (text, arrows, lines, rectangles and ellipses) are placed directly on the main canvas. Native2D owns world/device transforms and geometric primitives, including drag gesture previews and handles; Tk is used for text glyphs and event delivery. Click-to-select, direct movement, endpoint resizing and double-click text editing preserve the object IDs in the editable Workspace recipe. JSON layer data is a generated interop projection in the same CORE-owned Workspace payload. Switching into Figure composition preserves independent source-image and multi-panel annotation layers.
- Pending filter/processing previews disable other editing commands, source selection and Workspace operations until Accept or Discard. The analysis and editing models cannot be accidentally altered by mouse/keyboard while pending.
- The bottom Description/History strip follows Curve Workbench’s compact combo/canvas timeline, click-to-inspect and right-click-to-restart interaction model. It stores bounded, lightweight recipe snapshots within the existing CORE Workspace payload (`history_timeline`), not pixel buffers or a private registry. Browsing is read-only and never calls `sessionWorkspaceUpdate`; a confirmed restart truncates later snapshots. Legacy Workspaces load with their current recipe as the base checkpoint. This remains distinct from a unified CORE Scientific Recipe patch engine and preserves pre-existing Undo/Redo domain stacks.
- Processing History uses Undo/Redo and Restore Original; restoration also clears the active annotation/figure edit state, with an immediate Undo snapshot. Workspace lifecycle/identity uses `SESSION_WORKSPACE_API_v1` + Interactive Documents, not a plugin-local persistence database.
- Analysis target is explicit: Working, Source or pending Preview, with an independent Working-only ROI checkbox. Histograms use 8-bit bins. Separate read-only channel display avoids mutating the visible working raster. Source metadata is distinguished from image processing. Preview LOD uses ImageMagick and Native2D transforms.
- User publication path is **only** `DATASET_FILE_PUBLICATION_API_v1` into a new `image.raster` Dataset (PNG16, TIFF16, TIFF32f). No image Save As / Export File action, no direct file report export. Framework Dataset export remains outside plugin.
- Manifest contract uses `DATASET_METADATA_API_v1` with keys `image.inspector.manifest` and `image.inspector.manifest_schema`. `::GX::SII::manifestGet`, `manifestSummary` and `apiCall manifest_get` permit headless use by other modules. Records parent hashes, source image facts, operations and ROIs, per-panel composition, annotations, ImageMagick engine, output properties/expected SHA and Workspace ID. The first-party CORE file publication service remains authoritative for committed Dataset identity and SHA.
- Viewer startup never selects the first available Dataset; only user choice, a named Workspace or a distinct `dataset_id` Viewer open context loads a source. Select / Transform / Pan / Draw show mutually exclusive active states through `native2DViewportToolState` with a Ttk compatibility fallback for older hosts. Help → About reads the plugin version declared by its public API, not a separate hardcoded dialog string.
- F1 and Help → User Manual open a dedicated toplevel containing **only the plugin manual**, rendered with the existing GX-TXT markup facility when available.

## Verified GX-TXT public facilities

| Requirement | Public API | Use |
|---|---|---|
| Viewer activation | Viewer Provider + Standard Module API | Lazy registration/activation |
| Canvas, geometry, pan and zoom | Native2D Geometry, ViewportHost | Shared retained transformations and shapes |
| Executable selection | Configuration/runtime Tool Resolver | `runtime.magick` |
| Sidebar defaults | Configuration module field | CORE User/Session precedence and commit |
| Workspace identity and portability | Session Workspace + Interactive Document | Save/open/rename/duplicate/manager |
| Derived image persistence | Dataset File Publication | Canonical new Dataset |
| Provenance and query | Dataset Metadata | Opaque structured UTF-8 manifest in existing metadata authority |
| Manual rendering | CORE markup renderer | Dedicated Tk toplevel, not global Help tab |

### 0.4.0 Workspace-local UI and ROI dispatch

Sidebar `sidebar_sections` is part of the existing `scientific_image_inspector.recipe.v2` payload and is validated in the registered Workspace provider; it uses CORE `sessionWorkspaceCreate/Get/Update` via existing `saveState`. The registered module Configuration `sidebar_tabs` supplies only a new draft's initial default and is no longer changed by the sidebar Apply dialog. This deliberately separates Workspace state from User configuration and avoids a second persistence authority.

`runtime/roi_context.tcl` dispatches right-click based on the active canvas context: pending candidate → Accept/Discard; figure composition → Edit source image; pixel inside ROI → ROI-specific actions; otherwise → existing Native2D object/creation context. Native2D device↔world conversion remains the coordinate authority. ROI processing draws from the shared catalog and `operationStatus`; incompatible or unavailable operators cannot enter the menu. Parameterized operations reuse one validated form then call `previewSteps`, leaving Accept/Discard unchanged. Cropping remains a separate whole-image geometry operator supplied with the exact selected rectangle. Source images are never overwritten.

`previewSteps` offers a guided figure-to-image transition rather than throwing a generic modal error. `editSourceImage` restores the individual working image through the existing rendering path and retains saved panel composition and independent annotation layers. Historic projects without `canvas_mode` are no longer automatically coerced to figure mode. Planned Native2D retained raster layers/figure composition are excluded pending CORE APIs; no CORE gap is asserted as implemented.

## Tests performed

- Engine/ImageMagick tests: representative RGB/alpha images, TIFF16, multipage TIFF, TIFF32f, ROI operation, per-channel stats/histogram and pixel sample, injected/unknown parameter rejection, immutable source SHA, publication mock and manifest metadata.
- Figure tests: independent per-parent image operations, layout, editable text/arrow/rectangle definitions, high-bit-depth output, preserved source hashes and exact multi-parent publication lineage.
- Tk/Native2D Debian Xvfb tests: editable overlay drawing, move/resize, pending-edit lock, viewer creation, one working canvas, temporary candidate, explicit Accept, panel restoration, mouse wheel zoom, responsive LOD, stacked scrollable sidebar, annotations, two distinct named Workspace states and F1 manual window.
- Headless API readback: canonical Metadata test double exposes published manifest; tests confirm ID, ordered steps, summary and missing-manifest error. This does not claim production end-to-end persistence across framework restart.

## Known limitations and CORE gaps

- No confirmed blocking CORE gap for this set of features. All persistence and publication is built on public API contracts; no CORE edits were made.
- The Native2D raster presenter requires persistent Interactive Document-owned raster resources. Ephemeral image previews therefore use bounded Tk images positioned by Native2D world/device transforms; source-backed high-detail tiles are generated asynchronously from the authorized image. A generic transient Native2D raster-source binding would be a potential optional CORE enhancement, **not** implemented here.
- ImageMagick catalog has 69 defined entries (46 validated/executable, 17 recognized-but-not-enabled, 6 restricted); actual engine policy/delegates can further restrict availability. Interactive clone/healing/brush, advanced layer stack and calibrated scale bars are not implemented.
- Figure display previews are 8-bit; manuscript publication recomputes full-resolution source data. TIFF16 is an output container choice, not a universal guarantee of linear physical measurements or ICC fidelity. No 16-bit-native histogram, complete profile-management pipeline, or automatic camera/sample calibration.
- No GUI-based real dev096 Plugin Manager installation, persisted Session restart, Manager import/export or output Dataset re-opening was performed here. The tests use isolated CORE native Tcl libraries and Session/API doubles. Such tests require an authorized disposable GX-TXT Session.
- Output UI does not offer direct file export as requested. The lower-level figure composition engine retains caller-managed output files **for internal temporary publication processing and isolated tests only**; it is not exposed as a user Save As action.

## Annotation-mode interaction and Native2D reuse

The viewer uses the same `native2DViewportControls` and `native2DViewportGlyph` pattern as Curve Workbench. The Select icon activates direct annotation selection; Esc finishes editing. Transform displays Native2D gizmos for the active annotation. A single drawing-menu CORE glyph exposes text and vector shape creation, without a large second palette. Right-button context actions use `native2DViewportContextMenu`. Mouse motion and full-resolution geometry are handled separately from transient Tk paint items.

Native2D owns sketch geometry, world/device conversion and affine transformation. Annotation rotation/pivot are logical per-object properties in the Workspace recipe, because a scene-global Native2D pivot cannot independently encode multiple text/shape overlay pivots. The validated affine matrix is supplied to Native2D sketch definitions, not regenerated as a parallel sampled geometry. Text rendering uses a Tk canvas text item with angle during interactive editing, and ImageMagick during explicit Dataset publication. Per-annotation pivots are measured in uncalibrated top-left image pixels. The image Dataset is immutable.

UI preferences (including optional exact coordinates) come from GX-TXT's module Configuration. The dedicated mode is separate from the ImageMagick candidate preview lock. GUI smoke testing uses the isolated dev088 native libraries; stable dev096 API source was reviewed, but live dev096 integration/installation has not been performed.

## Native2D annotation controller (0.3.3)

The working canvas uses the shared `native2DViewportControls` icons (`select`, `transform`, `pan`, `edit`, `panel`, `zoom_in`, `zoom_out`) and its ContextMenu. Each editable logical annotation has a stable `annN` identity and a separate printable name. For vector shapes, one or more CORE retained sketch tokens are created and selected using `Native2D::core object_style selected`. Text glyphs require Tk, but text also has a retained Native2D rectangle selection proxy. These are **ephemeral viewport tokens**, never canonical Workspace identities.

Selected operations use `Native2D::core gizmo` / `gizmo_hit` / `gizmo_parameters` and `drag_begin` / `drag_translate` / `drag_rotate` / `drag_commit`; the managed native pivot is moved by the pivot gizmo handle. A Native2D receipt updates the symbolic image-pixel JSON recipe after an atomic gesture. Live vector feedback comes from `native2DPresentationObjectSnapshot`; glyphs use the receipt for visual projection. Interactions do not modify the source Dataset. The old per-canvas selector is now only a navigation/list compatibility surface, not the transform authority for the Native2D gizmo.

The plugin still has limitations: interactive multiline text is finalized only on Apply; Tk displays rasterized font glyphs, not retained Native2D text; selected-object resize is not yet implemented as a generic Native2D gizmo. Existing endpoint geometry editing remains a specialized compatibility path when Native transform mode is disabled. Full Session persistence must be tested in an installed dev096 instance.


## Focused 0.3.4 corrections

- Discovered a duplicate `native_gizmo` presentation lifecycle: clearing `figure_annotation` left the CORE gizmo items on the Tk canvas. The refresh function now deletes `native_gizmo` before redrawing from the actual Native2D scene. A repeated-redraw test asserts the same item count.
- Creation controls use one Native2D ViewportHost drawing menu, with Add Text alongside shapes; the previous separate Text button is removed.
- Text input is a temporary Tk editing overlay positioned through Native2D world/device transforms, with a dashed border drawn on the canvas and CORE UI Field color picker (`uiFieldCreate` / `uiFieldChooseColor`). Font names are discovered through the configured ImageMagick binary and are used for final publication; Tk only previews the glyphs.
- The original dataset and Workspace registry are untouched by text placement. Editable font/box metadata survives the same validated project and manifest mechanisms, including the pixel-to-point conversion resolution assumption.
- Limitations: interactive font rasterization may not exactly match the ImageMagick output metrics, and multiline annotation layout is not implemented. The new text editor operates on the annotation layer; it does not alter source image pixels.

## 0.3.5 Native2D object selection and UI settings

The current selection identity is `ui(annotationActiveId)` (a stable Workspace-level `annN` ID), not the listbox `curselection`. The sidebar list is only an optional projection of the controller's selection. The CORE Native2D scene is the geometric authority for `selection_pick` (device coordinate, object target) and `selection_region` (Native2D world polygon, object target). The latter is used by Window and Polygon selection. The raster/pixel ROI is a distinct selection domain; it automatically enables ROI scope for operators the validated catalog permits. Image geometry-changing commands still require whole-image scope. Tk `bbox` serves only transient on-canvas selection highlighting; it is not a geometric measurement authority. Native2D gizmos continue to own pivot, translation, rotation and the live transform transaction. Text keeps a Native2D rectangle selection proxy with Tk for font glyphs.

The native gizmo currently manipulates one active annotation. Multiple selected annotations are suitable for Copy/Paste and visibility feedback, but whole-group geometric transformations have **not** been implemented. The Editor uses a dedicated in-memory annotation clipboard (not a file export or global image clipboard), creates fresh IDs and records a figure Undo snapshot before Paste. Edit Undo/Redo routes to existing domain stacks, not yet a unified chronological transaction manager; History redesign remains separate.

Configuration's `sidebar_tabs` and `annotation_coordinates` values retain the GX-TXT Configuration authority. The new Viewer Settings dialog is a projection with Interface, Annotations, and Processing pages, not a second persistent settings service. All UI text remains English. Changes have been tested using the actual Native2D dev088 build available in a disposable test tree plus accepted dev096 API signatures. **Live dev096 Plugin Manager / Session integration is still unverified.**
