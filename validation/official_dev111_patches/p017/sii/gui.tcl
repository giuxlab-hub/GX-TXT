# SPDX-License-Identifier: GPL-3.0-or-later
# Real mapped manual Viewer, xdotool mouse/keyboard; synthetic setup only by API.
if {[llength $argv]!=2} {error {usage: gui.tcl FRAMEWORK NEW_OUTPUT}}
lassign $argv framework out
set framework [file normalize $framework];set out [file normalize $out]
if {[file exists $out]} {error {Fresh output required}}
file mkdir $out
foreach name {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT TMPDIR} {set ::env($name) [file join $out $name];file mkdir $::env($name)}
set ::env(PYTHONDONTWRITEBYTECODE) 1
set argv0 __DEV111_P017_SII_GUI__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
::GX::ensureModuleConfigDefaults
::GX::moduleSetEnabled viewer.scientific_image_inspector 1
package require Tk
wm withdraw .
set ::GX::cfg(output_root) [file join $out Sessions]
::GX::configurationSet storage.cache_dir [file join $out cache]
::GX::configurationSet storage.temp_dir [file join $out temp]
::GX::createNewSession SYNTHETIC_IMAGE_HISTORY
::GX::moduleSetEnabled viewer.scientific_image_inspector 1
namespace eval ::S {variable checks {};variable input {};variable errors {};variable shots {};variable exports 0;variable terminal 0}
proc ::S::emit {name data} {set f [open [file join $::out $name] w];try {fconfigure $f -encoding utf-8;puts $f $data} finally {close $f}}
proc ::S::fail {message options} {
    if {$::S::terminal} return
    set ::S::terminal 1
    set observed {}
    dict for {window adapter} $::GX::ScientificHistory::viewers {
        catch {dict set observed $window status [::GX::scientificHistoryViewerStatus $window]}
        catch {dict set observed $window state [::GX::scientificHistoryViewerState $window]}
        catch {dict set observed $window focus [focus]}
        catch {dict set observed $window strip_mode $::GX::ScientificHistory::strip($window,mode)}
        if {[winfo exists $window] && [winfo viewable $window]} {catch {::S::shot $window failure}}
    }
    emit FIRST_FAILURE.tcldict [dict create message $message options $options checks $::S::checks inputs $::S::input observed $observed background_errors $::S::errors]
    puts stderr [dict get $options -errorinfo]
    set ::S::done 1
}
proc bgerror {message} {lappend ::S::errors $message;puts stderr "BACKGROUND: $message"}
proc ::S::resume {actor} {if {[llength [info commands $actor]] && [catch {$actor} message options]} {::S::fail $message $options}}
proc ::S::pause {{ms 140}} {after $ms [list ::S::resume [info coroutine]];yield}
proc ::S::wait {condition {limit 8000}} {
    set end [expr {[clock milliseconds]+$limit}]
    while {![uplevel 1 [list expr $condition]]} {if {[clock milliseconds]>$end} {error "Timed out: $condition"};pause 40}
}
proc ::S::check {name condition} {
    if {![uplevel 1 [list expr $condition]]} {error "FAIL: $name"}
    lappend ::S::checks [dict create name $name status PASS]
    puts "PASS $name";flush stdout
}
proc ::S::logInput {kind args} {lappend ::S::input [dict create at_ms [clock milliseconds] kind $kind arguments $args]}
proc ::S::focusWindow {window} {
    raise $window;update idletasks
    exec xdotool windowfocus --sync [winfo id $window]
    pause 70
}
proc ::S::click {widget {button 1} {x {}} {y {}}} {
    if {![winfo viewable $widget]} {error "Input widget is not viewable: $widget"}
    if {$x eq {}} {set x [expr {[winfo width $widget]/2}]}
    if {$y eq {}} {set y [expr {[winfo height $widget]/2}]}
    logInput click $widget $button $x $y
    exec xdotool mousemove [expr {[winfo rootx $widget]+$x}] [expr {[winfo rooty $widget]+$y}]
    pause 40
    exec xdotool click $button
    pause
}
proc ::S::key {keys} {logInput key $keys;exec xdotool key --clearmodifiers $keys;pause}
proc ::S::type {widget text} {
    click $widget
    key Home
    key shift+End
    logInput type $widget $text
    exec xdotool type --clearmodifiers --delay 2 -- $text
    key Return
}
proc ::S::widgets {parent} {
    set result [list $parent]
    foreach child [winfo children $parent] {set result [concat $result [widgets $child]]}
    return $result
}
proc ::S::shot {w label} {
    update idletasks
    set path [file join $::out "$label.png"]
    exec import -window root $path
    lappend ::S::shots $path
}
proc ::S::inside {child parent} {
    return [expr {[winfo rootx $child]>=[winfo rootx $parent] && [winfo rooty $child]>=[winfo rooty $parent] && [winfo rootx $child]+[winfo width $child]<=[winfo rootx $parent]+[winfo width $parent]+1 && [winfo rooty $child]+[winfo height $child]<=[winfo rooty $parent]+[winfo height $parent]+1}]
}
proc ::S::menuIndex {m pattern} {
    set end [$m index end]
    for {set i 0} {$end ne {none} && $i<=$end} {incr i} {
        if {[$m type $i] in {separator tearoff}} continue
        if {[string match $pattern [$m entrycget $i -label]]} {return $i}
    }
    error "Menu item '$pattern' absent in $m"
}
proc ::S::menuPick {m pattern} {
    wait {[winfo ismapped $m]}
    set index [menuIndex $m $pattern]
    if {[$m entrycget $index -state] eq {disabled}} {error "Menu item is disabled: $pattern"}
    set y [$m yposition $index]
    set h [expr {[font metrics [$m cget -font] -linespace]+8}]
    click $m 1 35 [expr {$y+$h/2}]
}
proc ::S::context {w} {
    set c [dict get $::GX::ScientificHistory::viewers $w strip].timeline
    click $c 3 25 12
    set m $w.historyContext
    wait {[winfo exists $m] && [winfo ismapped $m]}
    return $m
}
proc ::S::topMenu {w label} {
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
proc ::S::modalButton {parent label} {
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
proc ::S::selector {combo viewer value} {
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
proc ::S::exportTrace {command operation} {incr ::S::exports}

proc ::S::recoverPrompts {} {
    set deadline [expr {[clock milliseconds]+18000}]
    while {!$::S::recoveryDone && [clock milliseconds]<$deadline} {
        set target {}
        if {[winfo exists .scientific_image_inspector]} {
            foreach child [widgets .scientific_image_inspector] {
                if {[winfo class $child] in {Button TButton} && [winfo viewable $child] && [$child cget -text] eq "Yes"} {set target $child;break}
            }
        }
        if {$target ne {}} {click $target;incr ::S::recoveryResponses} else {pause 50}
    }
}
proc ::S::run {} {
    set fixture [file join $::out source.png]
    exec magick -size 320x240 gradient:red-blue $fixture
    set request [dict create dataset_id synthetic_image contract image.raster format png media_type image/png storage_kind binary source_file $fixture source_dataset_ids {} source {P017 synthetic image fixture} producer_version 0.4.1 provenance {Controlled isolated History GUI validation} structured_metadata {fixture.synthetic 1}]
    ::GX::datasetFilePublicationPublish $::GX::currentSession viewer.scientific_image_inspector $request
    set sha [dict get [::GX::sessionInspectionDatasetPayload synthetic_image] sha256]
    ::GX::modulePublicApiActivate viewer.scientific_image_inspector SCIENTIFIC_IMAGE_INSPECTOR_API_v1
    set w [::GX::viewerOpen viewer.scientific_image_inspector scientific_image_inspector {dataset_id synthetic_image}]
    wm geometry $w 1420x950+30+20
    pause 600
    focusWindow $w
    check {manual Image Inspector mapped with canonical source} {[winfo viewable $w] && $::GX::SII::ui(sourceId) eq {synthetic_image} && [::GX::SII::historyAttached]}
    check {three distinct CORE managed native contexts} {[llength [dict keys $::GX::ScientificHistory::viewers]]==3}
    shot $w loaded
    trace add execution ::GX::scientificHistoryViewerRecord enter ::S::exportTrace
    set basic $w.layout.inspector.tabs.simple.basic
    click $basic.previewPreset
    wait {$::GX::SII::ui(pending)}
    click $w.head.approve
    wait {!$::GX::SII::ui(pending) && [llength $::GX::SII::ui(steps)]==1}
    check {native preset acceptance recorded without canonical Document write} {$::GX::SII::ui(documentId) eq {} && [dict get [::GX::scientificHistoryViewerStatus $w] count]>0 && $::S::exports==0}
    set c [::GX::SII::annotationCanvas]
    set toolbar [::GX::native2DViewportPanelWidget $c controls]
    click $toolbar.body.panel
    set menu $c.shapePopup
    menuPick $menu {Draw Rectangle}
    set scene $::GX::SII::ui(native-original)
    lassign [::GX::Native2D::core device $scene {60 180}] x0 y0
    lassign [::GX::Native2D::core device $scene {150 110}] x1 y1
    logInput drag_annotation $c $x0 $y0 $x1 $y1
    exec xdotool mousemove [expr {[winfo rootx $c]+int($x0)}] [expr {[winfo rooty $c]+int($y0)}]
    exec xdotool mousedown 1
    pause 80
    exec xdotool mousemove [expr {[winfo rootx $c]+int($x1)}] [expr {[winfo rooty $c]+int($y1)}]
    pause 100
    exec xdotool mouseup 1
    pause 400
    check {real Native2D annotation gesture joins shared History} {[llength $::GX::SII::ui(annotations)]==1 && [::GX::SII::historyDomainAvailable figure undo]}
    shot $w annotation
    # Dedicated image Undo preserves the later annotation domain.
    set menu [topMenu $w History]
    menuPick $menu Undo
    pause 350
    check {image Undo preserves later annotation edits} {[llength $::GX::SII::ui(steps)]==0 && [llength $::GX::SII::ui(annotations)]==1}
    set menu [topMenu $w History];menuPick $menu Redo
    pause 350
    check {image Redo uses CORE domain cursor} {[llength $::GX::SII::ui(steps)]==1 && [llength $::GX::SII::ui(annotations)]==1}
    focusWindow $w
    key ctrl+shift+z
    pause 250
    check {figure keyboard Undo preserves image recipe} {[llength $::GX::SII::ui(steps)]==1 && [llength $::GX::SII::ui(annotations)]==0}
    key ctrl+shift+y
    pause 250
    check {figure keyboard Redo restores annotation} {[llength $::GX::SII::ui(annotations)]==1}
    check {ordinary image annotation Undo Redo never materializes full histories} {$::S::exports==0}
    set menu [topMenu $w Image];menuPick $menu {Restore original*}
    pause 300
    check {Restore Original clears accepted image and annotation state} {[llength $::GX::SII::ui(steps)]==0 && [llength $::GX::SII::ui(annotations)]==0}
    set menu [topMenu $w History];menuPick $menu Undo
    pause 300
    check {image Undo of Restore Original restores all prior scientific overlays} {[llength $::GX::SII::ui(steps)]==1 && [llength $::GX::SII::ui(annotations)]==1}
    set menu [topMenu $w History];menuPick $menu Redo
    pause 300
    check {image Redo reapplies Restore Original} {[llength $::GX::SII::ui(steps)]==0 && [llength $::GX::SII::ui(annotations)]==0}
    set menu [topMenu $w History];menuPick $menu Undo
    pause 300
    check {second Restore Original Undo preserves image and annotation recipe} {[llength $::GX::SII::ui(steps)]==1 && [llength $::GX::SII::ui(annotations)]==1}
    check {Restore Original Undo Redo remains incremental} {$::S::exports==0}
    trace remove execution ::GX::scientificHistoryViewerRecord enter ::S::exportTrace
    set strip [dict get $::GX::ScientificHistory::viewers $w strip]
    selector $strip.choice $w History
    set before [::GX::SII::historySnapshot]
    click $strip.timeline 1 20 12
    pause 350
    check {shared timeline browse locks scientific editing} {$::GX::SII::ui(historyBrowsing) && ![::GX::scientificHistoryViewerEditable $w]}
    check {read-only browse blocks image and annotation mutation} {[::GX::SII::historyReadOnly] && [::GX::SII::annotationLocked]}
    set menu [context $w]
    check {History popup upper placement bounded by application} {[inside $menu $w] && [winfo rooty $menu]<[winfo rooty $strip.timeline]}
    shot $w bounded-history-popup
    menuPick $menu {Return to latest*}
    pause 350
    check {Latest restores scientific state and editability} {!$::GX::SII::ui(historyBrowsing) && [dict remove [::GX::SII::historySnapshot] history_channels] eq [dict remove $before history_channels]}
    set menu [topMenu $w Workspace]
    menuPick $menu Save
    pause 300
    set id $::GX::SII::ui(documentId)
    check {explicit Save creates bound canonical Document with all histories} {$id ne {} && [dict exists [dict get [::GX::sessionWorkspaceGet $id] payload] domain_history image] && [dict exists [dict get [::GX::sessionWorkspaceGet $id] payload] scientific_history]}
    foreach key [list $w $::GX::SII::ui(history-image) $::GX::SII::ui(history-figure)] {check {Save has no pending native writes} {[dict get [::GX::scientificHistoryViewerStatus $key] pending]==0}}
    set saved [dict get [::GX::sessionWorkspaceGet $id] payload]
    set menu [topMenu $w File];menuPick $menu Close
    wait {![winfo exists $w]}
    set w [::GX::viewerOpen viewer.scientific_image_inspector scientific_image_inspector [dict create workspace_id $id]]
    pause 600
    focusWindow $w
    check {explicit reopen preserves recipe and annotation and domain redo state} {[llength $::GX::SII::ui(steps)]==1 && [llength $::GX::SII::ui(annotations)]==1 && [::GX::SII::historyDomainAvailable image undo] && [::GX::SII::historyDomainAvailable figure undo]}
    # A bounded model-only retention check complements the native pointer path;
    # it proves the former 80-state trim is gone without repeating a GUI matrix.
    set countBefore [dict get [::GX::scientificHistoryViewerStatus $w] count]
    for {set i 0} {$i<90} {incr i} {
        set item [lindex $::GX::SII::ui(annotations) 0]
        dict set item name "Retained annotation $i"
        set ::GX::SII::ui(annotations) [list $item]
        ::GX::SII::saveState
    }
    check {more than eighty operations retain complete native History} {[dict get [::GX::scientificHistoryViewerStatus $w] count]==$countBefore+90}
    ::GX::SII::refreshAnnotations
    ::GX::SII::nativeDrawAnnotations
    # Confirmed main restart preserves the chosen checkpoint and reconstitutes
    # image-recipe Undo while explicitly clearing later figure domain controls.
    set strip [dict get $::GX::ScientificHistory::viewers $w strip]
    selector $strip.choice $w History
    click $strip.timeline 1 20 12
    pause 200
    set menu [context $w]
    menuPick $menu {Restart*}
    pause 150
    modalButton $w OK
    pause 300
    check {confirmed main restart returns editable selected scientific checkpoint} {!$::GX::SII::ui(historyBrowsing) && [dict get [::GX::scientificHistoryViewerStatus $w] cursor]==[dict get [::GX::scientificHistoryViewerStatus $w] count]}
    # Step zero has no image operation; build one through the real preset path.
    click $basic.previewPreset
    wait {$::GX::SII::ui(pending)}
    click $w.head.approve
    wait {!$::GX::SII::ui(pending) && [llength $::GX::SII::ui(steps)]==1}
    set scientificBeforeClear [dict remove [::GX::SII::historySnapshot] history_channels]
    set menu [context $w]
    menuPick $menu {Clear History*}
    pause 150
    modalButton $w No
    pause 300
    check {confirmed shared Clear keeps scientific state and resets all controls} {[dict get [::GX::scientificHistoryViewerStatus $w] count]==0 && [dict remove [::GX::SII::historySnapshot] history_channels] eq $scientificBeforeClear && ![::GX::SII::historyDomainAvailable figure undo]}
    set menu [topMenu $w Workspace];menuPick $menu Save
    check {Save after Clear retains zero timeline and no domain Undo} {[dict get [::GX::scientificHistoryViewerStatus $w] count]==0 && ![::GX::SII::historyDomainAvailable image undo] && ![::GX::SII::historyDomainAvailable figure undo]}
    set savedSteps [llength [dict get [dict get [::GX::sessionWorkspaceGet $id] payload] steps]]
    click $basic.previewPreset
    wait {$::GX::SII::ui(pending)}
    click $w.head.approve
    wait {!$::GX::SII::ui(pending) && [llength $::GX::SII::ui(steps)]==$savedSteps+1}
    check {bound normal acceptance keeps saved Document revision content unchanged} {[llength [dict get [dict get [::GX::sessionWorkspaceGet $id] payload] steps]]==$savedSteps}
    # Controlled interrupted-lifecycle fixture: close contexts with project=0,
    # preserving their drained journals while leaving the last saved Document.
    # Then normal GUI reopen explicitly chooses recovery for the real prompts.
    ::GX::SII::historyDetach 0
    ::GX::SII::guiClose
    set ::S::recoveryDone 0
    set ::S::recoveryResponses 0
    after 100 {coroutine ::S::recoveryActor ::S::recoverPrompts}
    set w [::GX::viewerOpen viewer.scientific_image_inspector scientific_image_inspector [dict create workspace_id $id]]
    set ::S::recoveryDone 1
    pause 500
    check {real recovery reconciles general and qualified domain journals} {[llength $::GX::SII::ui(steps)]==$savedSteps+1 && $::S::recoveryResponses>=1 && [::GX::SII::historyImageSnapshot] eq [::GX::scientificHistoryViewerState $::GX::SII::ui(history-image)] && [::GX::SII::historyFigureSnapshot] eq [::GX::scientificHistoryViewerState $::GX::SII::ui(history-figure)]}
    set menu [topMenu $w Workspace];menuPick $menu Save
    check {recovered scientific state projects only on explicit Save} {[llength [dict get [dict get [::GX::sessionWorkspaceGet $id] payload] steps]]==$savedSteps+1}
    # Read a real prior-format Workspace through the unchanged provider schema.
    set legacy [dict remove [dict get [::GX::sessionWorkspaceGet $id] payload] scientific_history domain_history]
    set current [dict remove [::GX::SII::historySnapshot] history_channels source_id source_sha image_reset_previous]
    set original $current
    dict set original steps {}
    dict set original image_annotations {}
    dict set original figure_annotations {}
    dict set legacy history_timeline [list [dict create kind base label {Original image} state $original] [dict create kind image label {Legacy accepted image operation} state $current]]
    set legacyId [dict get [::GX::sessionWorkspaceCreate scientific_image_inspector {Legacy timeline import fixture} $legacy] workspace_id]
    set menu [topMenu $w File];menuPick $menu Close
    wait {![winfo exists $w]}
    set w [::GX::viewerOpen viewer.scientific_image_inspector scientific_image_inspector [dict create workspace_id $legacyId]]
    pause 400
    check {legacy timeline imports without losing its base or current scientific state} {[dict get [::GX::scientificHistoryViewerStatus $w] count]>=1 && [llength $::GX::SII::ui(steps)]==$savedSteps+1 && [dict get [::GX::scientificHistoryState [::GX::scientificHistoryViewerRecord $w] 0] steps] eq {}}
    set menu [topMenu $w Workspace];menuPick $menu Save
    check {legacy Workspace saves compatible shared History fields} {[dict exists [dict get [::GX::sessionWorkspaceGet $legacyId] payload] scientific_history] && [dict exists [dict get [::GX::sessionWorkspaceGet $legacyId] payload] domain_history image]}
    check {source scientific payload fingerprint unchanged} {[dict get [::GX::sessionInspectionDatasetPayload synthetic_image] sha256] eq $sha}
    check {no GUI background callback errors} {$::S::errors eq {}}
    shot $w reopened
    emit receipt.tcldict [dict create status PASS_REAL_SII_HISTORY_GUI checks $::S::checks inputs $::S::input screenshots $::S::shots framework $::framework workspace_id $id source_sha256 $sha ordinary_full_record_exports $::S::exports scope {Mapped manual SII Viewer, actual xdotool controls and Native2D drawing; isolated synthetic API setup, user final GUI acceptance pending}]
    ::GX::SII::guiClose
    set ::S::terminal 1;set ::S::done 1
}
after 0 {if {[catch {coroutine ::S::actor ::S::run} message options]} {::S::fail $message $options}}
after 120000 {if {!$::S::terminal} {::S::fail {GUI actor timeout} [dict create -errorinfo {GUI actor timeout}]}}
vwait ::S::done
if {[file exists [file join $out FIRST_FAILURE.tcldict]]} {exit 1}
puts {PASS real SII History GUI}
exit 0
