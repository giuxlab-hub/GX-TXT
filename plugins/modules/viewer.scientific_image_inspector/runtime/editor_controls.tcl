# Scientific Image Inspector — editor selection and preferences.
# SPDX-License-Identifier: GPL-3.0-or-later
# Adapted to Native2D's semantic object picking, polygon selection and
# world/device conversion. Does not use a second geometry or Workspace registry.
namespace eval ::GX::SII {}

proc ::GX::SII::annotationSelectMode {mode} {
    variable ui
    if {![historyResumeForEditing] || [annotationLocked]} return
    if {$mode ni {object window polygon roi}} {error {Unknown selection mode}}
    set c [annotationCanvas]
    $c delete sii_selection_gesture
    unset -nocomplain ui(selectionPolygon) ui(selectionWindowStart)
    if {$mode eq "roi"} {
        annotationMode 0
        set ui(selectionMode) roi
        set ui(status) {IMAGE ROI — drag a rectangle to select pixels for processing. Annotation objects are not selected.}
    } else {
        if {!$ui(annotating)} {annotationMode 1}
        set ui(canvasMode) annotate
        set ui(annotationTool) Select
        set ui(annotationTransform) none
        set ui(selectionMode) $mode
        set ui(status) [dict get [dict create \
            object {SELECT OBJECT — click an annotation; Shift+click toggles it. Right-click the Select icon for other modes.} \
            window {SELECT WINDOW — drag a rectangle to select annotation objects.} \
            polygon {SELECT POLYGON — click polygon corners; double-click to finish selection.}] $mode]
    }
    annotationToolbarSync
    nativeDrawAnnotations
}

proc ::GX::SII::annotationSelectPopup {X Y} {
    variable ui
    if {$ui(pending)} return
    set c [annotationCanvas]
    set m $c.selectPopup
    if {![winfo exists $m]} {menu $m -tearoff 0}
    $m delete 0 end
    foreach {mode label} {
        object {Select object (click / Shift-click)}
        window {Select annotations in window}
        polygon {Select annotations in polygon}
        roi {Select image ROI (pixel processing)}
    } {
        $m add radiobutton -label $label -variable ::GX::SII::ui(selectionMode) -value $mode \
            -command [list ::GX::SII::annotationSelectMode $mode]
    }
    $m add separator
    $m add command -label {Select all annotations} -command ::GX::SII::editSelectAll
    $m add command -label {Select none} -command ::GX::SII::editSelectNone
    $m add separator
    $m add command -label {Finish annotation editing (Esc)} -command {::GX::SII::annotationMode 0}
    if {[llength [info commands ::GX::uiMenuPopup]]} {
        ::GX::uiMenuPopup $m $X $Y
    } else {tk_popup $m $X $Y}
}

proc ::GX::SII::annotationSelectionSet {ids} {
    variable ui
    set valid {}
    foreach a $ui(annotations) {
        set id [get $a id {}]
        if {$id in $ids && $id ni $valid} {lappend valid $id}
    }
    set ui(selectedAnnotationIds) $valid
    set ui(annotationActiveId) [expr {[llength $valid] ? [lindex $valid end] : {}}]
    set lb $ui(window).layout.inspector.tabs.annotations.list
    if {[winfo exists $lb]} {
        $lb selection clear 0 end
        set i 0
        foreach a $ui(annotations) {
            if {[get $a id {}] in $valid} {$lb selection set $i}
            incr i
        }
    }
    set count [llength $valid]
    set ui(status) [expr {$count==0 ? {No annotation selected.} : "$count annotation object(s) selected — use Transform or Edit > Copy."}]
    nativeDrawAnnotations
}

proc ::GX::SII::annotationSelectionToggle {index} {
    variable ui
    if {$index<0 || $index>=[llength $ui(annotations)]} return
    set id [dict get [lindex $ui(annotations) $index] id]
    set prior [expr {[info exists ui(selectedAnnotationIds)] ? $ui(selectedAnnotationIds) : {}}]
    set n [lsearch -exact $prior $id]
    if {$n<0} {lappend prior $id} else {set prior [lreplace $prior $n $n]}
    annotationSelectionSet $prior
}

proc ::GX::SII::annotationGestureDraw {points mode} {
    set c [annotationCanvas]
    $c delete sii_selection_gesture
    set flat {}
    if {$mode eq "window"} {
        lassign [lindex $points 0] x0 y0
        lassign [lindex $points 1] x1 y1
        $c create rectangle $x0 $y0 $x1 $y1 -dash {5 4} -outline #22B8F0 \
            -width 2 -tags sii_selection_gesture
    } else {
        foreach point $points {lappend flat {*}$point}
        if {[llength $flat]>=4} {
            $c create line {*}$flat -dash {5 4} -width 2 -fill #22B8F0 \
                -tags sii_selection_gesture
        }
        foreach point $points {
            lassign $point x y
            $c create oval [expr {$x-3}] [expr {$y-3}] [expr {$x+3}] [expr {$y+3}] \
                -fill #22B8F0 -outline #20252C -tags sii_selection_gesture
        }
    }
}

proc ::GX::SII::annotationPolygonPoint {x y} {
    variable ui
    if {![info exists ui(selectionPolygon)]} {set ui(selectionPolygon) {}}
    if {[llength $ui(selectionPolygon)] >= 4095} {
        set ui(status) {Polygon selection supports up to 4096 vertices. Double-click to finish.}
        return
    }
    set point [list $x $y]
    if {[llength $ui(selectionPolygon)] && [lindex $ui(selectionPolygon) end] eq $point} return
    lappend ui(selectionPolygon) $point
    annotationGestureDraw $ui(selectionPolygon) polygon
}

proc ::GX::SII::annotationPolygonFinish {} {
    variable ui
    if {![info exists ui(selectionPolygon)]} return
    set points $ui(selectionPolygon)
    unset ui(selectionPolygon)
    [annotationCanvas] delete sii_selection_gesture
    if {[llength $points]<3} {
        set ui(status) {A polygon selection needs at least three distinct corners.}
        return
    }
    annotationSelectRegion $points
}

proc ::GX::SII::annotationSelectRegion {devicePolygon} {
    variable ui
    if {[annotationLocked]} return
    set scene [annotationScene]
    # Coordinates are converted by Native2D, and polygon containment / object
    # intersection is evaluated by its retained semantic selection engine.
    set polygon {}
    foreach point $devicePolygon {
        lappend polygon [::GX::Native2D::core world $scene $point]
    }
    set tokens {}
    dict for {id objects} $ui(nativeAnnotationMap) {
        foreach token $objects {lappend tokens $token}
    }
    set ids {}
    if {[llength $tokens]} {
        if {[catch {
            set selected [::GX::Native2D::core selection_region $scene $tokens $polygon 65536 object]
        } err]} {
            set ui(status) "Native2D selection was rejected: $err"
            return
        }
        foreach member $selected {
            set token [dict get $member id]
            dict for {id objects} $ui(nativeAnnotationMap) {
                if {$token in $objects && $id ni $ids} {lappend ids $id}
            }
        }
    }
    annotationSelectionSet $ids
    set ui(selectionMode) object
}

proc ::GX::SII::annotationEscape {} {
    variable ui
    if {[info exists ui(selectionPolygon)] || [info exists ui(selectionWindowStart)]} {
        unset -nocomplain ui(selectionPolygon) ui(selectionWindowStart)
        [annotationCanvas] delete sii_selection_gesture
        set ui(selectionMode) object
        set ui(status) {Selection cancelled. Select an annotation or right-click the Select icon.}
        return
    }
    annotationMode 0
}

proc ::GX::SII::editFocusInText {} {
    set f [focus]
    if {$f eq {} || ![winfo exists $f]} {return 0}
    return [expr {[winfo class $f] in {Entry TEntry Text TCombobox TSpinbox Spinbox}}]
}
proc ::GX::SII::editSelectAll {} {
    variable ui
    if {[editFocusInText] || [annotationLocked]} return
    if {![info exists ui(workingInfo)]} return
    if {!$ui(annotating)} {annotationSelectMode object}
    set ids {}
    foreach a $ui(annotations) {lappend ids [dict get $a id]}
    annotationSelectionSet $ids
}
proc ::GX::SII::editSelectNone {} {
    variable ui
    if {[editFocusInText] || [annotationLocked]} return
    set ui(roi) {}
    if {[info exists ui(window)] && [winfo exists $ui(window)]} {drawRoi}
    annotationSelectionSet {}
}
proc ::GX::SII::editCopy {} {
    variable ui
    if {[editFocusInText] || [annotationLocked]} return
    set selected [expr {[info exists ui(selectedAnnotationIds)] ? $ui(selectedAnnotationIds) : {}}]
    set payload {}
    foreach a $ui(annotations) {
        if {[dict get $a id] in $selected} {lappend payload $a}
    }
    set ui(annotationClipboard) $payload
    set ui(status) "[llength $payload] annotation object(s) copied to the Viewer clipboard."
}
proc ::GX::SII::editPaste {} {
    variable ui
    if {[editFocusInText] || [annotationLocked]} return
    if {![info exists ui(workingInfo)] || ![info exists ui(annotationClipboard)]} return
    if {![llength $ui(annotationClipboard)]} return
    set iw [dict get $ui(workingInfo) width]
    set ih [dict get $ui(workingInfo) height]
    set candidates {}
    # Keep the clipboard independent of Workspace/source identity. Every
    # pasted object obtains a fresh stable annotation ID on commit.
    foreach source $ui(annotationClipboard) {
        set a [dict remove $source id]
        foreach key {x1 x2 pivot_x} {
            if {[dict exists $a $key]} {
                dict set a $key [expr {min($iw,max(0,[dict get $a $key]+16))}]
            }
        }
        foreach key {y1 y2 pivot_y} {
            if {[dict exists $a $key]} {
                dict set a $key [expr {min($ih,max(0,[dict get $a $key]+16))}]
            }
        }
        dict set a name "[get $a name [dict get $a kind]] copy"
        if {[catch {set a [validateAnnotation $a $iw $ih]} err]} {
            set ui(status) "Paste rejected (no changes): $err"
            return
        }
        lappend candidates $a
    }
    recordFigureEdit
    foreach a $candidates {lappend ui(annotations) $a}
    annotationsEnsureIds
    set selected {}
    foreach a [lrange $ui(annotations) end-[expr {[llength $candidates]-1}] end] {
        lappend selected [dict get $a id]
    }
    refreshAnnotations
    annotationSelectMode object
    annotationSelectionSet $selected
    saveState
}
proc ::GX::SII::editUndo {} {
    variable ui
    if {[editFocusInText] || [annotationLocked]} return
    if {[info exists ui(editDomain)] && $ui(editDomain) eq "annotations" && [llength $ui(figureUndo)]} {
        undoFigure
        set ui(editDomain) annotations
    } else {
        undo
        set ui(editDomain) image
    }
}
proc ::GX::SII::editRedo {} {
    variable ui
    if {[editFocusInText] || [annotationLocked]} return
    if {[info exists ui(editDomain)] && $ui(editDomain) eq "annotations" && [llength $ui(figureRedo)]} {
        redoFigure
    } else {redo}
}

proc ::GX::SII::viewerSettingsDialog {} {
    variable ui
    set w $ui(window).viewerSettings
    if {[winfo exists $w]} {raise $w;focus $w;return}
    toplevel $w
    wm title $w {Scientific Image Inspector — Viewer Settings}
    wm transient $w $ui(window)
    wm geometry $w 550x390
    ttk::notebook $w.tabs
    pack $w.tabs -fill both -expand 1 -padx 12 -pady 12
    foreach {key title} {interface Interface annotations Annotations processing Processing} {
        ttk::frame $w.tabs.$key -padding 15
        $w.tabs add $w.tabs.$key -text $title
    }
    set f $w.tabs.interface
    ttk::label $f.h -text {Workspace display and navigation} -font TkHeadingFont
    ttk::button $f.sidebar -text {Choose visible sidebar sections...} -command ::GX::SII::sidebarPreferencesDialog
    ttk::checkbutton $f.compare -text {Synchronize comparison zoom and pan} -variable ::GX::SII::ui(sync)
    ttk::checkbutton $f.grid -text {Show pixel coordinate grid} -variable ::GX::SII::ui(grid) -command ::GX::SII::displayBoth
    pack $f.h $f.sidebar $f.compare $f.grid -fill x -pady 8
    set f $w.tabs.annotations
    ttk::label $f.h -text {Annotation presentation} -font TkHeadingFont
    ttk::checkbutton $f.coords -text {Show exact annotation coordinates} \
        -variable ::GX::SII::ui(showAnnotationCoordinates) -command ::GX::SII::annotationCoordinateToggle
    ttk::label $f.note -text {Annotation objects remain visible when editing is disabled. Selection mode can be changed by right-clicking the Select icon above the canvas.} -wraplength 455
    pack $f.h $f.coords $f.note -fill x -pady 8
    set f $w.tabs.processing
    ttk::label $f.h -text {Image processing engine} -font TkHeadingFont
    ttk::button $f.engine -text {Inspect ImageMagick capabilities and policy...} -command ::GX::SII::showCapabilities
    ttk::label $f.note -text {The installed engine is resolved through GX-TXT CORE Configuration. Processing remains non-destructive until the derived image is published as a Dataset.} -wraplength 455
    pack $f.h $f.engine $f.note -fill x -pady 8
    ttk::button $w.close -text Close -command [list destroy $w]
    pack $w.close -side bottom -anchor e -padx 15 -pady 10
}
