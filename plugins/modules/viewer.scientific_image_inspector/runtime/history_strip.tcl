# Scientific Image Inspector - Description/History bottom strip.
# SPDX-License-Identifier: GPL-3.0-or-later
# Follows the Curve Workbench compact strip/popup model. Image/annotation
# snapshots are *viewer recipes*, not a duplicate Dataset or Workspace registry.
namespace eval ::GX::SII {}

# Editing commands explicitly request a writable state. A historical step is
# only a read-only visual inspection: return to Latest, never rewrite/truncate
# past History without confirmation. Pending image adjustments remain locked.
proc ::GX::SII::historyResumeForEditing {} {
    variable ui
    if {[info exists ui(pending)] && $ui(pending)} {
        set ui(status) {Accept or discard the image adjustment before editing.}
        return 0
    }
    if {[info exists ui(historyBrowsing)] && $ui(historyBrowsing)} {
        historyBrowse [expr {[llength $ui(historyTimeline)]-1}]
        if {$ui(historyBrowsing)} {
            set ui(status) {Could not return to the latest History state; editing is disabled.}
            return 0
        }
    }
    return 1
}
proc ::GX::SII::historyReadOnly {} {
    variable ui
    if {[info exists ui(historyBrowsing)] && $ui(historyBrowsing)} {
        set ui(status) {History inspection is read-only. Click Latest to resume editing, or explicitly restart from a historical step.}
        return 1
    }
    return 0
}
proc ::GX::SII::historySnapshot {} {
    variable ui
    if {![info exists ui(info)]} {return {}}
    set composed $ui(figurePreviewActive)
    set image [expr {$composed ? $ui(imageAnnotations) : $ui(annotations)}]
    set figure [expr {$composed ? $ui(annotations) : $ui(figureAnnotations)}]
    return [dict create steps $ui(steps) panels $ui(panels) \
        image_annotations $image figure_annotations $figure \
        canvas_mode [expr {$composed ? "figure" : "image"}] \
        figure_settings [figureSettings]]
}
proc ::GX::SII::historyStripCreate {w} {
    variable ui
    # Workbench pattern: status/description and a horizontal timeline occupy
    # the same strip; the picture canvas loses only one short row.
    ttk::frame $w.strip -height 36
    pack propagate $w.strip 0
    pack forget $w.footer
    pack $w.strip -side bottom -fill x
    # A ttk::combobox near the bottom of the screen can open its native
    # drop-down *below* the Viewer (observed with Tk on Windows). Use a compact
    # upward-opening menubutton, while retaining the same Description/History
    # state and timeline API.
    ttk::menubutton $w.strip.choice -textvariable ::GX::SII::ui(historyStripView) \
        -width 13 -menu $w.strip.choice.menu
    menu $w.strip.choice.menu -tearoff 0
    foreach mode {Description History} {
        $w.strip.choice.menu add radiobutton -label $mode -value $mode \
            -variable ::GX::SII::ui(historyStripView) -command ::GX::SII::historyStripSwitch
    }
    bind $w.strip.choice <Button-1> {::GX::SII::historyChoicePopup; break}
    bind $w.strip.choice <Return> {::GX::SII::historyChoicePopup; break}
    bind $w.strip.choice <space> {::GX::SII::historyChoicePopup; break}
    pack $w.strip.choice -side left -fill y -padx 3
    pack $w.footer -in $w.strip -side left -fill x -expand 1
    canvas $w.strip.timeline -height 28 -highlightthickness 0 -background #edf1f5 \
        -xscrollincrement 20
    bind $w.strip.timeline <Button-1> {::GX::SII::historyStripClick %x %y}
    bind $w.strip.timeline <Button-3> {::GX::SII::guardEvent {History context menu} [list ::GX::SII::historyStripContext %x %y %X %Y]}
    bind $w.strip.timeline <MouseWheel> {::GX::SII::historyStripWheel %D}
    bind $w.strip.timeline <Button-4> {%W xview scroll -3 units}
    bind $w.strip.timeline <Button-5> {%W xview scroll 3 units}
    historyStripSwitch
}
# Always place the two-option popup ABOVE its control. Clamping occurs in
# tk_popup as well, so moving/resizing the Viewer does not strand the menu.
proc ::GX::SII::historyChoicePopup {} {
    variable ui
    set button $ui(window).strip.choice
    if {![winfo exists $button]} return
    set menu $button.menu
    update idletasks
    set height [expr {max(60,[winfo reqheight $menu]+12)}]
    set x [winfo rootx $button]
    set y [expr {[winfo rooty $button] - $height - 2}]
    tk_popup $menu $x [expr {max(0,$y)}]
}
proc ::GX::SII::historyStripShow {} {
    variable ui
    set w $ui(window)
    if {$ui(historyStripVisible)} {pack $w.strip -side bottom -fill x} else {pack forget $w.strip}
}
proc ::GX::SII::historyStripSwitch {} {
    variable ui
    set w $ui(window)
    if {![winfo exists $w.strip]} return
    pack forget $w.footer $w.strip.timeline
    if {$ui(historyStripView) eq "History"} {
        pack $w.strip.timeline -side left -fill both -expand 1
        historyStripRender
    } else {pack $w.footer -in $w.strip -side left -fill x -expand 1}
}
proc ::GX::SII::historyStripWheel {delta} {
    variable ui
    if {$delta==0} return
    $ui(window).strip.timeline xview scroll [expr {$delta>0?-3:3}] units
}
proc ::GX::SII::historyStripReset {} {
    variable ui
    set ui(historyBrowsing) 0
    unset -nocomplain ui(historyLive)
    set ui(historyTimeline) {}
    if {[info exists ui(info)]} {
        lappend ui(historyTimeline) [dict create kind base label {Original image} state [historySnapshot]]
    }
    set ui(historyCursor) 0
    historyStripRender
}
proc ::GX::SII::historyStripRestore {saved} {
    variable ui
    set ui(historyBrowsing) 0
    unset -nocomplain ui(historyLive)
    if {[catch {llength $saved} n] || $n>80 || $n<1} {
        historyStripReset
        return
    }
    foreach record $saved {
        foreach key {kind label state} {if {![dict exists $record $key]} {historyStripReset;return}}
        if {[catch {dict size [dict get $record state]}]} {historyStripReset;return}
    }
    set ui(historyTimeline) $saved
    set ui(historyCursor) [expr {[llength $saved]-1}]
    # Older Workspaces have no timeline: their current state is the base.
    # For consistent saved recipes, the last timeline state is identical to
    # the persisted authoritative working project state.
    if {[dict get [lindex $saved end] state] ne [historySnapshot]} {
        set ui(historyTimeline) [list [dict create kind base label {Loaded Workspace} state [historySnapshot]]]
        set ui(historyCursor) 0
    }
    historyStripRender
}
proc ::GX::SII::historyChangeKind {previous current} {
    if {[dict get $previous steps] ne [dict get $current steps]} {return image}
    if {[dict get $previous panels] ne [dict get $current panels] ||
        [dict get $previous figure_settings] ne [dict get $current figure_settings] ||
        [dict get $previous canvas_mode] ne [dict get $current canvas_mode]} {return figure}
    if {[dict get $previous image_annotations] ne [dict get $current image_annotations] ||
        [dict get $previous figure_annotations] ne [dict get $current figure_annotations]} {return annotation}
    return edit
}
proc ::GX::SII::historyObserve {} {
    variable ui
    if {![info exists ui(info)] || $ui(historyBrowsing)} return
    if {![llength $ui(historyTimeline)]} {historyStripReset}
    set state [historySnapshot]
    set previous [dict get [lindex $ui(historyTimeline) end] state]
    if {$state eq $previous} return
    set kind [historyChangeKind $previous $state]
    switch $kind {
        image {
            set steps [dict get $state steps]
            if {[llength $steps]>[llength [dict get $previous steps]]} {
                set op [dict get [lindex $steps end] op]
                set label "Image: $op"
            } elseif {![llength $steps]} {set label {Restore original}} else {set label {Edit image recipe}}
        }
        figure {set label {Update article figure}}
        annotation {set label {Edit annotation overlay}}
        default {set label {Edit project}}
    }
    lappend ui(historyTimeline) [dict create kind $kind label $label state $state]
    # Bound historical snapshots, retaining the earliest state while trimming
    # old intermediate edits. No retained source pixels enter this structure.
    if {[llength $ui(historyTimeline)]>80} {
        set ui(historyTimeline) [linsert [lrange $ui(historyTimeline) end-78 end] 0 [lindex $ui(historyTimeline) 0]]
    }
    set ui(historyCursor) [expr {[llength $ui(historyTimeline)]-1}]
    historyStripRender
}
proc ::GX::SII::historyStripRender {} {
    variable ui
    if {![info exists ui(window)] || ![winfo exists $ui(window).strip.timeline]} return
    set c $ui(window).strip.timeline
    $c delete all
    set n [llength $ui(historyTimeline)]
    set x 3
    for {set i 0} {$i<$n} {incr i} {
        set record [lindex $ui(historyTimeline) $i]
        set kind [dict get $record kind]
        set tag step$i
        set fill [expr {$i==$ui(historyCursor) ? "#c5dff4" : "#edf1f5"}]
        set color [expr {$i>$ui(historyCursor) ? "#a8b0ba" : "#213c57"}]
        $c create rectangle $x 2 [expr {$x+47}] 26 -fill $fill -outline #c7cdd5 -tags $tag
        switch $kind {
            base {set glyph O}
            image {set glyph I}
            figure {set glyph F}
            annotation {set glyph A}
            default {set glyph +}
        }
        $c create text [expr {$x+24}] 14 -text "$glyph $i" -fill $color -tags $tag
        $c bind $tag <Enter> [list ::GX::SII::historyStripHint $i]
        incr x 51
    }
    $c configure -scrollregion [list 0 0 $x 28]
}
proc ::GX::SII::historyStripHint {index} {
    variable ui
    if {$index<0 || $index>=[llength $ui(historyTimeline)]} return
    set ui(status) "History $index: [dict get [lindex $ui(historyTimeline) $index] label]. Click to inspect; right-click for actions."
}
proc ::GX::SII::historyStripHit {x y} {
    variable ui
    set c $ui(window).strip.timeline
    set cx [$c canvasx $x];set cy [$c canvasy $y]
    set hit [lindex [$c find overlapping $cx $cy $cx $cy] end]
    if {$hit eq {}} {return -1}
    foreach tag [$c gettags $hit] {if {[regexp {^step([0-9]+)$} $tag -> i]} {return $i}}
    return -1
}
proc ::GX::SII::historyStripClick {x y} {
    set index [historyStripHit $x $y]
    if {$index>=0} {historyBrowse $index}
}
proc ::GX::SII::historyDisplayState {state} {
    variable ui
    set mode [dict get $state canvas_mode]
    # Exactly the same non-destructive source/recipe/overlay separation as the
    # normal editor. No sessionWorkspaceUpdate is called during inspection.
    set ui(figurePreviewActive) 0
    set ui(steps) [dict get $state steps]
    set ui(panels) [dict get $state panels]
    set ui(imageAnnotations) [dict get $state image_annotations]
    set ui(figureAnnotations) [dict get $state figure_annotations]
    set ui(annotations) $ui(imageAnnotations)
    set ui(annotationActiveId) {}
    set ui(selectedAnnotationIds) {}
    dict for {field value} [dict get $state figure_settings] {set ui(figure-$field) $value}
    refreshSteps
    refreshPanels
    if {![renderImages]} {error {Could not render historical image preview}}
    if {$mode eq "figure" && [llength $ui(panels)]} {previewFigure}
    refreshAnnotations
    annotationToolbarSync
}
proc ::GX::SII::historyBrowsingLock {enabled} {
    variable ui
    set w $ui(window)
    # A historic preview is read-only. Unlike a filter preview, navigation of
    # the History strip remains available to return to the latest state.
    foreach name {file edit image analyze operations workspace configuration} {
        catch {$w.menu entryconfigure [string totitle $name] -state [expr {$enabled ? "disabled" : "normal"}]}
    }
    foreach widget [list $w.head.ds $w.head.refresh $w.head.preview] {
        if {$enabled} {catch {$widget state disabled}} else {catch {$widget state !disabled}}
    }
    pendingSetChildren $w.layout.inspector.tabs $enabled
    if {$enabled} {set ui(annotating) 0;set ui(canvasMode) view;set ui(annotationTransform) none}
}
proc ::GX::SII::historyBrowse {index} {
    variable ui
    if {$ui(pending)} {set ui(status) {Accept or discard the processing preview before viewing History.};return}
    set count [llength $ui(historyTimeline)]
    if {!$count || $index<0 || $index>=$count} return
    if {!$ui(historyBrowsing)} {set ui(historyLive) [historySnapshot]}
    set newest [expr {$count-1}]
    set previous [historySnapshot]
    set wasBrowsing $ui(historyBrowsing)
    set previousCursor $ui(historyCursor)
    if {$index==$newest} {
        set desired [expr {[info exists ui(historyLive)] ? $ui(historyLive) : [dict get [lindex $ui(historyTimeline) end] state]}]
    } else {set desired [dict get [lindex $ui(historyTimeline) $index] state]}
    set ui(historyBrowsing) 1
    if {[catch {historyDisplayState $desired} error]} {
        catch {historyDisplayState $previous}
        set ui(historyBrowsing) $wasBrowsing
        set ui(historyCursor) $previousCursor
        historyBrowsingLock $wasBrowsing
        set ui(status) "History preview failed: $error"
        return
    }
    set ui(historyCursor) $index
    if {$index==$newest} {
        set ui(historyBrowsing) 0
        unset -nocomplain ui(historyLive)
        historyBrowsingLock 0
        set ui(status) "Latest state restored: $newest / $newest. Editing enabled."
    } else {
        historyBrowsingLock 1
        set ui(status) "Inspecting History $index / $newest — read-only. Select Latest to edit."
    }
    historyStripRender
}
proc ::GX::SII::historyRestart {index} {
    variable ui
    set count [llength $ui(historyTimeline)]
    if {!$count || $index<0 || $index>=$count-1} return
    set remaining [expr {$count-1-$index}]
    if {$remaining==0} {historyBrowse $index;return}
    if {[tk_messageBox -parent $ui(window) -type okcancel -default cancel \
        -icon warning -title {Restart from History} -message \
        "Discard $remaining later editing steps and restart at step $index? This changes the Workspace recipe; the source Dataset will remain unchanged."] ne "ok"} return
    set state [dict get [lindex $ui(historyTimeline) $index] state]
    set ui(historyTimeline) [lrange $ui(historyTimeline) 0 $index]
    set ui(historyCursor) $index
    set ui(historyBrowsing) 0
    unset -nocomplain ui(historyLive)
    historyBrowsingLock 0
    historyDisplayState $state
    set ui(redo) {};set ui(figureRedo) {};set ui(figureUndo) {}
    saveState
    historyStripRender
}
proc ::GX::SII::historyStripContext {x y X Y} {
    variable ui
    set index [historyStripHit $x $y]
    if {$index<0 || $index>=[llength $ui(historyTimeline)]} return
    set record [lindex $ui(historyTimeline) $index]
    set m $ui(window).strip.menu
    if {![winfo exists $m]} {menu $m -tearoff 0}
    $m delete 0 end
    $m add command -label "Inspect step $index — [dict get $record label]" -command [list ::GX::SII::guardEvent {History inspection} [list ::GX::SII::historyBrowse $index]]
    $m add command -label {Return to latest state} -command [list ::GX::SII::guardEvent {History latest} [list ::GX::SII::historyBrowse [expr {[llength $ui(historyTimeline)]-1}]]]
    $m add separator
    $m add command -label {Restart editing here; discard future...} -command [list ::GX::SII::guardEvent {History restart} [list ::GX::SII::historyRestart $index]]
    if {[llength [info commands ::GX::uiMenuPopup]]} {::GX::uiMenuPopup $m $X $Y} else {tk_popup $m $X $Y}
}
