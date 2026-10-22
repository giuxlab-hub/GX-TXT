# LEGACY / DEPRECATED — historical 3D Viewer

This module (`viewer.native_3d`, backend `gx3d_native_host`) is retained for historical compatibility and selected legacy uses. **Do not use it for new development.** Use `viewer.engine_3d` (`gx3de_viewer`) and the modern public CORE Native3D (`libgx3de`) APIs. Its stable module ID, public contracts and behavior remain available. The modern CORE Native3D engine is not deprecated.

# Native 3D Viewer

On Linux and other non-Windows systems, Native 3D first tries normal rendering.
If the renderer fails during OpenGL or GLX initialization, GX-TXT retries once
with Mesa llvmpipe and reports the active software mode in the Viewer status.
For an explicit software launch, use
`GXTXT_NATIVE3D_SOFTWARE=1 tclsh gxtxt_pipeline.tcl`. This setting affects only
the renderer child. The server needs Mesa llvmpipe and an available X display;
an NVIDIA or AMD GPU is not required for the software path.

This general-purpose viewer renders imported STL and OBJ triangle meshes,
STEP CAD models, VTU geometry, VTP point/line/surface scenes and VTI scalar
grid isosurfaces. It does not edit source data.

Import geometry with **Geometry 3D Acquisition** first. Open the Session,
select **Native 3D Viewer** in Viewers, choose a compatible Session Dataset
from its panel and render it. The viewer opens without a file chooser. Plot
Dataset 3D scenes use the same renderer after Plot Dataset prepares the
scientific scene. Camera, clipping, visibility and opacity are Session
presentation state. Source Dataset and artifact hashes are checked on reopen;
a changed or missing source produces an explicit error.

Choose **Plot Dataset 3D graph** in the Source type selector to list
compatible persistent Plot Dataset graph/Variant identities. **Create
interactive view** creates an independent Viewer representation; a graph may
have more than one view. The panel shows Source, Variant and Status. A changed
graph reports **OUT OF SYNC** while the current view remains unchanged. Use
**Sync** to rebuild the scientific scene explicitly; the viewer preserves
valid camera, projection, clipping, background, lighting and compatible layer
presentation. A deleted graph reports **SOURCE MISSING** and leaves the
existing representation saved. Graph output filenames are never source
identity. Normal modules use `PLOT_DATASET_API_v3` and Viewer Provider API v1
for this workflow.
For a VTI scalar grid, enter its scalar array name and semicolon-separated
isovalues before rendering. A VTP scalar array is optional.

The explicit external-file control below is retained for compatibility with
older Sessions. It is not the normal import workflow.

Open a Session, then select **Native 3D Viewer** in Viewers. Choose a model and
whether to keep an external reference or copy the original into the Session.
Reference mode stores a hash-verified path hint and avoids duplicating a large
source. Portable mode makes an explicit copy in Session resources. After moving
a reference-only Session to another computer, locate the original model again;
the viewer verifies its SHA-256 hash before use.

To overlay a scientific VTU result, first store the `.vtu` file in the open
Session, open a 3D model, then choose **Add Session VTU...** in the Native 3D
control panel. Enter a one-component scalar array name for surface colors and
an optional three-component point vector array name for sampled arrows. The
file, selected array names and layer visibility are saved with the Session;
the original VTU is hash-checked on reopen. Select a layer in the panel to
show, hide, change its opacity or remove it. A VTU result outside the Session must be explicitly
imported or copied into Session resources first.

For a canonical CSV Dataset, choose **Add Dataset points...**, then select
stable variable IDs for X, Y and Z. An optional scalar variable colors the
points; three optional vector component variables add sampled arrows. Rows
without valid numeric values in the selected columns are skipped. The Dataset
identity, variable IDs and a source hash are saved in the Session, so reopening
requires the same canonical Dataset content. Dataset points can be shown,
hidden, made translucent or removed independently of a VTU layer.

Use the mouse to rotate, pan and zoom. Arrow keys in the model window or the
control-panel arrow buttons orbit the camera. **Fit** resets the framing. Camera
presets show front, back, left, right, top and bottom views. Choose perspective
or orthographic projection, surface, wireframe or surface-with-edges display,
set model opacity or a clipping plane, choose a background color, toggle model
lighting, and show or hide it with **Visible**. These appearance choices are
saved with the Session viewer state. The status panel reports the picked
cell when selection succeeds. **Save view PNG** captures the current model
window for a lab note or report.

Auto, Preview, Low, Medium, High and Full are display quality levels. Auto
chooses a level within the configured presentation triangle and display-memory budgets. The viewer
temporarily uses a low level during interaction. Large models may take longer
to preprocess; progress and Cancel remain available. Display caches live in
the configured user cache directory and can be rebuilt from the original.
Incomplete work is not used as a warm cache. A first preview can open while
higher display levels are prepared. Configuration exposes the preprocessing
memory budget, presentation triangle budget and display-memory budget. An
explicit quality level over the display-memory budget is rejected before
the native renderer loads its geometry.

For binary STL and sufficiently large indexed OBJ files, the worker scans a
bounded sample and opens a first preview before the full VTK mesh import. The
sample is temporary display geometry; the original file remains authoritative.
OBJ files with unsupported face indexing fall back to the full importer for
their first preview. ASCII STL and STEP use their respective import paths. A
cancelled job cannot publish a complete display cache.
Malformed OBJ references are rejected before VTK import with an explicit
error; incomplete or invalid source files do not become valid display caches.
For disconnected or thin geometry, simplified levels are checked against the
source bounds. A level that loses the source envelope is rebuilt using a
coarser source-point representation; select Full for detailed inspection of
small features and openings.

Very large or complex STEP assemblies can require substantial tessellation
time and memory. The STEP importer records XDE assembly names and occurrence
metadata. Repeated parts share prototype display geometry and use saved
placements in the native renderer. The control panel lists STEP part
prototypes and lets you show or hide one part independently; those choices
are saved with the Session. Source STEP/B-Rep remains intact.
For large assemblies the progress panel distinguishes file reading, XDE
transfer, assembly inspection and tessellation. The Linux OCCT 7.8.1 worker
caches repeated shared-part lookups during transfer. It still reads the full
STEP model and publishes the first complete assembly preview after transfer;
the preview is not a partial scientific model. Reopening a valid display cache
avoids translation. The worker uses serial OCCT meshing and does not start
additional computation workers outside the configured framework policy.

For a mesh model at Full quality, click a source cell and choose **Pattern
selected cell...**. Set a patch radius and a linear, rectangular or circular
placement layout. Linear uses one row; rectangular uses rows and columns;
circular uses a ring count, positions per ring, radial spacing and angle step
in degrees. Explicit placement accepts a `.csv` already inside the Session
with header `x,y,z` and one finite coordinate triplet per row. The file hash
is checked when the Session reopens. The viewer extracts a bounded patch around the selected displayed
cell and renders it once at each placement through a shared glyph source. The
pattern is a display layer: it does not remove or rewrite source geometry.
The selected Full-quality display cell and source model hash remain in the
Session document. Pattern layers can be hidden, made translucent or removed.
An over-budget or invalid patch is rejected without saving it in the Session.

For a mesh with disconnected repeated components, select a cell at Full
quality and choose **Find matches for selected cell**. The viewer highlights
components whose triangle geometry matches the representative under an
axis-aligned proper rotation and translation. Review the proposal, then
**Accept matches** or **Reject** it. Acceptance renders one representative
component with saved transforms and preserves any unmatched model geometry.
The chosen source cell and accepted representation remain in the Session;
the repeat prototype and transforms are derived, integrity-checked cache
data and can be rebuilt. The original source mesh is never modified. This
bounded matching mode currently checks the 24 proper orthogonal axis
orientations, so components at arbitrary other angles are not proposed.

GX-TXT code is GPL-3.0-or-later. This component uses VTK (BSD-3-Clause), Open
CASCADE Technology (LGPL-2.1 with OCCT exception), OpenSSL (Apache-2.0) and
system graphics libraries. The exact binary dependency and license notices
belong with each platform package.

Debian package 0.9.6 uses the library next to the installed module. Rebuilds must use CMake install output, which applies `$ORIGIN/../lib`; do not package a build-tree host. See `docs/legal/DEBIAN_NATIVE_REBUILD_dev097.md` in the framework. The `Native3DHost` CMake install component permits packaging a changed host alone while retaining the compatible existing worker and library.

In dev109 the dedicated native window follows its application's lifetime. Normal
root closure sends the existing QUIT command and briefly drains its response.
The host also exits when its owning command pipe reaches EOF, including loss of
the parent process. Closing an idle interactive scene is independent of cancelling
a preprocessing worker. The user-reproduced orphan-window failure is preserved;
corrected installed GUI closure acceptance remains pending its recorded test.
