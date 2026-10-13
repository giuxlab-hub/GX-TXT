# Crystal Chemistry Viewer

Open **Crystal Chemistry Viewer** from GX-TXT's Viewers tab in an active
Session. The left panel contains 13 real COD crystal structures and three
solver-computed Gaussian CUBE electron-density examples. Double-click a
library row or choose **Install selected into Session**. This publishes the
exact source bytes as a canonical Dataset with a stable ID, SHA-256, source URL,
citation and rights metadata. The selected Dataset then appears in the
**Structure source Dataset** or **Electron-density CUBE Dataset** selector.

External CIF/CUBE sources can be imported through **Crystal and Electron
Density Import** in Acquisition. They appear in these selectors as ordinary
Session Datasets. CIF imports preserve original source bytes and decode the
unit cell, space group, fractional sites, occupancies and symmetry operations.
CUBE imports preserve original bytes, embedded atom positions, grid axes,
scalar range and field-unit declaration. Invalid or incomplete sources fail
with a concrete diagnostic.

Choose a CIF and a supercell size of 1, 2 or 3, then select **Open / update 3D
structure and density**. A separate Native 3D window renders the atoms, bonds,
unit cell, a/b/c axes and any chosen density layers. The crystal panel is the
scientific control surface; Native 3D receives only generic VTP/VTI geometry
and scalar fields. The site table shows the symmetry-expanded structure.
Select one site for its element, occupancy, fractional and Cartesian
coordinates. Select two, three or four sites for distance, angle or dihedral.
**Fit** and standard a/b/c camera buttons adjust the rendering view.

For density, choose one or more semicolon-separated isovalues, opacity, slice
axis/position and contour value. Positive and negative isovalues are accepted
for signed CUBE fields. The field unit and exact source SHA-256 are shown in
the details panel. Updating controls regenerates Session-owned VTI/VTP display
artifacts; the CUBE remains authoritative. The domain settings and Native 3D
scene persist across Session save/reopen.

## Real examples

* **Water RHF electron density:** the CUBE contains solver-input H2O atom
  positions and the computed molecular electron-density grid, so its source
  structure and density render together. PySCF 2.14.0, RHF/STO-3G,
  total energy -74.94588076098967 Hartree.
* **Diamond periodic RHF charge density:** COD 2101499 CIF supplies the
  conventional diamond lattice and symmetry; the CUBE contains a periodic
  Gamma-point RHF/GTH-SZV/GTH-Pade computed density using the COD lattice
  constant and aligned carbon sites. Total energy -10.137229024352761
  Hartree. Both source identities remain visible and independent.
* **Water signed difference density:** a second RHF/STO-3G water calculation
  moves one hydrogen by 0.06 Å. The perturbed density is subtracted from the
  first calculation on exactly the same 48³ grid. The resulting CUBE has real
  positive and negative lobes. Use isovalues `-0.003;0.003` to display both.
* **Halite, quartz, calcite, anatase, iron, copper, silicon, layered carbon,
  urea and additional structures:** select their COD entries from the library.

`library/index.tsv` records every original CIF/CUBE file's URL, citation,
rights and SHA-256. COD states the database is CC0; each CIF also carries its
original author and publication. The dataset authors release the computed
CUBE output data under CC0-1.0. The exact PySCF input script and solver logs
are in `library/density/`; `crystal_data.py` performs CUBE Bohr-to-ångström
coordinate conversion and VTI/VTP display conversion. The original density
numbers remain in e/Bohr³.

## Limits

CIF atom sites require fractional coordinates and a valid unit cell. The
viewer handles operations in the CIF, or uses its bundled crystallographic
space-group operation table when a CIF supplies only group identity. A CUBE
with multiple orbital arrays is rejected because it is not a scalar electron
density field. VTI display artifacts are regenerable and may differ in byte
encoding from the source CUBE; original scientific values are never changed.
