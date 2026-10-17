# Scientific Image Inspector — Public API and Manifest Contract

SPDX-License-Identifier: GPL-3.0-or-later

## Registration

Module ID: `viewer.scientific_image_inspector`; Viewer Provider ID: `scientific_image_inspector`; declared public API: `SCIENTIFIC_IMAGE_INSPECTOR_API_v1`. Activate through GX-TXT's normal `modulePublicApiActivate` contract. GUI activation remains lazy. Do **not** source Viewer Tcl files directly in another module.

## Headless public operations

These procs are defined in namespace `::GX::SII` after API activation; they do not require a Tk window. Metadata reads use CORE's public Dataset Metadata API and current Session identity, not a separate plugin registry.

```tcl
::GX::modulePublicApiActivate viewer.scientific_image_inspector SCIENTIFIC_IMAGE_INSPECTOR_API_v1
set info [::GX::SII::apiInfo]
set manifest [::GX::SII::manifestGet my_derived_image]
set summary [::GX::SII::manifestSummary my_derived_image]
set annotations_json [::GX::SII::apiCall annotations_json my_derived_image]
# Alternative dispatch:
set manifest [::GX::SII::apiCall manifest_get my_derived_image]
set summary [::GX::SII::apiCall manifest_summary my_derived_image]
```

Additional supported `apiCall` operations: `inspect dataset_id`, `catalog ?search?`, `capabilities`. `manifestGet` fails explicitly when the source Dataset has no Inspector manifest, schema is unsupported, output ID is mismatched, or a known output SHA differs from CORE's published payload receipt.

`::GX::SII::catalogList ?query?`, `::GX::SII::catalogGet operation_id`, `::GX::SII::validate operation_id parameters_dict`, `::GX::SII::inspect dataset_id`, `::GX::SII::stats canonical_source_path ?roi? ?channel?` (internal path trust boundary applies), and `::GX::SII::histogram` are exposed Tcl procedures. Authorized Dataset entrypoints should be preferred to naked file paths in third-party modules. `::GX::SII::process dataset_id steps_list ?format?` produces a bounded temporary resource which must be released with `::GX::SII::releaseResult`; it does not publish.

`::GX::SII::publish source_id steps output_dataset_id ?format? ?manifest?` and `::GX::SII::figurePublish panels settings annotations output_dataset_id ?format? ?manifest?` go through the existing `::GX::datasetFilePublicationPublish` public service and return its authoritative Dataset publication receipt. Supported Dataset output formats: `png16`, `tiff16`, `tiff32f`. The consumer must not replace a canonical Dataset identity without explicit ownership permission. No Viewer UI command writes directly to a user-selected image file.

## Dataset manifest schema

Namespace in CORE structured metadata:

```text
image.inspector.manifest_schema = scientific_image_inspector.manifest.v1
image.inspector.manifest        = <UTF-8 serialized Tcl dictionary>
```

Manifest required fields:

| Field | Contents |
|---|---|
| `schema` | `scientific_image_inspector.manifest.v1` |
| `producer_module` | `viewer.scientific_image_inspector` |
| `primary_source_id` | Main canonical source Dataset ID |
| `source_sha256_map` | Canonical parent Dataset IDs → 64-character hashes |
| `source_facts` | Per-parent file size, format/MIME, decoded dimensions, channels, depth, color space, orientation, density/resolution and upstream Dataset metadata |
| `operation_steps` | Ordered, validated global operations, typed parameters, step scope and ROI |
| `figure_panels` | Exact per-panel Dataset references, parent SHA and approved processing steps for compositions |
| `figure_settings` | Canvas width/height, margins/gutters, background and layout for compositions |
| `annotations` | Editable annotation dictionaries (stable `id`, type, color, pixel coordinates, text/stroke as relevant) |
| `annotation_layers_json` | JSON projection of the same retained objects with `scientific_image_inspector.annotations.v1`, top-left pixel coordinates and stable IDs |
| `coordinate_system` | Image pixel coordinates with top-left origin, no inferred physical calibration |
| `color_policy` | Processing/color calibration disclosure |
| `image_magick_version` | Actual ImageMagick engine version string at publication |
| `workspace_id` | GX-TXT Session Workspace ID when available, otherwise empty |
| `created_utc` | UTC timestamp |
| `output` | `format`, new `dataset_id`, `expected_sha256`, `raster_properties` (format, dimensions, depth, channels, color space, etc.) |

Manifest text is **data**, never executable Tcl code; retrieve with `dict get` and validate fields using the provided `manifestValidate`. SHA-256 for the committed Dataset is authoritative in CORE publication; manifest's expected output SHA can be checked against the CORE payload. The original parent Dataset always retains its own independent identity and hash. A client should not infer scientific correctness or sample calibration from this recipe. File format conversion, ICC transforms and 8-bit previews remain scientific/provenance considerations.

## Workspace recipe (distinct from Dataset manifest)

Provider ID: `scientific_image_inspector`; workspace schema: `scientific_image_inspector.recipe` version `1.0` (payload marker `scientific_image_inspector.recipe.v2`). This Workspace contains `source_id`, `source_sha`, `steps`, `panels`, `figure_settings`, `annotations`, and optional `image_annotations`, `figure_annotations`, `canvas_mode` and derived `annotation_layers_json`, with `sidebar_sections` for Workspace-specific visible inspector panels and `history_timeline` for retained editing checkpoints. These optional collections preserve independent image/figure overlays; compatibility with earlier experimental alpha payloads is not guaranteed. CORE owns ID, revisions, notes, preview/resources and serialization.

`::GX::sessionWorkspaceViewerMenu` supplies New/Open/Save/Duplicate/Rename/Close/Delete/Manager. Opening a Workspace by exact ID verifies source SHA before restoring state. Pending adjustment previews and Tk photo caches are never authoritative Workspace state. The JSON layer projection is generated from the authoritative `annotations` objects, and cannot be modified independently. `::GX::SII::annotationsJson annotations` serializes trusted validated objects. After publication `apiCall annotations_json dataset_id` reads the validated manifest and returns the overlay projection.

## Security, lifecycle and permissions

Runtime executable comes from `::GX::runtimeToolRequired magick`. No user-entered unrestricted CLI strings or direct shell interpolation are accepted. Images are taken from GX-TXT canonical Dataset sources and managed temporary files. Preview/candidate storage is ephemeral; publication is explicit. The plugin does not write into other Viewers or GX-TXT CORE. `F1` opens a viewer-local manual window and uses CORE markup renderer when present.

## Editable annotation overlay transform extension

Within the `annotations_json` projection, each object may contain `rotation` (clockwise degrees), `pivot_x` and `pivot_y` (working-image pixel coordinates, top-left origin). `pivot_x` and `pivot_y` must occur as a pair when supplied. Omitting them selects a default pivot: text insertion point, or geometric bounds-center. The Workspace Tcl dictionary remains authoritative; JSON is a read-only interoperable projection available through `SCIENTIFIC_IMAGE_INSPECTOR_API_v1` after Dataset publication. The schema ID stays `scientific_image_inspector.annotations.v1`; these optional fields are backward-compatible.

### Named overlay objects

The `annotations_json` result includes a user-editable `name` for each object when available, in addition to the stable `id`, `kind`, coordinates, style, `rotation`, and optional `pivot_x`/`pivot_y`. The JSON schema identifier remains `scientific_image_inspector.annotations.v1` (additive optional field). Workspace payloads from earlier versions without names receive display names on load; their original stable IDs are retained.


### Text annotation properties

Text overlay records additionally support `font_family` (validated ImageMagick font name), `size` (final size in image pixels), `font_unit` (`px` or `pt`), `font_value` (user-entered size), optional `font_dpi` (the output-DPI assumption used for pt conversion), and `box_width`/`box_height` (editable image-pixel bounding box). These are additive fields of `annotations_json` and are retained in the CORE-owned Workspace payload and published Dataset manifest. The stable annotation/manifest API IDs remain unchanged.
