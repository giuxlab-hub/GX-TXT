# MAGNETICS_API_v1

Provider: `math.magnetics` 1.2.0. API ID/version: `MAGNETICS_API_v1`/1. This service analyzes supplied fields, curves and circuit quantities. It does not solve Maxwell equations or infer materials. GNU Octave and the public NUMERIC_API interpolation/integration routines are the current backend. Execution is serial.

## Bindings and field contract

- GNU Octave: `gxtxt_magnetics_v1(family,action,a,b,c,options)`.
- Tcl: activate `math.magnetics`/`MAGNETICS_API_v1`; call `::GX::MagneticsAPIv1::call family action a b c ?options?`.
- Registered Octave/Python scripts: `gxtxt_api_require('MAGNETICS_API_v1@1:math.magnetics')`, then `gxtxt_api_call('MAGNETICS_API_v1','family.action',args)`.
- Tcl `apiInfo`, `listOperations`, `operationMetadata`, `api/operations_v1.tsv`, and Script Bridge descriptors provide discovery.

Tcl/Bridge arguments use typed nodes with explicit shapes and split real/imaginary values (see `SIGNAL_API_v1`). Direct Octave accepts numeric arrays, cells of axes and option structs. Cartesian vector samples are `N×3`; regular vector fields are `nx×ny×nz×3`. Grid coordinates are strictly increasing vectors in the same order as array dimensions. Angles are radians. Cylindrical coordinates are `(r,azimuth,z)` and spherical coordinates are `(radius,polar,azimuth)` with polar measured from positive z. Transforming components uses the local orthonormal basis. The caller must declare coordinate system, unit and source provenance when publishing a Dataset.

## Operation inventory

| Family | Actions | Inputs, units and result |
|---|---|---|
| `coordinates` | Cartesian↔cylindrical, Cartesian↔spherical | `a=N×3` points, optional `b=N×3` vector components. Returns transformed coordinates and components. Negative radius fails. |
| `field` | `magnitude`, `phasor`, `normal_component`, `dot`, `cross`, `time_average_power`, `joule_loss` | Component magnitude, real/imaginary/phase, normal/tangential decomposition with real nonzero normals, complex vector algebra, and `0.5 E×conj(H)` complex Poynting density. |
| `field` | `sample`, `gradient`, `divergence`, `curl`, `laplacian` | 2D/3D regular-grid sampling with explicit interpolation/extrapolation policy; finite-difference differential operators on 3D Cartesian grids. Boundary first derivatives are one-sided, interiors central; the Laplacian uses local three-point second derivatives. Nonuniform axes are accepted. |
| `integral` | `line`, `circulation`, `mmf`, `surface_flux`, `flux`, `volume`, `power` | Trapezoidal `F·dl`; oriented triangulated face flux using vertex order and per-face vectors; 3D regular-grid volume integration. Field units multiply path length, face area or volume, respectively. |
| `constitutive` | `vacuum_permeability`, `b_from_h`, `h_from_b`, `permeability`, `anisotropic_b_from_h`, `nonlinear_b_from_h` | Explicit linear isotropic relative permeability. `μ₀=4π·10⁻⁷ H/m`; complex permeability is accepted. Nonlinear evaluation requires a caller-supplied monotonic B-H curve; no material law is inferred. |
| `loss` | `steinmetz`, `arbitrary_waveform` | Declared empirical coefficients yield sinusoidal Steinmetz or improved generalized Steinmetz loss density. The waveform integral requires an explicit time/flux-density cycle; no material database is used. |
| `circuit` | reluctance/permeance, series/parallel reluctance, MMF, flux linkage, inductance, mutual inductance, coupling, inductance matrix, energy-derived inductance | Inputs are explicitly supplied geometry, turns, current, flux or energy. Results report `A/Wb`, `Wb/A`, `A_turn`, `Wb_turn`, or `H` where applicable. Passive two-coil coupling magnitude must not exceed one. |
| `energy` | `density`, `integrated`, `energy_curve`, `coenergy_curve`, `electric_density`, `force_from_gradient`, `torque_from_gradient` | `0.5·B·H` for real/quasi-static linear data, `0.25·Re(B·conj(H))` with `phasor=true` for cycle-average phasors, regular-grid volume integration, and B-H curve integrals. Units `J/m³` or `J`. |
| `bh` | `loop_area`, `remanence`, `coercivity`, `differential_permeability`, `saturation_indicator`, `incremental_permeability`, `interpolate`, `cycle_align` | Loop area, linearly interpolated zero crossings, finite-difference permeability, and observed extrema. Loop area closes the supplied cycle by a final segment; it is an area diagnostic, not a hysteresis model. |

Invalid dimensions, zero denominators, nonfinite values, bad coordinates and absent curve crossings produce `GXTXT:Magnetics:*` errors. The finite-difference and interpolation assumptions apply to Cartesian regular grids; cylindrical/spherical differential operators are not silently substituted. Triangulated face orientation controls the flux sign. Complex field arrays are transported as split real/imaginary values. Complex B/H energy rejects a missing `phasor=true` declaration.

## Examples

```octave
r=gxtxt_magnetics_v1('circuit','reluctance',1,0.01,1000,struct());
assert(abs(r.value_real-1/(4*pi*1e-7*1000*0.01))<1e-7);
```

```python
from gxtxt import gxtxt_api_require, gxtxt_api_call
gxtxt_api_require('MAGNETICS_API_v1@1:math.magnetics+circuit')
arr=lambda x:{'kind':'array','shape':[1,1],'real':[x]}
r=gxtxt_api_call('MAGNETICS_API_v1','circuit.reluctance',[arr(1),arr(0.01),arr(1000)])
```

```octave
gxtxt_api_require('MAGNETICS_API_v1@1:math.magnetics+circuit');
a=@(x) struct('kind','array','shape',[1 1],'real',x);
r=gxtxt_api_call('MAGNETICS_API_v1','circuit.reluctance',{a(1),a(0.01),a(1000)});
```

Field Datasets use existing Canonical Dataset, Variable Schema, Metadata, Selection, Unit and Publication APIs. A field variable should carry stable identity, coordinate axes or point positions, component meaning, coordinate system and physical unit; mesh connectivity remains a Dataset variable or published artifact reference. The shared details are in `docs/api/SCIENTIFIC_FIELD_AND_SWEEP_DATASET_CONTRACT_v1.md`. This API does not create a second field Dataset model.
# Guided-client metadata

`operationMetadata(id)` also returns `arguments`, `argument_descriptors`,
`signature`, `worksheet_example`, `result_fields`, and `unit_behavior`.
These fields are derived from the provider-owned operation and family
contracts. They let a Worksheet or other guided client display the public
call's inputs and unit/result expectations without parsing implementation
code. The existing `call(family, action, a, b, c, options)` contract is
unchanged.
