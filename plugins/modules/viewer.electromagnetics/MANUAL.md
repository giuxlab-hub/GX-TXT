# Electromagnetics Studio

This retained implementation continues to open existing models. When the approved
compiled `viewer.electromagnetics_studio/electromagnetics_studio` presentation is
installed and enabled, the catalog presents that implementation once and the
original `em_models` Workspace owner dispatches to it. The scientific model
identity and `gxtxt.em_model` schema remain unchanged. The legacy launcher is
available when the compiled presentation is absent or disabled; its public API
and original source remain installed. This staged transition still requires
independent GUI acceptance before release.

## Start and runtime

Open a scientific Session, enable Electromagnetics Studio in the Plugin Manager if necessary, then open it from Viewers. The bundled Electromagnetic Simulation CORE supplies `ELECTROMAGNETIC_SIMULATION_API_v1`. Actual Gmsh and GetDP installations are required. Configuration → Backend Settings selects the main GX-TXT Configuration → Runtime page, where their executable configuration belongs. Solver paths are not part of the scientific model.

The Model, Materials, Excitation, Mesh, Solve, Results and Learning tabs retain separate scientific responsibilities. The menus are Model, Simulation, Results, Configuration and Help. The compact toolbar offers Open, Save, Validate, Run FEM, Cancel, Show field and Help. Help → User Manual… and F1 open the independently rendered common documentation window.

## Models and Workspaces

Model uses a stable scientific model ID, a planar physics choice, half domain width and full domain height in metres. The complete horizontal domain is twice its half width. Only linear planar static electrostatics and magnetostatics are supported. Full 3D, axisymmetric, nonlinear B–H, transient electromagnetics and arbitrary CAD are unavailable.

Model → Use Magnetic Physics or Use Electric Physics changes the current draft; it does not silently delete or replace a saved model. Materials and Excitation enable the controls relevant to that physics. Inactive values remain in the draft and do not enter its equations. Validation checks the actual typed model, SI units, radius/domain relationship and bounded mesh policy. Validation alone performs no FEM solve.

The shared Model Workspace commands create, open, save, duplicate, rename, inspect, export and import Session Workspaces. Save retains the model in its original Interactive Document identity. Duplicate creates a separate owned Workspace; source and previously published Datasets remain unchanged. Shared unsaved-change review protects switches and closing. Session changes invalidate an old window and its callbacks. Reopen the correct Session and Workspace to continue; a Job never transfers into another Session.

## Electrostatic laboratory

The homogeneous rectangle has potential 0 V on the left, the applied positive voltage on the right and natural insulating top/bottom boundaries. Relative permittivity is explicit and dimensionless. The solver uses `div(epsilon grad(V)) = 0` and `E = -grad(V)`, with `epsilon = epsilon0*eps_r`.

For these particular ideal boundaries the exact comparison is `V(x)=Vapplied*(x+half_width)/(2*half_width)`, `Ex=-Vapplied/(2*half_width)` and `Ey=0`. This comparison never substitutes for the real GetDP output. The model does not include finite-plate fringing or extract a physical three-dimensional capacitance.

## Magnetostatic laboratory

A round conductor carries uniform positive axial current density inside rectangular air. Enter radius in metres, current density in A/m² and conductor relative permeability as a dimensionless linear value. Exterior air has relative permeability 1. The outer rectangle imposes `Az=0`. GetDP solves the out-of-plane magnetic potential; `B=curl(A)` and `H=B/mu` describe the field.

For comparison, an unbounded uniform conductor with relative permeability 1 has `I=Jz*pi*a²`, `Btheta(r>=a)=mu0*I/(2*pi*r)` and `Btheta(r<a)=mu0*Jz*r/2`. The finite rectangle changes this ideal field, especially near its boundary. A planar result is not a finite device inductance or a terminal-based R/L/C model.

## Mesh, execution and diagnostics

Mesh size is a nominal maximum length in metres. Gmsh generates the actual oriented triangles; requested size is not a claim about exact node/cell count. The bounded native adapter accepts at most 30,000 triangles and requires adequate radius resolution. To study mesh dependence, solve separately at several sizes while keeping the physical geometry, material and observable fixed. The Viewer has no automatic mesh-sweep feature.

Run FEM first saves the model, then submits actual Gmsh and GetDP stages through the durable CORE Scientific Execution and Script Job authorities. Status distinguishes queued, running, completed, failed, cancelled and interrupted outcomes. Cancel requests termination of precisely the owned Job tree. There is no pause control because pause is not supported. Closing a window leaves Job ownership with CORE; open the saved Workspace to reconnect to its retained Job and log.

A successful process exit alone is insufficient. Native C++ verifies finite solver outputs against complete mesh topology, shared-node scalar consistency, the field/potential-gradient relation, actual GetDP residual output and an independently assembled free-node weak residual. Results show these values and their limitations. A growing or incomplete output is not an accepted immutable scientific Dataset. Missing tools, malformed results and numerical validation failures prevent publication; use the retained CORE Job log for diagnosis.

## Fields, samples and publication

Publish Verified Field creates two new canonical Datasets: the chosen cell-field ID and its linked node Dataset `<ID>_nodes`. Existing IDs are refused. The existing atomic Publication batch protects partial failures. Nodes retain their actual IDs and source coordinates. Cells retain element, region, material and ordered node identities. Metadata declares the role bindings, physics, Job identity, solver versions, units and scientific checks.

Potential is the average of the actual nodal scalar values on each triangle, explicitly associated with the cell centroid. The first-order vector field is constant on each triangle. Magnetic potential has unit Wb/m, magnetic flux density T and H A/m. Electric potential has unit V and electric field V/m. Coordinates are in metres; areas are in m². No cell value is relabelled as a nodal measurement.

Show exact cell field uses the public native `PLOT_DATASET_API_v4` exact-cell binding, complete nodes and original oriented connectivity. The color annotation states the actual scalar range and unit. There is no Delaunay replacement, smooth interpolation or invented connecting line. Click a triangle to inspect its true cell/source-row identity and scalar value. Wheel zoom, middle-button drag pan and double-click complete fit use the shared native viewport. Canonical data and units remain unchanged.

Show sample profile displays a separate native scatter chart of actual cell-centroid field magnitudes versus X, including all Y positions. It is a sample distribution, not an interpolated centerline profile or a continuous curve. Open CORE Dataset View provides ordinary canonical table/metadata consultation.

Publish charts to Plots explicitly creates independently identified native field and sample Graph Variants. Existing Plots presentation editing, rendering, scientific Clone and portable Graph operations retain their canonical source identities. A scientific field capture includes both complete cell and node Dataset resources. Export field uses the public native Plot export owner for PNG, SVG or PDF. A missing or invalid cell binding produces an error; it never silently changes into a centroid scatter plot.

## Troubleshooting and limits

If a solver is unavailable, configure its installed executable through Configuration → Runtime. If a model is invalid, correct its physical values rather than bypassing validation. If publication collides, choose a new ID. If a source or Workspace changed, review the new revision and submit another Job; a historical result is not silently rebound. If a retained field resource is unavailable, preserve its scientific identity and restore its canonical source before rendering.

Mesh refinement may be nonmonotonic for a particular local field integral. Report the real values, finite-boundary approximation and mesh current/geometry error. An Ampere-loop check evaluates the actual piecewise-constant FEM field inside each source triangle; it does not turn that field into an interpolated measurement. Learning explains these assumptions and the two laboratory equations. No circuit extraction, automatic uncertainty, nonlinear material certification or unsupported numerical accuracy is implied.

The GetDP absolute residual is a norm of its assembled, possibly scaled linear system. The independently assembled relative weak residual is dimensionless. Neither residual is a physical uncertainty or a stand-alone estimate of field accuracy; use explicit physical references and mesh dependence for that assessment.

For registered programmatic operations, see the [Electromagnetic Simulation API](../../../docs/api/ELECTROMAGNETIC_SIMULATION_API_v1.md) and [Plot Dataset API v4](../../../docs/api/PLOT_DATASET_API_v4.md). These are the actual public owners used by the Studio; scripts use the existing Python/Octave bridge.
