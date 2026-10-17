proc sourceModesAudit {} {
    source [file join $::root core tcl document_source_api_v1.tcl]
    source [file join $::root plugins modules viewer.html api html.tcl]
    foreach id {html xml} {
        set read [::GX::datasetDocumentRead $id];set sha [dict get $read sha256]
        set before [winfo children .]
        set original [::GX::datasetDocumentOpen $id]
        if {$id eq {html}} {::GX::viewerCommandInvoke $original view_source} else {$original.sourceButton invoke}
        set sources {}
        foreach window [winfo children .] {if {$window ni $before && [winfo exists $window.source.text]} {lappend sources $window}}
        gcheck {[llength $sources]==1} ${id}_actual_view_source_action
        set w [lindex $sources 0]
        gcheck {[$w.source.text cget -state] eq {disabled} && [::GX::sourceSurfaceGet $w.source] eq [dict get $read source]} ${id}_same_read_only_source_component
        guiWait {[dict exists $::GX::SourceSurface::state($w.source,model) engine]}
        gcheck {[::GX::sha256File [::GX::datasetResolvePath $::GX::currentSession $id]] eq $sha} ${id}_view_source_preserves_sha
        raise $w;after 300 {set ::sourceShot 1};vwait ::sourceShot;capture $w ${id}_shared_source_mode
    }
    record source_modes_gui PASS
}
if {[catch {sourceModesAudit} reason options]} {record source_modes_failure [dict get $options -errorinfo]}
