# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::buildInstrumentationPage {} {
    variable cfg
    variable ch
    variable probe
    variable extra
    variable ui
    variable version
    # Instrumentation tab
    set f .top.nb.instr
    grid rowconfigure $f 1 -weight 1
    grid columnconfigure $f 0 -weight 1

    ttk::frame $f.scope
    ttk::frame $f.probes
    grid $f.scope -row 0 -column 0 -sticky ew -padx 5 -pady {5 8}
    grid $f.probes -row 1 -column 0 -sticky nsew -padx 5 -pady {0 5}

    grid columnconfigure $f.scope 1 -weight 1
    set row 0
    foreach {label key} {
        "Oscilloscope manufacturer" scope_manufacturer
        "Oscilloscope model" scope_model
        "Serial number" scope_serial
        "Firmware" scope_firmware
        "Memory depth" scope_memory_depth
        "Sample rate (annotation)" scope_sample_rate
        "Bandwidth limit" scope_bandwidth_limit
        "Coupling" scope_coupling
        "Oscilloscope notes" scope_notes
    } {
        addLabeledEntry $f.scope $row $label ::GX::cfg($key)
        incr row
    }

    grid columnconfigure $f.probes 0 -weight 0
    grid columnconfigure $f.probes 1 -weight 1
    grid columnconfigure $f.probes 2 -weight 1
    grid columnconfigure $f.probes 3 -weight 0
    grid columnconfigure $f.probes 4 -weight 0
    grid columnconfigure $f.probes 5 -weight 0

    foreach {c txt} {0 "Channel" 1 "Probe manufacturer" 2 "Model" 3 "Attenuation" 4 "Bandwidth" 5 "Coupling"} {
        ttk::label $f.probes.ph$c -text $txt
        grid $f.probes.ph$c -row 0 -column $c -padx 3 -pady {2 5} -sticky w
    }
    for {set i 1} {$i <= 8} {incr i} {
        ttk::label $f.probes.pl$i -textvariable ::GX::ch($i,scope)
        ttk::entry $f.probes.pm$i -textvariable ::GX::probe($i,manufacturer) -width 18
        ttk::entry $f.probes.pmod$i -textvariable ::GX::probe($i,model) -width 18
        ttk::entry $f.probes.pa$i -textvariable ::GX::probe($i,attenuation) -width 10
        ttk::entry $f.probes.pb$i -textvariable ::GX::probe($i,bandwidth) -width 12
        ttk::entry $f.probes.pc$i -textvariable ::GX::probe($i,coupling) -width 10
        grid $f.probes.pl$i -row $i -column 0 -padx 3 -pady 2 -sticky w
        grid $f.probes.pm$i -row $i -column 1 -padx 3 -pady 2 -sticky ew
        grid $f.probes.pmod$i -row $i -column 2 -padx 3 -pady 2 -sticky ew
        grid $f.probes.pa$i -row $i -column 3 -padx 3 -pady 2 -sticky w
        grid $f.probes.pb$i -row $i -column 4 -padx 3 -pady 2 -sticky w
        grid $f.probes.pc$i -row $i -column 5 -padx 3 -pady 2 -sticky w
    }

}
