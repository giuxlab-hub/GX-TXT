# GX-TXT Preview Descriptor API v1

SPDX-License-Identifier: GPL-3.0-or-later

## Purpose

Preview Descriptor API v1 lets a plugin describe a preview without requiring the framework to understand or decode the source format. It is intended primarily for binary acquisition sources and binary canonical datasets, but it is host-independent and may also be used by text handlers.

The plugin produces preview content. The framework owns preview workspace rendering, temporary preview storage, validation and cleanup.

## Framework-provided preview directory

When the common acquisition Preview workspace asks `inspect_proc` for a preview, the request contains:

```text
preview_dir=<absolute framework-owned temporary directory>
```

`dataset_preview_proc` receives the same field. A plugin that wants to create an artifact MUST write it inside this directory. The framework rejects path traversal and artifacts outside `preview_dir`.

When inspection is performed only for metadata/variable discovery, `preview_dir` may be empty. Plugins MUST therefore treat artifact generation as optional.

## Descriptor fields returned by the plugin

The inspection/dataset-preview result may contain:

```text
preview_kind=metadata
preview_metadata=<Tcl dict of label/value pairs>
```

or:

```text
preview_kind=artifact
preview_artifact=<Tcl dict>
```

with artifact fields:

```text
path=<path relative to preview_dir, or an absolute path still inside preview_dir>
media_type=<MIME media type>
label=<optional human-readable label>
```

Both branches may be requested with:

```text
preview_kind=metadata+artifact
```

`both` is accepted as an alias. `none` explicitly requests no preview content. For compatibility, absence of `preview_kind` preserves legacy text preview behavior; for a binary source, existing `metadata` is used as metadata preview when no explicit descriptor is returned.

## Rendering contract

The framework:

- renders metadata as label/value rows;
- may display visual artifacts supported by the current host renderer;
- never decodes the original binary source;
- does not itself generate thumbnails, waveforms or extracted frames; the separate CORE Dataset Preview API may create safe temporary fallback artifacts for registered media datasets;
- shows a safe fallback description when the host cannot display the declared artifact media type.

A plugin that needs guaranteed display in the current Tcl/Tk host should produce a simple image artifact such as PNG or another image format supported by the host. Future hosts, including GiuxLab-Calc, may render the same descriptor differently without changing the plugin.

## Security and lifecycle

Artifact paths are validated to remain below the framework-owned `preview_dir`. The directory is temporary and is removed after the host has consumed the preview. It is not part of the canonical dataset or scientific provenance unless the plugin separately publishes an artifact as a dataset/output.

## Non-goals

Preview Descriptor API v1 does not define audio playback, video playback, image decoding, codecs, ROI semantics or scientific image processing. Those belong to plugins and future scientific APIs.

## Dataset tabs (dev111, incremental patch P002)

Installed `kind=preview` modules can add panes to the existing Dataset Preview.
The ordinary Module and Plugin Manager owners control installation, dependencies,
activation and pending updates. Multiple compatible components can contribute;
none removes the standard Preview. Disabled, incompatible or failed components
leave the generic fallback available.

A presentation-only component declares the following in its normal `module.ini`:

```ini
[meta]
api_version=1
id=preview.example
kind=preview
name=Example Dataset views
version=1.0.0
selectable=1
default_enabled=0
runner=service
enabled_key=
run_key=

[preview_provider]
api_version=1
profile=presentation
dataset_contracts=curve_family.table
gui_public_api=PREVIEW_COMPONENT_GUI_API_v1

[public_apis]
ids=PREVIEW_COMPONENT_GUI_API_v1

[public_api.PREVIEW_COMPONENT_GUI_API_v1]
api_version=1
entrypoint=api/preview.tcl
namespace=::GX::ExamplePreview
```

The normal public-API loader activates that entrypoint. Its fixed
`::GX::ExamplePreview::preview context` callback returns a dictionary with a
`tabs` list. Each pane has a stable component-local `id`, a readable `label` and
one of these `kind` values:

| Kind | Content fields | CORE rendering owner |
| --- | --- | --- |
| `metadata` | `metadata` label/value dictionary | Preview Descriptor metadata renderer |
| `artifact` | `artifact` with `path`, `media_type`, optional `label` | Existing artifact validator/renderer; path must stay inside the supplied Preview directory |
| `table` | `dataset_id`, optional `variable_ids`, optional `count` | Canonical `datasetPreviewPage` and existing text sample renderer; count 1–1000, at most 32 variables |
| `native` | No new geometry or renderer command | The current prepared CORE `native_model`, rendered by existing Plot Dataset API v4 |

For example, a module may return calibration or acquisition metadata only when
those registered fields exist. It should omit a source-image pane when the
linked registered Dataset or prepared image is unavailable. A `native` pane may
rename the current curve view (for example Curves or Chromatograms) without
creating another numerical or drawing engine. This patch does not ship new
scientific Digitizer or chromatography Viewers.

The context carries the canonical Dataset identity and registered contract,
Session token, structured metadata/contributors, variable schema, actual payload
availability and a bounded projection of the current prepared representation.
Use those facts together; a contract name alone does not prove that calibration,
integrated peaks, uncertainty or a source image exist. Empty metadata and absent
native/table/artifact data do not create useful scientific views. Labels and
contents are supplied by the component; widget identity includes the component
ID, so two modules may use the same local tab ID.

Callbacks are trusted installed module code and run under the existing module
ownership context. They are a read-only display contract: do not publish, edit
canonical data/contracts/metadata, run analyses, or create persistent selections
merely to show a pane. Return descriptor data rather than Tcl renderer commands.
Provider errors are shown as component diagnostics and do not replace the
standard Preview. Source, Session and provider-byte changes invalidate existing
Preview identities through the existing cache and lifecycle owners.

The strict native profile retains its ABI, platform, native/design hashes and
ordinary public-API declarations. A presentation component does not claim native
admission or verified C++ capabilities. Native processing uses the existing
common batch/plane/overlay engines and the fixed managed Preview worker;
capability/readiness remains separate from presentation availability.

Native processing on Linux x86_64/Tcl 8.6 is supplied by the prebuilt P002 addon;
the base native engine is unchanged. The fixed managed Preview worker admits
normal installed native components after descriptor/asset/design and ABI checks.
The GUI may inspect adapter metadata but cannot enable native admission. Actual
invocations verify only their used capabilities: grouped curves, bounded array
planes, and optional raster overlays. Raster reuse requires the same canonical
role map, filters, source/provider identity and Preview key; otherwise the
existing CORE collector remains the fallback. A shared canonical stream retains
opaque curve identities and point order; Preview never invents uncertainty or
source-image availability. No runtime compiler is introduced.

DEV111-P004 keeps the same notebook and descriptor renderers. Standard numerical
Datasets expose Plot and bounded Table inspection. Source image appears only
for an applicable prepared, verified source image; published Digitizer Quality
appears only when its report is available. A validated Curve Digitizer
publication without an image retains its existing curve controls in Curve
details. These controls do not imply image or Quality availability.

Normalized component tabs additionally carry `role=primary|complementary`;
omission retains the P002 complementary behavior. The installed component
declaration and validated Dataset match determine whether it can be primary.
A sole specialized match can be selected by default after specialized CORE
views have precedence. Equally suitable primary alternatives require an
explicit choice in the existing Preview notebook. Standard inspection remains
available. Selecting a native alternative goes through existing Render/cache
preparation; a pending or failed request retains and qualifies the previous
successful presentation.

## Optional GUI pane (DEV111-P006)

`kind=gui` is an additive tab kind, requiring `[preview_provider] gui_api_version=1`.
It names no callback/script or Viewer design. CORE invokes the module public
namespace `guiMount host context` and `guiDispose host context reason` in its
Preview-owned pane. Old descriptor-only modules need no changes. See
[Preview Component GUI API v1](PREVIEW_COMPONENT_GUI_API_v1.md) for controls,
shared icons, native Plot panels and lifecycle.
