# 3D Geometry Import 1.1.0

Install `acq.geometry_3d_1.1.0.zip` using GX-TXT **Modules → Install plugin...**.
Use **3D Geometry Import** in Acquisition for STL, OBJ, STEP/STP, VTU, VTP and VTI files.
Each file becomes a normal source-preserving Dataset, including metadata and
provenance. No CORE files are included or modified.

The importer package requires GX-TXT 0.9.8.09 or newer and a configured Python
3.10+ executable. The Dataset-driven Native 3D workflow requires GX-TXT
0.9.8.10-dev or newer.
No additional Python package or viewer is required for import.

See `MANUAL.md` for the workflow and precise format-validation scope,
`docs/ARCHITECTURE.md` for the portable parser/runtime boundaries.

The Native 3D viewer selects imported Datasets directly from the Session.
For VTI, enter a scalar array name and one or more isovalues before rendering.
OBJ external materials/textures are not bundled automatically. Geometry and
scientific payloads are preserved without transformations or CSV conversion.

License: GNU GPL version 3 or later. All source code is included.
