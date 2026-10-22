proc modulePause {ms} {after $ms [list set ::modulePauseDone 1];vwait ::modulePauseDone;update}
proc moduleTab {nb target} {
    for {set x 3} {$x<[winfo width $nb]} {incr x 6} {
        if {![catch {$nb index @$x,10} index] && [lindex [$nb tabs] $index] eq $target} {
            exec xdotool mousemove [expr {[winfo rootx $nb]+$x}] [expr {[winfo rooty $nb]+10}] click 1
            modulePause 200
            if {[$nb select] ne $target} {error {Native tab selection failed}}
            return
        }
    }
    error {Modules tab absent}
}
proc moduleSee {widget} {
    set viewport .top.nb.modules.cards.scroll
    for {set attempt 0} {$attempt<100} {incr attempt} {
        set y [winfo rooty $widget];set top [winfo rooty $viewport];set bottom [expr {$top+[winfo height $viewport]}]
        if {$y>=$top+5 && $y+[winfo height $widget]<=$bottom-5} {return}
        set button [expr {$y<$top?4:5}]
        # Native scrollbar arrows give one-unit precision near a row; the wheel
        # moves three units and can jump over the usable gap with large fonts.
        if {abs($y-$top)<240 || abs($y-$bottom)<240} {
            set bar .top.nb.modules.cards.bar
            set arrowY [expr {$button==4?[winfo rooty $bar]+5:[winfo rooty $bar]+[winfo height $bar]-5}]
            exec xdotool mousemove [expr {[winfo rootx $bar]+[winfo width $bar]/2}] $arrowY click 1
        } else {
            exec xdotool mousemove [expr {[winfo rootx $viewport]+25}] [expr {$top+40}] click $button
        }
        modulePause 40
    }
    error "Cannot expose widget with native wheel: $widget"
}
