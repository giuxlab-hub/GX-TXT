# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_circuit_workbench {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_circuit_workbench::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.circuit_workbench circuit_workbench [set ::GX::Restricted_viewer_circuit_workbench::root]]}
proc ::GX::Restricted_viewer_circuit_workbench::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.circuit_workbench circuit_workbench [set ::GX::Restricted_viewer_circuit_workbench::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_circuit_workbench::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.circuit_workbench circuit_workbench [set ::GX::Restricted_viewer_circuit_workbench::root] $context]}
::GX::viewerBackendRegister viewer_circuit_workbench_restricted_cpp_v1 ::GX::Restricted_viewer_circuit_workbench::dispatch
