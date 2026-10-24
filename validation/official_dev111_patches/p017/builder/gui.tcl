# SPDX-License-Identifier: GPL-3.0-or-later
# Real mapped GUI input against an unchanged, locally rebuilt generated Viewer.
if {[llength $argv]!=3} {error {usage: gui.tcl FRAMEWORK REBUILD_OUTPUT NEW_OUTPUT}}
lassign $argv framework rebuild out
set framework [file normalize $framework];set rebuild [file normalize $rebuild];set out [file normalize $out]
if {[file exists $out]} {error {Fresh output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT TMPDIR} {set ::env($key) [file join $out $key];file mkdir $::env($key)}
set ::env(PYTHONDONTWRITEBYTECODE) 1
set argv0 __DEV111_P017_BUILDER_GUI__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
package require Tk
wm withdraw .
set ::GX::cfg(output_root) [file join $out Sessions]
::GX::configurationSet storage.cache_dir [file join $out cache]
::GX::configurationSet storage.temp_dir [file join $out temp]
::GX::createNewSession SYNTHETIC_BUILDER_HISTORY
namespace eval ::B {variable checks {};variable input {};variable errors {};variable shots {};variable exports 0;variable terminal 0}
proc ::B::emit {name data} {set f [open [file join $::out $name] w];try {fconfigure $f -encoding utf-8;puts $f $data} finally {close $f}}
proc ::B::fail {message options} {
    if {$::B::terminal} return
    set ::B::terminal 1
    set observed {}
    dict for {window adapter} $::GX::ScientificHistory::viewers {
        catch {dict set observed $window status [::GX::scientificHistoryViewerStatus $window]}
        catch {dict set observed $window state [::GX::scientificHistoryViewerState $window]}
        catch {dict set observed $window focus [focus]}
        catch {dict set observed $window strip_mode $::GX::ScientificHistory::strip($window,mode)}
        if {[winfo viewable $window]} {catch {::B::shot $window failure}}
    }
    emit FIRST_FAILURE.tcldict [dict create message $message options $options checks $::B::checks inputs $::B::input observed $observed background_errors $::B::errors]
    puts stderr [dict get $options -errorinfo]
    set ::B::done 1
}
proc bgerror {message} {lappend ::B::errors $message;puts stderr "BACKGROUND: $message"}
proc ::B::resume {actor} {if {[llength [info commands $actor]] && [catch {$actor} message options]} {::B::fail $message $options}}
proc ::B::pause {{ms 140}} {after $ms [list ::B::resume [info coroutine]];yield}
proc ::B::wait {condition {limit 8000}} {
    set end [expr {[clock milliseconds]+$limit}]
    while {![uplevel 1 [list expr $condition]]} {if {[clock milliseconds]>$end} {error "Timed out: $condition"};pause 40}
}
proc ::B::check {name condition} {
    if {![uplevel 1 [list expr $condition]]} {error "FAIL: $name"}
    lappend ::B::checks [dict create name $name status PASS]
    puts "PASS $name";flush stdout
}
proc ::B::logInput {kind args} {lappend ::B::input [dict create at_ms [clock milliseconds] kind $kind arguments $args]}
proc ::B::focusWindow {window} {
    raise $window;update idletasks
    exec xdotool windowfocus --sync [winfo id $window]
    pause 70
}
proc ::B::click {widget {button 1} {x {}} {y {}}} {
    if {![winfo viewable $widget]} {error "Input widget is not viewable: $widget"}
    if {$x eq {}} {set x [expr {[winfo width $widget]/2}]}
    if {$y eq {}} {set y [expr {[winfo height $widget]/2}]}
    logInput click $widget $button $x $y
    exec xdotool mousemove [expr {[winfo rootx $widget]+$x}] [expr {[winfo rooty $widget]+$y}]
    pause 40
    exec xdotool click $button
    pause
}
proc ::B::key {keys} {logInput key $keys;exec xdotool key --clearmodifiers $keys;pause}
proc ::B::type {widget text} {
    click $widget
    key Home
    key shift+End
    logInput type $widget $text
    exec xdotool type --clearmodifiers --delay 2 -- $text
    key Return
}
proc ::B::widgets {parent} {
    set result [list $parent]
    foreach child [winfo children $parent] {set result [concat $result [widgets $child]]}
    return $result
}
proc ::B::shot {w label} {
    update idletasks
    set path [file join $::out "$label.png"]
    exec import -window root $path
    lappend ::B::shots $path
}
proc ::B::inside {child parent} {
    return [expr {[winfo rootx $child]>=[winfo rootx $parent] && [winfo rooty $child]>=[winfo rooty $parent] && [winfo rootx $child]+[winfo width $child]<=[winfo rootx $parent]+[winfo width $parent]+1 && [winfo rooty $child]+[winfo height $child]<=[winfo rooty $parent]+[winfo height $parent]+1}]
}
proc ::B::menuIndex {m pattern} {
    set end [$m index end]
    for {set i 0} {$end ne {none} && $i<=$end} {incr i} {
        if {[$m type $i] eq {separator}} continue
        if {[string match $pattern [$m entrycget $i -label]]} {return $i}
    }
    error "Menu item '$pattern' absent in $m"
}
proc ::B::menuPick {m pattern} {
    wait {[winfo ismapped $m]}
    set index [menuIndex $m $pattern]
    if {[$m entrycget $index -state] eq {disabled}} {error "Menu item is disabled: $pattern"}
    set y [$m yposition $index]
    set h [expr {[font metrics [$m cget -font] -linespace]+8}]
    click $m 1 35 [expr {$y+$h/2}]
}
proc ::B::context {w} {
    set c [dict get $::GX::ScientificHistory::viewers $w strip].timeline
    click $c 3 25 12
    set m $w.historyContext
    wait {[winfo exists $m] && [winfo ismapped $m]}
    return $m
}
proc ::B::topMenu {w label} {
    set bar {}
    foreach candidate [widgets $w] {
        if {[winfo class $candidate] eq {Menu} && [winfo ismapped $candidate] && [$candidate cget -type] eq {menubar}} {set bar $candidate;break}
    }
    if {$bar eq {}} {error {Mapped native menubar not found}}
    set index [menuIndex $bar $label]
    click $bar 1 [expr {[$bar xposition $index]+25}] [expr {[winfo height $bar]/2}]
    set m [$bar entrycget $index -menu]
    wait {[winfo ismapped $m]}
    return $m
}
proc ::B::modalButton {parent label} {
    set target {}
    set end [expr {[clock milliseconds]+5000}]
    while {$target eq {}} {
        foreach child [widgets $parent] {
            if {[winfo class $child] in {Button TButton} && [winfo viewable $child] && [$child cget -text] eq $label} {set target $child;break}
        }
        if {[clock milliseconds]>$end} {error "Modal button '$label' not found"}
        if {$target eq {}} {pause 50}
    }
    click $target
}
proc ::B::selector {combo viewer value} {
    click $combo
    set panel [::GX::_uiFieldSelectorPanel $combo $viewer]
    wait {[winfo exists $panel] && [winfo viewable $panel.options]}
    set index [lsearch -exact [$panel.options get 0 end] $value]
    if {$index<0} {error "Selector value missing: $value"}
    $panel.options see $index;update idletasks
    lassign [$panel.options bbox $index] x y width height
    click $panel.options 1 [expr {$x+20}] [expr {$y+$height/2}]
    return $panel
}
proc ::B::exportTrace {command operation} {incr ::B::exports}
proc ::B::run {} {
    set plan [::GX::datasetPublicationV2Prepare $::GX::currentSession math.numeric {dataset_id synthetic_xy contract table.generic storage hdf5 structured_metadata {fixture.synthetic 1}}]
    set writer [::GX::datasetPublicationV2OpenWriter $plan]
    ::GX::datasetPublicationV2DeclareDimension $writer row 129
    foreach {id unit} {x m y V} {::GX::datasetPublicationV2DeclareVariable $writer $id [dict create dtype float64 unit $unit dimension_ids row]}
    set xs {};set ys {}
    for {set n 0} {$n<129} {incr n} {set x [expr {$n/16.0}];lappend xs $x;lappend ys [expr {sin($x)+.03*$x}]}
    ::GX::datasetPublicationV2WriteRange $writer x 0 $xs
    ::GX::datasetPublicationV2WriteRange $writer y 0 $ys
    ::GX::datasetPublicationV2Finalize $writer
    set scientificBefore [::GX::datasetViewerScientificIdentity synthetic_xy]
    source [file join $::rebuild source api viewer.tcl]
    set w [::GX::Generated_viewer_dev107_scientific_xy::open]
    pause 500
    focusWindow $w
    check {real rebuilt generated Viewer is mapped} {[winfo viewable $w] && [set ::GX::Generated_viewer_dev107_scientific_xy::root] eq [file join $::rebuild source]}
    set controls [dict get $::GX::ViewerGui::instances $w widgets]
    set note [dict get $controls note].entry
    set strip [dict get $::GX::ScientificHistory::viewers $w strip]
    set dataset [dict get $controls dataset]
    if {[winfo class $dataset] ne {TCombobox}} {set dataset $dataset.entry}
    selector $dataset $w synthetic_xy
    click [dict get $controls load]
    set viewport [dict get $controls xy].curve
    wait {![catch {::GX::native2DViewportCurveDescribe $viewport} source] && [dict get $source status] eq {ready}}
    check {unchanged handwritten handler loads canonical scientific source} {[dict get [::GX::viewerGuiDesignValues $w] dataset] eq {synthetic_xy}}
    set before [dict get [::GX::scientificHistoryViewerStatus $w] count]
    trace add execution ::GX::scientificHistoryViewerRecord enter ::B::exportTrace
    type $note first
    type $note second
    type $note third
    set latest [dict get [::GX::scientificHistoryViewerStatus $w] count]
    check {three native field commits append three immediate operations} {$latest==$before+3 && [dict get [::GX::scientificHistoryViewerState $w] values note] eq {third}}
    check {ordinary generated edits avoid full History exports} {$::B::exports==0}
    click $strip.details
    wait {[winfo viewable $w.historyDetails]}
    check {Description details retain current text} {[$w.historyDetails.text get 1.0 end] ne {}}
    click $w.historyDetails.text
    key Escape
    check {Details Escape closes dialog} {![winfo exists $w.historyDetails]}

    # Shortcuts are scoped to non-editor controls, preserving text Undo semantics.
    focusWindow $w
    click [dict get $controls fit]
    key ctrl+z
    check {native Ctrl Z performs shared scientific Undo} {[dict get [::GX::viewerGuiDesignValues $w] note] eq {second} && [dict get [::GX::scientificHistoryViewerStatus $w] cursor]==$latest-1}
    key ctrl+y
    check {native Ctrl Y performs shared scientific Redo} {[dict get [::GX::viewerGuiDesignValues $w] note] eq {third} && [dict get [::GX::scientificHistoryViewerStatus $w] cursor]==$latest}
    click $strip.choice
    set panel [::GX::_uiFieldSelectorPanel $strip.choice $w]
    wait {[winfo viewable $panel.options]}
    check {History mode popup is above control and application bounded} {[inside $panel $w] && [winfo rooty $panel]<[winfo rooty $strip.choice]}
    shot $w mode-popup
    key Down
    key Return
    check {keyboard chooses History and returns focus} {$::GX::ScientificHistory::strip($w,mode) eq {History} && [focus] eq "${strip}.choice"}
    set grouped [::GX::scientificHistoryGroupedEntries [::GX::scientificHistoryViewerSummary $w]]
    check {consecutive field descriptions produce grouped timeline entries} {[dict get [lindex $grouped end] count]==3 && [string match {*Change note*} [dict get [lindex $grouped end] description]]}
    set menu [context $w]
    check {History context posts upward within application boundaries} {[inside $menu $w] && [winfo rooty $menu]<[winfo rooty $strip.timeline]}
    shot $w history-context
    menuPick $menu {Previous history step}
    check {native browsing preserves future operations and scientific cursor} {![::GX::scientificHistoryViewerEditable $w] && [dict get [::GX::scientificHistoryViewerStatus $w] cursor]==$latest && [dict get [::GX::viewerGuiDesignValues $w] note] eq {second}}
    type $note forbidden
    check {read-only browsing rejects field mutation without losing preview} {[dict get [::GX::viewerGuiDesignValues $w] note] eq {second} && [dict get [::GX::scientificHistoryViewerStatus $w] count]==$latest}
    set menu [context $w]
    menuPick $menu {Restart here*}
    pause 150
    modalButton $w Cancel
    check {real branch Cancel preserves future History} {[dict get [::GX::scientificHistoryViewerStatus $w] count]==$latest}
    set menu [context $w]
    menuPick $menu {Restart here*}
    pause 150
    modalButton $w OK
    check {real branch confirmation preserves selected scientific state} {[::GX::scientificHistoryViewerEditable $w] && [dict get [::GX::scientificHistoryViewerStatus $w] count]==$latest-1 && [dict get [::GX::viewerGuiDesignValues $w] note] eq {second}}
    type $note branched
    check {native edit appends after explicit branch} {[dict get [::GX::scientificHistoryViewerStatus $w] count]==$latest && [dict get [::GX::viewerGuiDesignValues $w] note] eq {branched}}
    click $strip.details
    wait {[winfo viewable $w.historyDetails]}
    check {History details retain operation descriptions} {[string match {*Change note*} [$w.historyDetails.text get 1.0 end]] && [inside $w.historyDetails $w]}
    shot $w history-details
    click $w.historyDetails.text
    key Escape
    focusWindow $w
    set menu [context $w]
    menuPick $menu {Hide Description*}
    check {shared context hides strip} {![winfo ismapped $strip]}
    set menu [topMenu $w History]
    menuPick $menu {Show / hide*}
    check {generic History menu restores strip without authored source change} {[winfo ismapped $strip]}
    check {GUI navigation and dirty checks avoid full History exports} {$::B::exports==0 && [::GX::viewerGuiDesignDirty $w]}
    trace remove execution ::GX::scientificHistoryViewerRecord enter ::B::exportTrace

    set menu [topMenu $w Workspace]
    menuPick $menu Save
    wait {[::GX::viewerGuiDesignCurrent $w] ne {}}
    set id [::GX::viewerGuiDesignCurrent $w]
    check {normal Workspace Save binds native History owner and becomes clean} {[dict get $::GX::ScientificHistory::viewers $w document_id] eq $id && ![::GX::viewerGuiDesignDirty $w] && [dict get [::GX::scientificHistoryViewerStatus $w] pending]==0}
    set saved [::GX::scientificHistoryViewerRecord $w]
    set menu [context $w]
    menuPick $menu {Clear History*}
    pause 120
    modalButton $w Cancel
    check {real Clear cancellation preserves complete History} {[::GX::scientificHistoryViewerRecord $w] eq $saved}
    set menu [topMenu $w Workspace]
    menuPick $menu Close
    wait {![winfo exists $w]}
    check {normal Close drains and releases shared History} {![dict exists $::GX::ScientificHistory::viewers $w]}
    # Explicit public open uses the same unchanged generated connector and saved
    # Workspace ID. All subsequent History controls remain real GUI input.
    set w [::GX::Generated_viewer_dev107_scientific_xy::open [dict create workspace_id $id]]
    pause 400
    focusWindow $w
    check {public Workspace reopen restores scientific state and exact History} {[::GX::scientificHistoryViewerRecord $w] eq $saved && [dict get [::GX::viewerGuiDesignValues $w] note] eq {branched} && ![::GX::viewerGuiDesignDirty $w]}
    set strip [dict get $::GX::ScientificHistory::viewers $w strip]
    selector $strip.choice $w History
    set menu [context $w]
    menuPick $menu {Clear History*}
    pause 120
    modalButton $w No
    check {real Clear preserves current scientific state and resets timeline} {[dict get [::GX::scientificHistoryViewerStatus $w] count]==0 && [dict get [::GX::viewerGuiDesignValues $w] note] eq {branched} && [::GX::viewerGuiDesignDirty $w]}
    set menu [topMenu $w Workspace]
    menuPick $menu Save
    check {explicit Save retains cleared current state} {![::GX::viewerGuiDesignDirty $w] && [dict get [::GX::interactiveDocumentRead $id] payload history steps] eq {}}
    check {scientific Dataset identity remains unchanged} {[::GX::datasetViewerScientificIdentity synthetic_xy] eq $scientificBefore}
    check {real GUI produced no background callback errors} {$::B::errors eq {}}
    shot $w final-cleared
    set menu [topMenu $w Workspace]
    menuPick $menu Close
    wait {![winfo exists $w]}
    emit receipt.tcldict [dict create status PASS_REAL_BUILDER_HISTORY_GUI checks $::B::checks inputs $::B::input screenshots $::B::shots framework $::framework rebuild $::rebuild workspace_id $id source_identity $scientificBefore ordinary_full_record_exports $::B::exports scope {Real mapped Tcl/Tk Viewer and xdotool native pointer/keyboard; API synthetic setup and explicit public reopen; user final GUI acceptance still required}]
    set ::B::terminal 1;set ::B::done 1
}
after 0 {if {[catch {coroutine ::B::actor ::B::run} message options]} {::B::fail $message $options}}
after 140000 {if {!$::B::terminal} {::B::fail {GUI actor timeout} [dict create -errorinfo {GUI actor timeout}]}}
vwait ::B::done
if {[file exists [file join $out FIRST_FAILURE.tcldict]]} {exit 1}
puts {PASS real Builder History GUI}
exit 0
