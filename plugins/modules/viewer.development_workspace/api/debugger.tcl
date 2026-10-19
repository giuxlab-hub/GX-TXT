# SPDX-License-Identifier: GPL-3.0-or-later
# Presentation client of the trusted Development/Script Job/GDB owner.
namespace eval ::GX::ViewerDevelopmentWorkspace {variable debug;array set debug {request {} poll {} token {} sequence -1 generation 0 state IDLE frame 0 status {Debug admitted C++ source with real GDB/MI.} snapshot {} visible 1}}
proc ::GX::ViewerDevelopmentWorkspace::debugMount {w} {
    variable debug
    menu $w.menus.view -tearoff 0;$w.menus insert 2 cascade -label View -underline 0 -menu $w.menus.view
    foreach {id label} {debug {Debugger toolbar} stack {Call Stack} variables Variables output {Build / runtime output} diagnostics Diagnostics} {
        set debug(show,$id) 1
        $w.menus.view add checkbutton -label $label -variable ::GX::ViewerDevelopmentWorkspace::debug(show,$id) -command [list ::GX::ViewerDevelopmentWorkspace::debugView $id]
    }
    ttk::frame $w.debugbar -padding 3
    pack $w.debugbar -after $w.toolbar -fill x -padx 5
    foreach {id label asset command} {run Run play {request run} start {Start Debug} play debugStart continue Continue play {debugControl continue} pause Pause pause {debugControl pause} into {Step Into} step_into {debugControl into} over {Step Over} step_over {debugControl over} out {Step Out} step_out {debugControl out} stop Stop stop debugStop} {
        ttk::button $w.debugbar.$id -text $label -width 0 -command [list ::GX::ViewerDevelopmentWorkspace::safe {*}$command]
        set a [::GX::viewerGuiIconImport [file join $::GX::scriptDir core assets icons $asset.svg] $label Debugger GPL-3.0-or-later]
        ::GX::uiFieldIconApply $w.debugbar.$id {presentation icon_text icon_position left icon_size 16 icon_spacing 4} $a
        pack $w.debugbar.$id -side left -padx 2
        bind $w.debugbar.$id <Enter> [list ::GX::plotsToolbarTipSchedule $w.debugbar.$id $label]
        bind $w.debugbar.$id <Leave> ::GX::plotsToolbarTipHide
    }
    set debug(full_toolbar_width) 0
    foreach widget [winfo children $w.debugbar] {incr debug(full_toolbar_width) [expr {[winfo reqwidth $widget]+8}]}
    bind $w.debugbar <Configure> [list ::GX::ViewerDevelopmentWorkspace::debugLayout $w.debugbar %w]
    foreach {id title columns} {stack {Call Stack} {level function file line} variables Variables {name type value}} {
        ttk::frame $w.bottom.$id
        ttk::treeview $w.bottom.$id.tree -columns $columns -show headings -height 6 -selectmode browse
        foreach col $columns {$w.bottom.$id.tree heading $col -text [string totitle $col];$w.bottom.$id.tree column $col -width [expr {$col in {line level}?55:200}] -minwidth 35 -stretch 1}
        ttk::scrollbar $w.bottom.$id.scroll -command [list $w.bottom.$id.tree yview]
        $w.bottom.$id.tree configure -yscrollcommand [list $w.bottom.$id.scroll set]
        pack $w.bottom.$id.scroll -side right -fill y;pack $w.bottom.$id.tree -fill both -expand 1
        $w.bottom add $w.bottom.$id -text $title
    }
    bind $w.bottom.stack.tree <<TreeviewSelect>> ::GX::ViewerDevelopmentWorkspace::debugFrame
    ttk::label $w.debugstatus -textvariable ::GX::ViewerDevelopmentWorkspace::debug(status) -anchor w -padding 4
    pack $w.debugstatus -after $w.debugbar -fill x
    bind $w <Control-F5> {::GX::ViewerDevelopmentWorkspace::safe request run;break}
    bind $w <F5> {::GX::ViewerDevelopmentWorkspace::safe debugStart;break}
    bind $w <F10> {::GX::ViewerDevelopmentWorkspace::safe debugControl over;break}
    bind $w <F11> {::GX::ViewerDevelopmentWorkspace::safe debugControl into;break}
    bind $w <Shift-F11> {::GX::ViewerDevelopmentWorkspace::safe debugControl out;break}
    bind $w <Shift-F5> {::GX::ViewerDevelopmentWorkspace::safe debugStop;break}
    bind $w <Destroy> +[list ::GX::ViewerDevelopmentWorkspace::debugDestroyed %W]
    debugButtons
}
proc ::GX::ViewerDevelopmentWorkspace::debugLayout {frame width} {
    variable debug
    set presentation [expr {$width<$debug(full_toolbar_width) ? {icon_only} : {icon_text}}]
    foreach widget [winfo children $frame] {
        if {![dict exists $::GX::ViewerGui::iconBindings $widget]} continue
        set record [dict get $::GX::ViewerGui::iconBindings $widget]
        set properties [dict get $record properties];dict set properties presentation $presentation
        ::GX::uiFieldIconApply $widget $properties [dict get $record asset] [dict get $record catalog]
    }
    ::GX::uiFieldControlsLayout $frame $width
}
proc ::GX::ViewerDevelopmentWorkspace::debugView {id} {
    variable debug;set w .gxViewerDevelopment
    if {$id eq {debug}} {
        if {$debug(show,debug)} {pack $w.debugbar -after $w.toolbar -fill x -padx 5;pack $w.debugstatus -after $w.debugbar -fill x} else {pack forget $w.debugbar $w.debugstatus}
    } elseif {$debug(show,$id)} {$w.bottom add $w.bottom.$id} else {$w.bottom hide $w.bottom.$id}
}
proc ::GX::ViewerDevelopmentWorkspace::debugButtons {} {
    variable debug;variable s
    if {![winfo exists .gxViewerDevelopment.debugbar]} return
    set active [expr {$debug(request) ne {}}];set paused [expr {$debug(state) eq {PAUSED}}]
    foreach id {run start continue pause into over out stop} {
        set enabled [expr {$id eq {stop}?$active:($id eq {pause}?($active&&$debug(state) eq {RUNNING}):($id in {continue into over out}?($active&&$paused):(!$active&&$s(busy) eq {}&&$s(project) ne {})))}]
        .gxViewerDevelopment.debugbar.$id state [expr {$enabled?{!disabled}:{disabled}}]
    }
}
proc ::GX::ViewerDevelopmentWorkspace::debugStart {} {
    variable s;variable debug
    if {$debug(request) ne {}} {if {$debug(state) eq {PAUSED}} {debugControl continue};return}
    if {$s(project) eq {}||$s(file) ne {handlers.cpp}||$s(dirty)||$s(busy) ne {}} {error {Open and save handlers.cpp before starting Debug}}
    set debug(snapshot) [::GX::_viewerDevelopmentSnapshot $s(project)]
    set debug(state) STARTING;set debug(sequence) -1;incr debug(generation)
    set debug(token) [format debug-%x-%x [pid] [clock microseconds]]
    ::GX::sourceSurfaceBreakpoints [text] lock
    set debug(request) [::GX::viewerDevelopmentRequest debug $s(project) [list ::GX::ViewerDevelopmentWorkspace::debugFinished $debug(generation)] [dict create breakpoints [::GX::sourceSurfaceBreakpoints [text]] debug_token $debug(token)]]
    set debug(status) {GDB is validating and compiling the current admitted C++ source…}
    debugButtons;after 150 [list ::GX::ViewerDevelopmentWorkspace::debugPoll $debug(generation)]
}
proc ::GX::ViewerDevelopmentWorkspace::debugPoll {generation} {
    variable debug;variable s
    if {![winfo exists .gxViewerDevelopment]||$generation!=$debug(generation)||$debug(request) eq {}} return
    if {$s(dirty)||[catch {::GX::_viewerDevelopmentSnapshot $s(project)} current]||$current ne $debug(snapshot)} {set debug(status) {Source changed; cancelling stale C++ debug execution.};debugStop;return}
    set debug(poll) [::GX::viewerDevelopmentRequest debug_status $s(project) [list ::GX::ViewerDevelopmentWorkspace::debugPolled $generation] [dict create debug_token $debug(token)]]
}
proc ::GX::ViewerDevelopmentWorkspace::debugPolled {generation response} {
    variable debug
    if {![winfo exists .gxViewerDevelopment]||$generation!=$debug(generation)||$debug(request) eq {}} return
    set debug(poll) {}
    if {[dict get $response ok]} {debugRender [dict get $response result debug]}
    after 180 [list ::GX::ViewerDevelopmentWorkspace::debugPoll $generation]
}
proc ::GX::ViewerDevelopmentWorkspace::debugRender {snapshot} {
    variable debug
    set previousState $debug(state)
    set debug(state) [dict get $snapshot state]
    if {$previousState eq $debug(state)&&[dict exists $snapshot sequence]&&$debug(sequence)==[dict get $snapshot sequence]} {debugButtons;return}
    set debug(sequence) [::GX::datasetPublicationV2DictDefault $snapshot sequence 0]
    set debug(status) "GDB / admitted C++ · $debug(state)"
    if {$debug(state) eq {PAUSED}&&[dict exists $snapshot reason]} {append debug(status) " · [dict get $snapshot reason]"}
    if {[dict exists $snapshot errors]&&[llength [dict get $snapshot errors]]} {append debug(status) " · [lindex [dict get $snapshot errors] end]"}
    set line 0
    if {$debug(state) eq {PAUSED}&&[dict exists $snapshot frame line]} {
        set frame [dict get $snapshot frame]
        if {[file tail [::GX::datasetPublicationV2DictDefault $frame fullname {}]] eq {handlers.cpp}} {set line [dict get $frame line]}
    }
    ::GX::sourceSurfaceLocation [text] $line
    if {$debug(state) ni {PAUSED RUNNING CONTINUING STARTING}} {dict set snapshot frames {};dict set snapshot locals {}}
    set stack .gxViewerDevelopment.bottom.stack.tree
    set selected [::GX::datasetPublicationV2DictDefault $snapshot selected_frame 0]
    $stack delete [$stack children {}]
    foreach frame [::GX::datasetPublicationV2DictDefault $snapshot frames {}] {
        set level [dict get $frame level]
        $stack insert {} end -id frame$level -values [list $level [dict get $frame func] [file tail [::GX::datasetPublicationV2DictDefault $frame file {}]] [::GX::datasetPublicationV2DictDefault $frame line {}]]
    }
    set vars .gxViewerDevelopment.bottom.variables.tree;$vars delete [$vars children {}]
    foreach local [::GX::datasetPublicationV2DictDefault $snapshot locals {}] {$vars insert {} end -values [list [dict get $local name] [::GX::datasetPublicationV2DictDefault $local type {}] [::GX::datasetPublicationV2DictDefault $local value {not available}]]}
    # Rows arrive asynchronously after the empty inspector was constructed.
    # Reuse the common font-aware table owner once the actual values exist.
    ::GX::uiFieldInspectionColumnsSchedule $stack
    ::GX::uiFieldInspectionColumnsSchedule $vars
    debugButtons
}
proc ::GX::ViewerDevelopmentWorkspace::debugControl {operation {frame 0}} {
    variable debug;variable s
    if {$debug(request) eq {}} {error {Start an admitted C++ Debug execution first}}
    if {$s(dirty)||[::GX::_viewerDevelopmentSnapshot $s(project)] ne $debug(snapshot)} {debugStop;error {Source changed; restart Debug}}
    if {$operation ni {continue into over out pause stop frame}} {error {Unsupported C++ debug control}}
    set json [format {{"operation":"%s","source_sha256":"%s","frame":%d}} $operation [dict get $debug(snapshot) source_sha256] $frame]
    ::GX::viewerDevelopmentRequest debug_control $s(project) [list ::GX::ViewerDevelopmentWorkspace::debugControlled $debug(generation)] [dict create request_json $json debug_token $debug(token)]
    if {$operation in {continue into over out}} {set debug(state) CONTINUING;debugButtons}
    if {$operation eq {pause}} {set debug(state) PAUSING;debugButtons}
}
proc ::GX::ViewerDevelopmentWorkspace::debugControlled {generation response} {
    variable debug;if {$generation!=$debug(generation)||$debug(request) eq {}} return
    if {![dict get $response ok]} {set debug(status) [dict get $response error]}
}
proc ::GX::ViewerDevelopmentWorkspace::debugFrame {} {
    set tree .gxViewerDevelopment.bottom.stack.tree
    set id [lindex [$tree selection] 0]
    if {[regexp {^frame([0-9]+)$} $id -> frame]} {safe debugControl frame $frame}
}
proc ::GX::ViewerDevelopmentWorkspace::debugStop {} {
    variable debug
    if {$debug(request) ne {}} {::GX::scriptJobRequestCancel $debug(request) cancelled;set debug(status) {Stopping the owned GDB/native worker process tree…}}
}
proc ::GX::ViewerDevelopmentWorkspace::debugFinished {generation response} {
    variable debug
    if {$generation!=$debug(generation)} return
    set debug(request) {}
    if {![winfo exists .gxViewerDevelopment]} return
    ::GX::sourceSurfaceBreakpoints [text] unlock
    ::GX::sourceSurfaceLocation [text] 0
    if {[dict get $response ok]&&[dict exists $response result debug]} {
        debugRender [dict get $response result debug]
    } else {
        set terminal [expr {[::GX::datasetPublicationV2DictDefault $response error_type {}] in {cancelled closed} ? {CANCELLED} : {FAILED}}]
        debugRender [dict create state $terminal sequence [expr {$debug(sequence)+1}] frames {} locals {}]
        set debug(status) "C++ debug $terminal · managed process request ended."
        if {[dict exists $response error]} {append debug(status) " [dict get $response error]"}
    }
    if {[dict get $response ok] && [dict exists $response result]} {
        set result [dict get $response result]
        set report [::GX::datasetPublicationV2DictDefault $result validation {}]
        diagnosticsShow $report
        log "C++ debug: $debug(state)\n"
        if {[dict exists $result debug worker_limits]} {log "Native worker limits: [dict get $result debug worker_limits]\nDebugger active wall budget: [dict get $result debug active_wall_seconds] seconds (paused time excluded).\n"}
        foreach row [::GX::datasetPublicationV2DictDefault $report diagnostics {}] {
            log "[dict get $row file]:[dict get $row line]:[dict get $row column]: [dict get $row message]\n"
        }
        if {[dict exists $result log]} {log "[string range [dict get $result log] 0 8191]\n"}
        if {[dict exists $result debug errors]} {foreach error [dict get $result debug errors] {log "$error\n"}}
    } else {log "$debug(status)\n"}
    debugButtons
}
proc ::GX::ViewerDevelopmentWorkspace::debugDestroyed {actual} {
    variable debug
    if {$actual ne {.gxViewerDevelopment}} return
    if {$debug(poll) ne {}} {catch {::GX::scriptJobRequestCancel $debug(poll) closed}}
    if {$debug(request) ne {}} {catch {::GX::scriptJobRequestCancel $debug(request) closed}}
    incr debug(generation);set debug(request) {};set debug(poll) {};set debug(state) IDLE
    set debug(token) {};set debug(sequence) -1;set debug(snapshot) {};set debug(status) {Debug admitted C++ source with real GDB/MI.}
}
