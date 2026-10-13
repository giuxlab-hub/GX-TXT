# Plot Annotation Editor — user guide

SPDX-License-Identifier: GPL-3.0-or-later

## Open the editor

1. Open a session and select a plot in **Plots**.
2. Click **Annotate...**.
3. The editor shows the current server PNG at 1:1. Scroll if the image is larger than the window.

The background image is read-only. All edits belong to the JSON overlay.

## Tools

- **Select** — select and drag an existing object.
- **Text** — click once to create a text label, then edit `Text` and its properties on the right and press **Apply properties**.
- **Line** — drag from start to end.
- **Arrow** — drag from start to arrow tip.
- **Rectangle** — drag two opposite corners.
- **Ellipse** — drag the bounding rectangle.

After drawing an object the editor returns to Select mode.

## Properties

Common properties include visibility, lock state and Z order. Vector objects expose stroke color, width, px/pt unit and line style. Rectangle/Ellipse also expose fill and opacity. Arrow adds a head style.

Text exposes UTF-8 multiline content, font family, font size, px/pt unit, bold/italic, color, rotation, alignment, optional background and border.

Changes in the property panel become part of the working copy only after **Apply properties**.

## Ordering and history

- **Send back** moves the selected object behind the others.
- **Bring front** moves it above the others.
- **Undo / Redo** keeps up to 50 editor-state snapshots.
- **Delete** removes the selected object from the working copy.

## Save

**Save JSON** writes:

```text
analysis/<module>/annotations/<plot-name>.json
```

The base PNG is not rewritten. Save also refreshes the Plots preview and the session manifest reference.

**Save & close** performs the same operation and closes the editor.

If the editor is closed while modified, it asks whether to save, discard, or cancel.

## Export and print

- **Export selected...** exports the base PNG as before.
- **Export annotated...** creates a new raster with the JSON layer applied.
- **Print / PDF** applies saved annotations automatically. No manual “flatten” step is required.

## Important behavior

Rerendering the scientific plot does not remove the JSON file. Because v1 positions are stored as normalized figure coordinates, labels and vector objects keep their relative position when the base plot is regenerated.
