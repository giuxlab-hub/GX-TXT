# Session Workspace provider validation and independent identity check.
# SPDX-License-Identifier: GPL-3.0-or-later
set root [file normalize [file join [file dirname [info script]] ..]]
source [file join $root api workspace_provider.tcl]
set payload [dict create schema scientific_image_inspector.recipe.v2 source_id rasterA \
  source_sha [string repeat a 64] steps {} panels {} figure_settings [dict create layout {1x2}] annotations {}]
if {![::GX::SII::workspaceValidate $payload]} {error {Valid recipe rejected}}
set broken [dict replace $payload source_sha invalid]
if {![catch {::GX::SII::workspaceValidate $broken}]} {error {Corrupt source SHA accepted}}
set broken [dict remove $payload annotations]
if {![catch {::GX::SII::workspaceValidate $broken}]} {error {Missing annotations accepted}}
proc ::GX::viewerOpen {module viewer ctx} {return [list $module $viewer $ctx]}
set opened [::GX::SII::workspaceProviderOpen workspace-123]
if {[lindex $opened 0] ne "viewer.scientific_image_inspector" || \
    [dict get [lindex $opened 2] workspace_id] ne "workspace-123"} {
    error {Workspace provider did not forward its precise ID}
}
puts {WORKSPACE MODEL TESTS PASSED}
