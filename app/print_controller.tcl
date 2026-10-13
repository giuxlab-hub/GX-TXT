# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::choosePrintPdf {} {
    variable cfg; variable currentSession
    set init [expr {$currentSession ne "" ? [file join $currentSession report] : [pwd]}]
    set p [tk_getSaveFile -title "Print PDF" -initialdir $init -initialfile "GXTXT_plots.pdf" -defaultextension .pdf -filetypes {{PDF {.pdf}} {All {*}}}]
    if {$p ne ""} { set cfg(print_output_pdf) $p }
}

proc ::GX::composePdf_annotation_base {} {
    variable cfg; variable scriptDir; variable currentSession; variable ui
    set imgs [selectedGraphPaths]
    if {[llength $imgs] == 0} { tk_messageBox -icon error -title "GX-TXT" -message "Select at least one plot in the Plots tab."; return 0 }
    if {$cfg(print_output_pdf) eq ""} {
        if {$currentSession eq ""} { set cfg(print_output_pdf) [file join [pwd] GXTXT_grafici.pdf] } else { set cfg(print_output_pdf) [file join $currentSession report GXTXT_grafici.pdf] }
    }
    set py [file join $scriptDir services printing gxtxt_compose_pdf.py]
    set cmd [list [runtimeToolRequired python] $py --output $cfg(print_output_pdf) --page $cfg(print_page) --orientation $cfg(print_orientation) --rows $cfg(print_rows) --cols $cfg(print_cols) --margin-mm $cfg(print_margin_mm) --gap-mm $cfg(print_gap_mm) --title $cfg(print_title) --captions $cfg(print_captions)]
    set cmd [concat $cmd $imgs]
    set ui(printStatus) "Generazione PDF..."
    update idletasks
    if {[catch {exec {*}$cmd 2>@1} out]} { set ui(printStatus) "ERROR: $out"; tk_messageBox -icon error -title "GX-TXT PDF" -message $out; return 0 }
    set qstatus "qpdf unavailable: structural validation not performed"
    if {![catch {set qpdf [runtimeToolResolve qpdf]}] && $qpdf ne ""} {
        if {[catch {exec $qpdf --check $cfg(print_output_pdf) 2>@1} qout]} { set ui(printStatus) "PDF created, but qpdf reports an error: $qout"; return 0 }
        set qstatus "Verifica qpdf: OK"
    }
    set ui(printStatus) "$out\n$qstatus\n$cfg(print_output_pdf)"
    catch {refreshGraphs}
    return 1
}

proc ::GX::discoverPrinters {} {
    variable cfg; variable ui
    if {![info exists ui(printerCombo)] || ![winfo exists $ui(printerCombo)]} return
    set printers {}
    if {[auto_execok lpstat] ne ""} {
        if {![catch {exec lpstat -e} out]} {
            foreach l [split $out "\n"] { set l [string trim $l]; if {$l ne ""} { lappend printers $l } }
        }
        if {[llength $printers] == 0 && ![catch {exec lpstat -a} out]} {
            foreach l [split $out "\n"] { set l [string trim $l]; if {$l ne ""} { lappend printers [lindex $l 0] } }
        }
        if {![catch {exec lpstat -d} dout]} {
            if {[regexp {:\s*(\S+)\s*$} $dout -> def] && [string trim $cfg(print_printer)] eq ""} { set cfg(print_printer) $def }
        }
    }
    set printers [lsort -unique $printers]
    $ui(printerCombo) configure -values $printers
    if {[llength $printers]} {
        if {$cfg(print_printer) eq "" || [lsearch -exact $printers $cfg(print_printer)] < 0} {
            if {[info exists def] && [lsearch -exact $printers $def] >= 0} { set cfg(print_printer) $def } else { set cfg(print_printer) [lindex $printers 0] }
        }
    } else {
        set cfg(print_printer) ""
    }
    refreshPrinterOptions
}

proc ::GX::refreshPrinterOptions {} {
    variable cfg; variable ui
    if {![info exists ui(printerOptions)]} return
    set w $ui(printerOptions); $w configure -state normal; $w delete 1.0 end
    set p [string trim $cfg(print_printer)]
    if {$p eq ""} { $w insert end "No printer configured/selected.\n" } else {
        $w insert end "Printer: $p\n"
        if {![catch {exec lpstat -p $p} st]} { $w insert end "$st\n\n" }
        if {![catch {exec lpoptions -p $p -l} op]} { $w insert end "$op\n" } else { $w insert end "CUPS options unavailable: $op\n" }
    }
    $w configure -state disabled
}

proc ::GX::printPdf {} {
    variable cfg; variable ui
    if {$cfg(print_output_pdf) eq "" || ![file isfile $cfg(print_output_pdf)]} { if {![composePdf]} return }
    if {[string trim $cfg(print_printer)] eq ""} { tk_messageBox -icon error -title "GX-TXT" -message "Select a printer."; return }
    set cmd [list lp -d $cfg(print_printer) -n $cfg(print_copies)]
    switch -- $cfg(print_duplex) {
        simplex { lappend cmd -o sides=one-sided }
        long { lappend cmd -o sides=two-sided-long-edge }
        short { lappend cmd -o sides=two-sided-short-edge }
    }
    lappend cmd $cfg(print_output_pdf)
    if {[catch {exec {*}$cmd 2>@1} out]} { set ui(printStatus) "PRINT ERROR: $out"; tk_messageBox -icon error -title "GX-TXT Print" -message $out } else { set ui(printStatus) "Sent to $cfg(print_printer): $out" }
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

proc ::GX::exportPdf {} {
    variable cfg
    if {$cfg(print_output_pdf) eq "" || ![file isfile $cfg(print_output_pdf)]} { if {![composePdf]} return }
    set d [tk_chooseDirectory -title "PDF export folder" -initialdir [expr {$cfg(export_dir) ne "" ? $cfg(export_dir) : [pwd]}]]
    if {$d eq ""} return
    set cfg(export_dir) $d
    file copy -force $cfg(print_output_pdf) [file join $d [file tail $cfg(print_output_pdf)] ]
    setStatus "PDF exported to $d"
}

proc ::GX::openPrintPdf {} {
    variable cfg
    if {$cfg(print_output_pdf) eq "" || ![file isfile $cfg(print_output_pdf)]} { return }
    if {[auto_execok xdg-open] ne ""} { catch {exec xdg-open $cfg(print_output_pdf) &} }
}
