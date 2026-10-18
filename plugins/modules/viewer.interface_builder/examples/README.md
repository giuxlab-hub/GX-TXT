# Complete synthetic interface examples

Open any .gxtxt-viewer in Viewer Interface Builder. These are full validated
public designs with stable IDs, presentation properties and API requirements.

- toolbar_inspector: existing command toolbar and synthetic inspector. Commands
  remain unconnected in ordinary Preview; no public general icon property exists.
- table_selection: read-only table plus synthetic inspector. Gallery mounts its
  deterministic rows; the ordinary saved design does not persist those rows.
- native2d_interaction: an ordinary native source slot plus inspector. Use Gallery
  Native2D / composite for the full RAM hit/drag/pan/zoom/reset interaction; the
  saved scientific slot starts empty in ordinary Preview. It has no fake Dataset.
- native3d_embedded: an actual independent v2 Native3D component with explicit
  demo=1; Preview and a generated installed Viewer render the same RAM cube.

To run each full synthetic composition directly through the same public owner:

    wish run_demo.tcl /absolute/path/to/gxtxt native2d_interaction

Use toolbar_inspector, table_selection or native3d_embedded as the final argument
for the other examples. This launcher composes in explicit demo context; sample
values remain transient. It is trusted example integration, not authored restricted
C++ code. Close the example to release its owned widgets/native workers. No Session,
Dataset, science Job or Workspace is created. For ordinary installable generation,
use File → Generate installable Viewer and the normal Plugin Manager. Only the
explicit Native3D demo property travels into its generated runtime declaration.
