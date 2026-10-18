# SPDX-License-Identifier: GPL-3.0-or-later
proc settle {{ms 240}} {after $ms {set ::ownershipSettled 1};vwait ::ownershipSettled;update}
set d [::GX::viewerGuiDesignNew {Normal Preview · command ownership}]
dict set d handlers probe {arguments {window action} effect presentation label Probe default Ctrl+g}
dict set d components [list [dict create id probe type action parent toolbar properties {label Probe action probe shortcut Ctrl+g} layout {row 0 column 0}]]
dict set d requirements {VIEWER_GUI_HOST_API_v1 1 UI_FIELD_API_v1 1 CONFIGURATION_API_v1 1}
::GX::viewerGuiDesignCompose $d .normalCommandProbe viewer.interface_builder interface_builder preview
settle 300
set catalog [dict get $::GX::ViewerCommands::windows .normalCommandProbe module]
set before [::GX::viewerCommandCatalog $catalog]
key .normalCommandProbe ctrl+g;settle 100
::GX::viewerGuiComponentDemoOpen field;settle 300
set after [::GX::viewerCommandCatalog $catalog]
record demo_command_ownership [dict create status [expr {$before eq $after?{PASS}:{FAIL}}] original_catalog $catalog original_before $before original_after $after demo_catalog [dict get $::GX::ViewerCommands::windows .gxComponentDemo module]]
capture .gxComponentDemo demo_command_ownership_demo
if {$before ne $after} {error {Gallery changed the live normal Preview command catalogue}}
key .normalCommandProbe ctrl+g;settle 200
capture .normalCommandProbe demo_command_ownership_preview
if {[file exists [file join $::out tk_background_errors.log]]} {error {Normal Preview shortcut failed after Gallery}}
key .gxComponentDemo alt+F4;key .normalCommandProbe alt+F4
record demo_command_ownership_finished [dict create status PASS normal_preview_catalog_exact 1 native_shortcut_before_after 1 no_session [expr {$::GX::currentSession eq {}}]]
