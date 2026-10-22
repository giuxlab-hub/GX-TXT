# Public Builder raster controls: actual generic author example

This note describes the independently authored disposable generic Viewer 1.1.0,
not the user's Scientific Image Inspector. It is grounded in the actual official
Builder receipts in `v2_authoring01/configure68` and `continue70`, admitted source
in `project_v2`, Validate71, and the single Build/Test8/Export72. Separate installed human-input GUI evidence now covers this generic fixture;
see the exact acceptance scope.
The original frozen authoring note and every earlier failed receipt are retained.

The frozen authoring framework is
`9e133a7d3b154ee5191026499db872d252576a2f`. Its original SDK header SHA is
`759849a88f9d615625f0273df021c2bb3f8e6f2c029028a1597a2bd96ac2b1f0`.
All author project changes were made through official `gxtxt-viewer-dev init`,
`builder` and `save`; no generated source or installed module was hand-edited.

## Canonical raster source and immediate tools

Declare a `native2d` component with `source_kind raster` and a `dataset_selector`
with `content_kind raster`. This fixture names them `graphics` and `source`.
The source-free shared declaration for a tool action is, for example:

```json
{"id":"raster_annotation","type":"action","parent":"toolbar",
 "properties":{"label":"Text","action":"raster_annotation",
               "raster_tool":["graphics","annotation"]},
 "layout":{"row":0,"column":8}}
```

Pass the declaration as the single argument to Builder `add`. The shared host
applies declared local tools before authored C++ dispatch. Do not implement a
pointer controller or wait for a worker to select a local tool. Existing SDK
methods remain available for declared operations. In this specific fixture,
component ordinals 3 and 5 are the viewport and Dataset selector:

```cpp
host.raster_bind(3, 5);
host.raster_tool(3, "annotation");
host.raster_command(3, "panel_open:annotation_properties");
```

These ordinals belong to this declared design, not a universal API numbering.
The first eighteen original fixture IDs/ordinals are preserved in 1.1.0.

The exact requested capabilities are `VIEWER_GUI_HOST_API_v1` operations
`value_set`, `text_set`, `raster_bind`, `raster_tool`, `raster_command`;
`SESSION_WORKSPACE_API_v1` operations `create/get/update/list`; and
`SCIENTIFIC_RECIPE_API_v1` operations `scientificHistoryViewerRecord` and
`scientificHistoryViewerNavigate`, with `document_view_v1`. The CORE owns real
Workspace, History, Dataset, Resource and native annotation/ROI operations.

## Semantic menu conditions

Declare all command actions first. On an existing `context_menu`, set
`semantic_viewport` to `graphics`, retain its ordered `actions` list, and declare
`semantic_rules`, for example:

```json
{"annotation_open":{"visible":{"entity":["annotation"]},
                    "enabled":{"annotation_present":[1],"editable":[1]}},
 "roi_open":{"visible":{"entity":["roi"]},
             "enabled":{"roi_present":[1],"layer_visible":[1]}},
 "raster_fit":{"visible":{},"enabled":{}}}
```

Fields combine with AND; alternatives in one field list combine with OR. Empty
conditions are true. Entity values are background, object, ROI or annotation.
Boolean fields are `selection_present`, `roi_present`, `annotation_present`,
`layer_visible`, `layer_locked`, `editable`, with exact values 0/1. These are
actual native semantic facts, not user expressions or arbitrary callbacks.
Native target/generation/Document/source checks run again on invocation; an old
menu command must not silently affect a new selection.

## Target-following native editor

Add a normal `section` with the following property, using declared viewport ID:

```json
{"viewport_anchor":{"viewport":"graphics","target":"annotation",
                    "offset":[12,12]}}
```

Targets are `object`, `selection`, `roi`, `annotation`. The existing native
panel owner handles mapping, following, bounds and lifetimes. Anchored sections
cannot nest and their transient children cannot declare `change_action` or
`component_visibility`. No widget path or drawing callback is authored.

Create ordinary child UI Fields before declaring this root binding:

```json
{"annotation_fields":{"text":"annotation_text",
 "font_family":"annotation_font","font_size":"annotation_size",
 "color":"annotation_color","anchor":"annotation_anchor"}}
```

The four text/font/size/color keys are required and distinct. Font size uses a
numeric `field`; color uses a color `field` with `alpha: true`. Anchor is optional.
Text, family and anchor use admitted text/choice controls. This fixture declares
Sans/Serif/Monospace choices, size 6–96, and the nine native text anchors.

Each editor button uses the existing action property `raster_command`:

```json
{"raster_command":["graphics","editor_apply:annotation_properties"]}
```

Other admitted commands are `panel_open:SECTION`, `panel_close:SECTION` and
`editor_cancel:SECTION`. Apply collects actual UI Fields and performs one
validated native Document/History edit. Equivalent accepted values are a no-op.
Cancel or focused-field Escape discards the transient draft. The chooser's own
grab has first claim on its Escape. Workspace capture excludes unfinished drafts;
accepted native content/style remains with the existing image Resource/Document.
Shared actions named `undo` and `redo` navigate real History; no C++ undo store
or snapshot engine is authored.

## One icon catalog and one compilation lifecycle

All SVGs were imported using official Builder `icon_import`, with title, group
and GPL-3.0-or-later provenance. Use existing `icon`, `icon_disabled`,
`presentation: icon_text`, `icon_position: left`, and admitted `icon_size`
**16, 24, 32 or 48**. This author's rejected size20 request is retained as
`configure68/083_builder`; it is an author declaration error, not a CORE gap.

Native command containers use `command_icons`, keyed by an existing action ID.
Normal/disabled images and native placement are supported. Native menus do not
admit custom spacing, hover/selected image resources or icon-only tooltips.
Toolkit hover/highlight and real tool selection states remain shared owners.

Version 1.1.0 was explicitly built once. Its eight declared typed Tests and Export
reused native binary SHA
`c1548d516ae16ec07b33d807045093fbaea6a0ab5a6b17932117441ac8bee06c`.
The exported ordinary module contains `native/viewer.so`, interface, resources,
compatibility metadata and manual. Normal Plugin Manager installation and runtime
must execute the distributed binary with zero compiler/linker invocations.
Package verification, actual GUI input, canonical state preservation and
cleanup were checked separately; their exact evidence and limits are recorded
in the acceptance report. No acceptance is inferred solely from Build or Test.

The fixture's explicitly synthetic image is 65×37 RGBA with uncalibrated pixel
coordinates. Transparency is display alpha, not scientific uncertainty. No
physical calibration, Dataset publication, image processing result or source
coordinate change is fabricated by these controls.
