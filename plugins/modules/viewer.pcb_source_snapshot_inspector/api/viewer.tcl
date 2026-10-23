# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_pcb_source_snapshot_inspector {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_pcb_source_snapshot_inspector::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.pcb_source_snapshot_inspector pcb_source_snapshot_inspector [set ::GX::Restricted_viewer_pcb_source_snapshot_inspector::root]]}
proc ::GX::Restricted_viewer_pcb_source_snapshot_inspector::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.pcb_source_snapshot_inspector pcb_source_snapshot_inspector [set ::GX::Restricted_viewer_pcb_source_snapshot_inspector::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_pcb_source_snapshot_inspector::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.pcb_source_snapshot_inspector pcb_source_snapshot_inspector [set ::GX::Restricted_viewer_pcb_source_snapshot_inspector::root] $context]}
proc ::GX::Restricted_viewer_pcb_source_snapshot_inspector::texOpen {document} {return [::GX::viewerDevelopmentInstalledOpen viewer.pcb_source_snapshot_inspector pcb_source_snapshot_inspector [set ::GX::Restricted_viewer_pcb_source_snapshot_inspector::root] [dict create tex_document_id $document]]}
::GX::viewerBackendRegister viewer_pcb_source_snapshot_inspector_restricted_cpp_v1 ::GX::Restricted_viewer_pcb_source_snapshot_inspector::dispatch
