# Native binary ownership in dev097

Native2D is built by core/native2d/CMakeLists.txt and installed to
core/native2d/bin/gx2dtcl with the platform shared-library extension.
Both Curve Workbench and Dataset Curve Fit call ::GX::native2DEnsure;
the controlled GX2D_TCL_LIBRARY environment override remains available.
Their plugin packages require framework dev096 or newer, whose CORE already
supplies the adapter and required capabilities. No standalone duplicate is needed.

Native3D uses core/native3d/CMakeLists.txt, gx3de_viewer_tcl and gx3de,
core/native3d/bin and core/native3d/lib. The GUI, mesh consultation and
scientific multiview hosts use core/native3d/renderer_worker.tcl and the CORE
bridge. Preview availability checks this same file. The established plugin
build entry delegates to CORE CMake with an explicit separate build directory;
it no longer produces a second library. The obsolete plugin library, C++ include
wrapper and worker are removed. Native3D has no plugin-package.ini in this release.

Historical version-pinned validation/build scripts describe historical layouts;
they must not be run unchanged to deploy this candidate. Prior releases and their
packages remain untouched. Framework packaging copies the candidate tree and
regenerates manifests; module packages copy their own directory and cannot add a
second adapter. No scientific identifier, Dataset or persisted Workspace field
changes. No native component was rebuilt for this reconciliation.

Section 2A coverage is limited to three representative smoke cases. It does not
replace dev097 frozen-candidate acceptance or establish Windows native parity.
