# Electromagnetics Studio

Electromagnetics Studio models linear static planar 2D electrostatics and magnetostatics using the existing native Electromagnetic Simulation service, real Gmsh/GetDP tools and managed CORE Jobs. Open a scientific Session, then open the Studio from Simulation & Modeling.

For the source-only teaching exercise, choose New Session → Generate Session, then Workbench Source Practice → Electromagnetics → Planar Electromagnetics Practice. If the library is absent, use Manage Libraries → Import Library to import the published Workbench Source Practice library (org.giuxlab.gxtxt.workbench_validation 1.0.0; generator planar_em_practice 1.0.0). The generated parameters and references are source material, not a saved scientific model, mesh, Job or field. Enter the supplied values through Model, Materials, Excitation and Mesh, then use Validate, Save, Run FEM, Inspect results and Publish field normally.

## Orientation

The left sidebar has seven vertical tabs: Model, Materials, Excitation, Mesh, Solve, Results and Learning. The main area has Exact cell field, Dataset table, Planar field (3D) and Centroid samples views. The initial sidebar width leaves room for the complete model action labels; drag the normal pane sash to adjust the balance between controls and plots.

At narrow widths and large fonts, including font size 24, the four result pages use a compact native selector when their headers do not fit. Open its popup to read all four full titles. Choose a page with the pointer, or open the popup and press Ctrl+Home, then Enter, to return to Exact cell field. The six toolbar captions wrap onto additional rows and keep their commands and enabled states. Widen the window to restore the native page headers; narrowing it again retains the selected page and source. Selecting a result page does not submit a Job.

Use ordinary scrolling inside the field view to read the complete source explanation, then scroll back to the field. Use native wheel zoom and double-click Fit to navigate the field; Fit restores the original axes. These presentation actions preserve the retained canonical source.

The toolbar provides Validate, Open, Save, Run FEM, Cancel and Show field. Model, Simulation, Results and Configuration menus reuse the same actions. Help and F1 open this manual through the common Documentation Browser. Read the actual status, selected model and selected Job before an operation; an enabled control is not a scientific accuracy certificate.

## Configure the actual tools

Choose Configuration → Runtime settings, or Runtime settings in Model, to open GX-TXT's existing Configuration Runtime page. Select the actual Gmsh and GetDP executable configurations and use their normal Detect/Test facilities. Executable paths belong to Runtime configuration and are not scientific model parameters. The result provenance retains the actual solver versions.

Missing or incompatible tools must be corrected there. Do not substitute an analytic reference, a screenshot or a successful interface action for an actual FEM computation.

## Create, validate and save a scientific model

Refresh models lists original saved scientific models. New electric and New magnetic obtain normalized unsaved drafts from the original scientific service. Open loads the selected model; it does not silently choose a model from a Dataset.

Model contains a stable model ID, physics choice, half domain width and full domain height. Geometry is in metres; full horizontal width is twice the half width. Enter finite numeric SI values, for example 0.001 for one millimetre. A physical-unit word in a numeric entry is not a unit-conversion request.

Materials contains relative permittivity and conductor relative permeability; both relative values are dimensionless. The electric rectangle is homogeneous. Magnetic exterior air has relative permeability one. Excitation contains applied right-boundary potential in V, conductor radius in m and axial current density in A/m². The shared host disables parameters irrelevant to the selected physics while retaining their draft values. Model editing is disabled during its active owned Job. Ordinary numeric display retains binary-double precision without expanded formatting tails.

Mesh size is a nominal maximum length in m, not an exact element count. The native service validates geometry, material/source values, radius resolution and the bounded mesh policy. Validate performs those checks without solving. Correct an invalid draft rather than bypassing validation. Save retains the scientific model through its original Workspace owner.

## Scientific models and interface Workspaces

A scientific model and a saved interface Workspace are distinct records. The original model provider owns the scientific model and its resources. The interface retains controls, selection, presentation and the association with that scientific record.

The Model Workspaces action opens the common model Workspace manager. Its normal New/Open/Save, Duplicate, Rename, notes and resource-preserving import/export actions use the original owners. Duplicate creates a separate owned model while preserving the source; it does not clone a completed Job. Rename changes a Workspace name without replacing its scientific identity.

The shared interface Workspace and History controls preserve their own state. Use the normal Save/Discard/Cancel review when switching or closing. Session and source guards reject stale or foreign records. A stored interface with a changed executable source must not be silently reinterpreted; preserve the original and use the ordinary supported review/compatible-open route. A presentation-only revision is admitted only where the actual CORE contract supports it.

After reopening the correct model, List Jobs and Reconnect recover an actual retained Job. Reconnect does not run another solve. Closing a Viewer leaves durable Job supervision with CORE; a Job never transfers to another Session.

## Run, monitor and cancel

Run FEM saves the model and submits the real Gmsh→GetDP pipeline. There is no separate mesh-only Job or automatic mesh sweep. Solve provides actual retained Job choices, durable status and the bounded native log. Status reads the selected Job; Read log obtains its retained log. Inspect results reads verified result descriptions and bounded actual cell rows in Results.

Open and Reconnect require actual selections. Cancel requires an active owned Job. Results/publication require a completed source-current Job. Field, profile and planar 3D actions require a qualified selected field. These availability rules are shared by menus and buttons, and every operation still validates its scientific contract.

Cancel requests termination of the owned managed pipeline. Verify the actual terminal state: a short solve can finish before cancellation takes effect. A cancellation request alone is not a CANCELLED result. A cancelled, failed, running or stale Job cannot be presented as a verified publishable field. No pause capability is claimed.

## Electric laboratory and its reference

The homogeneous rectangle has left potential 0 V, right applied potential and natural insulating top/bottom boundaries. The equations are div(epsilon grad(V))=0 and E=−grad(V), with epsilon=epsilon0*epsilon_r.

For these particular ideal boundaries:

- V(x)=Vapplied*(x+half_width)/(2*half_width)
- Ex=−Vapplied/(2*half_width), Ey=0

Compare the actual solver output with that reference, including sign and units. Potential is in V; electric field is in V/m. This model does not describe finite-plate fringing or establish a three-dimensional device capacitance.

## Magnetic laboratory and its reference

A round conductor carries uniform positive axial current density inside finite rectangular air, with outer boundary Az=0. GetDP solves the out-of-plane potential; B=curl(A) and H=B/mu describe the field.

For relative permeability one and an unbounded surrounding domain:

- I=Jz*pi*a²
- Btheta(r>=a)=mu0*I/(2*pi*r)
- Btheta(r<a)=mu0*Jz*r/2

The actual finite rectangular boundary changes this reference, especially near its boundary. Compare signed tangential observables and the actual mesh current with the qualified reference; do not claim exact infinite-domain agreement. Magnetic potential has unit Wb/m, B has unit T and H has unit A/m. This is not a finite-device terminal inductance model.

## Numerical evidence and mesh dependence

A successful process exit or a colorbar alone is insufficient. The original native service checks complete oriented triangle topology, finite output, shared nodal potential consistency, the field/potential-gradient relation, actual GetDP residual output and an independently assembled free-node weak residual.

The GetDP absolute residual is a norm of its possibly scaled assembled linear system; the independently assembled relative weak residual is dimensionless. Neither is physical uncertainty or a stand-alone field-accuracy estimate.

For a mesh study retain geometry, material, excitation and observable, then perform separate actual runs at explicitly different mesh sizes. Preserve each model/Job/result identity. Compare observed errors and discretization effects without assuming monotonic improvement. Report finite-boundary and conductor/mesh-current qualifications for the magnetic case. The current bounded service accepts at most 30,000 triangles and 60,000 nodes.

## Publish and inspect canonical fields

In Results choose a new field Dataset ID, then Publish field from a completed source-current Job. Publication explicitly creates the canonical cell Dataset and its linked node Dataset. Existing identities are refused rather than overwritten.

Nodes retain actual node IDs, coordinates and solved nodal potential. Cells retain element, region/material and ordered node IDs. Cell potential is the triangle average of its actual nodal values; the first-order vector field is constant on each original triangle. Coordinates are m and areas m². A cell-centroid value is not a nodal measurement.

The Dataset selector permits canonical compatible tables. Inspect Dataset table uses existing read-only paging, actual schema/units and source identities. Inspecting an arbitrary table does not certify FEM data. Node-only or unrelated tables cannot stand in for a qualified linked cell field.

## Exact field, samples and planar 3D

Select a qualified canonical field and use Show field. The exact Plot Dataset v4 view uses original coordinates and triangle connectivity, with constant colors per source cell. It does not create a Delaunay mesh from centroids or invent a smooth nodal field. The graph title and explanatory note describe this representation without claiming that the current frame is unbound. Use native wheel zoom, middle-button pan and double-click Fit. Actual picking retains source-cell/source-row identity and the real scalar value/unit.

Consult the actual physical source range and units, not colors alone. A nearly uniform field can use an expanded display range for legibility; this does not alter the source values or turn roundoff into a physical variation.

Show centroid samples uses the original Plot v4 adapter to plot actual stored cell-centroid X and scalar at all Y locations. Select Centroid samples to inspect the scatter. This is not a centerline extraction, interpolated field, continuous spatial curve or new calculation.

Show planar field in 3D presents those same canonical triangles in the XY model plane at Z=0 through the shared native scientific owners. X/Y remain compatible physical lengths and scalar amplitude retains its own unit and cell association. Potential or field magnitude is not a geometric Z coordinate. No thickness, CAD volume or 3D FEM solution is implied. Use the viewport's navigation modes and Fit Scene controls; source pick receipts must retain actual canonical IDs as well as renderer ordinals.

The native 3D field is a derived presentation. After interface reopen, select its preserved canonical Dataset and use Show planar field in 3D again. Automatic native camera restoration is not promised by the current public contract. Missing/incompatible precompiled adapters fail explicitly; there is no runtime compilation fallback.

## Plots and native export

Publish charts to Plots explicitly retains two independent source-bound Plots: the exact node/cell field and the actual centroid-sample scatter. Their source and Plot identities remain with CORE. Repeated publication uses the installed producer's stable identity; it does not run another FEM solve.

Export exact field… requires the selected field already displayed in its declared exact Plot. Use the ordinary Save dialog to export native PNG, SVG or PDF through the existing File Publication owner. Review the destination and normal overwrite confirmation. Cancel creates no export. Missing, stale or mismatched bindings must fail before publication. Export-dialog Cancel is distinct from cancelling a running scientific Job.

## Troubleshooting and limits

For invalid geometry/material/source/mesh values, correct the typed model and Validate again. For unavailable solvers use Configuration Runtime and the native log. For a publication collision choose a new ID. For a changed model or Session, review the original source identity and reconnect/reopen through the normal owner; do not relabel a historical result as current. Preserve failed evidence rather than replacing it with a color image or a new solve.

Full 3D physics, axisymmetric formulations, nonlinear B–H, transient EM, arbitrary CAD, terminal L/R/C and SPICE extraction are unavailable. Supported scope remains bounded linear static planar 2D.

Programmatic scientific contracts are documented in [Electromagnetic Simulation API](../../../../docs/api/ELECTROMAGNETIC_SIMULATION_API_v1.md), [Plot Dataset v4](../../../../docs/api/PLOT_DATASET_API_v4.md) and [Native3D GUI Host v2](../../../../docs/api/NATIVE_3D_GUI_HOST_API_v2.md).
