# Pure public admission contract: no Session, Native scene or GUI is created.
lassign $argv root output epoch
if {[llength $argv]!=3 || $epoch ni {before after} || [file exists $output]} {
    error {Usage: planner.tcl FRAMEWORK NEW_OUTPUT before|after}
}
file mkdir $output
set argv0 __coordinate_metric421_source_only__
source [file join $root gxtxt_pipeline.tcl]
set records {}
set mismatches {}
foreach unit {°C unknown px dB} {
    set strictCode [catch {::GX::unitRegistryHomogeneousCoordinatePlan $unit $unit} strictResult]
    dict set records strict_$unit [dict create code $strictCode result $strictResult]
    if {!$strictCode} {lappend mismatches [list strict_basis_must_reject $unit]}
    foreach method {x path geometry} {
        set code [catch {::GX::native2DComparisonFrame $method [list $unit $unit] [list $unit $unit]} result]
        dict set records ${method}_$unit [dict create code $code result $result]
        set expected [expr {$epoch eq {after} && $method ne {x}}]
        if {$code!=$expected} {lappend mismatches [list expected_admission $method $unit $expected $code]}
    }
}
# Legacy unlabelled numeric inspection remains distinct from physical validity.
foreach method {x path geometry} {
    set code [catch {::GX::native2DComparisonFrame $method [list {} {}] [list {} {}]} result]
    dict set records ${method}_undeclared [dict create code $code result $result]
    if {$code || [dict get $result output_units] ne [list {} {}]} {
        lappend mismatches [list legacy_numeric_inspection $method]
    }
}
foreach {name reference target options expectedMatrix} {
    lengths {mm cm} {cm mm} {output_units {mm mm}} {1.0 0.0 0.0 10.0 0.0 0.0}
    volts {mV mV} {V V} {output_units {V V}} {0.001 0.0 0.0 0.001 0.0 0.0}
    dimensionless {1 1} {1 1} {} {1.0 0.0 0.0 1.0 0.0 0.0}
    kelvin {K K} {K K} {} {1.0 0.0 0.0 1.0 0.0 0.0}
} {
    foreach method {path geometry} {
        set code [catch {::GX::native2DComparisonFrame $method $reference $target $options} result]
        dict set records ${method}_$name [dict create code $code result $result]
        if {$code} {
            lappend mismatches [list valid_frame $method $name $result]
        } else {
            foreach actual [dict get $result reference_matrix] expected $expectedMatrix {
                if {abs($actual-$expected)>1e-14} {lappend mismatches [list reference_scale $method $name $actual $expected]}
            }
        }
    }
}
foreach method {path geometry} {
    set code [catch {::GX::native2DComparisonFrame $method {V mA} {V mA}} result]
    dict set records ${method}_heterogeneous [dict create code $code result $result]
    if {!$code} {lappend mismatches [list unlike_physical_axes $method]}
}
set receipt [dict create epoch $epoch cases $records mismatches $mismatches current_Session $::GX::currentSession scope {Constructed pure public planner admission, no Dataset/GUI/scientific Session acceptance}]
set stream [open [file join $output REPORT.tcldict] {WRONLY CREAT EXCL}]
try {puts -nonewline $stream $receipt} finally {close $stream}
if {[llength $mismatches]} {puts stderr [list FAILED $mismatches];exit 1}
puts [list status [expr {$epoch eq {before}?{BASELINE_INCONSISTENT_PHYSICAL_ADMISSION_REPRODUCED}:{SCOPED_PUBLIC_FRAME_CONTRACT_PASS}}] observations [dict size $records] current_Session $::GX::currentSession]
