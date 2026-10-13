# Changelog

## 1.1.0

- Added source-preserving VTP polydata and VTI regular scalar-grid Acquisition paths for the generic Native 3D Dataset selector.
- The standard-library inspector checks XML structure, 3-D extent/spacing, piece and array declarations, and appended-data envelopes; native VTK decodes values at render time.
- Added the generic `field.scalar_3d` Dataset contract for VTI. Existing STL, OBJ, STEP and VTU import behavior remains available.

## 1.0.0

Initial standalone acquisition package for GX-TXT 0.9.8.09.

- Source-preserving STL, OBJ, STEP/STP and VTU import through Acquisition Handler API v1.
- Framework batch/current-Session integration, metadata preview and independent Dataset IDs.
- Explicit per-format validation scope and unchanged original bytes.
- Structured geometry/CAD/VTU metadata through the existing Dataset Metadata transfer.
- Cancellable process worker; exact-copy verification and no destination overwrite.
- Framework-neutral format catalogue and inspector isolated for future CORE extraction.
- No CORE edits, viewer dependency, renderer binary, analysis module or Session generator.
