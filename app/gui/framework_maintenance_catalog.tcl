# SPDX-License-Identifier: GPL-3.0-or-later
# Maintenance presents the existing Catalog and Documentation owners only.
namespace eval ::GX::MaintenanceCatalog {variable state;array set state {};variable serial 0}
proc ::GX::frameworkMaintenanceCatalogBuild {parent} {
    variable ::GX::MaintenanceCatalog::state
    variable ::GX::MaintenanceCatalog::serial
    set state($parent,serial) [incr serial]
    foreach {key value} {ticket {} poll {} scan {} presentation {} offset 0 total 0 query {} api {} provider {} surface host rows {} inspecting {} window {} message {Ready. File availability and renderer outcomes are reported separately.}} {set state($parent,$key) $value}
    ttk::notebook $parent.tabs
    ttk::frame $parent.status;ttk::frame $parent.manuals
    $parent.tabs add $parent.status -text {Database status}
    $parent.tabs add $parent.manuals -text {Manual inspection}
    pack $parent.tabs -fill both -expand 1
    ttk::frame $parent.status.tools
    ttk::button $parent.status.tools.reload -text {Update status} -command [list ::GX::MaintenanceCatalog::diagnostics $parent 0]
    ttk::button $parent.status.tools.verify -text {Verify sources and checksums} -command [list ::GX::MaintenanceCatalog::diagnostics $parent 1]
    ttk::button $parent.status.tools.refresh -text {Refresh / Reconcile} -command [list ::GX::MaintenanceCatalog::refresh $parent]
    pack $parent.status.tools.reload $parent.status.tools.verify $parent.status.tools.refresh -side left -padx 3 -pady 4
    pack $parent.status.tools -fill x
    text $parent.status.text -wrap word -state disabled -width 65 -height 18
    ttk::scrollbar $parent.status.scroll -command [list $parent.status.text yview]
    $parent.status.text configure -yscrollcommand [list $parent.status.scroll set]
    pack $parent.status.scroll -side right -fill y;pack $parent.status.text -fill both -expand 1
    set p $parent.manuals
    ttk::frame $p.filters
    foreach {name label width} {query Search 24 api {API ID} 28 provider Provider 26} {
        ttk::label $p.filters.${name}_label -text $label
        ttk::entry $p.filters.$name -width $width -textvariable ::GX::MaintenanceCatalog::state($parent,$name)
        grid $p.filters.${name}_label -row [expr {$name eq {query}?0:1}] -column [expr {$name eq {provider}?2:0}] -sticky w -padx 3
        grid $p.filters.$name -row [expr {$name eq {query}?0:1}] -column [expr {$name eq {provider}?3:1}] -sticky ew -padx 3 -pady 2
        bind $p.filters.$name <Return> [list ::GX::MaintenanceCatalog::search $parent]
    }
    ttk::combobox $p.filters.surface -state readonly -width 16 -values {host script_bridge cpp_sdk} -textvariable ::GX::MaintenanceCatalog::state($parent,surface)
    grid $p.filters.surface -row 0 -column 2 -sticky ew -padx 3
    ttk::button $p.filters.search -text Search -command [list ::GX::MaintenanceCatalog::search $parent]
    grid $p.filters.search -row 0 -column 3 -sticky e -padx 3
    grid columnconfigure $p.filters 1 -weight 1;grid columnconfigure $p.filters 3 -weight 1
    bind $p.filters.surface <<ComboboxSelected>> [list ::GX::MaintenanceCatalog::search $parent]
    pack $p.filters -fill x
    ttk::frame $p.actions
    foreach {name label callback} {inspect {Inspect selected} inspect page {Inspect page} page open {Open manual} open} {
        ttk::button $p.actions.$name -text $label -command [list ::GX::MaintenanceCatalog::$callback $parent]
        pack $p.actions.$name -side left -padx 3 -pady 4
    }
    pack $p.actions -fill x
    ttk::panedwindow $p.body -orient vertical
    ttk::frame $p.body.list;ttk::frame $p.body.details
    $p.body add $p.body.list -weight 1;$p.body add $p.body.details -weight 1
    ttk::treeview $p.tree -columns {api provider surface status} -show headings -height 7 -selectmode browse
    foreach {column title width} {api {API ID} 300 provider Provider 190 surface Surface 100 status {Manual status} 180} {$p.tree heading $column -text $title;$p.tree column $column -width $width -minwidth 70 -stretch 1}
    ttk::scrollbar $p.y -command [list $p.tree yview];ttk::scrollbar $p.x -orient horizontal -command [list $p.tree xview]
    $p.tree configure -yscrollcommand [list $p.y set] -xscrollcommand [list $p.x set]
    pack $p.x -in $p.body.list -side bottom -fill x;pack $p.y -in $p.body.list -side right -fill y;pack $p.tree -in $p.body.list -fill both -expand 1
    text $p.details -wrap word -state disabled -height 11 -width 65
    ttk::scrollbar $p.details_scroll -command [list $p.details yview];$p.details configure -yscrollcommand [list $p.details_scroll set]
    pack $p.details_scroll -in $p.body.details -side right -fill y;pack $p.details -in $p.body.details -fill both -expand 1
    pack $p.body -fill both -expand 1
    bind $p.tree <<TreeviewSelect>> [list ::GX::MaintenanceCatalog::inspect $parent]
    ttk::frame $p.pages
    ttk::button $p.pages.previous -text Previous -command [list ::GX::MaintenanceCatalog::move $parent -1]
    ttk::button $p.pages.next -text Next -command [list ::GX::MaintenanceCatalog::move $parent 1]
    pack $p.pages.previous -side left;pack $p.pages.next -side right;pack $p.pages -fill x
    ttk::label $parent.message -textvariable ::GX::MaintenanceCatalog::state($parent,message) -wraplength 850 -anchor w
    pack $parent.message -fill x -pady 4
    bind $parent.tabs <Destroy> [list ::GX::MaintenanceCatalog::dispose $parent %W]
    ::GX::MaintenanceCatalog::diagnostics $parent 0
    ::GX::MaintenanceCatalog::search $parent
    # Opening Maintenance during startup owns a normal initialization consumer;
    # the panel must populate when that snapshot becomes ready.
    $parent.status.tools.refresh state disabled
    set state($parent,ticket) [::GX::apiCatalogRequest [list ::GX::MaintenanceCatalog::received $parent $state($parent,serial)]]
    set state($parent,poll) [after 100 [list ::GX::MaintenanceCatalog::poll $parent $state($parent,serial)]]
    return $parent
}
proc ::GX::MaintenanceCatalog::exists {p} {variable state;expr {[winfo exists $p] && [info exists state($p,serial)]}}
proc ::GX::MaintenanceCatalog::text {widget value} {$widget configure -state normal;$widget delete 1.0 end;$widget insert end $value;$widget configure -state disabled}
proc ::GX::MaintenanceCatalog::format {value {indent {}} {depth 0}} {
    if {$depth>3 || [catch {dict size $value}] || ![dict size $value]} {return $value}
    set out {};dict for {key item} $value {
        set label [string map {_ { }} $key]
        if {$item ne {} && ![catch {dict size $item}] && [dict size $item]>1 && $depth<3} {append out "$indent$label:\n[format $item "$indent  " [expr {$depth+1}]]\n"} else {append out "$indent$label: $item\n"}
    };return $out
}
proc ::GX::MaintenanceCatalog::diagnostics {p verify} {
    variable state
    if {![exists $p]} return
    if {[catch {set result [::GX::apiCatalogDiagnostics $verify]} message]} {set state($p,message) "Catalog unavailable: $message";text $p.status.text $state($p,message);return}
    set status [dict get $result status]
    set state($p,message) "[dict get $status freshness] — [dict get $status progress]. [dict get $status error]"
    text $p.status.text [format $result]
}
proc ::GX::MaintenanceCatalog::refresh {p} {
    variable state
    if {![exists $p] || $state($p,ticket) ne {}} return
    set state($p,message) {Reconciling metadata. The running definition snapshot remains unchanged.}
    $p.status.tools.refresh state disabled
    set state($p,ticket) [::GX::apiCatalogRefresh [list ::GX::MaintenanceCatalog::received $p $state($p,serial)]]
    set state($p,poll) [after 100 [list ::GX::MaintenanceCatalog::poll $p $state($p,serial)]]
}
proc ::GX::MaintenanceCatalog::poll {p serial} {
    variable state
    if {![exists $p] || $state($p,serial)!=$serial} return
    set state($p,poll) {};diagnostics $p 0
    if {$state($p,ticket) ne {}} {set state($p,poll) [after 500 [list ::GX::MaintenanceCatalog::poll $p $serial]]}
}
proc ::GX::MaintenanceCatalog::received {p serial response} {
    variable state
    if {![exists $p] || $state($p,serial)!=$serial} return
    set state($p,ticket) {};if {$state($p,poll) ne {}} {after cancel $state($p,poll);set state($p,poll) {}}
    $p.status.tools.refresh state !disabled
    diagnostics $p 0
    if {![dict get $response ok]} {set state($p,message) "Reconciliation failed; previous snapshot retained. [dict get $response error]"} else {
        load $p
        if {[dict get $response result freshness] eq {pending_restart}} {set state($p,message) {Reconciliation complete. Restart the framework to adopt the staged catalog; the current snapshot is preserved.}}
    }
}
proc ::GX::MaintenanceCatalog::search {p} {
    variable state
    if {![exists $p]} return
    set state($p,offset) 0;load $p
}
proc ::GX::MaintenanceCatalog::move {p direction} {
    variable state
    if {![exists $p]} return
    set state($p,offset) [expr {max(0,$state($p,offset)+50*$direction)}];load $p
}
proc ::GX::MaintenanceCatalog::load {p} {
    variable state
    if {![exists $p]} return
    if {$state($p,scan) ne {}} {after cancel $state($p,scan);set state($p,scan) {}}
    set state($p,inspecting) {};set tree $p.manuals.tree
    if {[catch {set result [::GX::apiCatalogQuery [dict create query $state($p,query) api_id $state($p,api) provider_id $state($p,provider) surface $state($p,surface) offset $state($p,offset) limit 50]]} message]} {set state($p,message) "Query unavailable: $message";return}
    $tree delete [$tree children {}];set state($p,rows) {}
    foreach row [dict get $result rows] {
        set id [dict get $row id];dict set state($p,rows) $id $row
        set doc [dict get $row payload catalog_meta documentation_status]
        $tree insert {} end -id $id -values [list [dict get $row api_id] [dict get $row provider_id] [dict get $row surface] "indexed: $doc"]
    }
    set state($p,total) [dict get $result total]
    $p.manuals.pages.previous state [expr {$state($p,offset)>0?{!disabled}:{disabled}}]
    $p.manuals.pages.next state [expr {$state($p,offset)+50<$state($p,total)?{!disabled}:{disabled}}]
    set state($p,message) "[llength [dict get $result rows]] / $state($p,total) indexed records; offset $state($p,offset). Inspect to check actual files and presentation."
    text $p.manuals.details {}
}
proc ::GX::MaintenanceCatalog::selected {p} {
    variable state
    set id [lindex [$p.manuals.tree selection] 0]
    if {$id eq {} || ![dict exists $state($p,rows) $id]} {error {Select an API/provider record.}}
    set row [dict get $state($p,rows) $id]
    set provider [dict get $row provider_id]
    if {[dict get $row surface] eq {family}} {set provider $state($p,provider)}
    return [list $id $provider]
}
proc ::GX::MaintenanceCatalog::inspect {p} {
    variable state
    if {![exists $p]} return
    if {[catch {lassign [selected $p] id provider;set result [::GX::apiCatalogManualInspect $id $provider $state($p,window)]} message]} {set state($p,message) $message;return}
    show $p $id $result
}
proc ::GX::MaintenanceCatalog::show {p id result} {
    variable state
    if {[$p.manuals.tree exists $id]} {$p.manuals.tree set $id status [dict get $result status]}
    text $p.manuals.details [format $result]
    set presentation [dict get $result presentation state]
    if {[dict exists $result presentation correlated] && ![dict get $result presentation correlated] && $presentation ne {not_attempted}} {append presentation { (uncorrelated)}}
    set state($p,message) "[dict get $result api_id] / [dict get $result provider_id]: [dict get $result status]. Presentation: $presentation."
}
proc ::GX::MaintenanceCatalog::page {p} {
    variable state
    if {![exists $p]} return
    if {$state($p,scan) ne {}} {after cancel $state($p,scan)}
    set state($p,inspecting) [$p.manuals.tree children {}]
    set state($p,scan) [after idle [list ::GX::MaintenanceCatalog::scan $p $state($p,serial)]]
}
proc ::GX::MaintenanceCatalog::scan {p serial} {
    variable state
    if {![exists $p] || $state($p,serial)!=$serial} return
    set state($p,scan) {}
    if {![llength $state($p,inspecting)]} {set state($p,message) {Current page inspection complete. No manuals were opened.};return}
    set id [lindex $state($p,inspecting) 0];set state($p,inspecting) [lrange $state($p,inspecting) 1 end]
    set row [dict get $state($p,rows) $id];set provider [dict get $row provider_id]
    if {[dict get $row surface] eq {family}} {set provider $state($p,provider)}
    if {[catch {set result [::GX::apiCatalogManualInspect $id $provider]} message]} {$p.manuals.tree set $id status "unavailable: $message"} else {$p.manuals.tree set $id status [dict get $result status]}
    set state($p,message) "Inspecting bounded page: [llength $state($p,inspecting)] records remaining."
    set state($p,scan) [after 1 [list ::GX::MaintenanceCatalog::scan $p $serial]]
}
proc ::GX::MaintenanceCatalog::open {p} {
    variable state
    if {![exists $p]} return
    if {[catch {lassign [selected $p] id provider;set result [::GX::apiCatalogManualOpen $id $provider [winfo toplevel $p]]} message]} {set state($p,message) $message;return}
    show $p $id $result
    if {[dict exists $result window]} {
        set state($p,window) [dict get $result window]
        if {$state($p,presentation) ne {}} {after cancel $state($p,presentation)}
        set state($p,presentation) [after 250 [list ::GX::MaintenanceCatalog::presented $p $state($p,serial) $id [dict get $result provider_id] [dict get $result window]]]
    }
}
proc ::GX::MaintenanceCatalog::presented {p serial id provider window {attempts 0}} {
    if {![exists $p] || $::GX::MaintenanceCatalog::state($p,serial)!=$serial} return
    set ::GX::MaintenanceCatalog::state($p,presentation) {}
    if {[lindex [$p.manuals.tree selection] 0] ne $id} return
    if {![catch {set result [::GX::apiCatalogManualInspect $id $provider $window]}]} {
        show $p $id $result
        if {[dict get $result presentation state] eq {loading} && $attempts<60} {
            set ::GX::MaintenanceCatalog::state($p,presentation) [after 500 [list ::GX::MaintenanceCatalog::presented $p $serial $id $provider $window [expr {$attempts+1}]]]
        }
    }
}
proc ::GX::MaintenanceCatalog::dispose {p actual} {
    variable state
    if {$actual ni [list $p $p.tabs] || ![info exists state($p,serial)]} return
    if {$state($p,ticket) ne {}} {::GX::apiCatalogCancel $state($p,ticket)}
    foreach key {poll scan presentation} {if {$state($p,$key) ne {}} {after cancel $state($p,$key)}}
    array unset state "$p,*"
}
