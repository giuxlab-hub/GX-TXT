# Source-level tests, not GX-TXT integration tests. Uses harmless local mocks.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX {}
proc ::GX::viewerBackendRegister {backend callback} {
    if {$backend ne "mathematics_explorer_tk"} {error "Unexpected backend ID"}
}
proc ::GX::modulePublicApiActivate {module api} {
    if {$module ni {math.numeric plot.dataset}} {error "Unexpected module activation"}
}
namespace eval ::GX::NumericAPIv1 {}
proc ::GX::NumericAPIv1::requireCapability {cap} {return 1}
proc ::GX::NumericAPIv1::octaveAvailable {} {return 1}
proc ::GX::NumericAPIv1::uniformGrid {start stop count options} {
    if {[dict get $options mode] ne "count"} {error "Wrong grid mode"}
    set values {}
    for {set i 0} {$i < $count} {incr i} {
        lappend values [expr {$start + ($stop-$start)*double($i)/($count-1)}]
    }
    return [dict create x $values]
}
proc ::GX::NumericAPIv1::_array {method a {b {}}} {
    set x [dict get $a value]
    set y {}
    if {$b ne ""} {set y [dict get $b value]}
    set n [expr {max([llength $x],[llength $y],1)}]
    set result {}
    for {set i 0} {$i < $n} {incr i} {
        set left [lindex $x [expr {[llength $x]==1?0:$i}]]
        set right 0
        if {$y ne ""} {set right [lindex $y [expr {[llength $y]==1?0:$i}]]}
        switch -- $method {
            add {set z [expr {$left+$right}]}
            subtract {set z [expr {$left-$right}]}
            multiply {set z [expr {$left*$right}]}
            divide {set z [expr {$left/$right}]}
            power {set z [expr {pow($left,$right)}]}
            sin {set z [expr {sin($left)}]}
            cos {set z [expr {cos($left)}]}
            negate {set z [expr {-$left}]}
            exp {set z [expr {exp($left)}]}
            default {error "Mock has no operation '$method'"}
        }
        lappend result $z
    }
    return [dict create values $result]
}
proc ::GX::NumericAPIv1::arrayUnary {method a {opts {}}} {return [_array $method $a]}
proc ::GX::NumericAPIv1::arrayBinary {method a b {opts {}}} {return [_array $method $a $b]}
proc ::GX::NumericAPIv1::differentiate {x y {opts {}}} {
    return [dict create dy_dx [lrepeat [llength $x] 1.0]]
}
proc ::GX::NumericAPIv1::integrate {x y {opts {}}} {return [dict create value 42]}

set root [file dirname [file dirname [file normalize [info script]]]]
foreach path [list [file join $root lib expression.tcl] [file join $root lib science.tcl] [file join $root ui mathematics_explorer_tk.tcl]] {
    set fp [open $path r];set text [read $fp];close $fp
    if {![info complete $text]} {error "Incomplete Tcl syntax in $path"}
}
source [file join $root api mathematics_explorer_api_v1.tcl]
proc assert {value what} {if {!$value} {error "FAIL: $what"}}
set s [::GX::MathematicsExplorer::initialState]
::GX::MathematicsExplorer::validateState $s
set ast [::GX::MathematicsExplorer::parseExpression {-x^2}]
assert [expr {[lindex $ast 0] eq "unary"}] {unary precedence}
set ast [::GX::MathematicsExplorer::parseExpression {2^3^2}]
assert [expr {[lindex $ast 0] eq "binary" && [lindex [lindex $ast 3] 0] eq "binary"}] {power right associativity}
foreach bad [list {x;exec id} {sin(x,3)} {[exec id]} {a**b} {exp(x} {unknown(x)} {1e309}] {
    assert [catch {::GX::MathematicsExplorer::parseExpression $bad}] "reject expression $bad"
}
set result [::GX::MathematicsExplorer::calculate $s]
assert [expr {[llength [dict get $result x]] == 301}] {grid count}
assert [expr {[llength [dict get $result series]] == 1}] {one enabled function}
assert [expr {[llength [dict get $result outputs f1]] == 301}] {function vector}
assert [expr {abs([lindex [dict get $result outputs f1] 150]) < 1e-12}] {sin at zero}
assert [expr {[::GX::MathematicsExplorer::integralOfFirst $result] == 42}] {integration public delegation}
dict set s derivative 1
set r2 [::GX::MathematicsExplorer::calculate $s]
assert [expr {[llength [dict get $r2 series]] == 2}] {derivative as extra series}
assert [expr {[llength [dict get $r2 outputs f1_derivative]] == 301}] {derivative public delegation}
dict set s samples 2000
assert [catch {::GX::MathematicsExplorer::validateState $s}] {sample limit}
puts "ISOLATED SOURCE TESTS: PASS (mocks; NOT GX-TXT integration)"
