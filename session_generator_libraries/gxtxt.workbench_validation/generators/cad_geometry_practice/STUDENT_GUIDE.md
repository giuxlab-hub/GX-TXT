# CAD geometry practice

Generate this Session using **New Session → Generate Session**, library
**Workbench Source Practice**, generator **CAD Geometry Practice**. The normal
host records the library and generator identity in `metadata/session_generator.ini`.
The source-only library supplies input Datasets and an independent reference;
it creates no 3D Workspace, History, body, profile, managed texture or result.

Open the existing 3D Workbench and create a Workspace. Select working unit **mm**.
Use **Import mesh / CAD Dataset…** to import `cad.box_closed_mm`,
`cad.box_open_mm` or `cad.tetrahedron_mm`. Explicitly declare the input unit **mm**:
STL carries no unit declaration. Preserve this physical size when later converting
working units. Do not treat a unit conversion as geometric scaling.

The closed box spans `(0,0,0)` to `(20,10,6)` mm. Its surface area is
`2*(20*10+20*6+10*6)=760 mm²`; its volume is `20*10*6=1200 mm³`.
The open box lacks the complete top face at `z=6`: area `560 mm²`, one
boundary loop with four edges and perimeter `60 mm`. Its enclosed volume is
undefined. The tetrahedron has axis intercepts `6,8,10` mm and volume
`6*8*10/6=80 mm³`. These references come directly from the source definition.
Use the existing inspection and boundary controls to compare the actual results.

Use **Profile from scientific coordinates** with `cad.rectangle`, variables
`x_mm` and `y_mm`, the XY working plane, and **Interpret the contour as closed**.
The four rows are ordered counterclockwise; closure connects the final row to
the first. Both coordinates declare **mm**. Keep explicit coordinate-unit
conversion enabled and leave the unitless-axis assumption disabled. The profile
has area `200 mm²` and perimeter `60 mm`; a new positive 6 mm extrusion has
volume `1200 mm³`. Preview, accept and save through the ordinary controls.

`cad.calibration.image` is an original 64×64 RGBA8 PNG with transparent bands,
visible orientation and four red fiducials. The independent pixel-centre mapping
and exact decoded-pixel hash are in `reference/cad_truth.json`. Raw/canonical
image availability alone does not make a retained managed image. Use the
existing image extraction/composition and Workspace retention workflow first;
the existing 3D texture chooser accepts a retained managed RGBA resource. Pick
a current planar face and explicitly request a decorative size of `20×10 mm`
only when that workflow has created the resource. Decorative resizing is not
scientific calibration. Managed intake and texture placement remain separate
GUI acceptance gates; no managed resource is injected by this generator.

The reference JSON is a comparison aid, never a scientific result source.
This small fixture covers analytic mesh/profile inputs. It contains no genuine
STEP/B-Rep source; STEP import/export and kernel-only operations require a
separately licensed genuine source or a body created using existing GUI controls.
Original coordinates, image and instructions: GPL-3.0-or-later.
