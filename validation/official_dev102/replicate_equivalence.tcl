set prior [file normalize [lindex $argv 2]];set golden [file normalize [lindex $argv 3]]
source [file join [file dirname [info script]] .. official_dev099 project_common.tcl]
try {
    ::GX::openSessionPath $prior
    set f [open $golden];try {set expected [string trim [read $f]]} finally {close $f}
    set id replicate.gui_independent_yx.profile
    set names [dict keys [dict get $expected columns]]
    set stream [::GX::tableStreamOpenDataset $prior $id $names 4096]
    try {set actual [dict get [::GX::tableStreamNext $stream] values]} finally {::GX::tableStreamClose $stream}
    dict for {name values} [dict get $expected columns] {
        set observed [dict get $actual $name];set valid [expr {[llength $observed]==[llength $values]}]
        foreach x $values y $observed {
            if {[string tolower $x] in {nan -nan} && [string tolower $y] in {nan -nan}} continue
            if {[catch {expr {abs($x-$y)<=1e-12*max(1,abs($x))}} equal] || !$equal} {set valid 0;break}
        }
        check {$valid} "14 real Viewer canonical column $name equals the public scientific result"
        check {![catch {::GX::unitRegistryConversionPlan [dict get [::GX::datasetVariableV3ById $id $name] unit] [dict get $expected units $name]}]} "14 $name preserves its physical unit"
    }
    save result [dict create status PASS checks $checks dataset_id $id source_session $prior]
} on error {message options} {save result [dict create status FAIL checks $checks details [dict get $options -errorinfo]];puts stderr [dict get $options -errorinfo];exit 1}
exit
