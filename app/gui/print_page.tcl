# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::buildPrintPage {} {
    variable cfg
    variable ch
    variable probe
    variable extra
    variable ui
    variable version
    # Print / PDF tab
    set f .top.nb.print
    grid columnconfigure $f 1 -weight 1
    grid rowconfigure $f 13 -weight 1
    set row 0
    ttk::label $f.pl -text "Paper size"
    ttk::combobox $f.p -textvariable ::GX::cfg(print_page) -values {A4 A3 LETTER} -state readonly -width 14
    grid $f.pl -row $row -column 0 -sticky e -padx 5 -pady 3; grid $f.p -row $row -column 1 -sticky w -padx 5 -pady 3; incr row
    ttk::label $f.ol -text "Orientation"
    ttk::combobox $f.o -textvariable ::GX::cfg(print_orientation) -values {portrait landscape} -state readonly -width 14
    grid $f.ol -row $row -column 0 -sticky e -padx 5 -pady 3; grid $f.o -row $row -column 1 -sticky w -padx 5 -pady 3; incr row
    foreach {label key width} {
        "Rows per page" print_rows 10
        "Colonne per pagina" print_cols 10
        "Margin [mm]" print_margin_mm 10
        "Plot spacing [mm]" print_gap_mm 10
        "PDF title" print_title 44
    } {
        addLabeledEntry $f $row $label ::GX::cfg($key) $width; incr row
    }
    ttk::checkbutton $f.cap -text "Caption with filename below each plot" -variable ::GX::cfg(print_captions)
    grid $f.cap -row $row -column 1 -sticky w -padx 5 -pady 3; incr row
    ttk::label $f.outl -text "PDF output"
    ttk::entry $f.out -textvariable ::GX::cfg(print_output_pdf) -width 70
    ttk::button $f.outb -text "Choose..." -command ::GX::choosePrintPdf
    grid $f.outl -row $row -column 0 -sticky e -padx 5; grid $f.out -row $row -column 1 -sticky ew -padx 5; grid $f.outb -row $row -column 2 -padx 5; incr row
    ttk::frame $f.pdfbuttons
    ttk::button $f.pdfbuttons.make -text "CREATE PDF FROM SELECTED PLOTS" -command ::GX::composePdf
    ttk::button $f.pdfbuttons.open -text "Open PDF" -command ::GX::openPrintPdf
    ttk::button $f.pdfbuttons.export -text "Export PDF..." -command ::GX::exportPdf
    pack $f.pdfbuttons.make $f.pdfbuttons.open $f.pdfbuttons.export -side left -padx 4
    grid $f.pdfbuttons -row $row -column 0 -columnspan 3 -sticky w -padx 5 -pady 6; incr row
    ttk::separator $f.sep -orient horizontal
    grid $f.sep -row $row -column 0 -columnspan 3 -sticky ew -pady 7; incr row
    ttk::label $f.prl -text "CUPS printer"
    ttk::combobox $f.pr -textvariable ::GX::cfg(print_printer) -state readonly -width 38
    ttk::button $f.prref -text "Autodiscovery / aggiorna" -command ::GX::discoverPrinters
    grid $f.prl -row $row -column 0 -sticky e -padx 5; grid $f.pr -row $row -column 1 -sticky w -padx 5; grid $f.prref -row $row -column 2 -padx 5; incr row
    set ui(printerCombo) $f.pr
    bind $f.pr <<ComboboxSelected>> {::GX::refreshPrinterOptions}
    ttk::label $f.cl -text "Copie"; ttk::spinbox $f.c -from 1 -to 99 -textvariable ::GX::cfg(print_copies) -width 8
    grid $f.cl -row $row -column 0 -sticky e -padx 5; grid $f.c -row $row -column 1 -sticky w -padx 5; incr row
    ttk::label $f.dl -text "Fronte/retro"
    ttk::combobox $f.d -textvariable ::GX::cfg(print_duplex) -values {auto simplex long short} -state readonly -width 14
    grid $f.dl -row $row -column 0 -sticky e -padx 5; grid $f.d -row $row -column 1 -sticky w -padx 5; incr row
    ttk::button $f.print -text "SEND PDF TO PRINTER" -command ::GX::printPdf
    grid $f.print -row $row -column 1 -sticky w -padx 5 -pady 6; incr row
    set ui(printStatus) "PDF composition and printing are performed on the server."
    ttk::label $f.st -textvariable ::GX::ui(printStatus) -wraplength 900 -justify left
    grid $f.st -row $row -column 0 -columnspan 3 -sticky ew -padx 5 -pady 4; incr row
    text $f.options -wrap none -height 10 -font TkFixedFont -state disabled
    grid $f.options -row $row -column 0 -columnspan 3 -sticky nsew -padx 5 -pady 5
    grid rowconfigure $f $row -weight 1
    set ui(printerOptions) $f.options

}
