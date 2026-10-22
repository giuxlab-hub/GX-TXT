source [file join $::root validation session_generator_dev109 common.tcl]
proc ackCompletion {title remaining} {
    set box .__tk__messagebox
    if {[winfo exists $box] && [wm title $box] eq $title} {
        record completion_[clock microseconds] [widgets $box]
        capture $box completion_[clock microseconds]
        click $box.ok
    } elseif {$remaining>0} {after 200 [list ackCompletion $title [expr {$remaining-1}]]}
}
proc chooseLocation {w label} {
    set choices [$w.project cget -values]
    set index [lsearch -exact $choices $label]
    if {$index<0} {error "Location not offered: $label"}
    click $w.project;settle
    exec xdotool key ctrl+Home
    for {set i 0} {$i<$index} {incr i} {exec xdotool key Down;update}
    exec xdotool key Return;settle
    check location_choice {[$w.project get] eq $label}
}
proc generateQA {} {
    set w .gxNewSession
    click $w.buttons.generate;settle
    nativeRow $w.generator.split.navigation.table [nodeFor $w {generator org.giuxlab.gxtxt.numerical_examples linear_regression}];settle
    set projectLabel {}
    foreach label [$w.project cget -values] {if {[string match {SYNTHETIC_GENERATOR_PROJECT *} $label]} {set projectLabel $label}}
    chooseLocation $w $projectLabel
    click $w.name
    exec xdotool key Home shift+End BackSpace
    exec xdotool type --clearmodifiers --delay 1 SYNTHETIC_GENERATOR_GUI_LINEAR
    settle
    capture $w real_generator_before
    after 400 [list ackCompletion {Generate Session} 100]
    click $w.generator.actions.generate;settle
    set path $::GX::currentSession
    check genuine_session {[file isfile [file join $path metadata session_generator.ini]] && [file isfile [file join $path raw linear_regression.csv]]}
    record genuine_session [list path $path project [::GX::projectCurrentId] source_sha256 [::GX::sha256File [file join $path raw linear_regression.csv]] provenance [::GX::parseIni [file join $path metadata session_generator.ini]]]
    capture . generated_session_open
}
proc manualQA {} {
    set w .gxNewSession
    chooseLocation $w {Standalone Session}
    click $w.buttons.generate;settle
    check reopen_no_stale_generator {[$w.generator.actions.generate instate disabled] && ![info exists ::GX::sessionGeneratorGui($w,selected_generator)]}
    click $w.name
    exec xdotool key Home shift+End BackSpace
    exec xdotool type --clearmodifiers --delay 1 SYNTHETIC_MANUAL_GUI_SESSION
    after 400 [list ackCompletion {New Session} 60]
    click $w.buttons.create;settle
    check manual_session {[file tail $::GX::currentSession] eq {SYNTHETIC_MANUAL_GUI_SESSION} && ![file exists [file join $::GX::currentSession metadata session_generator.ini]]}
    record manual_session [list path $::GX::currentSession]
}
nativeTab .top.nb Projects
click .top.nb.projects.toolbar.projectMenu
exec xdotool key Down Return
settle
check project_dialog {[winfo exists .gxProjectEditor]}
click .gxProjectEditor.name
exec xdotool type --clearmodifiers --delay 1 SYNTHETIC_GENERATOR_PROJECT
click .gxProjectEditor.buttons.ok;settle
record qa_projects [::GX::projectIds]
openNew generateQA
openNew manualQA
record generation_complete AUTHOR_GUI_GENERATION_COMPLETE
