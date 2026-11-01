# Scientific Image Inspector — Complete User Manual

**GX-TXT Viewer plugin · User guide for the current editor**

Scientific Image Inspector is a non-destructive image editor, technical image inspector and figure-preparation tool inside GX-TXT. Use it with imported photographic, microscopy/SEM, scanned, diagrammatic and other raster images. ImageMagick processes raster pixels; GX-TXT Native2D provides viewport coordinates, retained annotation geometry, selection and transform tools; GX-TXT owns Dataset, Workspace, Configuration and publication services.

**The central rule:** opening, viewing, annotating, previewing or saving a Workspace **never changes the original canonical image Dataset**. An edited image becomes a new GX-TXT Dataset **only when you explicitly publish it**. The Viewer does not provide a general Save As / Export Image file command.

This guide describes the implemented functions. A missing feature is described in **Limits and scientific interpretation**, not presented as a working command. Interface names below are the English names used by the plugin.

## Contents

1. [Five-minute start](#1-five-minute-start)
2. [Image, ROI, annotation, figure and Workspace: five different things](#2-image-roi-annotation-figure-and-workspace-five-different-things)
3. [Open the Viewer and choose a source](#3-open-the-viewer-and-choose-a-source)
4. [Interface map, menus and sidebar](#4-interface-map-menus-and-sidebar)
5. [Move around the image and use the Native2D toolbar](#5-move-around-the-image-and-use-the-native2d-toolbar)
6. [Basic Editor and all 15 task presets](#6-basic-editor-and-all-15-task-presets)
7. [Advanced Editor and the operation catalog](#7-advanced-editor-and-the-operation-catalog)
8. [The processing transaction: preview, compare, accept or discard](#8-the-processing-transaction-preview-compare-accept-or-discard)
9. [Select a pixel ROI and use its context menu](#9-select-a-pixel-roi-and-use-its-context-menu)
10. [Create and edit annotations](#10-create-and-edit-annotations)
11. [Figure Studio: multi-panel compositions](#11-figure-studio-multi-panel-compositions)
12. [Image information, color analysis and measurements](#12-image-information-color-analysis-and-measurements)
13. [Description, History, Undo and Redo](#13-description-history-undo-and-redo)
14. [Session Workspaces and persistence](#14-session-workspaces-and-persistence)
15. [Publish a derived image Dataset and inspect its manifest](#15-publish-a-derived-image-dataset-and-inspect-its-manifest)
16. [Viewer settings and ImageMagick capabilities](#16-viewer-settings-and-imagemagick-capabilities)
17. [Practical tutorials](#17-practical-tutorials)
18. [Errors, recovery and frequently asked questions](#18-errors-recovery-and-frequently-asked-questions)
19. [Scientific integrity, limitations and security](#19-scientific-integrity-limitations-and-security)
20. [Keyboard, mouse and command reference](#20-keyboard-mouse-and-command-reference)
21. [Public API and developer references](#21-public-api-and-developer-references)

---

## 1. Five-minute start

### Example: improve and label one SEM image

1. Open a GX-TXT **Session** that contains a canonical image Dataset, then open **Viewers → Scientific Image Inspector**. If necessary, enable `viewer.scientific_image_inspector` in GX-TXT's Plugin Manager first.
2. Choose the image in **Source Dataset**. Nothing is selected automatically when a new Viewer opens. The large canvas is labeled **Working image (accepted edits)**.
3. In the left **Editor**, choose **Basic Editor**. Select **Microscopy | Gentle sharpening** in **Task presets**, inspect its explanation, then choose **Preview selected preset**.
4. Compare the accepted image at left with **Adjustment preview (not accepted)** at right. Choose **Discard preview** if it overemphasizes the microstructure, or **Accept preview** to keep the step. Until you decide, other editing is locked.
5. Right-click the canvas and use its annotation commands, or open the **Draw** icon and choose **Add Text**. Click/drag a text box, type the caption, choose font, color and size, and select **Apply**. Press **Esc** when annotation editing is finished. The caption remains visible.
6. Use **Workspace → Save** to retain the editable project. If this is a new project, CORE assigns it a named Workspace. Its History and sidebar configuration belong to that Workspace.
7. Open the **Publish** sidebar section, enter a *new* Dataset ID and choose `png16`, `tiff16` or `tiff32f` as appropriate. Confirm **Publish Working Image as Dataset...**. The new Dataset has an auditable processing manifest.

**If the image is displayed as a composed Figure:** choose **Image → Edit source image** (or right-click the figure and choose **Edit source image**) before editing the individual raster. Panel definitions remain in the Workspace. A filter requested in Figure mode proposes this change of context rather than implicitly filtering an unrelated image.

### What this workflow does *not* do

It does not replace the original SEM image, infer a specimen calibration, export a file outside GX-TXT, or flatten the editable annotation objects in the Workspace. The published derived raster is a new Dataset with provenance metadata; it is distinct from the editable project.

## 2. Image, ROI, annotation, figure and Workspace: five different things

| Term | Meaning | What happens when you change it? |
|---|---|---|
| **Source image** | Original `image.raster` Dataset registered in the GX-TXT Session | Remains immutable. Its SHA-256 identifies the exact source bytes. |
| **Working image** | Source reconstructed with all **accepted** ImageMagick processing steps | Can be edited and restored through the recipe. It is not automatically a new Dataset. |
| **Adjustment preview** | Candidate image calculated from a proposed operation | Lives only until **Accept preview** or **Discard preview**; never silently published or saved. |
| **ROI** | Rectangle in the working image's pixel coordinates | Restricts compatible operations/analysis, or defines a crop. It is not an annotation object. |
| **Annotation** | Named text, line, arrow, rectangle or ellipse over the working image | Editable overlay in the Workspace; displayed independent of pixel filters; composited only in published output. |
| **Figure composition** | Layout of multiple canonical images/panels plus figure annotations | A separate editing/viewing context in the same Workspace, not a complete arbitrary image-layer editor. |
| **Workspace** | Named, Session-owned GX-TXT editing project | Stores the editable recipe, sources, panels, overlays, current image/figure mode and configured sidebar sections. |
| **Published Dataset** | New canonical `image.raster` result | Registered by GX-TXT's Dataset File Publication API with its own ID, SHA and processing manifest. |

The distinction matters when choosing commands: **Select object** changes an annotation selection; **Select image ROI** changes the pixel selection. Applying an image filter processes the working raster, not the selected arrow or caption. When the figure composition is active, use **Edit source image** to switch back to the single image before making an image adjustment.

## 3. Open the Viewer and choose a source

### Installation and requirements

Install the complete plugin package using **Configuration → Modules → Plugin Manager → Install** in GX-TXT, enable its module, then open it from the **Viewers** tab. GX-TXT must provide its documented Viewer Provider, Dataset inspection, Native2D, Session Workspace and File Publication services. ImageMagick must be resolvable through GX-TXT Configuration (`runtime.magick`); do not enter a hard-coded executable path in the Viewer.

The implementation was prepared against the accepted GX-TXT dev096 public contracts. Availability of particular file formats or ImageMagick operations depends on the configured binary, delegates and security policy. The test environment is not proof that every workstation installation behaves identically.

### Start without loading an arbitrary image

A new Viewer opens without selecting the first Dataset and without silently reopening a previous Workspace. You may:

- Select a canonical image in **Source Dataset**. The chooser lists image Datasets in the active Session. **Refresh** updates the choices after imports or Session changes.
- Open an existing project using **Workspace → Open workspace...** or **Session Workspaces...**. Its source identity and SHA are verified before restoring the recipe.
- Ask another GX-TXT component to open the Viewer with an explicit, authorized Dataset/Workspace context; this is not the same as an automatic guess.

If no suitable Dataset is listed, import it through **GX-TXT Acquisition** first. The Viewer is not an independent image-import registry. If the active Session lacks the referenced source or its SHA changes, the Viewer must not silently rebind the stored recipe to another image.

### The header controls

| Control | Action |
|---|---|
| **Source Dataset** | Choose which canonical raster is being edited. |
| **Refresh** | Reload available source Dataset names from the Session. |
| **Refresh image** | Rebuild the single working image from the accepted source and recipe. This also returns from a composed figure to source-image editing. |
| **Fit view** | Adjust the viewport to fit the image in the available canvas. |
| **Compare** | Show/hide the candidate canvas when an adjustment is pending. With no pending candidate, it cannot compare two independently editable images. |
| **Accept preview** | Commit the candidate operation sequence to the working recipe and History. |
| **Discard preview** | Reject the candidate without changing accepted work. |
| **Cancel operation** | Request cancellation of a running operation, when one is active. |

The footer or the lower **Description / History** strip reports the current action, selected-image pixel coordinates and failures. The title shows the current GX-TXT Workspace name, or **New (unsaved)** when no Workspace identity has yet been assigned.

## 4. Interface map, menus and sidebar

### Canvas and panels

The Viewer normally shows **one main image canvas** plus a **single scrollable inspector column** at left. A second, right-hand image canvas is exposed only for a pending ImageMagick candidate. Basic/Advanced are alternate *tool panels*, not two simultaneously independent images.

The left column contains optional stacked sections. The available labels are **Editor**, **Figures**, **Annotations**, **Image Info**, **Colors**, **History** and **Publish**. The initial new-project defaults normally show Editor and Figures; a Workspace may choose something entirely different. Drag the divider to resize the inspector; use its scrollbar or mouse wheel to reach lower controls.

Choose **Configuration → Visible sidebar sections...**, check the desired sections and click **Apply**. The change is immediate. The section selection belongs to the **current Workspace**, not to global GX-TXT User defaults. If the project has not yet been saved, the selection is kept in the draft and written when its Workspace is created. **Close** dismisses the dialog. At least one section must remain visible. Menu commands can temporarily reveal a hidden panel without making it a permanent visible section.

The optional **Annotations** sidebar list is not necessary for annotating: its functions are also available through Native2D icons and right-click context menus. Hiding it leaves annotations visible on the canvas. A hidden **Colors** section can be reached through **Analyze** commands or ROI context actions.

### Main menus (actual top-level names)

| Menu | Main use |
|---|---|
| **File** | Refresh Source Datasets, Copy Technical Report, Close. |
| **Edit** | Annotation select all/none, copy/paste, undo/redo. |
| **View** | Synchronized comparison, Pixel grid, Description/History strip visibility, Fit, comparison toggle and 1:1 display-LOD view. |
| **Image** | Open Basic/Advanced Editor or Figure Studio, edit source image, enable annotation tools, show image information, restore original. |
| **Analyze** | Compute statistics/histogram and inspect a pixel at the ROI origin. |
| **History** | Annotation editing entry, figure undo/redo, image undo/redo, preview decision, restore original and Workspace save. |
| **Workspace** | CORE-managed New, Open, Save, Save as/Duplicate, Rename, Manager, Close and Delete actions. |
| **Configuration** | Visible sidebar sections..., Viewer settings... |
| **Help** | User Manual... (F1) and About Scientific Image Inspector... |

There is **no separate top-level Operations menu**. The catalog is inside **Editor → Advanced Editor** and is also accessible from the ROI context menu.

### Help and version

**F1** or **Help → User Manual...** opens this manual in an independent, Viewer-only window; it does not redirect to GX-TXT's general Help tab. Use the **Find in manual** field with **Return** or **Find next** to search. **F3** repeats the search, **Ctrl+F** focuses it, and **Esc** closes the manual window. **Help → About Scientific Image Inspector...** displays the installed plugin version and GNU GPL license. The About version comes from the plugin's API entrypoint, not an independent handwritten string.

## 5. Move around the image and use the Native2D toolbar

- **Mouse wheel:** zoom around the pointer in the canvas under the cursor (Windows wheel or Linux/X11 wheel events).
- **Middle-button drag:** pan the image without changing annotation geometry.
- **Pan icon:** activate panning with left-button dragging; Select/Draw/Transform are not simultaneously active.
- **Fit view / View → Fit to window:** reframe the current image.
- **Zoom + / Zoom − icons:** increase/decrease zoom; **View → Actual display pixels (1:1 LOD preview)** requests the 1:1 *display* view, not a new raster operation.
- **Select icon:** activate object selection. Right-click that icon to choose a selection *mode*, including image ROI.
- **Transform icon:** display Native2D translation or rotation gizmos for an active annotation; right-click for transform-related choices.
- **Draw icon:** open a single creation menu for Text, Arrow, Line, Rectangle or Ellipse.

The Viewer uses GX-TXT's Native2D device/world coordinate transforms, selection methods, pivot and gizmo interactions. It uses bounded ImageMagick rendering for readable zoomed image detail. At high zoom a preliminary coarse image may appear before a higher-detail LOD arrives; **display pixels are not a reduction of the scientific source**.

**Pixel grid** helps locate raster pixel coordinates; it does not measure micrometers or establish an SEM scale. Normal XY pixel coordinates have their origin at the **top left**. The image's existing visual scale bar, if present in its pixels, is simply part of those pixels; the Viewer does not automatically calibrate it.

Tooltips should appear near the buttons in the Viewer. Native2D geometry errors are reported with context in the Viewer status and diagnostic stderr where possible. No invalid gesture should be interpreted as permission to overwrite the source.

## 6. Basic Editor and all 15 task presets

Open **Image → Basic Editor**, or select the **Basic Editor** option in the Editor section. A preset is a **fixed, explicit ImageMagick recipe**, not automatic image-content classification or a calibrated scientific correction. Each preset shows its explanation and the underlying operation names before it is previewed.

### Preset reference

| Task shown in the GUI | Exact processing intent | Suitable use / caveat |
|---|---|---|
| **Photo \| Balance tonal range** | `auto_level` | Expand a photograph's occupied tonal range; can change perceived intensities. |
| **Photo \| Gentle contrast** | `sigmoidal(contrast=4, midpoint=50%)` | Modest midtone separation without full histogram stretch. |
| **Photo \| Sharpen details** | `unsharp(radius=0, sigma=1, gain=0.8, threshold=0.04)` | Accentuate boundaries; may create halos and emphasize noise. |
| **Photo \| Soften grain** | `gaussian_blur(radius=0, sigma=0.8)` | Reduce apparent grain while sacrificing very fine detail. |
| **Color \| More saturated** | `modulate(brightness=100, saturation=120, hue=100)` | Increase encoded color saturation by about 20%; not quantitative colorimetry. |
| **Color \| Less saturated** | `modulate(brightness=100, saturation=75, hue=100)` | Decrease saturation by about 25%. |
| **Color \| Convert to grayscale** | `colorspace(Gray)` | Prepare monochrome visualization; not calibrated intensity conversion. |
| **Scan \| Remove small specks** | `despeckle` | Scanned dust or salt/pepper defects; may erase legitimate small marks. |
| **Scan \| Dark text on white** | `colorspace(Gray)` followed by `threshold(60%)` | Strong black/white document presentation; removes continuous tonal information. |
| **Scan \| Clarify faint writing** | `auto_level` followed by moderate `unsharp(0, 0.8, 0.5, 0.05)` | Visually improve faded print; may strengthen paper grain too. |
| **Microscopy \| Gentle sharpening** | `unsharp(0, 0.7, 0.35, 0.06)` | Cautious display enhancement; never infer a new feature size from the result. |
| **Microscopy \| Show edges** | `edge(radius=1)` | Diagnostic edge visualization, *not* an unchanged micrograph. |
| **Diagram \| Increase contrast** | `sigmoidal(contrast=7, midpoint=50%)` | Emphasize diagram line separation. |
| **Diagram \| Invert colors** | `negate` | Invert a light/dark diagram. |
| **Diagram \| Sharpen strokes** | `unsharp(0, 0.85, 1.0, 0.05)` | Accentuate printed strokes; can cause edge artifacts. |

The GUI renders these labels with a vertical separator `|` (for example, **Microscopy | Gentle sharpening**). The operation parameters above are recorded by the processing recipe; the catalog performs validation before execution. Changing from Basic to Advanced never automatically applies a preset.

### Manual adjustments

The **Manual adjustments** group provides four controls: **Brightness** (−100 to +100), **Contrast** (−100 to +100), **Gamma** (0.1 to 4) and **Rotation** (−180° to +180°). Set one or more sliders and choose **Preview manual adjustments**. Zero brightness/contrast, gamma 1 and rotation 0 correspond to no change; the preview command does not intentionally add empty operations.

**Preview crop from selected ROI** is different: it uses the ROI bounds as the *whole-image crop geometry*. Cropping changes the dimensions, so it is not an ROI-local same-size operation. See the ROI section before using it.

### Selecting the right preset

For a microscopy or SEM image, try **Gentle sharpening** first and compare with the accepted image at matched zoom. **Show edges** is a separate diagnostic view and should not be presented as raw microscopy. For a document scan, **Clarify faint writing** is less destructive than **Dark text on white**. For a general photo, **Gentle contrast** avoids automatic full-range stretching. Apply a step only after the before/after comparison supports the visual purpose.

## 7. Advanced Editor and the operation catalog

Open **Image → Advanced Editor** or switch from Basic inside **Editor**. The Advanced Editor exposes the same ImageMagick engine through a searchable, data-driven catalog. It is not a raw command terminal.

### Apply an operation

1. Enter a word in the catalog **search** field, or select a listed operation by name/category.
2. Read its description and **Status**. Only actually executable operations are usable. A recognized option is not automatically a validated editing operation.
3. Fill the generated **Parameters** form. A number, integer, percentage, enum or geometry field is validated against its declared bounds or accepted choices.
4. Choose **Whole image** or **Selected ROI**. The second requires an existing ROI and a same-size operation whose catalog descriptor explicitly supports ROI processing.
5. Click **Add processing step**. This starts a candidate preview, *not* an accepted step. Compare it, then **Accept preview** or **Discard preview**.

The catalog currently defines **69 entries**: **46 executable/validated**, **17 recognized but not enabled**, and **6 restricted**. Runtime availability may be narrower if the installed ImageMagick build lacks a format/delegate or enforces a stricter security policy. An unavailable entry includes a reason; there is no generic text box that executes arbitrary CLI flags.

### Supported families and representative commands

| Family | Examples in the catalog | Notes |
|---|---|---|
| **Geometry** | Resize, Sample, Crop, Rotate, Flip, Flop, Auto orient, Trim, Transpose, Transverse, Extent, Deskew | Geometry-changing operations work on the whole image. Input pixel coordinates after such an operation may no longer correspond to those before it. |
| **Tones** | Gamma, Levels, Brightness/contrast, Auto level/gamma, Normalize, Equalize, Contrast stretch, Sigmoidal contrast, Thresholds, Invert, Solarize | Can substantially change display intensities and distributions. |
| **Color** | Modulate, Colorspace, Posterize, Palette quantization, Alpha extract/deactivate | Mathematical colorspace conversion does not imply profile-calibrated color management. |
| **Filters** | Blur, Gaussian blur, Sharpen, Unsharp, Median, Despeckle, Enhance, Edge, Emboss | Smoothing/sharpening can remove or invent visual features. |
| **Morphology** | Erode, Dilate, Open, Close, Morphological gradient | Kernel radius is in image pixels; never treat the result as a validated specimen measurement. |
| **Composition/Output** | Registered possibilities include composites and file conversions | These are **not** general unrestricted catalog actions; several are recognized but not implemented. Multi-panel Figure Studio and explicit Dataset publication are separate validated workflows. |

Some recognized-but-disabled operations include free-form Distort/Affine matrices, external ICC profiles, CLUT, connected components and arbitrary convolution: they need additional validated schemas or authorized second inputs. Restricted examples include unrestricted FX, Draw, Write, Script, arbitrary Defines and direct delegate calls. The catalog deliberately reports these limitations instead of pretending they work.

### ROI eligibility

ROI support is explicit per operation. For example, non-geometric tonal and filtering operations may be ROI compatible; resize, rotate, crop and other geometry-changing actions are not offered as same-size ROI-only transforms. Crop is still available from the ROI menu as a **whole-image** output geometry operation. The ROI context menu automatically filters catalog entries by current runtime capability and ROI compatibility.

### Reproducibility

Accepting an operation stores the operation ID, validated parameters, order, requested scope and ROI when applicable. A future rebuild starts from the canonical source, not from an arbitrary screen capture. The published Dataset's manifest records these steps and the ImageMagick version used.

## 8. The processing transaction: preview, compare, accept or discard

The main canvas is the **accepted working image**. When a new operation is requested, the Viewer reconstructs a candidate in managed temporary storage and shows **Adjustment preview (not accepted)** to the right. The candidate is *not* appended to the Workspace recipe until accepted.

- **Accept preview:** the candidate's operation steps become accepted processing steps. The Viewer returns to the normal, single canvas and records an image History checkpoint.
- **Discard preview:** drops the candidate and returns to the unchanged accepted working image.
- **Compare:** shows/hides the unaccepted right-hand candidate. It is not a command to merge two images.
- **Cancel operation:** requests cancellation of a long-running processing job; if an operation is still active, do not assume its result has been accepted.

**Exclusive mode:** while a candidate is pending, source switching, annotation edits, Figure Studio edits, another image filter, Workspace switching and ordinary Undo/Redo are blocked. The canvas context menu offers **Accept adjustment preview** and **Discard adjustment preview**. This deliberately keeps the project in a consistent state.

A previewed change can be scientifically unsuitable even if it looks cleaner. Discard it and retry with different parameters. The source remains intact either way.

## 9. Select a pixel ROI and use its context menu

### Create a pixel ROI

1. **Right-click the Select icon** on the image toolbar.
2. Choose **Select image ROI (pixel processing)**.
3. Drag a rectangle with the left mouse button on the accepted working image. A highlighted region appears.
4. **Right-click inside the rectangle.** The menu is specific to the selected ROI, not to the whole image or an annotation object.

The rectangle uses **working-image pixel coordinates** `(x, y, width, height)` with origin at the upper left. It is independent of the selection of annotation objects. The ROI remains a selection until cleared; switching between ROI and ordinary annotation selection changes which gestures are meaningful.

### Context menu inside the ROI

| Entry | Result |
|---|---|
| **Preview crop to ROI** | Crop the whole working raster to the rectangle; requires Accept/Discard. |
| **ROI statistics (working image)** | Analyze exactly this working-image rectangle; opens the Colors/Analysis section. |
| **ROI histogram (working image)** | Build a 256-bin quantized histogram for the selected working-image rectangle. |
| **Inspect pixel here** | Read the working-image pixel at the pointer location. |
| **ROI task presets** | Choose from presets whose *entire* operation sequence supports ROI scope. |
| **ROI operations** | Group compatible executable ImageMagick operations by category. Parameterized operations open one generated validated form. |
| **Open Advanced Editor (ROI)** | Display Advanced Editor with ROI processing selected. |
| **Clear ROI selection** | Remove the pixel selection without modifying the image. |

A **right-click outside the ROI** opens the appropriate object/background context instead. The pixel statistics/histogram menu intentionally selects **Working** and enables the **Analyze selected ROI** flag, so the calculation target is not ambiguous.

**Important:** an ROI is not a non-destructive mask editor for arbitrary image layers. The current implementation supports a rectangular image region and compatible processing steps. Geometric cropping and local tone changes have different semantics, as stated above. No ROI command publishes a Dataset automatically.

## 10. Create and edit annotations

Annotations are independent editable objects placed *over* the accepted working raster. Disabling annotation editing hides editing handles but does not hide the annotations. Annotations are not silently flattened into the original image. Native2D supplies retained shape/proxy geometry, world/device conversion, selection and transform gizmos; Tk supplies the on-image text editing widget. The full-resolution published raster is composited through the controlled publication workflow.

### Activate and leave annotation editing

Use the canvas **Select**, **Transform** or **Draw** tools, or **Image → Annotation mode / Annotation tools...**, to work on annotations. Use **Esc** or the viewer's mode control to exit annotation editing. A separate **Pan** mode lets you move the view without moving any object. Only one pointer action mode should be active at a time; an ImageMagick candidate preview blocks editing until accepted or discarded.

### Create an arrow, line, rectangle or ellipse

Open the canvas **Draw** icon, or right-click an empty part of the working image. Choose **Draw Arrow**, **Draw Line**, **Draw Rectangle** or **Draw Ellipse**, then drag on the image. A transient shape follows the pointer. Releasing completes a valid shape and assigns a stable ID and a readable default name (for example, `Arrow ann4`). Use the right mouse button over the finished annotation to edit it.

A line or arrow needs distinct endpoints; a rectangle needs nonzero width and height. Clicking without sufficient displacement does **not** add a zero-length shape. If Native2D rejects an invalid geometry, the Viewer should preserve other overlays and print a diagnostic rather than repeatedly failing on every zoom or selection.

### Place text directly on the image

1. Select **Add Text** in the **Draw** menu or in the background right-click menu.
2. Click for a default text rectangle, or drag to define its bounds.
3. Type in the temporary **dashed-border text box** on the image. The small toolbar appears adjacent to it.
4. Use its **color swatch** (GX-TXT's shared UI Field color chooser), **font selector**, **size spinner** and **px/pt** unit selector.
5. Choose **Apply** to create/update the editable annotation or **Cancel** to reject the text draft.

Font names come from the configured ImageMagick installation. Tk is an interactive text preview; the final ImageMagick rasterization may differ slightly in glyph metrics. Point-size input is converted using an output DPI assumption, **not microscope calibration**. The current text tool is intended for simple single-line labels; it is not a full multiline article typesetting engine.

**Existing text:** select or right-click the text, then choose **Edit text on image...**; alternatively double-click the text. The same in-place editor reappears.

### Select objects: four modes under the Select icon

Right-click **Select** to choose:

- **Select object (click / Shift-click):** click an annotation to make it active; Shift-click adds/removes selection membership.
- **Select annotations in window:** drag a rectangle; Native2D determines matching retained annotation objects.
- **Select annotations in polygon:** click successive vertices and double-click to finish; Escape cancels the unfinished polygon.
- **Select image ROI (pixel processing):** select pixels for processing, **not** annotation objects. See the ROI chapter.

A selected annotation may display a dashed bounds box, handles and a Native2D gizmo. The selected object's name and stable identity are independent of whether the Annotations sidebar is visible. **Edit → Select All Annotations**, **Select None**, **Copy Selected Annotations**, **Paste Annotations** act on the annotation domain; Copy/Paste creates new editable annotations, not copies of the underlying raster pixels. Multiple selection supports Copy/Paste but **does not yet provide full multi-object geometric transforms**.

### Move, rotate and set a pivot

1. Activate **Transform** after selecting **one** annotation.
2. Use the Native2D **Free**, **X** or **Y** translation handle to reposition it. The geometry is updated through Native2D drag transactions.
3. Right-click the object and choose **Rotate (Native2D)**, or change the Transform tool mode from its context menu. Drag the rotation handle to rotate about the current pivot.
4. The **pivot** is the center of transformation. Use the pivot handle or the object context menu commands **Pivot at cursor** / **Pivot at object center**. Text and geometric primitives keep the corresponding retained transform properties.
5. Right-click for **Rename...**, **Edit style...**, **Delete annotation** or **Edit text on image...** for text objects.

The logical project stores a human-readable `name`, a stable annotation ID and relevant coordinates/rotation/pivot. Native2D's temporary drawing tokens are not used as permanent project identities.

### Annotation sidebar and exact coordinates

The optional **Annotations** sidebar provides an object list and editing fields. It can be hidden permanently for that Workspace through **Visible sidebar sections...**. Exact numerical coordinates are hidden by default; enable them in **Viewer settings → Annotations** or the registered GX-TXT module configuration control if you need precise pixel entry.

**Current style-dialog behavior:** the general **Edit style...** dialog uses a hexadecimal `#RRGGBB` color entry and line width in image pixels. The on-image **text** toolbar already offers the framework color swatch. The general style dialog has no recent-colors swatch list.

## 11. Figure Studio: multi-panel compositions

Figure Studio is a separate layout context in the same Workspace. It can build a figure from **up to 12** canonical parent image panels. It is not a generalized multi-layer image compositor or a complete vector layout application; a fuller layer architecture awaits appropriate Native2D CORE support.

### Assemble panels

1. Select the source image, accept any desired image corrections, and open the **Figures** sidebar (**Image → Figure Studio** will reveal it if hidden).
2. Click **Add current**. Its source Dataset ID, source SHA and approved processing steps become a panel record.
3. Optionally select another Source Dataset and repeat. Select a panel in the list to use **Update selected** (replace its stored current-image state) or **Remove selected**.
4. Set **Width** and **Height** of the complete figure in **pixels**, plus outer **Margin** and inter-panel **Gutter**.
5. Choose layout **grid**, **horizontal** or **vertical**. The layout arranges/resizes panels while preserving proportions rather than deliberately stretching images.
6. Choose **Preview composed figure**. The working canvas now represents the *figure composition*, not the independently editable source image.
7. Add figure labels, arrows or notes on the visible composed figure, if needed. Figure annotations are managed separately from single-image annotations.
8. Publish while the composition is actively displayed to produce a derived *figure* Dataset; full-resolution output is constructed from the registered source panels.

### Switch between the two editing contexts

When a composition is displayed, **right-click → Edit source image** or choose **Image → Edit source image**. This restores the single selected source raster and retains panel definitions and figure annotations. **Refresh image** also reconstructs the individual working image. Return to Figures and choose **Preview composed figure** to view the assembly again.

ImageMagick presets and Advanced pixel operations are defined for the *single working raster*. If you request one while Figure mode is active, the Viewer offers a **guided switch** to the source image first. Rejecting the switch leaves the composition unchanged. This is a context guard, **not** an ImageMagick error. A new alpha Workspace without a saved figure mode should not be assumed to be in Figure mode merely because it contains panels.

### Limitations of Figure Studio

The composition preview is display-only and may be 8-bit; it does not define the bit depth of the full-resolution output. Individual panel correction recipes remain separate and independently reproducible. Panel layout supports grid/horizontal/vertical arrangement, not free manipulation of arbitrary image layers with blend modes. Figure annotations should not be confused with source-image annotations or a source raster calibration.

## 12. Image information, color analysis and measurements

### Image information

Open **Image → Image Information** or the **Image Info** sidebar section. The technical report identifies the canonical source Dataset, SHA-256, file format/MIME/size, dimensions, pixel count, aspect ratio, channel layout, depth, colorspace, orientation, density, frame/page count, ImageMagick version and available Dataset metadata. Missing properties are reported as unavailable where appropriate.

**Full metadata** requests additional ImageMagick-derived properties, which are not the same authority as the imported source metadata. **Copy** or **File → Copy Technical Report** copies the available report to the system clipboard. The Viewer does **not** provide a general standalone technical-report file exporter. Repeated Full metadata requests may refresh or append detailed information; treat the visible report as an inspection result, not a mutable source file.

### Set the analysis target explicitly

Use the **Colors** sidebar controls and select **Image**:

| Analysis target | Exactly what is measured |
|---|---|
| **Working** | Raster with accepted processing steps; text/arrows/shapes are overlays and are not included in raster statistics. |
| **Source** | Immutable canonical source raster, before any accepted operations. |
| **Preview** | Unaccepted adjustment candidate, available only while a preview exists. |

Select **Channel**: `All`, `Gray`, `R`, `G`, `B` or `A`. For a histogram, the `All` selection uses a grayscale representation; it does **not** mean a separate full-resolution histogram for every channel. Select **Analyze selected ROI (Working image only)** if you want to use the current pixel rectangle. Source and Preview analysis do not automatically reuse working-image ROI coordinates after geometry changes.

### Available analysis actions

- **Statistics:** computed on the selected target, channel and optional Working ROI. Results are labeled with the target and normalized ImageMagick quantum range `0..1`.
- **Histogram:** **256 bins (8-bit quantization)** of the chosen channel, even when the source has higher bit depth. The plot is a visualization, not a native 16-bit/full quantum histogram.
- **Dominant palette:** quantized color distribution, with a requested upper palette count of **8, 16, 32, 64 or 128**. Quantized colors are estimates, not exact per-pixel spectral or colorimetric measurements.
- **Preview channel:** opens a separate, read-only **8-bit** channel image; no accepted operation is created.
- **Pixel inspection:** double-click or use the ROI context **Inspect pixel here** to query a pixel; the active canvas/target matters.
- **Analyze → Compute statistics / Compute histogram:** menu shortcuts for the corresponding tools. ROI right-click operations explicitly target Working.

### Scientific reading of the results

Encoded RGB values do **not** necessarily represent linear light intensity, reflectance, absorbance or concentration. A channel distribution is useful for visual quality control but not automatically a physical measurement. Embedded DPI/resolution does not provide microscopy specimen scale. The Viewer does **not** create a scientifically calibrated scale bar from EXIF or from a painted-on scale label.

No general, fully color-managed ICC conversion workflow or high-precision 16-bit bin histogram is promised by the available GUI. For scientific quantification, preserve original Dataset IDs/SHA and use validated laboratory calibration procedures or purpose-built analysis modules.

## 13. Description, History, Undo and Redo

### Bottom strip

At the bottom of the Viewer the compact selector switches between **Description** (status text) and **History** (a horizontally scrolling timeline). Its CORE-owned choice menu remains inside the application window. History context menus open **upward**; details appear near the top of the window. **View → Show Description / History strip** can show/hide the strip without changing scientific image data.

The CORE History timeline starts with a **source/base** checkpoint and tracks accepted changes. Image steps, annotation edits and figure/layout updates receive descriptions. Complete History is retained up to the shared limit of **4096 operations / 8 MiB per context**; reaching a limit rejects further recording explicitly. The previous 80-checkpoint trimming is removed. CORE owns the active RAM state, journals, background disk writes, recovery, navigation and controls. Scientific image state remains a recipe referencing the canonical source Dataset.

### Inspect and resume without modifying

- **Click an older checkpoint:** inspect that recipe's image/annotations in *read-only History browsing* mode. It does not rewrite the current Workspace or delete newer work.
- **Click the latest checkpoint:** return to normal current editing.
- **Right-click a checkpoint:** choose **Inspect step**, **Return to latest state**, or **Restart editing here; discard future...**. Only the last choice truncates later checkpoints, and it requests explicit confirmation.
- **Activate a drawing or select tool while inspecting History:** the Viewer attempts to return to the latest writable state rather than allowing an inconsistent historical edit.

### Undo and Redo

**Edit → Undo / Redo** routes to the Viewer editing domain. **History → Undo/Redo** and the optional History sidebar expose accepted image-recipe operations; **History → Undo Figure Edit / Redo Figure Edit** operate on figure/annotation editing snapshots. Both editing domains and the general timeline use the same CORE native History service. Image Undo preserves later figure/annotation edits, and Figure Undo preserves accepted image processing. Returning to a general timeline checkpoint aligns the domain controls; an explicit restart retains the chosen image recipe and restarts later figure Undo. **Clear History** preserves current scientific state and resets all Undo controls. Use the general timeline to inspect complete chronology.

**History → Restore original image** clears accepted processing/annotation edits in the working recipe; it **does not** overwrite or delete the canonical source. An Undo may recover prior state. **History → Save workspace** and **Workspace → Save** wait for pending native writes and save the accepted project with its general, image and figure History. Close and explicit source/Workspace changes do the same before releasing the old owner. Ordinary accepted gestures update RAM immediately while CORE writes journals in the background; acceptance alone does not assert crash durability. Unaccepted ImageMagick candidates cannot become recorded processing steps by saving. On reopening after an interrupted lifecycle, CORE asks whether to recover the verified journals or retain the saved Document; different domain checkpoints require an explicit reconciliation choice.

## 14. Session Workspaces and persistence

The Viewer uses the framework's **`SESSION_WORKSPACE_API_v1`** and **Interactive Document** implementation. This is the single Workspace ID, naming, revision and persistence authority. The plugin supplies its own schema and payload validator, but does not maintain a second registry. Workspaces are **Session-local projects**: two Workspaces may use the same source image but have independent recipes, figures and sidebar selections.

### Workspace menu

| Action | Meaning |
|---|---|
| **New workspace...** | Start a separate draft project with an explicit name; existing work is handled by the Workspace save/close callbacks. |
| **Open workspace...** | Open the CORE Session Workspace Manager; select the desired project. |
| **Save** | Create/update the Workspace with accepted processing, annotations, figure and view context. |
| **Save as / Duplicate...** | Create an independently named Workspace through CORE's official package duplication path. |
| **Rename...** | Rename the same registered Workspace, without changing its identity. |
| **Session Workspaces...** | Open GX-TXT's central Workspace Manager, including portable project package operations. |
| **Close** | Close the current editing project after the normal save checks. It does not delete its stored Workspace. |
| **Delete...** | Confirm deletion of that Workspace. The source and published Datasets remain. |

**Workspace package Export/Import in the Manager** handles portable *Workspace packages*, not image file export. It does not create a new image Dataset. Pending filter previews must be finished before Workspace switching. A refused save should leave the current project available for correction.

### What the saved project contains

- Canonical `source_id` and `source_sha`.
- Ordered accepted ImageMagick `steps` with typed parameters, scope and ROI where applicable.
- Figure `panels`, layout parameters and distinct annotation collections.
- Annotation names, stable IDs, pixel geometry, font/color/style, pivot and rotation.
- Saved image/figure canvas mode (`canvas_mode`) and the **`sidebar_sections`** Workspace-specific layout choice.
- Recipe-level `history_timeline`; temporary preview/LOD pixel caches are not authoritative scientific state.

If you change the visible sections and press **Apply**, the active project's setting is updated and saved using CORE when a source image/Workspace is available. It does **not** overwrite another Workspace's layout. A new unsaved project holds the choice as a draft. Module-level Configuration fields can provide *initial defaults* for newly created drafts; this is different from saving a particular Workspace layout.

**Alpha policy:** earlier experimental Workspace formats do not carry a guaranteed backwards-compatibility commitment. Old Workspaces can be used as diagnostic test cases, but missing or incompatible payload fields are not silently invented to make an old recipe look valid.

## 15. Publish a derived image Dataset and inspect its manifest

### Publish only after accepting the intended image

1. Ensure there is **no pending preview**. If necessary, **Accept preview** or **Discard preview**.
2. Decide what is being published: individual working image versus the currently displayed figure composition. Use **Image → Edit source image** for the former or **Preview composed figure** for the latter.
3. Reveal the **Publish** sidebar (it may be hidden by your Workspace layout).
4. Enter a **new derived Dataset ID** (the initial field may contain `image.processed`, which is only a suggestion) and choose **Output format and precision**.
5. Choose **Publish Working Image as Dataset...** and inspect the confirmation prompt before approving.
6. GX-TXT's canonical **`DATASET_FILE_PUBLICATION_API_v1`** publishes the image. A success notification contains the new Dataset ID and authoritative SHA-256; check it before assuming publication succeeded.
7. To create an external PNG/TIFF file afterward, use GX-TXT's **Dataset export** workflow on that published Dataset. Scientific Image Inspector itself does not write arbitrary destination files.

### Format choices

| GUI format | Intended use and limitations |
|---|---|
| `png16` | High-bit-depth PNG container for appropriate raster data; decoder/processing semantics still matter. |
| `tiff16` | TIFF with a 16-bit target depth, often useful for grayscale scientific images and publication workflows. |
| `tiff32f` | Floating-point TIFF when available from the ImageMagick build, with Q16-HDRI support relevant to processing. |

The display preview may be 8-bit while publication reprocesses the authoritative image source; however, a high-bit-depth *output format* is not proof of preserved native precision after an operation, accurate ICC transforms or calibrated physical measurements. The ImageMagick and format properties should be inspected after publication if scientific precision matters.

### Manifest and provenance

The new Dataset's **structured metadata** includes `image.inspector.manifest`, with schema `scientific_image_inspector.manifest.v1`. It describes:

- Source Dataset IDs and SHA-256 values, including contributing figure panels.
- Available original Dataset metadata and ImageMagick-derived image properties.
- Accepted operations in order, their parameters and ROI/selection context.
- Figure dimensions/layout and source-panel recipes when publishing a composition.
- Editable annotation definitions and JSON projection (`annotation_layers_json`).
- Color/calibration disclosure, output format, ImageMagick engine version and Workspace identity.
- Published output Dataset identity, expected output SHA-256 and resultant raster properties.

Another plugin can query the Dataset manifest *without opening this Viewer*. After activating `SCIENTIFIC_IMAGE_INSPECTOR_API_v1`, it may use `::GX::SII::manifestGet`, `manifestSummary`, or `apiCall annotations_json`. See `docs/API.md` for the exact code examples and field contracts. Metadata is a record of the processing; it does not turn an uncalibrated image into a calibrated measurement.

## 16. Viewer settings and ImageMagick capabilities

**Configuration → Visible sidebar sections...** is intentionally available directly because it is used frequently. **Configuration → Viewer settings...** groups less frequent adjustments into semantic areas:

- **Interface:** display/navigation-related settings where currently exposed.
- **Annotations:** annotation editing preferences, including the optional precise coordinate fields.
- **Processing:** engine information and **Inspect ImageMagick capabilities and policy...**.

The module's registered Configuration fields provide session/user defaults where supported by GX-TXT Configuration, but **the active Workspace's visible sidebar sections override those defaults**. Do not confuse the plugin's UI preferences with processing steps or Dataset metadata.

ImageMagick availability is established through GX-TXT's configured runtime tool resolution. Build version, Q-depth/HDRI capability, supported formats/delegates and policy restrictions can differ between machines. The Viewer does not install ImageMagick, bypass `policy.xml` or offer arbitrary ImageMagick command execution.

## 17. Practical tutorials

### A. Prepare a labeled microscopy figure without altering the evidence

1. Open the canonical SEM image from **Source Dataset** and note its source identity in **Image Info**.
2. If you only need labels, do not change the raster. Enter annotation mode and create **Add Text** and **Draw Arrow** objects using the canvas context menu.
3. Select the arrow, choose **Transform** and adjust its direction/pivot. Rename it if multiple arrows need to be distinguished.
4. Press **Esc** to leave annotation editing. The overlay remains visible.
5. Use **Workspace → Save**, then choose `tiff16` or `png16` in Publish, as appropriate, and publish a new Dataset.
6. Inspect the published Dataset's manifest before using the derived image in a report. Keep the untouched source and its genuine acquisition metadata available.

**Warning:** if the SEM raster contains a printed `10 μm` bar, the Viewer displays those source pixels but has not inferred its calibration. Adding a new numerical scale bar without an authoritative calibration would be scientifically misleading.

### B. Clarify a scanned page and extract a sub-image

1. Select the scanned image, open **Basic Editor**, choose **Scan | Clarify faint writing** and preview it.
2. If small strokes disappear or grain becomes exaggerated, discard the preview and try another parameter set in Advanced Editor.
3. Accept the desired adjustment. Right-click the Select icon and choose **Select image ROI**; drag a rectangle around the figure to keep.
4. Right-click **inside** the rectangle and choose **Preview crop to ROI**. Inspect the new dimensions, accept or discard.
5. Add any explanatory labels only after the crop if their pixel positions should refer to the cropped image.
6. Save the Workspace and publish a new Dataset. The original full-page scan is unchanged.

### C. Compare two panels in an article figure

1. Select image A, accept its desired adjustments and choose **Figures → Add current**.
2. Select image B, adjust it separately and choose **Add current** again.
3. In Figures, set figure width/height and choose **horizontal** layout. Adjust **Margin** and **Gutter**.
4. Choose **Preview composed figure**; add `A`/`B` text annotations on the composition.
5. To correct source B again, choose **Image → Edit source image**, select the appropriate source, apply a raster adjustment, then use **Update selected** on its panel and preview the composition again.
6. Save the Workspace. While the figure is displayed, publish the composite as a derived Dataset. Confirm that panel lineage appears in the manifest.

A Figure preview is not a replacement for a fully managed image-layer tree; avoid assumptions about blend modes, editable masks or automatic physical calibration across different microscopy images.

### D. Calculate a histogram for one region, without accidentally measuring annotations

1. Select a working image, then right-click Select and choose **Select image ROI**.
2. Draw the desired rectangle and right-click *inside it*.
3. Choose **ROI histogram (working image)**. The Viewer switches the analysis target to **Working** and enables ROI use.
4. Check the target, channel, ROI label and bin-count warning in **Colors**.
5. Compare a full-image result by clearing ROI use or the selection and computing the histogram again. The histogram measures raster pixels, not overlay arrows/text.

### E. Keep two different edits of one source

1. Open an image, apply a conservative recipe and save Workspace **Version A** (name chosen through CORE's Workspace menu).
2. Use **Workspace → Save as / Duplicate...** to create **Version B** as a distinct project; continue editing there.
3. You can configure different visible sidebar sections for A and B, and the settings will be restored separately on reopen.
4. Both Workspaces reference the same canonical source SHA, but their recipes and published results remain independent.

## 18. Errors, recovery and frequently asked questions

### “Switch from the composed figure to the source working image…”

**Cause:** a pixel adjustment was requested while a Figure composition was the active canvas. **Action:** accept the offered guided switch, or use **Image → Edit source image**, then apply the preset/filter to the single source image. Panels and figure annotations are retained. This is a mode mismatch, not proof of a corrupt Dataset.

### I see a second image. Which one is being changed?

The **left** canvas is always the accepted working image. The **right** one is an **unaccepted candidate**, visible during a pending adjustment. **Accept preview** is the only approval action; **Discard preview** cancels the proposed processing.

### A filter does nothing or is unavailable

Check the ImageMagick capability status, the operation's validated arguments, the current mode and whether an incompatible ROI is selected. Recognized catalog entries may be intentionally not executable. If all quick sliders are neutral, there may be no new step to preview. An ImageMagick policy or delegate may restrict a format on your machine.

### I cannot move or rotate an annotation

First return from a pending image preview or read-only History browsing. Enable **Select object**, click the target, then activate **Transform**. Use the gizmo handles and its right-click Rotate/Translate choices. Merely selecting a pixel ROI does not select an annotation. If the Annotations panel is hidden, continue directly on the canvas.

### An annotation is invisible or drawing stops

Check whether annotation editing is active and whether a previous text draft is awaiting Apply/Cancel. Degenerate shape gestures (zero-length line, zero-area rectangle) are invalid. The Viewer should isolate a malformed object on redraw, retaining other valid objects and reporting the logical annotation ID/coordinates in the status/terminal log. Keep the Workspace rather than deleting its data blindly.

### Image looks blocky when zoomed

A display preview may initially be low detail; Native2D viewport changes trigger source-backed higher-detail ImageMagick LOD generation. Allow the display to refresh, choose **Fit view**, or inspect at **Actual display pixels (1:1 LOD preview)**. A sharper *preview* does not create new source information.

### I opened an old Workspace and its editing mode looks wrong

The Viewer is under alpha development; earlier experimental Workspace payloads are **not** guaranteed compatible. Treat such cases as diagnostic material. For a composed figure showing while you want the source, use **Edit source image**. Never silently change source Dataset identity or hashes to force an old recipe to load.

### Where did my Workspace go?

Workspaces belong to the current GX-TXT Session. Use **Workspace → Session Workspaces...** and verify you are in the intended Session and that the Viewer module is enabled. Creating a new project does not create a new source Dataset. A deleted Workspace is not the same as a deleted Dataset.

### Does Apply in “Visible sidebar sections” write globally?

No. **Apply** changes the current Workspace layout immediately and saves it through CORE when that Workspace can be saved; otherwise it stays in the current draft. New project defaults may originate from GX-TXT Configuration, but the active project's `sidebar_sections` remains Workspace-local.

### Can I export the finished image to a file?

Not from this Viewer. **Publish** the accepted image/figure as a **new GX-TXT Dataset**; export that Dataset using the framework. Workspace package export is a different operation and does not replace Dataset publication.

### How do I report a reproducible error?

Record the plugin version from **Help → About**, the GX-TXT version, OS, current Workspace/image versus Figure mode, the operation and its parameters, whether an ROI or unaccepted preview exists, and the exact status/terminal traceback. Keep the source Dataset and the project state intact. If a redraw fails, avoid repeatedly applying transformations until the invalid object is identified.

## 19. Scientific integrity, limitations and security

**Scientific precautions:**

- An encoded gray or RGB value is **not automatically a calibrated physical intensity**. Contrast stretching, gamma, sharpening, smoothing, thresholding, quantization and segmentation may change visual evidence.
- Image density/DPI is **not a micrometer-per-pixel calibration**. No scale bar or measurement is fabricated from EXIF or from a visual ruler.
- High-bit-depth output formats do not guarantee that every intermediate operation preserved scientific precision or an ICC/color profile. Inspect the source, processing record and resulting output properties.
- The Viewer's GUI histogram has **256 bins**, even for high-bit-depth input. Quantized palettes and 8-bit preview images are visualization tools, not independent photometric measurements.
- An annotation is metadata plus overlay, not a modification of measured source pixels. The published raster intentionally includes the overlay but retains processing provenance.
- Different microscopy panels may have unrelated scales or acquisition settings. Do not imply they are metrically comparable without outside calibration.

**Current functional boundaries:** no interactive freehand clone/healing brush, no arbitrary editable raster layer tree with blend modes, no complete ICC profile-management pipeline, no arbitrary unconstrained ImageMagick CLI execution, no automatic physical specimen calibration, no general multi-object Native2D transform, and no complete multiline text typesetter. Arbitrary second-image comparison/composite commands are not implied by their presence in the catalog; use the supported Figure Studio workflow.

**Runtime safety:** the configured ImageMagick binary is invoked with validated arguments, bounded resources and authorized canonical Dataset or temporary inputs; security policies and delegates remain in force. Unsupported options are shown as recognized/disabled rather than executed. The Viewer does not create its own job scheduler, Dataset Registry, Workspace Registry or installation manager.

## 20. Keyboard, mouse and command reference

| Control | Context | Action |
|---|---|---|
| Mouse wheel | Working/preview canvas | Zoom about pointer. |
| Middle-button drag | Image canvas | Pan viewport. |
| Left drag in **Pan** mode | Image canvas | Pan viewport. |
| Left click in **Select object** mode | Annotation | Select object; Shift-click toggles membership. |
| Left drag in **Select image ROI** | Working raster | Draw pixel rectangle. |
| Right-click inside ROI | Working raster | Open ROI-specific crop/analysis/processing actions. |
| Right-click on annotation | Working raster | Object-specific rename, transform, pivot, style, edit or delete actions. |
| Right-click Select icon | Canvas toolbar | Choose Object, Window, Polygon or ROI selection. |
| Right-click Transform icon | Canvas toolbar | Choose transform/pivot behavior. |
| Draw icon | Canvas toolbar | Add Text, Arrow, Line, Rectangle, Ellipse. |
| **Esc** | Annotation editing | Leave/cancel appropriate annotation gesture and return to normal navigation. |
| **F1** | Viewer window | Open Viewer-only user manual. |
| **Ctrl+A** | Canvas/annotation context | Select all annotations. |
| **Ctrl+C / Ctrl+V** | Annotation context | Copy / paste selected annotation objects. |
| **Ctrl+Z / Ctrl+Y** | Viewer editing context | Undo / redo in current editing domain. |
| **Ctrl+Shift+Z / Ctrl+Shift+Y** | Figure/annotation history | Undo / redo figure edits. |

Text fields retain normal text-entry navigation and editing semantics; toolbar/editor shortcuts should not be used to operate on image data while typing a caption. Some context-menu actions require a currently selected object, active ROI or valid image and should be disabled or explained when unavailable.

## 21. Public API and developer references

The plugin registers `viewer.scientific_image_inspector` with Viewer Provider ID `scientific_image_inspector`. Its headless public API ID is **`SCIENTIFIC_IMAGE_INSPECTOR_API_v1`**. This API is separate from the GUI and uses GX-TXT's metadata and publication contracts.

For example, once the API is activated through the framework:

```tcl
::GX::modulePublicApiActivate viewer.scientific_image_inspector SCIENTIFIC_IMAGE_INSPECTOR_API_v1
set summary [::GX::SII::manifestSummary my_derived_image]
set manifest [::GX::SII::manifestGet my_derived_image]
set objectsJson [::GX::SII::apiCall annotations_json my_derived_image]
```

Read **`docs/API.md`** for exact public operations, security boundaries, serialized annotation properties and manifest schema. Read **`docs/TECHNICAL_REPORT.md`** for implementation and testing limitations. The Viewer-specific Workspace provider uses **`SESSION_WORKSPACE_API_v1`** and an Interactive Document recipe; the image publication path uses **`DATASET_FILE_PUBLICATION_API_v1`**; `image.inspector.manifest` belongs to GX-TXT Dataset Metadata.

No consumer should parse private window paths, Tk canvas item numbers, internal ImageMagick temporary files or Native2D ephemeral object tokens as stable scientific identities. Use canonical Dataset IDs, Workspace IDs, annotation IDs and the declared public metadata contracts.

---

**End of manual.** The authoritative functionality is defined by the installed plugin's source code and validated catalogs; this guide is written to match those current commands without relying on promises of future features. Release history and bugfixes are recorded separately in `CHANGELOG.md`.

### P017 Workspace History compatibility

Existing `history_timeline` snapshot lists remain readable and are imported once, without replaying image processing during ordinary History recording. Saved Workspaces now carry the compatible optional `scientific_history` and `domain_history` fields; the existing recipe schema and canonical source fingerprint remain unchanged. Older Viewer versions cannot interpret the new History fields, so retain a P016 backup when rolling back a framework patch. The image processing recipe and current annotations remain in their existing fields.
