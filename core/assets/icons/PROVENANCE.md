# Shared GX-TXT icon provenance

The original electrical and control SVG assets retain their embedded licensing.

`electromagnetics.png` is a byte-identical copy of the existing original GX-TXT
product artwork at
`plugins/modules/viewer.electromagnetics/icons/electromagnetics.png`.
SHA-256: `a8c0e967a0b4a77160f1956472953d39aa67e3ff3cc512e4557a8c82232d09ea`.
The corresponding original SVG embeds the credit “Original GX-TXT scientific
artwork” and `SPDX-License-Identifier: GPL-3.0-or-later`. This copy exposes the
existing licensed artwork through the normal shared Builder resource catalog;
it creates neither a new product identity nor a new icon renderer.

## TASK210 dev111 stock additions

GX210-MAIN1-SUB3 directly authored 70 original SVG source files for the semantic
briefs in `docs/development/task210/icon_preparation/implementation/NEW_ASSET_SPEC.tsv`.
No artwork generator, third-party asset library, tracing, font or raster image
tool was used. Copyright 2026 GX-TXT contributors, GPL-3.0-or-later. The drawings
use the existing transparent 128-unit canvas, blue `#236b9c`, six-unit stroke and
rounded caps/joins, intended for normal 24-pixel controls. They are editable
geometry, not embedded raster/text or SVG references. The exact bytes of all
30 previously distributed stock sources remain unchanged.

`catalog.json` is the sole stock manifest. Its existing stable IDs and source
names now include bounded English intended-action/origin text and the actual
source-byte SHA256. Five functional families each declare 20 entries. Neither
source row counts nor different hashes alone establish semantic/visual quality,
public admission, installed catalog counts or working Builder/package behavior.
The retained EM PNG remains its original multicolor identity; its consistency
at actual size requires explicit review, not an automatic redraw.

The complete 100-entry source inventory and exact baseline comparison are under
`docs/development/task210/icon_stock111/`. This source batch has not been parsed
by the public icon owner, rasterized, displayed, exported or installed. Those
checks require separate MAIN allocation. Device glyphs identify possible
commands; they confer no electrical model, pin-map, solver or component support.
