# Electromagnetics Studio Viewer API v1

SPDX-License-Identifier: GPL-3.0-or-later

Module `viewer.electromagnetics` declares version1 in
`api/electromagnetics_studio_api_v1.tcl`, namespace
`::GX::ElectromagneticsStudio`, Viewer ID electromagnetics, backend
electromagnetics_studio_tk. The module is an editing/presentation client of
[Electromagnetic Simulation](ELECTROMAGNETIC_SIMULATION_API_v1.md); physical
model validation, actual solver, durable Job and publication belong to that
existing public provider and CORE.

## Exact public activation entries

| Signature | Arguments/defaults | Result |
|---|---|---|
| `::GX::ElectromagneticsStudio::open ?context?` | Tcl dict default `{}` | dict `{state opened window .gxtxt_electromagnetics_studio}`; opens/raises native Studio and applies supported Workspace context |
| `::GX::ElectromagneticsStudio::viewerDispatch action scene` | required backend action and resolved scene | open uses scene.open_context; rerender calls open with default context; other actions error |

Use the normal trusted-host route:

```tcl
set receipt [::GX::viewerOpen viewer.electromagnetics electromagnetics]
```

This returns the adapter's dict, **not a bare Tk path or a FEM result**.
Ordinary dispatch checks installed provider/presentation policy. The GUI requires
Tk/current Session token and activates the public EM and Plot v4 owners. It
initializes a magnetic draft, never an analytic stand-in for solver output.

Supported context key `workspace_id` accepts an existing EM model Workspace ID,
loaded through the real owner, or `new`. The `new` path additionally requires
`workspace_name` and immediately calls the existing model Save owner. It is not
promised as an uncommitted blank draft. On an already open Studio, the current
model/Document is retained by the window constructor before that Save call;
this adapter alone does not guarantee a fresh identity for `new` in that case.
Use the established Workspace host transition rather than assume replacement.
Existing-ID context restores the model,
authoritative Workspace name and saved model, then reconnects an actual matching
managed Job. No Dataset/path/source selector key is declared. A previously open
window with a different current Session token is closed before recreation;
missing/unavailable current Session token remains an error. GUI callbacks guard
their captured Session before modifying state.

## Scientific workflow boundaries

The native workflow collects kind/model_id/formulation/half_width_m/height_m/
mesh_size_m/radius_m/current_density_A_m2/mu_r/voltage_V/eps_r, using the actual
provider defaults/normalization. Lengths are meters, current density A/m²,
potential volts, and relative material properties dimensionless. Supported kinds
are linear planar static electrostatic_2d and magnetostatic_2d; formulation is
planar_2d. Model Validate is not a mesh or solve. Run saves the model and submits
the actual managed Gmsh/GetDP provider; closing the GUI does not create a new
supervisor or imply cancellation/completion of that Job.

The magnetic case is an axial current disk in a **finite rectangular** air
domain with Az=0 on the outer boundary. The electric case is a homogeneous
rectangular dielectric with prescribed left/right voltage and insulating
top/bottom. Neither establishes a general3D component model, fringing plate
capacitor, inductance/capacitance extraction, nonlinear material, transient
solver or SPICE generation. Physical reference/residual/mesh validation and
resource bounds remain the actual EM provider's documented checks. A residual
norm is not physical uncertainty or a universal field-accuracy claim.

Publication explicitly requires an actual completed/current Job through the
same provider and produces create-only canonical cell/node data. A preview row
at a cell centroid is not nodal potential. Field presentation uses Plot v4 exact
cell binding with linked source nodes, triangle connectivity and constant cell
values; it does not interpolate a scalar field for acceptance. Sample profile
uses actual cell-centroid values across allY, not an invented fixed-Y line.
Separate chart publication and figure export use normal Plot/Session owners.

The underscore-prefixed GUI callbacks are not new public solver/Script methods.
For programmatic work use the actual EM/Scientific Execution/Workspace APIs.
This family declares no separate per-GUI-action argument/result/unit/error
schema; those scientific contracts must not be duplicated in a private Viewer.

## Errors, limits and exposure

Unsupported dispatch, missing context name, foreign/incompatible Workspace,
stale Session, invalid model, missing runtime, busy/failed Job, unavailable
published field and Plot/publication failures retain their actual owner
diagnostics. Native invocation catches errors into status/dialog presentation.
Model, FEM mesh, output, preview and Plot limits are owned by their respective
services; no new universal bound or scientific-success receipt is invented here.

This activation family has no registered Python/Octave Bridge family or typed
C++ SDK entry. Underlying ELECTROMAGNETIC_SIMULATION_API_v1 has its own actual
Script contract; that does not imply arbitrary GUI callback access. No generic
C++ invoke exists. See the installed Studio MANUAL.md and public
[Scientific Execution](SCIENTIFIC_EXECUTION_API_v1.md),
[Session Workspace](SESSION_WORKSPACE_API_v1.md) and
[Plot Dataset v4](PLOT_DATASET_API_v4.md) references. This manual is source-backed;
independent real GUI/solver/mesh/installed acceptance remains separate evidence.
