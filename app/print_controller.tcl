# SPDX-License-Identifier: GPL-3.0-or-later
source [file join $::GX::scriptDir core tcl print_document_api_v1.tcl]
proc ::GX::choosePrintPdf {} {
    variable cfg; variable currentSession
    set init [expr {$currentSession ne "" ? [file join $currentSession report] : [pwd]}]
    set p [tk_getSaveFile -title "Print PDF" -initialdir $init -initialfile "GXTXT_plots.pdf" -defaultextension .pdf -filetypes {{PDF {.pdf}} {All {*}}}]
    if {$p ne ""} { set cfg(print_output_pdf) $p }
}

proc ::GX::composePdf_annotation_base {} {
    printStudioAddLegacy
    if {[winfo exists .top.nb.print]} {.top.nb select .top.nb.print}
    printStudioPreview
    return 1
}

proc ::GX::exportSelectedGraphs {} {
    variable cfg
    variable currentSession
    set imgs [selectedGraphPaths]; if {[llength $imgs] == 0} { tk_messageBox -message "No plot selected."; return }
    set d [tk_chooseDirectory -title "Server export folder / Samba share" -initialdir [expr {$cfg(export_dir) ne "" ? $cfg(export_dir) : [pwd]}]]
    if {$d eq ""} return
    set cfg(export_dir) $d
    foreach f $imgs {
        if {$currentSession ne "" && [string first $currentSession $f] == 0} {
            set rel [string range $f [expr {[string length $currentSession]+1}] end]
        } else {
            set rel [file tail $f]
        }
        set dst [file join $d $rel]
        file mkdir [file dirname $dst]
        file copy -force $f $dst
    }
    setStatus "Exported [llength $imgs] plots to $d preserving subfolders"
}

proc ::GX::exportPdf {} {printStudioExport}
proc ::GX::openPrintPdf {} {
    if {![printStudioDocumentReady 1]} {error {Update and review the current document first.}}
    set path [dict get $::GX::PrintStudio::state(document) pdf]
    if {[auto_execok xdg-open] ne {}} {exec xdg-open $path &}
}

source [file join $::GX::scriptDir app print_cups_controller.tcl]
source [file join $::GX::scriptDir app print_studio_controller.tcl]
