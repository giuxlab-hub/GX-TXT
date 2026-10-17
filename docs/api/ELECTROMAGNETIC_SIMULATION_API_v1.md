# Electromagnetic Simulation API v1

Provider: `math.electromagnetic_simulation`. Activate `ELECTROMAGNETIC_SIMULATION_API_v1` through the existing Module API. Tcl namespace: `::GX::ElectromagneticSimulation`. The provider implements bounded **linear planar static 2D electrostatics and magnetostatics**, using configured real Gmsh/GetDP through the public Scientific Execution supervisor.

| Tcl operation | Operands | Result / meaning |
|---|---|---|
| `apiInfo` | none | Actual implementation, supported problems and limitations |
| `defaultModel` | kind | Normalized SI scientific model |
| `validate` | model | Validation-only receipt containing normalized model; no solve |
| `saveModel` | model, optional Document ID and Workspace name | Existing Session Workspace receipt; strict owner checks |
| `listModels` | none | Existing provider-owned model Documents |
| `loadModel` | Document ID | Normalized scientific model |
| `runAsync` | model, optional host callback and Document ID | Existing durable managed Job ID |
| `jobStatus` | Job ID | Actual public durable state |
| `cancel` | Job ID | Existing supervisor cancellation receipt |
| `resultDescribe` | Job ID | Verified physical/residual receipt, solver versions and native SHA |
| `resultPreview` | Job ID, optional offset and count | At most 100 actual cell rows through bounded public output snapshots |
| `publish` | Job ID, new Dataset ID | Atomic create-only canonical cell and linked node Datasets |
| `fieldDescribe` | canonical field Dataset ID | Actual qualified Dataset/Variable semantic roles and metadata |

`kind` is `electrostatic_2d` or `magnetostatic_2d`; `formulation` is `planar_2d`. Scientific fields are `model_id`, `half_width_m`, `height_m`, `mesh_size_m`, `radius_m`, `current_density_A_m2`, `mu_r`, `voltage_V`, and `eps_r`. Executable paths and commands are not model properties. Values must be finite and within the bounded model geometry/material/mesh contract. Unsupported fields or physics reject explicitly.

The electrode model uses left 0 V / right applied potential and natural insulating upper/lower boundaries. The magnetic model uses an axial current disk in finite rectangular air and outer `Az = 0`. The latter differs from an infinite surrounding domain. Independent native checks validate exact mesh coverage, field/potential gradient consistency, assembled weak residual and physical reference observables. Residual norms are not physical uncertainty or a standalone field-accuracy claim.

Publication preserves exact node, triangle, region and material identities. The node Dataset contains the actual solved potential; cell potential is its triangle average, and first-order vector fields are constant per triangle. Centroid samples never impersonate nodes. Metadata records units, exact role links, model, solver/native provenance, physical checks and approved raw solver resources through existing managed Resource references. Generic consumers obtain role IDs from `fieldDescribe`; they do not depend on producer CSV header positions.

Python/Octave use existing `gxtxt_api_call` under the same API ID. Operation names are `api_info`, `default_model`, `validate_model`, `save_model`, `list_models`, `load_model`, `run_async`, `job_status`, `cancel`, `result_describe`, `result_preview`, `publish`, and `field_describe`. Arguments and results are typed structs/scalars/lists. Script `run_async` has only the model operand; callbacks and Tk windows are host presentation concerns.

Jobs use actual queued/running/finalizing/completed/failed/cancelled/interrupted states. Closing a Viewer does not cancel or transfer ownership. Results are imported only from a completed, original-Session, source-current Job. Canonical publication is explicit; no successful process exit alone constitutes scientific acceptance.

Native field charts use [Plot Dataset API v4](PLOT_DATASET_API_v4.md) with exact `GXTXT_CELL_FIELD_BINDING_v1`, complete source nodes/connectivity and constant per-cell values. Current bounds are 60,000 nodes and 30,000 triangles. Axisymmetry, nonlinear B–H, transient EM, arbitrary CAD, device inductance/capacitance extraction and SPICE generation are unavailable.
