# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::buildExperimentPage {} {
    variable cfg
    variable ch
    variable probe
    variable extra
    variable ui
    variable version
    # Experiment tab
    set f .top.nb.exp
    grid columnconfigure $f 1 -weight 1
    set row 0
    foreach {label key} {
        "Project" project
        "Board / revision" board
        "Test type" test
        "Date" date
        "Remote control" remote
        "Button" button
        "Distance [cm]" distance_cm
        "P_GAIN [ohm]" p_gain_ohm
        "P_SENS [ohm]" p_sens_ohm
        "Supply [V]" supply_v
        "Notes" experiment_notes
    } {
        addLabeledEntry $f $row $label ::GX::cfg($key)
        incr row
    }
    ttk::separator $f.sep -orient horizontal
    grid $f.sep -row $row -column 0 -columnspan 3 -sticky ew -pady 8
    incr row
    ttk::label $f.exh1 -text "Extra field"
    ttk::label $f.exh2 -text "Value"
    grid $f.exh1 -row $row -column 0 -sticky e -padx 5
    grid $f.exh2 -row $row -column 1 -sticky w -padx 5
    incr row
    for {set i 1} {$i <= 8} {incr i} {
        ttk::entry $f.exk$i -textvariable ::GX::extra($i,key) -width 28
        ttk::entry $f.exv$i -textvariable ::GX::extra($i,value) -width 56
        grid $f.exk$i -row $row -column 0 -sticky e -padx 5 -pady 2
        grid $f.exv$i -row $row -column 1 -sticky ew -padx 5 -pady 2
        incr row
    }

}
