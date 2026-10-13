# Molecular library data

The 30 original SDF files in `library/` are individual ideal-coordinate records
from the wwPDB Chemical Component Dictionary. They are included under CC0-1.0,
per the [official PDB archive usage policy](https://www.rcsb.org/pages/usage-policy).
The exact source URL and SHA-256 of each file appear in `library/manifest.tsv`.
The records were retrieved on 2026-10-01 UTC. No coordinate adjustment or
reformatting was applied to the originals. Citation: wwPDB Chemical Component
Dictionary; [ligand download service](https://www.rcsb.org/downloads/ligands).

PubChem data are fetched only when a user requests lookup and are kept in that
user's Session. They are not included in this plugin's distributable library.
