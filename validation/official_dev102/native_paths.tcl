lassign $argv library out
if {[file exists $out]} {error {Output exists}};file mkdir $out
load [file normalize $library] Gx2dtcl
set scene [::GX::Native2D::core scene]
set checks {}
proc check {expression label} {if {![uplevel 1 [list expr $expression]]} {error "FAIL $label"};lappend ::checks $label;puts "PASS $label"}
try {
    set square [::GX::Native2D::core path_validate $scene {{0 0} {3 0} {3 2} {0 2}} 1]
    check {[dict get $square length]==10 && [dict get $square signed_area]==6} {Independent rectangle perimeter and signed area}
    set reverse [::GX::Native2D::core path_validate $scene {{0 2} {3 2} {3 0} {0 0}} 1]
    check {[dict get $reverse signed_area]==-6} {Reversed traversal preserves length and reverses oriented area}
    set open [::GX::Native2D::core path_validate $scene {{0 0} {2 0} {2 2} {1 2}} 0]
    check {[dict get $open length]==5 && [dict get $open closed]==0} {Returning open path remains a valid ordered path}
    check {[catch {::GX::Native2D::core path_validate $scene {{0 0} {2 2} {0 2} {2 0}} 1}]} {Self-intersecting contour refuses}
    check {[catch {::GX::Native2D::core path_validate $scene {{0 0} {2 0} {1 0}} 0}]} {Backtracking overlapping segment refuses}
    set report [dict create status PASS checks $checks]
} on error {message options} {set report [dict create status FAIL checks $checks details [dict get $options -errorinfo]];puts stderr [dict get $options -errorinfo]}
::GX::Native2D::core destroy $scene
set f [open [file join $out result.tcldict] w];puts $f $report;close $f
exit [expr {[dict get $report status] ne "PASS"}]
