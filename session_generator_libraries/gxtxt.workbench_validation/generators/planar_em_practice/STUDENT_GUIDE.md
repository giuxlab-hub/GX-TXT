# Planar electromagnetic practice

Generate this Session using **New Session → Generate Session**, library
**Workbench Source Practice**, generator **Planar Electromagnetics Practice**.
The normal host records the library/generator identity in
`metadata/session_generator.ini`. `em.practice.parameters` is an ordinary
source table of two input specifications. It is not a saved EM model, mesh or
field. The generator creates no solver output, Job, Interactive Document or
accepted numerical result.

Open the existing **Electromagnetics Studio** Viewer and create a new model
Workspace. Enter the appropriate source row using its Model, Materials,
Excitation and Mesh controls. Values are SI; domain width is **twice** the
half width. Formulation is the existing **planar_2d** choice. Use **Validate**,
then **Save** through the normal Model Workspace controls. Validation performs
no solve. Solver executable paths belong to **Configuration → Runtime**.

| Existing model field | Magnetic exercise | Electric exercise | Unit |
| --- | ---: | ---: | --- |
| model_id | magnetic_practice | electric_practice | identity |
| kind | magnetostatic_2d | electrostatic_2d | choice |
| half_width_m | 0.02 | 0.01 | m |
| height_m | 0.04 | 0.01 | m |
| mesh_size_m | 0.001 | 0.001 | m |
| radius_m | 0.005 | 0.002 | m |
| current_density_A_m2 | 1000000 | 1000000 | A/m² |
| mu_r | 1 | 1 | dimensionless |
| voltage_V | 10 | 10 | V |
| eps_r | 1 | 2 | dimensionless |

For magnetic physics, the round conductor carries positive axial current
density; conductor and air have relative permeability 1. The finite outer
rectangle imposes `Az=0`. Electric voltage/permittivity entries remain inactive.
The ideal unbounded-conductor current is `I=Jz*pi*a²=25*pi A`. With the existing
teaching-model convention `mu0=4*pi*10^-7 H/m`, the unbounded comparison at
`r=0.01 m` is `Btheta=mu0*I/(2*pi*r)=0.0005*pi T`.
This is **not** an exact solution for the finite rectangular boundary. Mesh
polygonization, current/area approximation and the finite boundary affect the
actual field. No finite-domain agreement tolerance is asserted by this fixture.

For electric physics, use 0 V on the left, 10 V on the right, and natural
insulation on the top and bottom of the homogeneous rectangle. Radius/current/
permeability values remain inactive. Here the exact comparison is
`V(x)=10*(x+0.01)/0.02 V`, `Ex=-500 V/m`, `Ey=0` and `V(0)=5 V`.
This ideal planar comparison includes no finite-plate fringing or 3D capacitance.
See `reference/em_truth.json` for independent formulas and qualifications.

When a subsequent authorized exercise requests a solve, use **Run FEM** with
the actual configured Gmsh/GetDP tools. Preserve the real Job log and numerical
validation receipt. Only **Publish Verified Field** from that genuine completed
Job creates the linked canonical nodes and cells. **Show exact cell field** and
**Show sample profile** then use those real publications. A source parameter
table or the reference JSON must never be relabelled as canonical EM output.
Independent QA must retain the real Generate Session provenance and perform
the actual GUI, solver and field checks; source diagnostics do not accept them.

This fixture supplies linear planar electrostatic and magnetostatic inputs.
It does not certify solver accuracy, nonlinear/axisymmetric/transient physics,
device inductance, automatic mesh sweeps or circuit extraction.
Original parameters, references and instructions: GPL-3.0-or-later.
