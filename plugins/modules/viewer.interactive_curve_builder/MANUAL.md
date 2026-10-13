# Interactive Curve Builder

Open the viewer from the Viewers tab or from a compatible Dataset. Choose X and Y for a 2-D curve, or choose X, Y, Z and a monotonic t for a 3-D parametric curve. In 3-D, **arc_length** constructs a cumulative path parameter in the common X/Y/Z unit. Family and Member have independent Variable, exact value and enabled controls. Both enabled filters combine with AND; empty text is a valid enabled value. Discovery is bounded: an incomplete value list asks for an exact value. Add further source Datasets as needed.

Select the whole curve, a numeric range, or highlighted individual rows in the source table. Selections are combined. **Clear selection** keeps source rows; **Restart sources** removes them. Preview calls the public NUMERIC_API. In 2-D it displays an unpublished overlay through the Plot Dataset transient-series API; in 3-D it displays an unpublished parametric line through the Plot Dataset transient-curve API. Nearest, linear, cubic, spline and PCHIP are interpolants. Line and polynomial degree N are fits; RMSE appears with the preview. Target sampling includes the source nodes plus uniform samples so an interpolant's passing through selected points remains visible.

The existing middle action row contains **Options** and **Workspace**. Options
offers Full Dataset or Selected Subset as an independent source-graph choice.
Changing it keeps selected fitting rows and any reviewed order. Full graphs use
separate observed Family/Member curves through CORE grouping. Selected graphs
use the exact original row identities; continuity breaks avoid drawing across
unselected source rows. Display scope never changes the derived numerical result.
The same scope applies to the checked post-publication Plot Dataset overlay.
Its caption reports the exact fit-row count independently of the visible context.
Legends retain both identity values, abbreviate long UUIDs, and mark each training
group with its used-row count. Full identities remain in the standard series
filters and published provenance.

**Auto-order points (non-temporal)** is OFF at factory defaults. OFF preserves
dev095 method ordering exactly, including the established 2-D X sort. Turning
it ON requires reviewing the original and proposed sequence before Preview.
Functional mode proposes stable X ordering (t for non-temporal 3-D parameters).
Arc-length mode proposes a geometric path through unchanged points in common
physical units. For a planar contour this samples X and Y separately through
the same Numerical methods. Ambiguous neighbors, crossings and disconnected
segments are reported; a candidate is not proof of physical connectivity.
An explicitly repeated closing endpoint stays last, retaining its original row
identity. Open paths are not automatically closed, and ambiguous interior links
still require review.
Ordering proposals support 2–4096 finite points. Larger inputs remain available
with automatic ordering OFF; an oversized proposal reports the limit without
changing or decimating the selected scientific rows.
Temporal variables/contracts disable automatic ordering. Use the existing
Dataset Curve Fit for broader parametric models or incompatible coordinate units.

Configuration uses the same typed module fields as central Configuration →
Modules, with explicit User/Session scope. A saved ON default is displayed as
an explicit preference and still requires review for each new candidate.
Workspace optionally saves settings and exact source lineage through CORE.
New/Open/Save/Rename/Duplicate/Manager/Close remain in the middle-row menu.
Ordinary launch creates no Workspace. Reopen rejects changed source bytes or
scientific schema. Builder has no History, Undo/Redo or Recipe strip.

**Publish as Dataset** writes a normal canonical table through Dataset Publication API v2. The Dataset registry and structured metadata retain source Dataset IDs, source variable IDs, exact source row ordinals, method, degree, parameter mode, target coordinates and units. The result survives Session save/reopen. The optional Plot Dataset overlay opens the standard Plot Dataset editor for 2-D curves after publication. For 3-D curves it opens the standard Plot Dataset `line3` graph and Native 3D interactive representation. No private plotting engine is used.


Source traces preserve exact measured row adjacency and genuine nonfinite gaps.
Full Dataset context is therefore not display-decimated and uses memory
proportional to its finite source rows. Selected Subset limits the drawn context
independently of the selected fitting input.
