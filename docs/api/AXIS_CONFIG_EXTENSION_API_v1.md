# Axis Configuration Extension API v1

SPDX-License-Identifier: GPL-3.0-or-later

Introduced in GX-TXT 0.9.7.41 for artifact-specific controls in the shared **Axes / grid / 3D / color** dialog.

## Purpose

Axis Configuration Extension API v1 lets a plot provider append presentation controls to the common CORE Axes dialog without changing generic CORE axis state or inspecting private widgets. The extension is matched by rendered artifact path, so a provider can recognize plots created through its public API even when another module is the consumer.

CORE remains authoritative for generic graph/panel numeric ranges, tick formatting, grid state and alignment. Provider extensions own only provider-specific presentation fields.

A plot with no registered extension behaves exactly as before GX-TXT 0.9.7.41.

## Registration

```tcl
::GX::axisConfigExtensionRegister my.plot.axes [dict create \
    match_proc ::MyPlot::matchesArtifact \
    build_proc ::MyPlot::buildAxisControls \
    close_proc ::MyPlot::closeAxisControls]
```

Required fields:

```text
match_proc
build_proc
```

`close_proc` is optional.

`match_proc path` returns true only when the provider owns/recognizes the rendered artifact. CORE rejects ambiguous cases where more than one registered provider matches the same artifact.

Inspection/removal:

```tcl
::GX::axisConfigExtensionDefinition provider_id
::GX::axisConfigExtensionForArtifact path
::GX::axisConfigExtensionUnregister provider_id
```

## Context

`build_proc` and `close_proc` receive a read-only dictionary:

```text
api_version
provider_id
artifact_path
graph_key
panel_ids
parent
```

`panel_ids` is the effective stacked-panel order returned by CORE discovery. The extension is hosted only for a selected multi-panel artifact.

`parent` is the only widget container in which the provider may create controls. Providers must not inspect or modify private CORE widgets.

## Lifecycle

The v1 hook intentionally has no generic Save callback. Provider controls commit through the provider's own validated public API, normally through an explicit provider-owned Apply action. This keeps CORE axis persistence and provider presentation persistence separate.

The optional `close_proc context` releases editor-instance state only. It must not delete persistent plot state.

## `plot.dataset` use

`plot.dataset 3.3.0` registers an artifact-based extension. For a multi-panel `plot.dataset` artifact it exposes:

- panel title;
- Y Left label, display unit and scale;
- Y Right label, display unit and scale.

CORE's generic multi-panel section in the same dialog remains authoritative for panel-local Y/Y2 min/max/step/format, grid mode/source/color and Y-label alignment position.

## Ownership boundary

CORE owns:

- detection of real stacked artifacts through `stackedGraphPanels(path)`;
- generic graph-wide X/Y/Y2/Z controls;
- generic per-panel Y/Y2 numeric/grid overrides;
- extension registration, matching, container creation and cleanup.

The provider owns:

- all controls created below `parent`;
- provider-specific validation and persistence;
- artifact recognition through its public state/API.

### Host widget path

Since GX-TXT 0.9.7.43 the shared plotting dialogs may place provider UI inside a scrollable canvas body. Extension providers must treat the `parent` widget supplied by CORE as opaque and build only beneath that widget; they must not hard-code `.axiscfg` or `.graphseriesbase` child paths. This is a GUI-hosting change only and does not change the API version.

