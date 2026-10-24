# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv]!=2} {error {usage: gui.tcl FRAMEWORK NEW_OUTPUT}}
lassign $argv framework out
set framework [file normalize $framework];set out [file normalize $out]
if {[file exists $out]} {error {Fresh output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT TMPDIR} {set ::env($key) [file join $out $key];file mkdir $::env($key)}
set ::env(PYTHONDONTWRITEBYTECODE) 1
set argv0 __DEV111_P017_CURVE_HISTORY_GUI__
set nativePins {}
foreach relative {core/history/history_engine.cpp core/history/libgxtxt_history.so core/tcl/scientific_history_native.tcl core/tcl/scientific_recipe_history.tcl core/tcl/interactive_document_api_v1.tcl core/tcl/parameter_service_api_v1.tcl core/tcl/native2d_viewport_host_v1.tcl} {
    dict set nativePins $relative [lindex [exec sha256sum [file join $framework $relative]] 0]
}
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
package require Tk;wm withdraw .
set ::GX::cfg(output_root) [file join $out Sessions]
::GX::configurationSet storage.cache_dir [file join $out cache]
::GX::configurationSet storage.temp_dir [file join $out temp]
::GX::createNewSession SYNTHETIC_CURVE_HISTORY_GUI
::GX::modulePublicApiActivate viewer.curve_workbench CURVE_WORKBENCH_API_v1
namespace eval ::G {variable checks {};variable input {};variable errors {};variable done 0;variable failed 0}
proc ::G::write {name data} {set f [open [file join $::out $name] w];try {puts $f $data} finally {close $f}}
proc ::G::shot {name} {exec import -window root [file join $::out "$name.png"]}
proc ::G::fail {message options} {
    set ::G::failed 1
    catch {shot failure}
    catch {write owner-failure.tcldict [::GX::scientificHistoryViewerStatus .curve_workbench]}
    write FIRST_FAILURE.tcldict [dict create message $message options $options checks $::G::checks inputs $::G::input errors $::G::errors]
    puts stderr [dict get $options -errorinfo]
    set ::G::done 1
}
proc bgerror {message} {lappend ::G::errors $message;puts stderr "BACKGROUND $message"}
proc ::G::resume {actor} {if {[llength [info commands $actor]] && [catch {$actor} message options]} {fail $message $options}}
proc ::G::pause {{ms 160}} {after $ms [list ::G::resume [info coroutine]];yield}
proc ::G::wait {condition {limit 15000}} {set end [expr {[clock milliseconds]+$limit}];while {![uplevel 1 [list expr $condition]]} {if {[clock milliseconds]>$end} {error "Timeout: $condition"};pause 60}}
proc ::G::check {name condition} {if {![uplevel 1 [list expr $condition]]} {error "FAIL $name"};lappend ::G::checks [dict create name $name status PASS];puts "PASS $name";flush stdout}
proc ::G::click {widget {button 1} {x {}} {y {}}} {
    if {![winfo viewable $widget]} {error "Widget not mapped: $widget"}
    if {$x eq {}} {set x [expr {[winfo width $widget]/2}]};if {$y eq {}} {set y [expr {[winfo height $widget]/2}]}
    lappend ::G::input [list click $widget $button $x $y]
    exec xdotool mousemove [expr {[winfo rootx $widget]+$x}] [expr {[winfo rooty $widget]+$y}]
    pause 40;exec xdotool click $button;pause
}
proc ::G::showControl {w target} {
    set c $w.side.scroll;set content $c.controls
    update idletasks
    set offset [expr {[winfo rooty $target]-[winfo rooty $content]}]
    set fraction [expr {max(0.0,($offset-0.25*[winfo height $c])/double([winfo height $content]))}]
    $c yview moveto $fraction
    lappend ::G::input [list existing_scroll_viewport $target $fraction]
    pause 100
    if {[winfo rooty $target]<[winfo rooty $c] || [winfo rooty $target]+[winfo height $target]>[winfo rooty $c]+[winfo height $c]} {error "Control outside sidebar viewport: $target"}
}
proc ::G::selectMode {combo parent value} {
    click $combo
    set popup [::GX::_uiFieldSelectorPanel $combo $parent]
    wait {[winfo exists $popup.options] && [winfo viewable $popup.options]}
    set i [lsearch -exact [$popup.options get 0 end] $value]
    if {$i<0} {error "Mode missing: $value"}
    lassign [$popup.options bbox $i] x y width height
    click $popup.options 1 [expr {$x+20}] [expr {$y+$height/2}]
}
proc ::G::menuPick {menu pattern} {
    wait {[winfo ismapped $menu]}
    set chosen -1;set end [$menu index end]
    for {set i 0} {$i<=$end} {incr i} {if {[$menu type $i] ne {separator} && [string match $pattern [$menu entrycget $i -label]]} {set chosen $i;break}}
    if {$chosen<0 || [$menu entrycget $chosen -state] eq {disabled}} {error "Unavailable menu item $pattern"}
    click $menu 1 30 [expr {[$menu yposition $chosen]+([font metrics [$menu cget -font] -linespace]+8)/2}]
}
proc ::G::context {w strip} {click $strip.timeline 3 30 12;return $w.historyContext}
proc ::G::widgets {w} {set result [list $w];foreach child [winfo children $w] {set result [concat $result [widgets $child]]};return $result}
proc ::G::modal {parent label} {
    set target {};set end [expr {[clock milliseconds]+5000}]
    while {$target eq {}} {
        foreach child [widgets $parent] {if {[winfo class $child] in {Button TButton} && [winfo viewable $child] && [$child cget -text] eq $label} {set target $child;break}}
        if {$target ne {}} break
        if {[clock milliseconds]>$end} {error "Modal button absent: $label"};pause 60
    }
    click $target
}
proc ::G::key {widget keys} {exec xdotool key --clearmodifiers $keys;pause 220}
proc ::G::dragGizmo {w handle dx dy} {
    set scene $::GX::CurveWorkbench::st($w,scene);set canvas $w.right.viewport.canvas;set point {}
    foreach item [::GX::Native2D::core render_gizmo $scene] {
        if {[dict get $item handle] ne $handle} continue
        lassign [dict get $item a] ax ay;lassign [dict get $item b] bx by
        set x [expr {($ax+$bx)/2.0}];set y [expr {($ay+$by)/2.0}]
        if {[::GX::Native2D::core gizmo_hit $scene [list $x $y] 5] eq $handle} {set point [list $x $y];break}
    }
    if {$point eq {}} {error "No visible hit point for $handle: [::GX::Native2D::core render_gizmo $scene]"}
    lassign $point x y
    lappend ::G::input [list real_gizmo_drag $handle $x $y $dx $dy]
    exec xdotool mousemove [expr {int([winfo rootx $canvas]+$x)}] [expr {int([winfo rooty $canvas]+$y)}] mousedown 1
    pause 80
    exec xdotool mousemove [expr {int([winfo rootx $canvas]+$x+$dx)}] [expr {int([winfo rooty $canvas]+$y+$dy)}]
    pause 120;exec xdotool mouseup 1;pause 300
}
proc ::G::run {} {
    set w [::GX::CurveWorkbench::open {workspace_id new}]
    wm geometry $w 1280x900+30+30;pause 350
    set values {family line controls {{0 0} {2 1}} radius_x 1 radius_y 1 rotation 0 angle_start 0 angle_sweep 360 closed 0 samples 17 name {GUI History line}}
    ::GX::CurveWorkbench::_sketchApply $w [::GX::interactiveDocumentSessionToken] {} $values
    ::GX::CurveWorkbench::_saveExplicit $w
    set id $::GX::CurveWorkbench::st($w,active);set document $::GX::CurveWorkbench::st($w,document)
    set strip $w.historyStrip;set history $w;set canvas $w.right.viewport.canvas
    exec xdotool windowfocus --sync [winfo id $w]
    check {manual Curve layout mounts CORE strip beside original scientific controls} {[winfo viewable $strip] && [winfo viewable $canvas]}
    set tree $w.leftScroll.viewport.content.curves
    lassign [$tree bbox $id] tx ty tw th
    click $tree 1 100 [expr {$ty+$th/2}]
    set pan [::GX::native2DViewportPanelWidget $canvas controls].body.pan
    set countBeforePan [dict get [::GX::scientificHistoryViewerStatus $w] count]
    set boundsBeforePan [lindex [::GX::Native2D::core view_requested $::GX::CurveWorkbench::st($w,scene)] 6]
    click $pan
    set px [expr {[winfo rootx $canvas]+int(.6*[winfo width $canvas])}]
    set py [expr {[winfo rooty $canvas]+int(.65*[winfo height $canvas])}]
    exec xdotool mousemove $px $py mousedown 1
    pause 80;exec xdotool mousemove [expr {$px+24}] [expr {$py+16}]
    pause 100;exec xdotool mouseup 1;pause 200
    check {actual camera pan persists auxiliary without a scientific Undo row} {[dict get [::GX::scientificHistoryViewerStatus $w] count]==$countBeforePan && [lindex [::GX::Native2D::core view_requested $::GX::CurveWorkbench::st($w,scene)] 6] ne $boundsBeforePan}
    click $w.sketchbar.modify
    menuPick $w.sketchbar.modify.menu Translate
    check {actual Modify Translate selects existing CAD tool} {$::GX::CurveWorkbench::st($w,cadTool) eq {translate}}
    set before [dict get [::GX::CurveWorkbench::_snapshotIds $w [list $id]] $id sketch_definition]
    set viewBeforeMove [lindex [::GX::Native2D::core view_requested $::GX::CurveWorkbench::st($w,scene)] 6]
    set selectionBeforeMove [dict get [::GX::CurveWorkbench::_historyAuxCapture $w] selection]
    set count [dict get [::GX::scientificHistoryViewerStatus $w] count]
    dragGizmo $w x 35 0
    set moved [dict get [::GX::CurveWorkbench::_snapshotIds $w [list $id]] $id sketch_definition]
    check {real translation gizmo records one accepted scientific edit} {$moved ne $before && [dict get [::GX::scientificHistoryViewerStatus $w] count]==$count+1}
    key $canvas ctrl+z
    check {actual Ctrl Z restores prior retained definition} {[dict get [::GX::CurveWorkbench::_snapshotIds $w [list $id]] $id sketch_definition] eq $before}
    check {Undo restores exact pre-operation pan tool and logical selection} {[lindex [::GX::Native2D::core view_requested $::GX::CurveWorkbench::st($w,scene)] 6] eq $viewBeforeMove && $::GX::CurveWorkbench::st($w,cadTool) eq {translate} && [dict get [::GX::CurveWorkbench::_historyAuxCapture $w] selection] eq $selectionBeforeMove}
    click $w.toolbar.redo
    check {actual Redo toolbar restores exact translated definition} {[dict get [::GX::CurveWorkbench::_snapshotIds $w [list $id]] $id sketch_definition] eq $moved}
    dragGizmo $w x 18 0
    click $w.sketchbar.modify
    menuPick $w.sketchbar.modify.menu Rotate
    dragGizmo $w rotate 22 25
    check {real rotation gizmo records transformed geometry} {[dict get [::GX::CurveWorkbench::_snapshotIds $w [list $id]] $id sketch_definition] ne $moved}
    exec xdotool key Escape;pause 160
    selectMode $strip.choice $w History
    set hasGroup 0;foreach row [::GX::scientificHistoryGroupedEntries [::GX::scientificHistoryViewerSummary $w] 1] {if {[dict get $row count]>1} {set hasGroup 1}}
    check {consecutive real translations appear as grouped shared rows} {$hasGroup}
    check {shared selector retains focus in owning Curve window} {[string match "$w*" [focus]] && [dict get [::GX::scientificHistoryViewerStripGet $w] mode] eq {History}}
    lassign [$strip.timeline bbox history_step_0] x1 y1 x2 y2
    click $strip.timeline 1 [expr {($x1+$x2)/2}] [expr {($y1+$y2)/2}]
    check {real timeline click browses checkpoint read-only} {[::GX::CurveWorkbench::_historyBrowsing $w] && [dict size $::GX::CurveWorkbench::st($w,curves)]==0}
    click $w.toolbar.redo
    check {legacy Redo toolbar browses the next retained step read-only} {[::GX::CurveWorkbench::_historyBrowsing $w] && [dict size $::GX::CurveWorkbench::st($w,curves)]==1}
    click $w.toolbar.undo
    check {legacy Undo toolbar returns to previous browse step without moving editable cursor} {[::GX::CurveWorkbench::_historyBrowsing $w] && [dict size $::GX::CurveWorkbench::st($w,curves)]==0 && [dict get [::GX::scientificHistoryViewerStatus $w] cursor]>0}
    set menu [context $w $strip]
    check {shared History popup stays inside upper application boundaries} {[winfo rootx $menu]>=[winfo rootx $w] && [winfo rooty $menu]>=[winfo rooty $w] && [winfo rooty $menu]+[winfo height $menu]<=[winfo rooty $w]+[winfo height $w]+1 && [winfo rooty $menu]<[winfo rooty $strip]}
    shot history-popup
    menuPick $menu {Return to latest}
    check {Latest restores live scientific identity} {![::GX::CurveWorkbench::_historyBrowsing $w] && [dict exists $::GX::CurveWorkbench::st($w,curves) $id]}
    click $strip.details
    wait {[winfo exists $w.historyDetails]}
    click $w.historyDetails.text
    exec xdotool key Escape;pause 180
    check {Details closes with Escape} {![winfo exists $w.historyDetails]}
    click $w.toolbar.settings
    menuPick $w.toolbar.settings.menu {Show Description / History strip}
    check {original Settings can hide CORE strip} {![winfo ismapped $strip]}
    click $w.toolbar.settings
    menuPick $w.toolbar.settings.menu {Show Description / History strip}
    check {original Settings restores hidden CORE strip} {[winfo ismapped $strip]}
    click $strip.timeline 1 [expr {($x1+$x2)/2}] [expr {($y1+$y2)/2}]
    set menu [context $w $strip]
    menuPick $menu {Restart here / discard*}
    modal $w Cancel
    check {real branch Cancel preserves all accepted operations} {[::GX::CurveWorkbench::_historyBrowsing $w] && [dict get [::GX::scientificHistoryViewerStatus $w] count]>0}
    set menu [context $w $strip]
    menuPick $menu {Restart here / discard*}
    modal $w OK
    check {real branch confirmation selects baseline without private stacks} {![::GX::CurveWorkbench::_historyBrowsing $w] && [dict get [::GX::scientificHistoryViewerStatus $w] count]==0 && [dict size $::GX::CurveWorkbench::st($w,curves)]==0}
    # Existing API prepares a constraint fixture; actual context menus own actions.
    ::GX::CurveWorkbench::_sketchApply $w [::GX::interactiveDocumentSessionToken] {} $values
    set id $::GX::CurveWorkbench::st($w,active)
    set native [dict get $::GX::CurveWorkbench::st($w,curves) $id native]
    ::GX::CurveWorkbench::_constraintCommit $w {} [dict create kind horizontal a $native a_index 3000000000]
    set index [dict get [::GX::scientificHistoryViewerStatus $w] count]
    check {scientific constraint enters shared History with semantic description} {[dict size $::GX::CurveWorkbench::st($w,constraints)]==1}
    click $w.toolbar.undo
    check {Undo retains final constraint step as a future operation} {[dict size $::GX::CurveWorkbench::st($w,constraints)]==0 && [dict get [::GX::scientificHistoryViewerStatus $w] cursor]<$index}
    ::GX::scientificHistoryViewerRefresh $w
    lassign [$strip.timeline bbox history_step_$index] x1 y1 x2 y2
    click $strip.timeline 1 [expr {($x1+$x2)/2}] [expr {($y1+$y2)/2}]
    check {actual numeric timeline inspects final future constraint without changing editable cursor} {[::GX::CurveWorkbench::_historyBrowsing $w] && [dict size $::GX::CurveWorkbench::st($w,constraints)]==1 && [dict get [::GX::scientificHistoryViewerStatus $w] cursor]<$index}
    click $strip.timeline 3 [expr {($x1+$x2)/2}] [expr {($y1+$y2)/2}]
    menuPick $w.historyContext {Select / inspect constraint*}
    set panel [::GX::CurveWorkbench::_constraintPanel $w]
    set parents {};set ancestor $panel
    while {$ancestor ne {.}} {lappend parents [list $ancestor [winfo manager $ancestor] [winfo ismapped $ancestor] [winfo viewable $ancestor]];set ancestor [winfo parent $ancestor]}
    write inspector-diagnostic.tcldict [dict create panel $panel parents $parents viewport [dict get $::GX::ViewportHost::hosts $canvas panels] status $::GX::CurveWorkbench::st($w,status) recovery $::GX::CurveWorkbench::st($w,recoveryNotice)]
    check {shared domain context inspects retained constraint identity} {[winfo viewable [::GX::CurveWorkbench::_constraintPanel $w]] && [dict size $::GX::CurveWorkbench::st($w,constraints)]==1}
    shot constraint-inspector
    set menu [context $w $strip]
    menuPick $menu {Restart here / discard*}
    modal $w OK
    check {shared restart resumes final future constraint step without discarding retained prefix} {![::GX::CurveWorkbench::_historyBrowsing $w] && [dict get [::GX::scientificHistoryViewerStatus $w] cursor]==$index && [dict get [::GX::scientificHistoryViewerStatus $w] count]==$index}
    ::GX::scientificHistoryViewerNavigate $w latest
    ::GX::scientificHistoryViewerRefresh $w
    lassign [$strip.timeline bbox history_step_$index] x1 y1 x2 y2
    click $strip.timeline 3 [expr {($x1+$x2)/2}] [expr {($y1+$y2)/2}]
    menuPick $w.historyContext {Restart here, then remove constraint*}
    check {actual shared domain action removes the identified constraint} {[dict size $::GX::CurveWorkbench::st($w,constraints)]==0}
    click $w.toolbar.undo
    check {Undo restores domain constraint through same CORE timeline} {[dict size $::GX::CurveWorkbench::st($w,constraints)]==1}
    click $w.toolbar.redo
    click $w.toolbar.undo
    set menu [context $w $strip]
    menuPick $menu {Restart here / discard*}
    modal $w OK
    # Explicit normal Save is driven by existing menu, then clear confirmation.
    click $w.toolbar.workspace
    menuPick $w.toolbar.workspace.menu {Save*}
    set count [dict get [::GX::scientificHistoryViewerStatus $w] count]
    set menu [context $w $strip]
    menuPick $menu {Clear History*}
    modal $w Cancel
    check {real Clear cancellation preserves timeline} {[dict get [::GX::scientificHistoryViewerStatus $w] count]==$count}
    set menu [context $w $strip]
    menuPick $menu {Clear History*}
    modal $w No
    check {shared Clear preserves current exact geometry and constraints} {[dict get [::GX::scientificHistoryViewerStatus $w] count]==0 && [dict exists $::GX::CurveWorkbench::st($w,curves) $id] && [dict size $::GX::CurveWorkbench::st($w,constraints)]==1}
    shot current-science-after-clear
    check {no background errors in real Curve GUI workflow} {$::G::errors eq {}}
    ::GX::CurveWorkbench::_close $w
    set w [::GX::CurveWorkbench::open [dict create workspace_id $document]];pause 300
    check {Workspace reopens current science and shared cleared History} {[dict exists $::GX::CurveWorkbench::st($w,curves) $id] && [dict size $::GX::CurveWorkbench::st($w,constraints)]==1}
    ::GX::CurveWorkbench::_close $w
    write receipt.tcldict [dict create status PASS_CURVE_HISTORY_GUI checks $::G::checks inputs $::G::input framework $::framework tested_native_pins $::nativePins scope {Original manual Curve UI; existing retained Line API seed, native xdotool transforms/menus/keyboard; constraint API fixture then actual domain context; human acceptance OPEN}]
    set ::G::done 1
}
after 0 {if {[catch {coroutine ::G::actor ::G::run} message options]} {::G::fail $message $options}}
after 165000 {if {!$::G::done} {::G::fail {Curve GUI actor timeout} [dict create -errorinfo {Curve GUI actor timeout}]}}
vwait ::G::done
if {$::G::failed} {exit 1}
puts {PASS real Curve History GUI}
exit 0
