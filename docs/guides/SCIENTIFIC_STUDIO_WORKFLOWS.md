# Scientific Studio workflows

Scientific inputs, results and editable Workspaces have separate identities.
Keep canonical Dataset and Variable IDs when choosing data. A display sample,
viewport, raster texture or successful process exit does not replace a scientific
source or establish its uncertainty.

## Managed execution and source access

Registered providers expose typed parameters through the
[Scientific Execution API](../api/SCIENTIFIC_EXECUTION_API_v1.md). The existing
Script Jobs service owns admission, process accounting, cancellation, logs and
recovery. Closing a Viewer detaches its presentation. Reopen its Workspace and
reconnect to the existing Job instead of submitting an unintended duplicate.

Live outputs are provisional. Observe their current generation before reading
complete bounded records; after truncation, replacement or a schema change,
observe again. Explicit result import validates scientific contents and creates
a canonical result. Freezing a completed output retains an immutable managed
resource without changing the source.

The [Scientific I/O API](../api/SCIENTIFIC_IO_API_v1.md) uses administrator- or
user-authorized scopes. Metadata browsing does not grant content access. Import
can make an immutable copy or retain a verified read-only external reference.
An offline or changed external source remains identifiable and explicitly
unavailable. Shared input namespace grants permit authorized creation only;
they do not permit replacement or deletion of another producer's data.

## Electromagnetics

Open Electromagnetics Studio through the Viewer catalog. Configure Gmsh and
GetDP in Runtime settings, choose electrostatics or magnetostatics, and enter
the model's actual physical quantities. Run submits the registered provider;
status and Cancel act on that managed Job. Save retains the editable model.

After a completed run, **Publish Verified Field** creates linked canonical node
and triangular-cell Datasets. Running a solver alone does not publish them. Nodal potential and
cell-associated fields are different quantities. The native field chart uses
the exact published connectivity and cell identity. Publish field/profile
Graphs explicitly when a retained canonical Graph is wanted. The sample profile
is cell-centroid scalar versus X across all Y, presented as scatter; it is not an
interpolated line cut. Mesh residuals,
finite-domain approximations and convergence measures are not physical
measurement uncertainties. The supported physics is linear planar static 2D.
Read the [domain contract](../api/ELECTROMAGNETIC_SIMULATION_API_v1.md).

## Fitting and mathematical expressions

The [Fitter manual](../../plugins/modules/viewer.dataset_curve_fit/MANUAL.md)
describes its actual model and result controls. Click a sidebar heading to
collapse it; use Configuration to show optional panels. User defaults and
Session overrides remain independent. Hiding a panel preserves its scientific
settings. Help → User Manual and F1 open an independent rendered manual with
links to the actual Numeric and statistical interpretation references.

The optional Mathematics Explorer uses the shared
[bounded expression operations](../api/NUMERIC_EXPRESSION_OPERATIONS.md).
Declare physical input/output units, domains and tolerances. Root, intersection
and extremum searches report finite numerical evidence, not a proof that every
solution has been found. Unit changes convert values and refit the corresponding
viewport. Publish Dataset/Graph is an explicit operation.

Replicate Curve Analysis is a protected bundled, selectable, default-off
Analysis. Its supplied legacy workflow remains available. The separately
requested independent scientific-service implementation has not been supplied;
its integration remains **PENDING USER SOURCE**. No replacement statistical
results or new independent callable engine are implied by CORE classification.

## Native image composition and geometry

The shared [raster composition API](../api/NATIVE2D_RASTER_COMPOSITION.md)
retains rectangular/polygon ROIs in original source-pixel coordinates. Native2D
owns transforms, layers, visibility, locks and opacity. ImageMagick performs
registered bounded effects/composites through managed Jobs. A processing mask
and a mask used as opacity have different meanings. Retain the managed output
receipt, source SHA and raster mapping with the Document.

Native3D can use a managed transparent image as decorative appearance without
turning pixels into geometry or changing scientific optical material properties.
A separate closed, unit-correct retained profile can be returned to its original
3D Workspace and extruded through the existing geometry service. Save the
Workspace and export actual supported geometry through managed STL/STEP paths.
Read the provider manuals for the texture and planar-return controls.

The [CAM foundation](../design/CREATIVE_CAM_FOUNDATION.md) is a design document.
It defines future owners and physical-unit boundaries; it supplies no toolpaths,
postprocessor, G-code or machine operation.
