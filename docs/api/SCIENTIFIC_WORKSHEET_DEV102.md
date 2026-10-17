# Worksheet 2.1 public extensions

Existing SCIENTIFIC_WORKSHEET_API_v1, Workbook format v2, canonical Dataset/Variable
and statistical authorities remain in use. Old Workspaces acquire empty optional
presentation fields; no formula source or scientific value is rewritten.

| Tcl / Script Bridge operation | Arguments |
| --- | --- |
| fillRange / fill_range | book, first seed, destination end, optional last seed, auto/copy/series |
| formatRange / format_range | book, first, last, style, optional borders |
| mergeRange / merge_range | book, first, last, optional unmerge boolean |
| setSizes / set_sizes | book, row/column, first index, last index, pixels |
| filterViewSave / filter_view_save | book, name, first row, last row, predicates, optional AND/OR |
| filterViewApply / filter_view_apply | book, name (empty clears display filter) |

Use the existing opaque Workbook bridge value; `inspect_cell` returns typed kind,
`value_utf8`, unit and lineage. `set_typed_cell` preserves explicit typing/units.
New model presentation fields are per-sheet sparse `styles`, ordered rectangular
`range_styles`, `merges`, `row_heights`, `column_widths`, named `filter_views`,
`active_filter`, `filter_hidden_rows`, and script references `scripts`. Full-column
styles do not allocate a million cell records or expand empty navigation extent.
Small ranges and clipboard resolve effective styles; structural edits remap ranges.
Filters retain exact visible row IDs and bound canonical source revisions. Structural
edits invalidate saved filter criteria pending explicit review, rather than applying
them to different columns silently. Display filtering never changes formula/chart
range interpretation. Visible-only script inputs are explicit and include row IDs.

Supported style fields: align, valign, wrap, foreground/background, font_family,
font_size, bold/italic/underline, rotation, category, decimals, grouping, custom,
border_color/width/style/edges. Categories General, Number, Scientific, Engineering,
Percentage, Date, Time, Text, Custom affect display only. Date/Time means Unix UTC
seconds, not inferred Excel serial dates. Supported custom patterns are listed in
the UI. A merge refuses nonempty subordinate cells, source/spill overlap and partial
merge overlap; it never silently discards measurements.

Host scripting: `scriptSave book name code`, `scriptSubmit book name first last
?visibleOnly?`, `scriptCollect book ticket`. Scripts are registered Session sources,
Workspace-referenced by ID/SHA and an exact managed source resource; wrappers run through existing supervised Python
Jobs. New bridge helpers script_context/script_selection/script_snapshot are for
this explicit context. Collect verifies Workbook identity/snapshot, source revisions,
completed Job and proposal identity. UI Apply is one History transaction. Cancelled,
failed and stale proposals cannot replace current Workbook contents. This is the
ordinary Script Job trust model, not an OS security sandbox; scripts may deliberately
use other public APIs under their ordinary permissions.

Current bounded operations: editing/fill/merge/filter max 20000 cells or rows per
operation as appropriate; styles use up to 2048 large-range layers; script source
1 MiB, context 8 MiB, proposal log 16 MiB. GUI rendering fetches visible native
cells, not nominal one-million-row capacity. Filter evaluation is synchronous and
bounded; a future asynchronous very-large filter engine is not claimed.
