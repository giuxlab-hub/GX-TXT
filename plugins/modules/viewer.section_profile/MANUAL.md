# 3D Section / Profile Viewer

Open a 3-D Dataset from **Viewers → 3D Section / Profile Viewer**. A source Dataset may be a canonical table with numeric X/Y/Z variables, a Session-owned mesh/surface, or a VTI scalar grid. The viewer opens the same source in Native 3D for spatial context. Its working plane uses public NUMERIC geometry operations.

Choose **XY**, **XZ**, **YZ**, **Arbitrary**, **Three points**, **Best fit**, either curve-derived plane, **Surface tangent**, or **Dataset plane**. For point-derived planes, select source rows in the point table. The curve modes have distinct meanings: **curve normal** takes the local tangent as the plane normal; **curve tangent + roll** keeps the tangent in the plane and rotates its transverse orientation. Arbitrary plane accepts a point and normal as three comma-separated numbers. Red X, green Y and blue Z controls move the plane origin along world axes; azimuth, elevation and roll sliders orient it immediately, with roll changing the in-plane U direction. Their numeric entries apply on Return or focus change. Offset moves along the current plane normal. **Flip normal**, **Center on selection**, **Reset**, and **Use Dataset plane** act on the current frame.

**Open in Native 3D** shows the visible working plane and local axes on the source. Move and orient the plane there with the mouse; the Section/Profile origin and normal update through Native 3D's public interaction events. Mouse picks appear in the **Native 3D mouse picks** list. Select three picks for **Three points**, at least three for **Best fit**, or one pick with a reliable surface normal for **Surface tangent**. For a trajectory, one mouse pick resolves to the nearest canonical source row before either curve-derived plane is calculated. **Clear picks** restarts selection. A zero or unavailable picked normal cannot define a surface tangent plane.

Choose an operation explicitly:

- **Intersection** cuts meshes/surfaces with the plane. It never projects a mesh as a fallback. For a VTI scalar grid, this is a true 2-D scalar slice with a scalar column and `section.output_kind=scalar_field_2d` metadata.
- **Slab projection** selects table points whose signed distance to the plane is within the entered half-thickness, then projects those source points. Source-row IDs are retained.
- **Trajectory intersection** returns exact segment/plane crossing points and row-pair provenance from the public geometry API.
- **Trajectory projection** projects the ordered trajectory explicitly.

**Extract / Preview** shows U/V points in the viewer. **Publish as 2-D Dataset** writes a canonical `table.generic` Dataset through Dataset Publication API v2. It contains U, V, source X/Y/Z, source row, segment ID and, for a scalar slice, scalar values. Dataset metadata records the source identity and SHA-256, plane definition, full O/N/U/V frame, manipulation values, operation and slab tolerance. The result is available to Plot Dataset and the Interactive Curve Builder after publication and survives Session save/reopen.

The source's already-recorded plane can be selected with **Dataset plane** when `section.origin` and `section.normal` metadata are present. A source with no such metadata reports that explicitly. Empty intersections report an error instead of changing operation semantics.
