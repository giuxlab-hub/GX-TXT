# SCIENTIFIC_IMAGE_INSPECTOR_API_v1

Provider: `viewer.scientific_image_inspector` (descriptor 0.4.2; loaded Tcl `::GX::SII::version` 0.4.1). This reference describes the existing public entry and the headless files it loads. It does not extend the Inspector implementation or expose its lazy GUI callbacks as SDK operations. Source-backed reference; no Inspector runtime or scientific verification was performed for this documentation batch.

The entry is `plugins/modules/viewer.scientific_image_inspector/api/scientific_image_inspector_api_v1.tcl`. It loads `runtime/catalog.tcl`, `engine.tcl`, `article.tcl`, `annotations_json.tcl`, `manifest.tcl`, and `local_sources.tcl`. Workspace callbacks are registered separately by `api/workspace_provider.tcl`. These are Tcl host interfaces, available when their provider is loaded. Descriptor/default enablement, runtime availability and caller admission are separate. No Python/Octave Script Bridge registration or direct C++ SDK wrapper for this family is established by this reference. Do not invent a generic C++ invocation method or bypass the existing public service owner.

## Declared dispatch and metadata

`::GX::SII::apiInfo {}` returns `api_id`, `manifest_schema scientific_image_inspector.manifest.v1`, `operations {manifest_get manifest_summary annotations_json inspect catalog capabilities}`, and `gui_required 0`. The current return does not declare `api_version` or machine-readable argument/result schemas.

`::GX::SII::apiCall {operation args}` has these operations:

| Operation | Arguments after operation | Result and effects |
|---|---|---|
| `manifest_get` | exactly one `dataset_id` | Validated retained manifest dictionary, current Session; read only. |
| `manifest_summary` | exactly one `dataset_id` | Dictionary `dataset_id schema sources operation_count panel_count annotation_count output workspace_id`. |
| `annotations_json` | exactly one `dataset_id` | UTF-8-compatible Tcl string containing `scientific_image_inspector.annotations.v1` JSON; image pixels, top-left origin. |
| `inspect` | exactly one `dataset_id` | Current raster facts, engine version and available container information; executes configured ImageMagick processes. |
| `catalog` | optional `query`, default `""` | Sorted operation specification list; case-insensitive substring search in ID/family/label/about. Native `catalogList` arity rejects extra arguments. |
| `capabilities` | no arguments needed | Dictionary of raw engine text: version/formats/colorspaces/channels/filters/policy/delegates. Help text is cached internally, not returned. The current dispatcher ignores extra arguments for this operation. Executes processes; not an inert capability guarantee. |

Unknown operations and wrong fixed arities raise Tcl errors. `gui_required 0` means the declared operations need no Tk window; it does not mean ImageMagick, a current Session, canonical files or appropriate service availability are unnecessary.

Source-backed example (not executed here), in a host where this provider is already loaded and `derived_image` is an actual published Inspector Dataset:

```tcl
set summary [::GX::SII::apiCall manifest_summary derived_image]
set editableJson [::GX::SII::apiCall annotations_json derived_image]
set candidates [::GX::SII::apiCall catalog blur]
```

`::GX::SII::dispatch {action scene}` is the Viewer provider entry. It lazily loads the GUI files and delegates to the existing `guiOpen`; this document does not claim headless operation for that entry or specify private GUI state.

## Retained manifest and identity

`manifestGet {datasetId}` reads `image.inspector.manifest` from Dataset Metadata in the current Session, calls `manifestValidate`, and requires `output.dataset_id` to equal the requested Dataset. When `sessionInspectionDatasetPayload` exists **and succeeds**, a returned `sha256` must match `output.expected_sha256` case-insensitively. Absence of that helper, errors obtaining its receipt, or a receipt without `sha256` do not themselves reject the manifest. This conditional check is not an unconditional independent payload-integrity proof. `manifestSummary {datasetId}` delegates to `manifestGet`; its required `workspace_id` lookup can fail for an externally supplied manifest that passed the less strict validator without that optional-to-validator field.

`manifestValidate {manifest}` returns the input dictionary after requiring schema, producer_module, source_sha256_map, source_facts, primary_source_id, operation_steps, figure_panels, figure_settings, annotations, coordinate_system, image_magick_version, output and created_utc. Schema must be `scientific_image_inspector.manifest.v1`; producer module must be this provider. Source IDs are nonempty and source hashes 64 hexadecimal characters; output requires format/dataset_id/expected_sha256 keys. If annotation_layers_json exists it must equal the JSON projection of annotations. This is structural validation, not replay of the recipe or verification of every source/current raster field.

`makeManifest {sourceId steps panels settings annotations format {workspaceId {}}}` obtains current source identities and technical facts, rejects any `local:*` panel source, verifies any supplied panel source_sha, validates steps and retains editable annotations plus their JSON projection. With no panels it uses sourceId and steps. It records source Dataset metadata, dimensions/depth/channels/colorspace/orientation/frame count/density facts, engine version, UTC time and an initially empty output identity. Coordinates are explicitly `{origin top-left coordinate_unit pixel calibrated 0}`. DPI does not establish physical pixel size; mathematical color conversion does not silently assign an ICC profile or establish quantitative color calibration.

`annotationsJson {annotations}` returns an object with schema `scientific_image_inspector.annotations.v1`, coordinate_system `image-pixels-top-left`, and objects. Allowed kinds are text/arrow/line/rectangle/ellipse. Optional IDs must match `ann[0-9]+`; absent IDs use a local ordinal. Integer coordinate/style fields are 0..1000000; rotation/pivots must have absolute value <=1000000; font_value is 1..1200. Known text fields are escaped; unknown fields are omitted. This serializer does not perform full `validateAnnotation` geometry validation or enforce uniqueness of generated and supplied IDs. `jsonQuote {text}` is its string escaping helper. JSON is an interoperation view, not a separate Workspace store.

## Canonical sources and local transient sources

`datasetIds {}` lists current compatible canonical `image.raster` Datasets plus registered transient local source IDs. `sourceInfo {sourceId}` returns `id sha256 path contract metadata format media_type size_bytes` for a canonical source (actual payload receipt/file identity), or revalidates an unchanged regular local file against its captured hash. Canonical file SHA comparison is performed when the existing `::GX::sha256File` command is present; a canonical receipt must always supply a 64-hex SHA. The original canonical implementations remain named `canonicalDatasetIds {}` and `canonicalSourceInfo {datasetId}` after the local-source adapter renames them.

`openLocalFile {}` uses the existing GUI chooser and Inspector window, inspects a regular image, records a hash-derived `local:*` identity and returns through its existing GUI workflow. It does not publish a Dataset. Local IDs may be inspected and processed into transient files; publication's default manifest rejects local sources. Despite the comment on `process` saying canonical-only, the final `sourceInfo` adapter accepts registered local IDs. Canonical publication still requires canonical source identities through the manifest/publication owners. Raw host paths below are host helper arguments, not grants of filesystem access to restricted Viewer/SDK callers.

## Processing, parameters and resource limits

`catalogGet {id}` returns a catalog specification or errors. Each specification has id/family/class/label/about/option/params/support/roi/reason/safety_class/input_requirements/output_requirements. Each parameter is `{name type default low high choices}`; types are int, number, percent, geometry and enum. `catalogList {{query ""}}` and `catalogCompare {a b}` provide sorting/search. `catalogAdd {id family class label about option params {support executable} {roi 1} {reason ""}}` and `param {name type default {low ""} {high ""} {choices {}}}` construct this existing provider-owned catalog; external callers should inspect it rather than mutate it to evade declared support.

`operationStatus {id}` distinguishes the declared support from current configured engine/help-option availability. `recognized` and `disabled` entries do not execute through `validate`. These are this plugin's existing operation boundaries, not universal CORE or C++ architectural prohibitions. Engine availability is not scientific validation of an operation.

`validate {id values}` supplies catalog defaults, checks actual support/availability, rejects unknown parameters and checks each bound/type/enum; `level` additionally requires black < white. `operationArgs {id values}` formats validated values into the engine's actual argv; it is not an arbitrary command interface. `validateSteps {steps}` accepts at most 64 dictionaries with op/params and optional scope (all default, or roi), roi `{x y width height}`. ROI is permitted only by that operation, uses integer nonnegative current-raster pixels <=1000000 per component, positive dimensions and area <=100000000. It returns normalized steps; full per-step containment is checked during processing.

The complete current catalog declarations below supply exact operation IDs, labels, default values, limits, enum choices, ROI flags and non-executable reasons. A declaration is not a passed runtime test. Radius/sigma and morphology/neighborhood sizes are pixels; angles are degrees; explicit percent parameters are percentages. Normalized tone controls and colorspace transformations do not acquire physical measurement units.

```tcl
catalogAdd resize Geometry operator Resize {Resize image pixels (geometry WxH).} -resize [list [param geometry geometry 1024x768]] executable 0
catalogAdd sample Geometry operator Sample {Nearest-neighbor resize.} -sample [list [param geometry geometry 640x480]] executable 0
catalogAdd crop Geometry operator Crop {Crop to geometry WxH+X+Y.} -crop [list [param rect geometry 256x256+0+0]] executable 0
catalogAdd rotate Geometry operator Rotate {Angle in degrees.} -rotate [list [param degrees number 90 -360 360]] executable 0
catalogAdd flip Geometry operator Flip {Flip vertically.} -flip {} executable 0
catalogAdd flop Geometry operator Flop {Flip horizontally.} -flop {} executable 0
catalogAdd auto_orient Geometry operator {Auto orient} {Respect EXIF orientation where supported.} -auto-orient {} executable 0
catalogAdd trim Geometry operator Trim {Remove edge background; may alter coordinates.} -trim {} executable 0
catalogAdd transpose Geometry operator Transpose {Transpose image axes.} -transpose {} executable 0
catalogAdd transverse Geometry operator Transverse {Transverse image axes.} -transverse {} executable 0
catalogAdd extent Geometry operator Extent {Resize canvas to geometry (top-left aligned).} -extent [list [param geometry geometry 800x600]] executable 0
catalogAdd deskew Geometry operator Deskew {Auto straighten using threshold percentage.} -deskew [list [param threshold percent 40 0 100]] executable 0
catalogAdd distort Geometry operator Distort {Affine, perspective and barrel distortion need structured control points.} -distort {} recognized 0 {Validated control-point and virtual pixel schemas not implemented}
catalogAdd affine Geometry operator Affine {Affine matrix transform requires geometry-safe matrices.} -affine {} recognized 0 {Coordinate schema and transform tracking not implemented}
catalogAdd resample Geometry setting Resample {Resolution dependent resampling.} -resample {} recognized 0 {Requires unit and density policy}
catalogAdd gamma Tones operator Gamma {Power-law gamma modification.} -gamma [list [param gamma number 1.2 0.01 10]]
catalogAdd level Tones operator Levels {Black and white input points in percent.} -level [list [param black percent 1 0 99] [param white percent 99 1 100]]
catalogAdd brightness_contrast Tones operator {Brightness / contrast} {Brightness and contrast percentages.} -brightness-contrast [list [param brightness number 5 -100 100] [param contrast number 5 -100 100]]
catalogAdd auto_level Tones operator {Auto level} {Stretch per-channel image intensity dynamically.} -auto-level {}
catalogAdd auto_gamma Tones operator {Auto gamma} {Automatic gamma adjustment.} -auto-gamma {}
catalogAdd normalize Tones operator Normalize {Normalize histogram range.} -normalize {}
catalogAdd equalize Tones operator Equalize {Histogram equalization.} -equalize {}
catalogAdd contrast_stretch Tones operator {Contrast stretch} {Clip lower and upper distribution tails (%).} -contrast-stretch [list [param black percent 1 0 99] [param white percent 1 0 99]]
catalogAdd sigmoidal Tones operator {Sigmoidal contrast} {Sigmoidal contrast midpoint in percent and strength.} -sigmoidal-contrast [list [param contrast number 5 0 50] [param midpoint percent 50 0 100]]
catalogAdd threshold Tones operator Threshold {Threshold relative to quantum maximum.} -threshold [list [param threshold percent 50 0 100]]
catalogAdd white_threshold Tones operator {White threshold} {Set pixels above threshold to white.} -white-threshold [list [param threshold percent 80 0 100]]
catalogAdd black_threshold Tones operator {Black threshold} {Set pixels below threshold to black.} -black-threshold [list [param threshold percent 20 0 100]]
catalogAdd negate Tones operator Invert {Negate color channels.} -negate {}
catalogAdd solarize Tones operator Solarize {Invert pixel intensities above a threshold.} -solarize [list [param threshold percent 50 0 100]]
catalogAdd modulate Color operator Modulate {Brightness, saturation and hue factors.} -modulate [list [param brightness number 100 0 300] [param saturation number 100 0 300] [param hue number 100 0 300]]
catalogAdd colorspace Color setting Colorspace {Mathematical color-space conversion, not ICC profile management.} -colorspace [list [param space enum sRGB "" "" {sRGB RGB Gray Lab LCH HSV HSL CMYK XYZ YCbCr}]]
catalogAdd posterize Color operator Posterize {Discrete output color levels.} -posterize [list [param levels int 8 2 256]]
catalogAdd quantize Color operator {Palette quantization} {Reduce to at most N colors.} -colors [list [param count int 64 2 65536]]
catalogAdd alpha_extract Color channel {Extract alpha} {Convert output to an alpha coverage plane.} -alpha [list [param mode enum Extract "" "" {Extract}]] executable 0
catalogAdd alpha_deactivate Color channel {Deactivate alpha} {Deactivate alpha channel without applying transparency.} -alpha [list [param mode enum Off "" "" {Off}]] executable 0
catalogAdd separate_channel Color channel {Channel extraction} {Extract a channel; renders as grayscale.} -channel [list [param channel enum R "" "" {R G B A}]] recognized 0 {Requires channel sequence and availability validation}
catalogAdd color_matrix Color operator {Color matrix} {Arbitrary pixel matrix is not yet validated.} -color-matrix {} recognized 1 {Validated matrix schema not implemented}
catalogAdd profile Color setting {ICC profile} {External ICC file requires managed resource authorization.} -profile {} recognized 0 {External resources are not accepted as direct arguments}
catalogAdd clut Color operator CLUT {Requires an authorized second image.} -clut {} recognized 0 {Secondary Dataset selection is not implemented}
catalogAdd blur Filters operator Blur {Radius and sigma (pixels).} -blur [list [param radius number 0 0 80] [param sigma number 1 0.1 80]]
catalogAdd gaussian_blur Filters operator {Gaussian blur} {Gaussian filtering in pixels.} -gaussian-blur [list [param radius number 0 0 80] [param sigma number 2 0.1 80]]
catalogAdd sharpen Filters operator Sharpen {Sharpen radius and sigma.} -sharpen [list [param radius number 0 0 80] [param sigma number 1 0.1 80]]
catalogAdd unsharp Filters operator Unsharp {Unsharp radius, sigma, gain and threshold.} -unsharp [list [param radius number 0 0 80] [param sigma number 1 0.1 80] [param gain number 1 0 10] [param threshold number 0.05 0 1]]
catalogAdd median Filters operator Median {Median neighborhood filter (NxN).} -statistic [list [param size int 3 1 31]]
catalogAdd despeckle Filters operator Despeckle {Reduce small speckles.} -despeckle {}
catalogAdd enhance Filters operator Enhance {ImageMagick noise enhancement.} -enhance {}
catalogAdd edge Filters operator Edge {Edge detection with a fixed radius.} -edge [list [param radius number 1 0.1 30]]
catalogAdd emboss Filters operator Emboss {Emboss radius and sigma.} -emboss [list [param radius number 0 0 50] [param sigma number 1 0.1 50]]
catalogAdd add_noise Filters operator {Add noise} {Synthetic noise; stochastic result depends on seed.} -noise [list [param distribution enum Gaussian "" "" {Uniform Gaussian Multiplicative Poisson Laplacian Impulse}]] recognized 1 {Seed and reproducibility policy not yet defined}
catalogAdd convolve Filters operator Convolution {Custom convolution coefficients not yet validated.} -convolve {} recognized 1 {Kernel matrix validation not implemented}
catalogAdd erode Morphology operator Erode {Disk-shaped erosion; radius in pixels.} -morphology [list [param radius int 1 1 15]]
catalogAdd dilate Morphology operator Dilate {Disk-shaped dilation; radius in pixels.} -morphology [list [param radius int 1 1 15]]
catalogAdd open Morphology operator Open {Morphological opening using Disk.} -morphology [list [param radius int 1 1 15]]
catalogAdd close Morphology operator Close {Morphological closing using Disk.} -morphology [list [param radius int 1 1 15]]
catalogAdd gradient Morphology operator {Morphological gradient} {Gradient using Disk.} -morphology [list [param radius int 1 1 15]]
catalogAdd distance Morphology operator Distance {Euclidean distance transform; verify quantitative meaning.} -morphology {} recognized 1 {Requires calibrated output semantics and morphology scaling}
catalogAdd canny Morphology operator Canny {Requires structured sigma and thresholds.} -canny {} recognized 1 {Threshold pipeline not implemented}
catalogAdd connected_components Morphology operator {Connected components} {Segmentation labels with artifact metadata.} -connected-components {} recognized 1 {Label output and stats publication need dedicated schema}
catalogAdd compose Composition sequence Composite {Requires second canonical Dataset.} -compose {} recognized 0 {Second image and alpha alignment not implemented}
catalogAdd compare Composition sequence Compare {Quantified image differences require registered second input.} -compare {} recognized 0 {Second image Dataset selection not implemented}
catalogAdd append Composition sequence Append {Multi-frame stack generation.} -append {} recognized 0 {Sequence policy and frame count not implemented}
catalogAdd flatten Composition sequence Flatten {Flatten image layers.} -flatten {} recognized 0 {Requires explicit multi-frame handling}
catalogAdd convert_file Output output {Format conversion} {PNG and TIFF publication choices are available in Publish dialog.} {} {} recognized 0 {Handled by controlled publication only}
catalogAdd set_define Unsafe setting {Arbitrary defines} {Unrestricted -define is unsafe.} -define {} disabled 0 {Unrestricted coder/delegate settings prohibited}
catalogAdd fx Unsafe operator FX {Arbitrary expression evaluator is not permitted.} -fx {} disabled 0 {Unrestricted expressions are prohibited}
catalogAdd draw Unsafe operator Draw {External MVG/URL/path payload not accepted.} -draw {} disabled 0 {Unrestricted primitive strings are prohibited}
catalogAdd write Unsafe output Write {Arbitrary filenames and side effects prohibited.} -write {} disabled 0 {Only canonical explicit publication/export is permitted}
catalogAdd script Unsafe input Script {Arbitrary ImageMagick scripts not permitted.} -script {} disabled 0 {Can execute unrestricted command sequences}
catalogAdd delegate Unsafe input Delegate {External delegates not executable through this catalog.} -delegate {} disabled 0 {No direct delegate invocation}
```

`processFile {path steps output {format miff}}` inspects the first frame, rejects inputs above 100 million pixels and runs each step through temporary floating-point MIFF intermediates. ROI must lie within the raster at that step. Formats are miff/png16/tiff16/tiff32f; output must exist and be nonempty. Scratch stage files are deleted in finally; caller output is not implicitly published. Processing-stage and final-conversion invocations use a 35-second local timeout; `inspectFile` uses run's default 30 seconds, and initial operation-availability help probing uses 8 seconds. `process {datasetId steps {format miff}}` owns a temporary output and returns `{result_path source_dataset_id source_sha256 format}`; caller must release it with `releaseResult {path}`, which accepts only a tracked Inspector temporary. `cleanTemps {}` deletes tracked Inspector temporaries. These resources are this existing implementation's local files, not a substitute public CORE resource service.

`publish {sourceId steps outputId {format tiff16} {manifest {}}}` accepts png16/tiff16/tiff32f, validates output ID `[A-Za-z][A-Za-z0-9_.-]{0,95}`, processes the source, rechecks Session token and source SHA, fills output hash/raster facts into a supplied or newly built manifest, then calls the existing Dataset File Publication owner. It returns that owner's receipt; replacement is not automatic and foreign Datasets are not overwritten by this interface. A supplied manifest is structurally validated, not exhaustively reconciled against every recipe argument. Temporary output is deleted in finally. No raw file write becomes a canonical Dataset until public publication succeeds.

Other loaded host inspection/helpers:

| Signature in `::GX::SII` | Result, units, context and limits |
|---|---|
| `get {d key {fallback ""}}` | Dictionary value or fallback. |
| `magickPath {}` / `magickVersion {}` / `capabilities {}` | Configured Runtime tool path / first version line / raw capability text; subprocess errors propagate. |
| `run {argv {limitMs ""}}` / `cancel {}` | Existing local event-loop process adapter, merged stdout/stderr text; default 30000ms, explicit limit 100..240000ms, nominal1048576-character output guard (Tcl string length), timeout/output excess errors. Cancel targets latest local job counter. These are not durable CORE Script Jobs. |
| `tempFile {extension}` | Tracked path under configured temporary directory; extension must match the implementation's dot/lowercase-alphanumeric pattern. |
| `frame0 {path}` / `limits {}` | First-frame engine operand / actual argv limits: memory192MiB, map384MiB, disk768MiB, time30s, threads2, list-length64. |
| `inspectFile {path}` | First-frame format/dimensions/depth/channels/colorspace/type/orientation/frames/resolution/density/byte text and pixel_count. Accepts PNG/JPEG/TIFF/BMP variants or tracked internal MIFF; positive dimensions. This helper alone does not enforce the 100MP processing bound. |
| `inspect {datasetId}` / `detailedInfo {path}` | Combined current source/technical/container facts / engine verbose identification text. No physical calibration inferred. |
| `number {value low high integer}` / `geometry {text}` | Validate numeric bounds / numeric WxH with optional offsets, positive dimensions <=100MP. Invalid/NaN values error. |
| `previewFile {source output {width 1100} {height 850}}` | First-frame non-enlarging 8-bit PNG preview path; width/height each80..4000; output existence required. Display image is not canonical scientific data. |
| `regionArgs {roi}` | Empty args for empty ROI or validated crop argv; integer nonnegative x/y/w/h <=1000000, w/h positive. This helper alone does not verify raster containment/area. |
| `stats {source {roi {}} {channel All}}` | Dictionary parsed from engine text: minimum/maximum/mean/stddev/median/rms/skewness/kurtosis/entropy/unique_colors when emitted. Channels All/Gray/R/G/B/A. Values retain engine quantum/intensity semantics, not calibrated physical units or uncertainty estimates. |
| `histogram {source {channel Gray} {roi {}}}` | `{channel bins bin_depth 8 roi}`; 256 integer count bins, channels Gray/R/G/B/A. Explicit 8-bit reduction. |
| `palette {source {roi {}} {colors 16}}` | Count/hex-color pairs sorted by decreasing integer count; colors2..128; quantized 8-bit display palette. |
| `pixel {source x y}` | Raw engine text for one pixel; nonnegative integer x/y<=1000000 and strict bounds inside current raster. |

## Figure and annotation host helpers

`validateAnnotation {a width height}` returns normalized editable geometry. Coordinates are integer pixels within inclusive canvas bounds; kinds text/line/arrow/rectangle/ellipse. Non-text requires x2/y2. Line/arrow endpoints must differ; rectangle requires both dimensions nonzero. Color defaults #FFCC00 and must be #RRGGBB; stroke defaults4, range1..40. Text defaults A, size46 range8..1200; font_family defaults DejaVu-Sans with a bounded simple name; font_unit px or pt; font_value1..1200; optional font_dpi36..2400 and box dimensions1..12000. Text has at most256 characters and rejects `%`, `@`, backslash, CR/LF and NUL per actual expression. Rotation defaults0, absolute value<=3600 degrees. Optional pivot must supply both coordinates and lie within canvas; optional name single-line<=100, ID ann+digits. Validation precedes the retained geometry/publication workflow; a rendered text size is not a physical calibration.

`figureValidInt {value low high name}`, `figureColor {color}` and `figureText {text}` expose the corresponding validators. `annotationPivot {a}` uses the explicit pivot or text anchor/nontext midpoint. `annotationTransformPoint {a x y}` and `annotationInversePoint {a x y}` return image-space rotated/inverse XY pairs. `annotationNativeMatrix {a height}` returns a six-value retained affine matrix after converting top-left image coordinates to bottom-left Native2D coordinates (opposite angular sign). These helpers require structurally valid annotation dictionaries; they are not generic Script Bridge operations.

`figurePlan {panels width height margin gutter layout}` returns per-panel slot dictionaries (panel/index/x/y/width/height). It requires1..12 panels, width/height120..12000, margin/gutter0..1000, layout horizontal/vertical/grid; slot dimensions must each be at least24. `figureVerifyPanels {panels}` returns source_id/source_sha/normalized steps after revalidating each source hash.

`figureCreate {panels settings annotations output {format png16}}` validates panel identities, normalized annotations and settings; defaults width2400/height1600/margin32/gutter24/layoutgrid/background#FFFFFF. Canvas bound80MP; formats png16/tiff16/tiff32f/png8/jpeg/webp. Each panel is processed from first-frame source, resized into its slot preserving engine aspect behavior, centered, composited, then editable overlays rendered. Returns output/width/height/format/panel_count/annotation_count. JPEG/WebP remove alpha onto background and use 8-bit encoding, quality90/88; other formats use their explicit depth/floating-point choices. Temporary intermediates are cleaned; caller output remains. There is no calibrated resampling or statistical uncertainty propagation claim.

`figurePublish {panels settings annotations outputId {format png16} {manifest {}}}` renders, verifies source identities again, fills manifest output hash/facts and delegates to Dataset File Publication, returning its receipt and deleting temporary output. Use canonical publication formats png16/tiff16/tiff32f: although figureCreate accepts additional display formats, the publication helper chooses PNG only for png16 and TIFF metadata for other inputs; it does not establish correct publication format/media contracts for png8/jpeg/webp. This existing inconsistency is not resolved by documentation. Source/Session validation and overwrite admission belong also to the public publication owner; no additional atomicity beyond its receipt is claimed.

## Workspace callbacks and boundaries

`workspaceValidate {payload}` validates inner schema `scientific_image_inspector.recipe.v2`, required source_id/source_sha/steps/panels/figure_settings/annotations; source ID<=512 characters, SHA64hex, steps/panels/annotations each<=10000 list entries, settings dictionary. Optional sidebar_sections is a nonempty unique subset of simple/figure/annotations/source/analyze/history/publish. It is a structural validator, not execution of up to10000 processing steps; processing still caps64 and figure planning12 panels. The descriptor's outer Workspace schema/version (`scientific_image_inspector.recipe`,1.0) identifies provider storage separately. `workspaceProviderOpen {id}` routes through existing public Viewer open with workspace_id; opening may require GUI/runtime dependencies.

Related owners: `DATASET_FILE_PUBLICATION_API_v1`, `DATASET_METADATA_API_v1`, `SESSION_INSPECTION_API_v1`, `INTERACTIVE_DOCUMENT_API_v1`, `SESSION_WORKSPACE_API_v1`, `CONFIGURATION_API_v1`, `DOCUMENTATION_API_v1`, `VIEWER_PROVIDER_API_v1`. The existing Inspector GUI implementation, its internal callbacks and its retained user workflows are outside this reference's public invocation surface and were not modified.
