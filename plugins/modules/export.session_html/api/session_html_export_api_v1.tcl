# GX-TXT Session HTML Export API v1
# SPDX-License-Identifier: GPL-3.0-or-later

namespace eval ::SessionHtmlExport {
    variable version 1.0.4
}

proc ::SessionHtmlExport::_moduleRoot {} {
    set descriptor [::GX::moduleField export.session_html descriptor ""]
    if {$descriptor eq ""} { error "Session HTML Export module descriptor is unavailable." }
    return [file dirname $descriptor]
}

proc ::SessionHtmlExport::export {destinationParent {makeZip 1}} {
    variable version
    if {![llength [info commands ::GX::sessionInspectionWriteSnapshot]]} { error "GX-TXT Session Inspection API v1 is unavailable." }
    set info [::GX::currentSessionInfo]
    if {![dict size $info]} { error "Open a Session before exporting HTML." }
    set session [dict get $info path]
    set sessionName [dict get $info name]
    set destinationParent [file normalize $destinationParent]
    file mkdir $destinationParent
    set target [file join $destinationParent "${sessionName}-html"]
    if {[file exists $target]} { error "HTML export destination already exists: $target" }
    set snapshot [file join $destinationParent ".gxtxt-html-snapshot-[pid]-[clock clicks].txt"]
    try {
        ::GX::sessionInspectionWriteSnapshot $snapshot $session
        set helper [file join [_moduleRoot] runtime session_html_export.py]
        if {![file isfile $helper]} { error "Session HTML exporter runtime is missing: $helper" }
        set renderer [file join $::GX::scriptDir services annotations plot_annotation_renderer.py]
        set cmd [list python3 $helper export --session $session --snapshot $snapshot --output $target --module-version $version --framework-version $::GX::version --annotation-renderer $renderer]
        if {$makeZip} { lappend cmd --zip }
        if {[catch {set out [exec {*}$cmd 2>@1]} err opts]} { return -options $opts $err }
    } finally {
        catch {file delete -force -- $snapshot}
    }
    set result [dict create]
    foreach line [split $out "\n"] {
        if {[string trim $line] eq ""} continue
        set p [string first "=" $line]
        if {$p < 1} continue
        dict set result [string range $line 0 [expr {$p-1}]] [string range $line [expr {$p+1}] end]
    }
    return $result
}

proc ::SessionHtmlExport::guiExport {} {
    source [file join [_moduleRoot] ui session_html_export_gui_v1.tcl]
    return [::SessionHtmlExport::UI::exportDialog]
}
