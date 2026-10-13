# Molecule Viewer

Open the Molecule Viewer from the Viewer menu in a Session. In **Library &
import**, install any of 30 wwPDB Chemical Component Dictionary references,
import local SDF/MOL, XYZ or PDB, or request a 3-D conformer from PubChem.
The library's original SDFs are CC0-1.0 (wwPDB archive usage policy). PubChem
lookup is online and user triggered; individual external data source rights
remain with their providers.

In **Structure**, choose a Dataset and conformer, then open a Native 3D
ball-and-stick or space-filling representation. The atom table and coordinate
projection allow selection; select exactly two, three or four atoms before
requesting a distance, bond angle or dihedral. Measurements use source
coordinates in ångström. SDF bond order and formal charge appear in the bond
and atom tables. The source tab exposes canonical payload and RAW SHA-256,
license, source URL, query and retrieval date when available.

Use **Save view** to retain the selected Dataset, conformer, style and label
setting in the Session. The generated VTP mesh is a derived display artifact
whose SHA-256 is checked by the Viewer Provider; original molecular bytes are
retained and checked through the canonical Dataset payload. Native 3D owns
camera, zoom and fit controls; molecular semantics remain in this viewer.

## Reference rights

The 30 bundled SDF files are individual wwPDB CCD ideal-coordinate records.
The [official wwPDB/RCSB usage policy](https://www.rcsb.org/pages/usage-policy)
states that PDB archive data files are CC0-1.0. `library/manifest.tsv` records
the exact source URL and SHA-256 of every original SDF. Citation: wwPDB Chemical
Component Dictionary; see also the [CCD download page](https://www.rcsb.org/downloads/ligands).
