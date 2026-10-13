# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::buildDatasetPage {} {
    variable cfg
    variable ch
    variable probe
    variable extra
    variable ui
    variable version
    # Channels tab
    set f .top.nb.channels
    foreach {c txt} {0 "Use" 1 "CSV column" 2 "Scope channel" 3 "Logical name"} {
        ttk::label $f.h$c -text $txt
        grid $f.h$c -row 0 -column $c -padx 5 -pady 6 -sticky w
    }
    grid columnconfigure $f 3 -weight 1
    for {set i 1} {$i <= 8} {incr i} {
        ttk::checkbutton $f.use$i -variable ::GX::ch($i,enabled)
        ttk::entry $f.col$i -textvariable ::GX::ch($i,column) -width 12
        ttk::entry $f.scope$i -textvariable ::GX::ch($i,scope) -width 16
        ttk::entry $f.name$i -textvariable ::GX::ch($i,name) -width 36
        grid $f.use$i -row $i -column 0 -padx 5 -pady 4
        grid $f.col$i -row $i -column 1 -padx 5 -pady 4 -sticky w
        grid $f.scope$i -row $i -column 2 -padx 5 -pady 4 -sticky w
        grid $f.name$i -row $i -column 3 -padx 5 -pady 4 -sticky ew
    }
    ttk::label $f.note -text "CSV columns are 1-based. The logical name is used in files and subsequent analyses." -foreground #555555
    grid $f.note -row 10 -column 0 -columnspan 4 -sticky w -padx 5 -pady 8

}
