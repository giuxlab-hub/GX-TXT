source [file join $::root validation session_generator_dev109 common.tcl]
proc dragSash {split fraction} {
    set x [expr {[winfo rootx $split]+[$split sashpos 0]+2}]
    set y [expr {[winfo rooty $split]+[winfo height $split]/2}]
    set target [expr {[winfo rootx $split]+int($fraction*[winfo width $split])}]
    exec xdotool mousemove $x $y mousedown 1 mousemove $target $y mouseup 1
    settle
}
proc geometryFinal {} {
    set w .gxNewSession
    click $w.buttons.generate;settle
    set t $w.generator.split.navigation.table
    set bs $w.generator.split
    set ms $w.manager.split
    set lib {}
    foreach id [::GX::sessionGeneratorLibraryIds] {if {[string match user.synthetic-qa-library* $id]} {set lib $id}}
    check long_fixture_cold {$lib ne {}}
    nativeRow $t [nodeFor $w [list library $lib]];settle
    exec xdotool key Left;settle
    dragSash $bs .60
    set browserRatio [expr {double([$bs sashpos 0])/[winfo width $bs]}]
    capture $w final_browser_long
    click $w.generator.actions.manage;settle
    dragSash $ms .46
    set managerRatio [expr {double([$ms sashpos 0])/[winfo width $ms]}]
    capture $w final_manager_normal
    click $w.manager.top.hide;settle
    check long_browser_ratio {abs(double([$bs sashpos 0])/[winfo width $bs]-$browserRatio)<.01}
    check long_collapse_persist {![$t item [nodeFor $w [list library $lib]] -open]}
    exec xdotool windowsize [wm frame $w] 680 520
    settle
    record final_narrow_browser [list window [wm geometry $w] tree [winfo geometry $t] details [winfo geometry $w.generator.split.description.info]]
    check final_narrow_panels {[winfo width $t]>180 && [winfo width $w.generator.split.description.info]>180}
    set narrowRatio [expr {double([$bs sashpos 0])/[winfo width $bs]}]
    capture $w final_browser_narrow_long
    click $w.generator.actions.manage;settle
    check long_manager_ratio {abs(double([$ms sashpos 0])/[winfo width $ms]-$managerRatio)<.01}
    capture $w final_manager_narrow_long
    click $w.manager.top.hide;settle
    check narrow_long_browser_ratio {abs(double([$bs sashpos 0])/[winfo width $bs]-$narrowRatio)<.01}
    check narrow_long_identity {[selectedSpec $w] eq [list library $lib]}
    check narrow_long_disabled {[$w.generator.actions.generate instate disabled]}
    click $w.buttons.cancel
    record final_geometry_complete AUTHOR_GUI_FINAL_GEOMETRY_COMPLETE
}
openNew geometryFinal
