# SPDX-License-Identifier: GPL-3.0-or-later
# Configuration form for the existing execution location policy.
proc ::GX::scientificExecutionNodeManagerBuild {parent} {
    scientificExecutionNodesInit
    set f $parent.nodes;ttk::frame $f -padding 12;pack $f -fill both -expand 1
    ttk::label $f.intro -text {Compute nodes use authenticated HTTPS and explicitly authorized remote Sessions. Certificate and key files stay outside scientific Sessions and Workspaces.} -wraplength 1000
    grid $f.intro -row 0 -column 0 -columnspan 3 -sticky ew -pady 8
    ttk::treeview $f.tree -columns {endpoint session enabled} -show {tree headings} -height 4
    $f.tree heading #0 -text Node
    foreach {column label} {endpoint Endpoint session {Remote Session} enabled Enabled} {$f.tree heading $column -text $label}
    grid $f.tree -row 1 -column 0 -columnspan 3 -sticky nsew -pady 8
    bind $f.tree <<TreeviewSelect>> [list ::GX::_computeNodeSelect $f]
    set row 2
    foreach {key label} {node_id {Node identity} endpoint {HTTPS endpoint} session_id {Authorized remote Session ID} ca_file {Trusted CA file} client_cert {Client certificate file} client_key {Private client key file}} {
        set ::GX::ui(computeNode,$key) {}
        ttk::label $f.label_$key -text $label;ttk::entry $f.value_$key -textvariable ::GX::ui(computeNode,$key) -width 70
        grid $f.label_$key -row $row -column 0 -sticky e -padx 6 -pady 4;grid $f.value_$key -row $row -column 1 -sticky ew -padx 6 -pady 4
        if {$key in {ca_file client_cert client_key}} {ttk::button $f.browse_$key -text Browse… -command [list ::GX::_computeNodeBrowse $f $key];grid $f.browse_$key -row $row -column 2 -padx 5}
        incr row
    }
    set ::GX::ui(computeNode,enabled) 1
    ttk::checkbutton $f.enabled -text {Node enabled} -variable ::GX::ui(computeNode,enabled);grid $f.enabled -row $row -column 1 -sticky w;incr row
    ttk::frame $f.actions
    ttk::button $f.actions.save -text {Save node} -command [list ::GX::_computeNodeSave $f]
    ttk::button $f.actions.test -text {Test connection / capabilities} -command [list ::GX::_computeNodeProbe $f]
    pack $f.actions.save $f.actions.test -side left -padx 5
    grid $f.actions -row $row -column 0 -columnspan 3 -sticky w -pady 8;incr row
    set ::GX::ui(computeNode,destination) [scientificExecutionDestination]
    ttk::label $f.destinationLabel -text {Scientific execution destination}
    ttk::combobox $f.destination -state readonly -textvariable ::GX::ui(computeNode,destination)
    bind $f.destination <<ComboboxSelected>> {::GX::scientificExecutionDestination $::GX::ui(computeNode,destination)}
    grid $f.destinationLabel -row $row -column 0 -sticky e;grid $f.destination -row $row -column 1 -sticky ew;incr row
    ttk::label $f.status -text {Select a node or enter its connection details. Local execution remains available.} -wraplength 1000 -anchor w
    grid $f.status -row $row -column 0 -columnspan 3 -sticky ew -pady 10
    grid columnconfigure $f 1 -weight 1
    _computeNodeRefresh $f
}
proc ::GX::_computeNodeRefresh {f} {
    $f.tree delete [$f.tree children {}]
    dict for {id node} [scientificExecutionNodes] {$f.tree insert {} end -id $id -text $id -values [list [dict get $node endpoint] [dict get $node session_id] [dict get $node enabled]]}
    $f.destination configure -values [concat {local auto} [dict keys [scientificExecutionNodes]]]
}
proc ::GX::_computeNodeSelect {f} {
    set selected [$f.tree selection];if {$selected eq {}} return
    set id [lindex $selected 0];set ::GX::ui(computeNode,node_id) $id
    dict for {key value} [dict get [scientificExecutionNodes] $id] {set ::GX::ui(computeNode,$key) $value}
}
proc ::GX::_computeNodeBrowse {f key} {
    set path [tk_getOpenFile -parent [winfo toplevel $f] -title {Select authentication file}]
    if {$path ne {}} {set ::GX::ui(computeNode,$key) $path}
}
proc ::GX::_computeNodeSave {f} {
    set descriptor {};foreach key {endpoint session_id ca_file client_cert client_key enabled} {dict set descriptor $key $::GX::ui(computeNode,$key)}
    if {[catch {scientificExecutionNodeRegister $::GX::ui(computeNode,node_id) $descriptor} reason]} {$f.status configure -text $reason;return 0}
    _computeNodeRefresh $f;$f.status configure -text {Node saved. Test the authenticated connection before selecting it as a destination.};return 1
}
proc ::GX::_computeNodeProbe {f} {
    if {![_computeNodeSave $f]} return
    set node [dict get [scientificExecutionNodes] $::GX::ui(computeNode,node_id)]
    set request [dict create node $node session_id [dict get $node session_id] operation capabilities arguments {}]
    $f.status configure -text {Contacting the authenticated compute node…}
    scriptJobAsync [list [runtimeToolResolve python] -B [file join $::GX::scriptDir core python gxtxt_remote_transport.py]] $request [list ::GX::_computeNodeProbeDone $f]
}
proc ::GX::_computeNodeProbeDone {f response} {
    if {![winfo exists $f]} return
    if {![dict get $response ok]} {$f.status configure -text "Node unavailable: [dict get $response error]";return}
    set result [dict get $response result];set providers {}
    foreach provider [dict get $result providers] {lappend providers "[dict get $provider provider_id] [dict get $provider version]: [expr {[dict get $provider available]?"available":"tool unavailable"}]"}
    $f.status configure -text "[dict get $result node_id] · [dict get $result os] / [dict get $result architecture] · [dict get $result cores] cores\n[join $providers \n]\nEffective Supervisor policy: [dict get $result policy]"
}
