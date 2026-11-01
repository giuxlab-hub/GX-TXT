# SPDX-License-Identifier: GPL-3.0-or-later
# Fixed trusted GUI auxiliary request; existing CORE Registry/inventory owner.
# No authored command, Registry mutation, Session creation or source execution.
set framework [lindex $argv 0]
set argv0 __gxtxt_script_provided_inventory_request__
if {[catch {
    set request [read stdin 33554433]
    if {[string bytelength $request]>33554432 || [catch {dict size $request}]} {error {Provided API request exceeds bounded dictionary transport}}
    if {[lsort [dict keys $request]] ne {code_pins options python reference session}} {error {Exact provided API request fields required}}
    set codeFiles {app/script_provided_inventory_request.tcl core/tcl/script_provided_api_v1.tcl core/tcl/script_project_v1.tcl core/tcl/script_execution_api_v1.tcl core/python/script_project.py core/python/script_api_exports.py core/python/script_api_declarations.py}
    if {[lsort [dict keys [dict get $request code_pins]]] ne [lsort $codeFiles]} {error {Exact public owner code pins required}}
    source [file join $framework gxtxt_pipeline.tcl]
    ::GX::defaults;::GX::configurationLoad;::GX::loadModuleCatalog
    ::GX::configurationSet runtime.python [dict get $request python]
    dict for {relative sha} [dict get $request code_pins] {
        if {$relative ni {app/script_provided_inventory_request.tcl core/tcl/script_provided_api_v1.tcl core/tcl/script_project_v1.tcl core/tcl/script_execution_api_v1.tcl core/python/script_project.py core/python/script_api_exports.py core/python/script_api_declarations.py} || [::GX::sha256File [file join $framework $relative]] ne $sha} {error {Provided API owner code changed before request}}
    }
    set result [::GX::scriptRegistryProvidedApiInventory [dict get $request reference] [dict get $request options] [dict get $request session]]
    dict for {relative sha} [dict get $request code_pins] {if {[::GX::sha256File [file join $framework $relative]] ne $sha} {error {Provided API owner code changed during request}}}
} reason]} {puts [dict create ok 0 error $reason]} else {puts [dict create ok 1 result $result]}
