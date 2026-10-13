# Scientific Dataset Plot: GUI guide

`plot.dataset` creates 2D and 3D graphs from canonical GX-TXT Datasets. This
guide covers graph setup, the Series editor, family curves, value filters,
rendering, and export. For the scientific data model and public APIs, see the
[module README](README.md).

## Start with a Dataset

Open a Session containing canonical Datasets. In **Analysis**, find
**Scientific Dataset Plot** and enable **Run / recalculate now**. The module
offers **Scientific dataset 2D**, **Scientific dataset 2D - rectangle
selection**, and **Scientific dataset 3D**. Enable the graphs you need. Each
graph has **Configure...**, **Variants...**, and **Series...** controls.

Use **Series...** for 2D X/Y curves. A Series can choose its own Dataset, so
one graph may combine curves from several Datasets. The Analysis tab's
**Dataset sources** bindings are used by the regular 3D graph setup.

The examples below use two Datasets from the `plotdataset-extended-audit`
example Session, if available:

| Dataset | Rows | Example variables |
| --- | ---: | --- |
| `audit.longform` | 504 | `x_s`, `response_V`, `reference_V`, `material`, `batch`, `temperature_C`, `quality`, `gain`, `point_order` |
| `audit.reference` | 21 | `x_s`, `baseline_V`, `upper_V`, `phase` |

`audit.longform` contains Copper, Aluminum, and Steel; batches A and B;
temperatures 20 and 40; gains 1 and 2; and quality values `pass` and
`review`. Each combination has 21 X values from 0 to 10 seconds. You can
follow the same steps with equivalent variables in another Dataset.

## Configure individual Series

Open **Series...** on the intended graph. The table at the top lists that
graph's Series with their ID, enabled state, Dataset, X/Y variable IDs, axis,
label, filter count, and panel. Select a row to edit it. The editor is specific
to the graph you opened.

Choose **Dataset** first, then numeric **X** and **Y** variables. The variable
choices update for that Dataset. Give a new Series a unique **ID** and a
readable **Label** for the legend. Choose the left or right **Axis**; a right
axis adds a separate Y scale. Use **Add/update one series** to create the row
or save edits to the selected row. **Remove selected series** deletes selected
rows. **Up**, **Down**, and **Refresh values** are also available in the editor.

For example, add a `basic` Series from `audit.longform` with X=`x_s`,
Y=`response_V`, left axis, and label `All observations`. Add a `reference`
Series from `audit.reference` with X=`x_s`, Y=`baseline_V`, right axis, and
label `Reference baseline` to display both Datasets in one 2D graph.

For a single-panel 2D graph, **Configure...** has **Single-panel Y scales**.
Choose Auto, Linear or Log for Y Left and, when a right-axis Series exists,
Y Right; click **Apply Y scales**, then save and render. In multi-panel mode,
use each panel's Y Left/Y Right controls in **Configure...**. The common
**Axes...** window can override X, Y Left and Y Right scale for an individual
rendered graph or Variant; its 2D XY aspect control can make X and Y data
units equal in screen length when both axes are linear.

For graph-wide X presentation, use **Axes...** to set scale, step, and minor
grid. A linear step is a tick interval; a log step counts decades. Log minor
grid **Auto** draws subdivisions 2 through 9 within each decade. The same
dialog has a plot background color, chooser, and Inherit action for the
selected base graph or Variant. In **Plot layout**, the Y-label offset stays
non-negative until **Allow negative Y-label offset** is checked.

## Create family curves

Set **Primary family variable** to the column that separates curves. In the
example Dataset, `material` provides Copper, Aluminum, and Steel, while
numeric `gain` provides 1 and 2. **Family values** can use:

- **All values as separate series** for every available value;
- **Selected value** for one value;
- **Selected values** for several values selected with Ctrl-click.

Click **Create family series** to materialize a separate Series row for each
chosen family value. These rows have their own stable IDs and can be edited or
removed individually.

For another grouping, choose a **Secondary parameter variable** and **Second
values**. **Second behavior** offers:

| Behavior | Result |
| --- | --- |
| **Filter** | Restrict each primary family curve to the chosen second value. |
| **Split into series** | Make a separate curve for every selected primary/secondary combination. |
| **Style category** | Keep separate combination curves and reuse each secondary category's style across primary families. |

For example, `material` × `batch` with **Split into series** makes six curves
for three materials and two batches. Choosing Copper and Steel with batch A
and B under **Style category** makes four curves; A's color repeats across
materials, as does B's. A Copper family filtered to batch B makes one curve.
When you reopen a generated row, the editor shows its saved per-Series values
and filters. It may therefore display **Filter** or **All values as separate
series** instead of the choices used to generate the family.

## Filter and order points

Choose **Filter variable**, then pick an exact **Filter value** from its value
list before adding or updating a Series. Text and numeric values both work.
Family and secondary choices add further per-Series value restrictions.

| Example choice | Use |
| --- | --- |
| `quality=pass` | Combine with material and batch families. |
| `quality=review` | Restrict a Copper, batch B curve. |
| `temperature_C=20` | Create two gain curves for Copper. |
| `temperature_C=40` | Edit one gain curve or create styled material/batch curves. |

These controls select exact values. Other row-filter predicates are part of
the public Graph Series model, but the examples here use the GUI's exact value
chooser. Set **Ordering variable** to `point_order` when observations have an
explicit within-curve order. Without grouping and ordering, an all-observations
Series may connect unrelated experimental combinations.

With the example Session, the Copper/batch A/quality pass family has 64
plotted points. A Copper/batch A/temperature 40 styled family has 42 points
because both gain values remain; the Copper/batch B/quality review family has
20 points. These counts help check that family and filter choices were saved
as intended.

The lower editor also offers **Provider details**, **Representation**, style
controls, auxiliary variables, and alignment fields. Use them when those
presentation or data bindings are needed; the family and filter steps above
do not require them. Panel assignment is available when multi-panel mode is
enabled through **Configure...**.

## Worked configurations

### Text families with a text filter

1. Enable **Scientific dataset 2D** and add the `basic` Series above.
2. Choose `audit.longform`, X=`x_s`, Y=`response_V`, primary family
   `material`, and **All values as separate series**.
3. Choose secondary `batch`, **Split into series**, values A and B, filter
   `quality=pass`, and ordering `point_order`.
4. Click **Create family series**. The graph has the basic line and six
   material/batch curves.

### Numeric family, edit, and right axis

1. Enable **Scientific dataset 2D - rectangle selection**. In its Series
   editor, choose `audit.longform`, X=`x_s`, Y=`response_V`, primary family
   `gain` with both values, secondary `material` restricted to Copper,
   filter `temperature_C=20`, and ordering `point_order`.
2. Click **Create family series** to make two gain rows. Select one row,
   change its filter value to `temperature_C=40`, edit its label, and click
   **Add/update one series**.
3. Add the `reference` Series from `audit.reference` on the right axis.
   The graph displays a separate `baseline_V` Y scale.

### Selected text values and category styles

1. Select primary family `material`, **Selected values** Copper and Steel,
   secondary `batch` with A and B, **Style category**, filter
   `temperature_C=40`, and ordering `point_order`.
2. Click **Create family series** to make four styled rows.
3. For another row, choose primary `material` with **Selected value** Copper,
   secondary `batch` with **Filter** B, filter `quality=review`, and ordering
   `point_order`. Click **Create family series**.

### 3D bindings

Enable **Scientific dataset 3D**. In the Analysis tab, bind the `primary`
source to `audit.longform` and choose `primary.x_s` for X,
`primary.temperature_C` for Y, `primary.response_V` for Z, and
`primary.material` for Family. Save and run to obtain a scatter graph grouped
by material. This path uses the Analysis bindings; it does not require the 2D
Series editor.

## Save, inspect, and export

Click **Save Config**, then **Run enabled analyses**. Open **Plots** and select
a graph to inspect its preview and render information. **Export...** saves
the selected graph outputs as PNG files in a directory you choose. **Session
Tools → Export Session to HTML...** creates a browser-readable export and ZIP.

Save the Session to retain Series rows, filters, labels, and category styles.
After reopening it, open the same graph's **Series...** window to inspect or
edit those settings, and rerun the analysis if a new render is needed.

The rectangle-selection graph has its own Series configuration. Region
Selection semantics are described separately from Series editing in the
[module README](README.md#region-selection-compatibility).

## Dataset selection, caching and shared graphics

Series Dataset selection is a dropdown of registered Session Datasets with their contract/count context; optional manual ID remains available for advanced entry. Family/secondary/filter variable choice lazily loads distinct values. Reopening unchanged choices uses a Session/source/schema cache; **Refresh values** explicitly rescans. Lists are bounded at 2,000 values; use typed predicates for high-cardinality data. Dataset content/schema changes and Session changes invalidate the applicable entries.

Tree refresh obtains provider columns in one batch. Add/update/remove/reorder commit the affected scientific/presentation entry through the existing public PlotSpec/Graph Series lifecycle. Rerender retains unchanged per-series preparation when its scientific identity, filters, alignment, auxiliary bindings and reduction requirements match. Title/label/legend/background changes use current presentation without rereading unchanged series. Compatible filtered same-Dataset series share one bounded stream while retaining exact independent filters and original source-row indexes. Budget/reduction or source/schema changes can require preparation again.

Use **Axes...** for `auto`/`xy_equal` 2-D aspect, the existing 3-D aspect modes and graph background (`inherit`, a hex color, or `transparent`). Transparent static PNGs retain requested dimensions and alpha through annotations, viewer, copy/save and export. **Notes...** opens independent graph Markdown. **Graph info...** includes Graph Metadata and note presence. Variant creation/duplication and Clones copy notes/metadata independently.

**Export Graph ZIP... / Import Graph ZIP...** transfer an individual scientific or rendered graph into a new Detached Clone; the import review explains dependency collisions and scientific/rendered-only modes. See the [resource guide](../../../docs/guides/PORTABLE_RESOURCE_EXPORT_IMPORT.md). Save Config and reopen the Session to verify persisted controls.

## Compact read-only Native3D preview

Plots ⟳ 3D opens the existing exact XYZ Variant in the shared read-only CORE host.
Arrows rotate; ■ restores the initial camera; Exit restores the original static PNG.
Tab returns retain the scene and frame. This ordinary preview creates no Viewer
Document or Dataset. Scientific axis ticks/layout and log/reversed axes have the
limits documented in PLOT_DATASET_3D_API_v1. The persistent Viewer commands stay explicit.


## Native3D preview controls and high-resolution export

`native3DPreviewAcquire` retains its existing shared DatasetViewer host/worker and
RAM frame. Plots' eligibility control is a placed canvas child, with no layout row;
`PLOT_DATASET_API_v3.previewCompatibility ref` gates supported prepared XYZ Variants.
No persistent Viewer Document is needed. Ordinary 2D/static double-click is unchanged.
The compact controls provide orbit left/right/up/down, native camera roll clockwise/
counterclockwise, exact reset, Exit and a presentation-only scientific axes/grid toggle.

`::GX::native3DPreviewEnlarge host` moves the shared consultation into a resizable
independent Tk window. It reuses the same prepared VTP/native objects/worker/camera.
Resize uses the existing native target/viewport APIs; no Dataset reload or Octave
preparation occurs. Closing returns the synchronized camera to the embedded host.
The frame remains cached across unchanged tabs. Source/Session guards and cancellation
remain authoritative. Destroying the original owner closes enlarged/export resources.

Only explicit Render & Publish in Save High-Resolution Image creates a Dataset.
Full HD (1920×1080) and 4K (3840×2160) use native offscreen rendering and the current
CORE graphics export-supersampling policy; intermediate pixel/GPU/worker budgets apply.
The PNG includes the current geometry, calibrated axes/grid when enabled, original
scalar-bar palette/limits/label when present, compatible title/legend and opaque
background. No Tk screenshot enlargement. Existing IDs are rejected; no replacement.
CORE `DATASET_FILE_PUBLICATION_API_v1` publishes `image.raster`, binary PNG/image/png
transactionally and verifies SHA-256. Structured metadata retains graph/Variant identity,
source IDs/digests/bindings, exact camera/projection, dimensions, figure calibration,
scalar palette/limits and graphics settings. The normal Dataset GUI lists/reopens it.

Calibrated axes use linear increasing displayed scientific ranges mapped to effective
aspect-scaled world bounds. Original units/labels and scalar mapping are retained.
The native cube axes follow projection, orbit and roll, with camera-calibrated label
margins. Flat source surfaces retain constant per-cell RGB on both triangles of each
original quad; interpolated source colors remain interpolated. No scientific smoothing.
Ticks/grid/font layout follows Native3D's scientific presentation rather than Octave's
pixel layout. Logarithmic/reversed axes still require a nonlinear calibrated coordinate
mapping contract and are rejected, never labeled as linear. Other providers/base graphs
need an exact prepared-scene identity API. Transparent figure backgrounds remain unsupported.
