# Task 006 scientific Dataset contracts

These Dataset kinds identify source material used by the dedicated chemistry
and NMR viewers. The domain plugins own parsing and scientific meaning; CORE
retains canonical Dataset identity, payload bytes, SHA-256, metadata and normal
Session persistence. Native 3D receives only generic geometry and scalar-field
artifacts from a domain viewer.

| Dataset kind | Original payload | Domain owner |
|---|---|---|
| `molecular.structure` | SDF/MOL, XYZ or PDB structure | `acq.molecule_structure`, `viewer.molecule_3d` |
| `structure.crystal` | CIF crystal structure | `acq.crystal_density`, `viewer.crystal_structure` |
| `field.scalar_3d` | Gaussian CUBE volumetric field | `acq.crystal_density`, `viewer.crystal_structure` |
| `spectrum.nmr_multidimensional` | acquired NMRPipe 2-D or 3-D data | `acq.nmr_multidimensional`, `viewer.nmr_multidimensional` |

All four kinds use a stable Dataset ID from `metadata/datasets.ini`, an
original source SHA-256, and source metadata. A rendered VTP/VTI artifact is
derived display data; its `source_dataset_id` and `source_dataset_sha256` link
back to the canonical Dataset. Reopen and rerender must check that link. A
source file path is never the Dataset's public scientific identity.

## Molecular structure metadata

`molecule.format`, `molecule.name`, `molecule.atom_count`,
`molecule.bond_count`, `molecule.conformer_count`, `molecule.coordinates`
(`angstrom`), `molecule.elements`, `molecule.net_formal_charge`,
`molecule.source_filename`, and `molecule.source_sha256` describe a local
structure. Library and online records also carry `molecule.reference_name`
for the external component name or query label. Installed wwPDB CCD examples additionally record
`molecule.source_service`, `molecule.source_id`, `molecule.source_url`,
`molecule.license`, `molecule.rights_url`, `molecule.citation` and
`molecule.library_original_sha256`. A PubChem online resolution additionally
records the query kind/identifier, resolved CID, exact source URL, UTC
retrieval time and `molecule.online_original_sha256`.

## Crystal and scalar-field metadata

Both crystal and CUBE imports record `chemistry.format`,
`chemistry.source_sha256`, `chemistry.source_id`, `chemistry.citation`, and
`chemistry.doi` when available. Crystal data can record `chemistry.formula`,
`chemistry.space_group`, `chemistry.space_group_number`,
`chemistry.site_count`, `chemistry.expanded_count`,
`chemistry.operator_count`, and `chemistry.cell`. A CUBE field can record
`chemistry.atom_count`, `chemistry.dimensions`, `chemistry.range`,
`chemistry.field_unit`, `chemistry.description`, and `chemistry.generator`.
Installed reference entries additionally record `chemistry.title`,
`chemistry.source_url`, and `chemistry.license`. Source CIF and CUBE bytes
remain authoritative; VTP/VTI files are derived representations.

## Multidimensional NMR metadata

`nmr_multi.dimensions`, `nmr_multi.shape`, `nmr_multi.experiment`,
`nmr_multi.source_sha256`, `nmr_multi.minimum`, `nmr_multi.maximum`,
`nmr_multi.source_citation`, `nmr_multi.source_license`, and
`nmr_multi.original_filename` describe the acquired input. Each axis has
`axis_<n>_label`, `axis_<n>_nucleus`, `axis_<n>_frequency_mhz`,
`axis_<n>_ppm_first`, `axis_<n>_ppm_last`, and `axis_<n>_points` under the
`nmr_multi.` prefix. Extracted profile/plane Datasets record
`source_dataset_id`, `source_sha256`, `extraction_kind`, `plane`,
`fixed_indices`, and fixed ppm coordinates for their source axes.

These are Task 006 plugin domain contracts, not Native 3D semantics or a new
solver. The [Viewer Provider API](VIEWER_PROVIDER_API_v1.md) supplies generic
lazy activation and layer persistence; the Dataset and Acquisition APIs retain
canonical source identity and hashes.
