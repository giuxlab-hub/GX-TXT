# Desktop adapter for Session HTML Export. Loaded only by guiExport.
# SPDX-License-Identifier: GPL-3.0-or-later

namespace eval ::SessionHtmlExport::UI {}

proc ::SessionHtmlExport::UI::exportDialog {} {
    package require Tk
    set info [::GX::currentSessionInfo]
    if {![dict size $info]} { tk_messageBox -icon info -title "Session HTML Export" -message "Open a Session before exporting HTML."; return }
    set initial [expr {[info exists ::GX::cfg(export_dir)] && [file isdirectory $::GX::cfg(export_dir)] ? $::GX::cfg(export_dir) : [file dirname [dict get $info path]]}]
    set dest [tk_chooseDirectory -title "Choose folder for Session HTML export" -initialdir $initial]
    if {$dest eq ""} return
    if {[catch {set r [::SessionHtmlExport::export $dest 1]} err]} { tk_messageBox -icon error -title "HTML export failed" -message $err; return }
    set msg "Read-only HTML Session export created:\n[dict get $r directory]\n\nOpen index.html directly in a browser. No web server or internet connection is required."
    if {[dict exists $r zip] && [dict get $r zip] ne ""} { append msg "\n\nZIP: [dict get $r zip]" }
    tk_messageBox -icon info -title "Session HTML Export" -message $msg
}
