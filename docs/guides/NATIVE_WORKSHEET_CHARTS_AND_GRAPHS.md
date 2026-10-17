# Worksheet charts and native scientific Graphs

The Worksheet uses the shared Native2D C++ grid. Only visible cells are drawn;
the Workbook and public scientific services retain values, formulas, units,
Dataset bindings and source identities. Scrollbars address rows 1–1,000,000 and
columns A–ZZ. Scientific operations retain their explicit bounded range limits.

Select at least two columns and choose **Insert → Native chart from selection**.
The first column supplies X and the other columns supply Y. Charts appear in a
separate area below the grid. **Data → Charts / Publish…** opens the left Chart
inspector. **Data → Publish Dataset…** retains standalone canonical Dataset
publication through the existing publication service.

The Chart inspector controls source sheet/columns/range, representation, title,
color, line width, markers, legend, axis limits/scales and a text annotation.
Assign a Y column to the right axis or use separate panels for different
dimensions. Commensurate units are converted through the CORE Unit Registry for
display; source values and their units remain unchanged. Missing and NaN values
create breaks. Complex or otherwise unsuitable sources produce an explicit error
and preserve the last valid representation.

Drag a chart header to move it and its lower-right grip to resize it. Click an
object to select it, use the wheel to zoom and the middle button to pan. Fit or
double-click restores the complete scientific extent. Save retains intentional
viewport limits in the existing Workspace. Changing a source coordinate frame
invalidates an incompatible retained viewport. Completed edits and gestures use
the shared semantic History.

**Publish immutable Graph to Plots** publishes evaluated values and source
provenance as a new canonical Dataset, then creates a native Graph Variant.
Subsequent live cell edits do not change that Dataset or Graph. Choose a Z column
and use **Publish and open authentic Native3D** for the shared native 3D engine.
All scientific calculations and publication remain owned by the existing public
Worksheet, Numeric, Dataset and Session APIs.

Native Graphs use the existing Plots presentation controls, Analysis queue,
scientific Clone editor and portable Graph transport. Their explicit Graph
metadata selects public Plot Dataset API v4. Historical unmarked graphs retain
their existing renderer. A scientific native Clone captures complete canonical
Dataset packages and can rerender independently of the original Dataset or
Variant. Rendered-only import retains its truthful lack of scientific rerendering.

Automatic bounds use the complete selected scientific source, independently of
display reduction. Negative extrema remain visible after Fit. Native labels and
grid lines use the same numerical tick coordinates. A deliberate partial zoom is
preserved until Fit is requested. Display samples retain exact source-row
identities and breaks; they are not a replacement scientific Dataset.

See the [Worksheet manual](../../plugins/modules/viewer.scientific_worksheet/MANUAL.md),
[native grid contract](../api/NATIVE_2D_VIRTUAL_GRID.md),
[Plot Dataset API v4](../api/PLOT_DATASET_API_v4.md),
[axis presentation contract](../api/NATIVE2D_AXIS_PRESENTATION_v1.md) and
[portable resources guide](PORTABLE_RESOURCE_EXPORT_IMPORT.md).
