# Dataset Table

Dataset Table reads compatible canonical tabular Datasets in the current GX-TXT Session. It does not edit cells, run formulas, import data or publish a result.

## Open and clear

Open your Session, then choose **Viewers → Documents → Dataset Table**. Choose a registered identity in **Tabular Dataset**; selection opens its table. **Open table** refreshes the selection. Images, PDF documents and non-table arrays are excluded by the shared compatibility owner. With no Session or eligible Dataset, the Viewer shows a selection prompt.

**Clear selection** empties the selector and the current consultation through CORE's normal changed-selection action. It does not delete or modify a Dataset. Select another identity to start reading again.

## Read values and schema

The shared CORE Preview supplies up to 100 rows per page, with a one-based **Source row** column and the canonical variable labels and unit suffixes. **Previous**, **Next** and the source-row entry/**Go** controls navigate the bounded source. The default projection contains at most 32 compatible rank-one variables; unsupported dimensions and schema combinations are reported clearly.

Open **Column details** for the displayed variables' IDs, labels, declared types/value kinds, units, semantic roles and shapes. Missing metadata is labelled **(not declared)**. These details come from the same canonical page as the displayed values; this Viewer infers no scientific meaning from a cell.

Select a row and use **Ctrl+C** to copy its presentation. Horizontal scrolling reveals wide columns; vertical scrolling moves within the current page. Resize the window for more visible data. There is no find/filter operation.

## Session, source and limits

Dataset selection and source revision remain under CORE authority. A Session change invalidates this Viewer's old document binding; open a new consultation in the intended Session. The shared pager additionally guards navigation across Session changes. Missing, incompatible or changed sources report an unavailable state rather than reading a different source silently. No source is stored in the Viewer project.

Use **Help** or **F1** for this guide through the Documentation Browser. This package composes existing CORE Dataset Access, Preview paging, Table Stream, Variable Schema, Unit Registry and GUI Host services. It contains no table engine or scientific data store.

Public references: [Dataset Preview](../../../../docs/api/DATASET_PREVIEW_API_v1.md), [Table Stream v3](../../../../docs/api/TABLE_STREAM_API_v3.md), [Variable Schema v3](../../../../docs/api/DATASET_VARIABLE_SCHEMA_API_v3.md), [Viewer GUI Host](../../../../docs/api/VIEWER_GUI_HOST_API_v1.md).

Development status: v1.0.2 adds the public optional selector to the preserved restricted-author project. Its installed native acceptance is recorded separately; this manual is not a release-acceptance claim.
