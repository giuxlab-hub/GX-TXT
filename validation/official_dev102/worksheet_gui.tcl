source [file join [file dirname [info script]] .. official_dev099 workspace_common.tcl]
if {$::env(DISPLAY) ne {:1}} {error {Actual Debian DISPLAY :1 required}}
set argv {};::GX::main
proc pointer {w x y} {exec xdotool mousemove --sync [expr {[winfo rootx $w]+int($x)}] [expr {[winfo rooty $w]+int($y)}];pause 60}
proc drag {w x1 y1 x2 y2} {pointer $w $x1 $y1;exec xdotool mousedown 1;pause 80;for {set i 1} {$i<=5} {incr i} {pointer $w [expr {$x1+($x2-$x1)*$i/5.}] [expr {$y1+($y2-$y1)*$i/5.}]};exec xdotool mouseup 1;pause 250}
proc run {} {
    workspaceSeed
    set w [::GX::viewerOpen viewer.scientific_worksheet scientific_worksheet {workspace_id new}];pause 500
    proc model {method args} {tailcall ::GX::ScientificWorksheet::$method {*}$args}
    set b [::GX::ScientificWorksheet::UI::book $w]
    foreach {a v} {A1 4 A2 5 A3 6} {set b [model setCell $b $a $v]}
    ::GX::ScientificWorksheet::UI::applyBook $w $b {Seed reference values};pause
    set g [::GX::ScientificWorksheet::UI::grid $w]
    check {[dict get [$g receipt] rows]<200 && [dict get [$g receipt] columns]<30} {Actual native scroll range starts compact}
    lassign [$g bbox 1 1] x y cw rh;lassign [$g bbox 3 1] x3 y3
    drag $g [expr {$x+20}] [expr {$y+10}] [expr {$x3+20}] [expr {$y3+10}]
    check {[::GX::ScientificWorksheet::UI::selection $w] eq {A1 A3}} {Native pointer selects the whole three-row seed}
    lassign [$g bbox 6 1] x6 y6
    drag $g [expr {$x3+$cw-2}] [expr {$y3+$rh-2}] [expr {$x6+$cw-2}] [expr {$y6+$rh-2}]
    set b [::GX::ScientificWorksheet::UI::book $w]
    check {[dict get [model value $b A4] value]==7 && [dict get [model value $b A6] value]==9} {Actual fill-handle drag continues 7,8,9}
    ::GX::ScientificWorksheet::UI::navigate $w undo;pause
    check {![dict exists [::GX::ScientificWorksheet::UI::book $w] cells A4]} {Native fill is one reversible History transaction}
    ::GX::ScientificWorksheet::UI::navigate $w redo;pause
    lassign [$g bbox 2 1] x2 y2 cw rh
    drag $g 20 [expr {$y2+$rh-1}] 20 [expr {$y2+$rh+32}]
    set b [::GX::ScientificWorksheet::UI::book $w]
    check {[dict exists $b row_heights 2] && [dict get $b row_heights 2]>50 && ![dict exists $b row_heights 3]} {Actual native header drag resizes row 2 independently}
    set expectedHeight [dict get $b row_heights 2]
    lassign [$g bbox 2 1] x2 y2 cw actualHeight
    check {$actualHeight==$expectedHeight} {Native bbox follows actual variable row geometry}
    ::GX::ScientificWorksheet::UI::goto $w H1;pause
    lassign [$g bbox 1 8] hx hy hw hh
    drag $g [expr {$hx+$hw-1}] 12 [expr {$hx+$hw+30}] 12
    set b [::GX::ScientificWorksheet::UI::book $w]
    check {[dict exists $b column_widths 8] && [dict get $b column_widths 8]>130} {Existing native column drag now persists in the Workbook}
    set id [::GX::ScientificWorksheet::UI::save $w];set b [model load $id]
    check {[dict get $b row_heights 2]==$expectedHeight && [dict get $b column_widths 8]>130} {Save and public reopen retain independent row/column sizes}
    exec import -window [winfo id $w] [file join $::out native_grid.png]
    check {[sha $::source] eq $::sourceSha} {Canonical source payload remains unchanged}
    check {![info exists ::bgfailed]} {No native/Tk background errors}
    save result [dict create status PASS checks $::checks session $::session document_id $id grid_receipt [$g receipt]]
}
set failed {};set done 0
after 500 {if {[catch {run} message options]} {set ::failed [dict get $options -errorinfo];save result [dict create status FAIL checks $::checks details $::failed];puts stderr $::failed};catch {destroy .};set ::done 1}
vwait done
exit [expr {$failed ne {}}]
