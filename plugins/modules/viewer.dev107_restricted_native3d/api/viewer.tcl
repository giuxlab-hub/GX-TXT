# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_dev107_restricted_native3d {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_dev107_restricted_native3d::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.dev107_restricted_native3d development_example [set ::GX::Restricted_viewer_dev107_restricted_native3d::root]]}
proc ::GX::Restricted_viewer_dev107_restricted_native3d::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.dev107_restricted_native3d development_example [set ::GX::Restricted_viewer_dev107_restricted_native3d::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
::GX::viewerBackendRegister viewer_dev107_restricted_native3d_restricted_cpp_v1 ::GX::Restricted_viewer_dev107_restricted_native3d::dispatch
