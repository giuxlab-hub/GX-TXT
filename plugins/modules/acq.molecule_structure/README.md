# Molecular Structure Import

Import SDF/MOL V2000, XYZ or PDB through the standard Acquisition window. Each
source is copied to Session RAW storage and to an opaque `molecular.structure`
Dataset. The original coordinates remain authoritative. SDF bond order and
formal charge are preserved; XYZ and PDB without `CONECT` use a covalent-radius
distance estimate for display bonds. A multi-record SDF or XYZ file supplies
multiple selectable conformers. Units are ångström.

The dedicated Molecule Viewer can install CC0 wwPDB Chemical Component Dictionary
examples and perform user-triggered PubChem 3-D lookup through this importer.
