# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv]!=2} {error {usage: gui.tcl FRAMEWORK NEW_OUTPUT}}
lassign $argv framework out
set framework [file normalize $framework];set out [file normalize $out]
if {[file exists $out]} {error {Fresh output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT TMPDIR} {set ::env($key) [file join $out $key];file mkdir $::env($key)}
set ::env(PYTHONDONTWRITEBYTECODE) 1
set argv0 __DEV111_P017_3D_HISTORY_GUI__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
package require Tk;wm withdraw .
set ::GX::cfg(output_root) [file join $out Sessions]
::GX::configurationSet storage.cache_dir [file join $out cache]
::GX::configurationSet storage.temp_dir [file join $out temp]
::GX::createNewSession SYNTHETIC_3D_HISTORY_GUI
::GX::modulePublicApiActivate viewer.3d_workbench WORKBENCH_3D_API_v1
::GX::configurationSet viewers.native3d.execution Software
namespace eval ::G {variable checks {};variable input {};variable errors {};variable done 0;variable failed 0}
proc ::G::write {name data} {set f [open [file join $::out $name] w];try {puts $f $data} finally {close $f}}
proc ::G::shot {name} {exec import -window root [file join $::out "$name.png"]}
proc ::G::fail {message options} {
    set ::G::failed 1
    catch {shot failure}
    catch {write owner-failure.tcldict [::GX::Workbench3D::guiInspect]}
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
proc ::G::run {} {
    set w [::GX::Workbench3D::open {workspace_id new}]
    wm geometry $w 1280x880+30+30
    pause 500
    exec xdotool windowfocus --sync [winfo id $w]
    set panel $::GX::Workbench3D::panel
    set history $::GX::Workbench3D::historyContext
    set document $::GX::Workbench3D::document
    set strip $w.historyStrip
    check {original manual UI mounts shared CORE scientific History strip} {[winfo viewable $w] && [winfo viewable $strip] && [dict get [::GX::scientificHistoryViewerStatus $history] count]==0}
    showControl $w $panel.primitiveGo
    click $panel.primitiveGo
    wait {[dict size [dict get $::GX::Workbench3D::model objects]]==1 && !$::GX::Engine3D::workerBusy}
    set object [lindex [dict keys [dict get $::GX::Workbench3D::model objects]] 0]
    set sha [dict get $::GX::Workbench3D::model objects $object geometry sha256]
    check {actual Create primitive button accepts scientific operation} {[dict get [::GX::scientificHistoryViewerStatus $history] count]==1}
    showControl $w $panel.undo
    click $panel.undo
    wait {[dict size [dict get $::GX::Workbench3D::model objects]]==0 && !$::GX::Engine3D::workerBusy}
    check {actual manual Undo button restores prior scientific scene} {[dict get [::GX::scientificHistoryViewerStatus $history] cursor]==0}
    click $panel.redo
    wait {[dict size [dict get $::GX::Workbench3D::model objects]]==1 && !$::GX::Engine3D::workerBusy}
    check {actual manual Redo preserves exact scientific resource and logical ID} {[dict exists $::GX::Workbench3D::model objects $object] && [dict get $::GX::Workbench3D::model objects $object geometry sha256] eq $sha}
    selectMode $strip.choice $w History
    check {shared context timeline describes existing box operation} {[dict get [lindex [dict get [::GX::scientificHistoryViewerSummary $history] steps] 0] description] eq {box}}
    lassign [$strip.timeline bbox history_step_0] x1 y1 x2 y2
    click $strip.timeline 1 [expr {($x1+$x2)/2}] [expr {($y1+$y2)/2}]
    wait {[dict size [dict get $::GX::Workbench3D::model objects]]==0}
    check {native shared timeline browse is scientifically read-only} {![::GX::scientificHistoryViewerEditable $history] && [dict get [::GX::scientificHistoryViewerStatus $history] cursor]==1}
    set menu [context $w $strip]
    check {scientific context popup is application bounded} {[winfo rootx $menu]>=[winfo rootx $w] && [winfo rooty $menu]>=[winfo rooty $w] && [winfo rooty $menu]+[winfo height $menu]<=[winfo rooty $w]+[winfo height $w]+1}
    menuPick $menu {Return to latest}
    wait {[dict size [dict get $::GX::Workbench3D::model objects]]==1 && !$::GX::Engine3D::workerBusy}
    check {shared Latest restores original scientific geometry} {[dict get $::GX::Workbench3D::model objects $object geometry sha256] eq $sha && [::GX::scientificHistoryViewerEditable $history]}
    set menu [context $w $strip]
    menuPick $menu Undo
    wait {[dict size [dict get $::GX::Workbench3D::model objects]]==0 && !$::GX::Engine3D::workerBusy}
    set menu [context $w $strip]
    menuPick $menu Redo
    wait {[dict size [dict get $::GX::Workbench3D::model objects]]==1 && !$::GX::Engine3D::workerBusy}
    check {shared menu Undo Redo delegates to same scientific owner} {[dict get [::GX::scientificHistoryViewerStatus $history] cursor]==1}
    shot scientific-history
    showControl $w $panel.historyVisibility
    click $panel.historyVisibility
    check {manual layout can hide shared History controls} {![winfo ismapped $strip]}
    click $panel.historyVisibility
    check {manual control restores strip without a private timeline implementation} {[winfo ismapped $strip]}
    showControl $w $panel.save
    click $panel.save
    wait {!$::GX::Engine3D::workerBusy}
    set saved [::GX::interactiveDocumentRead $document]
    check {actual Save button persists shared scientific History} {[dict exists $saved payload scientific_history] && [dict get [::GX::scientificHistoryViewerStatus $history] pending]==0}
    set record [::GX::scientificHistoryViewerRecord $history]
    set menu [context $w $strip]
    menuPick $menu {Clear History*}
    modal $w Cancel
    check {real nonWorkspace Document Clear cancellation preserves History} {[::GX::scientificHistoryViewerRecord $history] eq $record}
    set menu [context $w $strip]
    menuPick $menu {Clear History*}
    modal $w No
    check {real shared Clear preserves complete current 3D state} {[dict get [::GX::scientificHistoryViewerStatus $history] count]==0 && [dict get $::GX::Workbench3D::model objects $object geometry sha256] eq $sha}
    shot cleared-current-science
    check {no background errors during manual scientific GUI History flow} {$::G::errors eq {}}
    ::GX::Engine3D::close
    check {public normal close releases scientific context and window} {$::GX::Workbench3D::historyContext eq {} && ![winfo exists $w]}
    write receipt.tcldict [dict create status PASS_MANUAL_3D_HISTORY_GUI checks $::G::checks inputs $::G::input framework $::framework document_id $document geometry_sha256 $sha scope {Original manual Workbench3D UI; native xdotool action input; existing scroll viewport positioning and final public close; no new CAD functionality}]
    set ::G::done 1
}
after 0 {if {[catch {coroutine ::G::actor ::G::run} message options]} {::G::fail $message $options}}
after 165000 {if {!$::G::done} {::G::fail {3D GUI actor timeout} [dict create -errorinfo {3D GUI actor timeout}]}}
vwait ::G::done
if {$::G::failed} {exit 1}
puts {PASS real manual3D History GUI}
exit 0
