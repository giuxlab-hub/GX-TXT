# Final Large Dataset architecture audit - GX-TXT 0.9.7.27

The integrated read path is Dataset identity, Schema v3 metadata, Canonical Dataset v2 provider access, optional Table Stream v3 for flat tables, capability planning, direct or materialized representation, then bounded range or chunk reads. The write path is Publication v2, Storage Auto, a transactional provider writer, integrity validation, atomic placement, registry commit, then Canonical reopen.

Responsibilities are separate and no duplicated API ownership was found. Canonical Dataset owns identity and backend-neutral access. Schema v3 owns dtype, rank, shape, dimensions, coordinates and semantic variable metadata. Table Stream owns bounded flat-table streaming. Publication creates new scientific Datasets. Storage Policy selects providers. Materialization and cache own optional representations of an existing Dataset.

Dataset ID, Variable ID and Dimension ID remain scientific identity. HDF5 paths, CSV positions, filenames, cache keys and cache paths remain private physical locators. Materialization never calls datasetRegister and never creates a scientific provenance step.

Schema paths were validated for CSV, HDF5, both Publication writers, Table Stream, both materialization directions, reopen and copied sessions. Uniform origin, step and count remain Schema v3 authority. Compatibility CSV expands the coordinate without changing canonical interpretation.

No runtime defect was found. No runtime architecture change was required in this release.
