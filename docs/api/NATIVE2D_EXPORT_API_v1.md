# NATIVE2D_EXPORT_API_v1

API version1, provider `export.native2d_presentation` version1.0.1, Tcl namespace
`::GX::Native2DExport`, loaded from `api/native2d_export_api_v1.tcl` by the normal
module/public-API activation owner. This installed exporter consumes the existing
[Native2D presentation snapshot](NATIVE2D_PRESENTATION_SNAPSHOT_v1.md); it has no
geometry, canonical Dataset or unit-conversion authority of its own.

## Public calls and exposure

| Exact Tcl signature | Result |
|---|---|
| `::GX::Native2DExport::svg context` | Structured successful result containing UTF-8 SVG bytes |
| `::GX::Native2DExport::png context` | Structured successful result containing PNG bytes |

Both calls require exactly one context dictionary. `_render format context` is
their internal implementation, not a third consumer operation. The descriptor
advertises extension IDs `svg` and `png`, category `exporter`, `mutates=0`, for
`viewer.curve_viewer`, `viewer.curve_workbench`, and `viewer.dataset_curve_fit`.
The required API is `NATIVE2D_PRESENTATION_SNAPSHOT_v1`.

This family has no registered direct Python/Octave Script Bridge binding or
typed C++ SDK method at this source checkpoint. Scripts may use an admitted
Workbench Extension workflow with its own context/result contract; that does
not create `gxtxt_api_call` operations on this exporter family. The current SDK's
`diagram_open`, `diagram_tool`, and `diagram_command` remain their actual typed
Native2D viewport integration methods. They do not accept arbitrary Tcl/API
names or provide a snapshot/export call.

## Context and normal extension workflow

The provider reads required `presentation_snapshot` and `parameters` dictionaries.
`presentation_snapshot.api_id` must be `NATIVE2D_PRESENTATION_SNAPSHOT_v1` and
`api_version` must equal1. `parameters.scale` defaults to1. The `png` action's
declared `scale` parameter is a number in0.25–4; SVG has no declared parameter
and ignores scale in its renderer. The direct functions do not build a snapshot
or select a Session, Workspace, native scene, file name or Document.

Use the existing [Workbench Extension API](WORKBENCH_EXTENSION_API_v1.md) to
discover/describe an enabled compatible action, validate its context, invoke it,
and publish its output. That owner requires the current Workbench identity,
version, Document ID and nonnegative revision; it checks actual Document owner
and revision, validates declared parameters, captures configuration, activates
required APIs, and appends action/provider provenance. Calling the adapter
directly does not perform those Workbench ownership/revision checks.

For file delivery, `::GX::workbenchExtensionExport module action context destination`
normalizes the destination and rejects an existing destination. It verifies
returned format/bytes and delegates the bundle to File Publication; its receipt
replaces in-memory bytes with the real published file receipt and
`published_files`. The two adapter functions themselves return bytes and do not
publish the user's chosen file or return its hash. No Dataset or source geometry
is edited by the adapter.

## Returned adapter dictionary

| Field | Actual value / meaning |
|---|---|
| `status` | `ok`; failures throw rather than return a successful partial result |
| `format` | `svg` or `png` |
| `bytes` | Complete binary output; treat PNG as binary and SVG as UTF-8 XML |
| `warnings` | Empty list from this provider; not a proof of scientific completeness |
| `export_policy.source` | `Native2D_presentation_snapshot` |
| `export_policy.point_budget` | Snapshot's declared per-object display budget |
| `export_policy.scientific_materialization` |0 |
| `export_policy.clipping` | `native_viewport` |
| `export_policy.vector` |1 for SVG,0 for PNG |

The inherited snapshot budget is a display policy, not a row count or global
bound on all objects. Hidden objects/layers and reference-role exclusions have
already been selected by the snapshot producer. Export does not reread the
authoritative Dataset to verify or replace the supplied presentation.

## Rendering, units and resource bounds

Coordinates, line widths, glyph radii and fonts are snapshot device pixels.
Converted axis labels/text are supplied by the shared presentation owner; they
do not convert Native geometry or canonical Variable values. Paths, grid,
direction/part-direction markers and legend swatches are clipped to the plot
viewport. A plot border and text are then drawn; text uses supplied position,
anchor, rotation, size and RGBA. Text is not globally clipped to the plot, so
axis labels can occupy margins. Background alpha is composited over white.

Curve paths remain display polylines even in vector SVG. Styles preserve RGBA,
line width, solid/dashed/dotted line policy and circle/square/cross point glyphs.
An object's optional `point_markers` list draws separate explicit device points;
the renderer does not infer that all display samples are authoritative source
points. Ordinary and compound-part direction markers use their snapshot styles.
SVG contains vector paths/glyphs and text, without an embedded raster image.
PNG uses Python Cairo with the standard sans-serif font support.

The renderer decodes Tcl lists/dictionaries using Tcl's list decoder, without
evaluating the input as Tcl code. Its input-file limit is64MiB. View width and
height must be finite and each in1–16384, with a positive plot clip rectangle;
decoded coordinate tuples must be finite and RGBA components in0–1. The PNG
scale must be finite and0.25–4; output dimensions are `ceil(width*scale)` and
`ceil(height*scale)`, with at most64,000,000 pixels. SVG retains the snapshot's
unscaled dimensions. These checks do not establish a universal output-byte bound
or validate all scientific/semantic content of a hand-built snapshot.

## Effects, dependencies and failures

The adapter writes an internal UTF-8 temporary input file and invokes the
configured Python runtime with the installed `runtime/native2d_export.py` using
`-B`; output is read in binary. Input/output temporary files are deleted in
`finally`, including on failure. Python3 with tkinter's Tcl list decoder is
required; PNG additionally requires Python Cairo. The normal installed module
descriptor locates the renderer. This is an actual external rendering process,
not an implicit scientific Managed Job or Dataset publication.

Missing context fields, wrong snapshot API/version, malformed Tcl dictionaries,
nonfinite coordinates, invalid viewport/colors/scale, exceeded transport/pixel
bounds, unavailable Python/Cairo/font/runtime components, and file/process
errors propagate as errors. The public adapter does not reinterpret a failure
as an empty image. File destination collision/atomic publication/provenance are
owned by Workbench Extension and File Publication, not this renderer.

## Source-backed host example

The host must already own a live native scene and have activated this public
module API. This example obtains bytes only; it is illustrative, not a newly
executed test or a substitute for the normal Document-bound export action.

```tcl
set snapshot [::GX::native2DPresentationSnapshot $nativeScene \
    [dict create point_budget 4096 legend auto]]
set result [::GX::Native2DExport::svg \
    [dict create presentation_snapshot $snapshot parameters {}]]
set imageBytes [dict get $result bytes]
```

For complete scientific output use the canonical publication/geometry export
service with its own retained definition, sampling, Variables and units contract.
Successful presentation export is not scientific materialization, uncertainty
propagation, full-resolution Dataset export or independent numerical validation.
