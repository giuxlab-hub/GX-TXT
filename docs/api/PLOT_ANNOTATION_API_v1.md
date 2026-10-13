# GX-TXT Plot Annotation API v1

SPDX-License-Identifier: GPL-3.0-or-later

## Purpose

The Plot Annotation API adds a non-destructive presentation layer to plots produced by Standard Module API modules. The analysis module remains responsible only for the scientific base plot. Text and simple vector graphics are stored in a separate UTF-8 JSON document and never modify the module PNG.

```text
analysis module -> base PNG
                     +
                annotation JSON
                     |
            preview / export / print
```

The base PNG and `render_cache.mat` remain valid even when all annotations are deleted.

## Descriptor opt-in

A descriptor-defined plot enables the common editor explicitly:

```ini
[graph.curvefit.family.overlay]
file=01_curve_family_fit.png
supports_annotations=1
annotation_editor=standard
annotation_types=text;line;arrow;rectangle;ellipse
annotation_coordinate_spaces=figure_norm
```

The core does not contain a Curve Family Fitting-specific annotation branch. Any future plot can opt into the same editor with the same keys.

## Storage

For a base plot:

```text
analysis/<module>/01_curve_family_fit.png
```

the standard annotation document is:

```text
analysis/<module>/annotations/01_curve_family_fit.json
```

The JSON is the authoritative editable state. Annotated PNG files created for export or printing are derived outputs and may be regenerated at any time.

## JSON document

Version 1 uses normalized figure coordinates and a flat object schema:

```json
{
  "annotation_api_version": 1,
  "plot_id": "curvefit.family.overlay",
  "base_plot": "01_curve_family_fit.png",
  "enabled": true,
  "canvas": {
    "width_px": 1600,
    "height_px": 900,
    "dpi": 200
  },
  "objects": [
    {
      "id": "text_001",
      "type": "text",
      "visible": true,
      "locked": false,
      "z_index": 10,
      "space": "figure_norm",
      "x": 0.32,
      "y": 0.66,
      "text": "Knee region",
      "font_family": "sans",
      "font_size": 11,
      "font_unit": "pt",
      "bold": false,
      "italic": false,
      "color": "#000000",
      "rotation_deg": 0,
      "h_align": "left",
      "v_align": "middle",
      "background": "",
      "border": false
    },
    {
      "id": "arrow_002",
      "type": "arrow",
      "visible": true,
      "locked": false,
      "z_index": 5,
      "space": "figure_norm",
      "x1": 0.31,
      "y1": 0.63,
      "x2": 0.24,
      "y2": 0.49,
      "stroke": "#000000",
      "stroke_width": 1.5,
      "stroke_unit": "px",
      "dash": "solid",
      "head": "triangle"
    }
  ]
}
```

## Coordinate system

Version 1 implements `figure_norm`:

```text
x = 0  left edge
x = 1  right edge
y = 0  bottom edge
y = 1  top edge
```

The coordinates are independent of the preview window size. A module rerender may therefore replace the base PNG without rewriting the annotation document.

The schema reserves the `space` field so a later API revision can add data-coordinate anchors without changing existing documents. v1 validators reject unsupported coordinate spaces instead of silently misinterpreting them.

## Object types

### `text`

Supports UTF-8 multiline text, font family, font size, `px` or `pt`, bold/italic, color, rotation, horizontal/vertical alignment, optional background and border.

### `line`

Two normalized endpoints plus color, width/unit and line style.

### `arrow`

Line properties plus an arrow head (`triangle`, `open`, `none`).

### `rectangle` and `ellipse`

Two opposite corners plus stroke, optional fill and fill opacity.

Every object also has `id`, `visible`, `locked`, `z_index` and `space`.

## GUI contract

Plots declaring `annotation_editor=standard` receive:

- `Annotate...`
- `Export annotated...`

The editor opens the current server PNG at 1:1 as a read-only background. The toolbar provides Select, Text, Line, Arrow, Rectangle and Ellipse. Object state is edited in a property panel and can be moved directly with Select. The editor includes undo/redo, delete, send-to-back, bring-to-front, Save JSON and Save & close.

Saving uses an atomic temporary-file + rename operation through the JSON bridge. Closing with unsaved modifications asks whether they should be saved.

## Preview contract

The ordinary Plots preview continues to read the unmodified module PNG and then draws the JSON objects as a Tk Canvas overlay. No annotated raster file is required for interactive viewing.

## Export contract

`Export selected...` retains the historical behavior and exports the base plots.

`Export annotated...` invokes the standard annotation compositor and writes a new PNG containing base image + enabled JSON layer. The session PNG is not changed.

## Print / PDF contract

Printing and PDF composition automatically apply annotation JSON when present. Before the PDF compositor is called, the framework creates an ephemeral annotated PNG under:

```text
report/annotated_print/<module>/
```

Plots without an annotation document are passed through unchanged.

## Manifest Format 2

The manifest stores references, not object payloads:

```ini
[plot_annotations]
api_version=1
count=1

[plot_annotation.1]
plot_id=curvefit.family.overlay
plot_path=analysis/curvefit.family_global/01_curve_family_fit.png
file=analysis/curvefit.family_global/annotations/01_curve_family_fit.json
enabled=1
api_version=1
```

The JSON remains authoritative. This keeps the manifest readable and avoids escaping arbitrary multiline text into INI sections.

## Renderer

`services/annotations/plot_annotation_renderer.py` is the shared non-destructive compositor used for export and printing. It accepts:

```text
--base <PNG>
--annotations <JSON>
--output <PNG>
```

The renderer currently uses Pillow. `pt` is converted to pixels using the document DPI; `px` is used directly.

## Validation

`services/annotations/plot_annotation_bridge.py validate FILE` verifies at least:

- API version;
- object array;
- unique non-empty IDs;
- supported object types;
- supported coordinate space.

Unknown v1 object types or coordinate spaces are errors rather than silently ignored configuration mistakes.

## Non-goals of v1

Version 1 does not yet implement data-coordinate anchors, multi-object selection, groups, or vector SVG/PDF-native output. Those can be added without changing the non-destructive storage principle.

## Public graph-addressed API (dev-051)

CORE provides `plotAnnotationInfo(module, graph, ?variant?)`, `plotAnnotationRead(...)`, `plotAnnotationValidate(module, graph, variant, objects)`, `plotAnnotationAdd(..., object)`, `plotAnnotationUpdate(..., id, changes)`, `plotAnnotationRemove(..., id)`, `plotAnnotationReplace(..., objects)`, `plotAnnotationClear(...)`, and `plotAnnotationSetEnabled(..., enabled)`. Tcl names are `::GX::plotAnnotationInfo`, etc. These operations use the existing annotation JSON authority and normal Manifest lifecycle. No activation or direct JSON editing is required.

`info` describes the graph's declared support/editor/types/spaces. Public mutation validates stable module/graph/Variant identity against the descriptor, rejects unsupported types/spaces, unknown object fields, duplicate IDs, changed IDs and nonfinite coordinates. `add` assigns a deterministic unused `aNNNNNN` ID when omitted; the returned document contains it. `update`/`remove` address IDs rather than array positions. Writes validate a temporary document before atomic replacement. The PNG and scientific values remain unchanged. Rerender preserves the overlay, and graph/Variant deletion uses the existing cleanup path. Clone capture copies an existing overlay; its viewer/export can compose it.

```tcl
set doc [::GX::plotAnnotationAdd plot.dataset plot.dataset.xy p0004 \
    [dict create id comment type text x 0.15 y 0.8 text {Reviewed measurement}]]
::GX::plotAnnotationAdd plot.dataset plot.dataset.xy p0004 \
    [dict create id direction type arrow x1 0.2 y1 0.3 x2 0.4 y2 0.6]
::GX::plotAnnotationUpdate plot.dataset plot.dataset.xy p0004 comment \
    [dict create text {Reviewed again}]
::GX::plotAnnotationRemove plot.dataset plot.dataset.xy p0004 direction
```

Both Script Bridge languages expose `info`, `read`, `validate`, `add`, `update`, `remove`, `replace`, `clear`, `set_enabled`; require `PLOT_ANNOTATION_API_v1@1:plot_annotation`. Pass module/graph/Variant strings plus object structs or object lists, never a storage path. Returned `read` documents contain `meta` and `objects`; `validate` returns normalized objects.
