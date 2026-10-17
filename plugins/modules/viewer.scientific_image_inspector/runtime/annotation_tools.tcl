# Scientific Image Inspector: Native2D gizmo / context-owned annotation controls.
# SPDX-License-Identifier: GPL-3.0-or-later
# This controller records semantic image-pixel recipes. The CORE Native2D
# scene performs selection geometry, pointer/device transforms and manipulations.
# It does not implement a parallel numeric manipulation engine.
namespace eval ::GX::SII {}

proc ::GX::SII::annotationScene {} {
    variable ui
    return $ui(native-original)
}
proc ::GX::SII::annotationCanvas {} {
    variable ui
    return $ui(window).layout.main.panes.original.canvas
}
proc ::GX::SII::annotationPanMode {} {
    variable ui
    if {![historyResumeForEditing] || [annotationLocked]} return
    if {[info exists ui(annotationNativeDrag)]} {annotationNativeDragCancel}
    set ui(canvasMode) pan
    set ui(annotating) 0
    set ui(annotationTransform) none
    set ui(annotationTool) Select
    set c [annotationCanvas]
    catch {::GX::Native2D::core gizmo [annotationScene] {visible 0}}
    $c configure -cursor fleur
    annotationToolbarSync
    nativeDrawAnnotations
    set ui(status) {PAN — drag with the left mouse button. Select or Transform icons to leave Pan mode.}
}
proc ::GX::SII::annotationToolbarSync {} {
    variable ui
    if {![info exists ui(window)] || ![winfo exists $ui(window)]} return
    set c [annotationCanvas]
    if {![info exists ::GX::ViewportHost::hosts] || ![dict exists $::GX::ViewportHost::hosts $c]} return
    set panel [::GX::native2DViewportPanelWidget $c controls]
    foreach {name enabled} [list select [expr {($ui(annotating) && $ui(annotationTool) eq "Select" && $ui(annotationTransform) eq "none") || (!$ui(annotating) && [info exists ui(selectionMode)] && $ui(selectionMode) eq "roi")}] \
        transform [expr {$ui(annotating) && $ui(annotationTool) eq "Select" && $ui(annotationTransform) ne "none"}] \
        pan [expr {$ui(canvasMode) eq "pan"}] \
        panel [expr {$ui(annotating) && $ui(annotationTool) in {Text Arrow Line Rectangle Ellipse}}]] {
        if {[llength [info commands ::GX::native2DViewportToolState]]} {
            catch {::GX::native2DViewportToolState $panel.body.$name $enabled}
        } else {
            # Compatible older Native2D hosts: selected remains a *single*
            # logical mode even before the common ToolState helper existed.
            catch {$panel.body.$name state [expr {$enabled ? "selected" : "!selected"}]}
        }
    }
}
proc ::GX::SII::annotationTransformStart {{mode translate}} {
    variable ui
    if {![historyResumeForEditing] || [annotationLocked]} return
    if {[info exists ui(selectedAnnotationIds)] && [llength $ui(selectedAnnotationIds)]>1} {
        set ui(status) {Group transformations are not yet supported. Select one annotation to translate or rotate it.}
        return
    }
    if {$mode ni {translate rotate}} {error {Unknown Native2D transform mode}}
    if {!$ui(annotating)} {annotationMode 1}
    set ui(selectionMode) object
    set ui(annotationTool) Select
    set ui(annotationTransform) $mode
    set ui(canvasMode) annotate
    nativeDrawAnnotations
    annotationToolbarSync
    set ui(status) "ANNOTATIONS — Native2D $mode gizmo. Select a shape, drag a handle, or right-click it."
}
proc ::GX::SII::annotationTransformPopup {X Y} {
    variable ui
    if {$ui(pending)} return
    set c [annotationCanvas]
    set m $c.transformPopup
    if {![winfo exists $m]} {menu $m -tearoff 0}
    $m delete 0 end
    $m add command -label {Translate / pivot (Native2D)} -command {::GX::SII::annotationTransformStart translate}
    $m add command -label {Rotate / pivot (Native2D)} -command {::GX::SII::annotationTransformStart rotate}
    if {[llength [info commands ::GX::uiMenuPopup]]} {::GX::uiMenuPopup $m $X $Y} else {tk_popup $m $X $Y}
}
proc ::GX::SII::annotationGizmoConfigure {} {
    variable ui
    if {![info exists ui(nativeAnnotationMap)] || ![info exists ui(workingInfo)]} return
    set scene [annotationScene]
    set idx [annotationCurrentIndex]
    if {[info exists ui(selectedAnnotationIds)] && [llength $ui(selectedAnnotationIds)]>1} {
        ::GX::Native2D::core gizmo $scene {visible 0}
        return
    }
    dict for {logical ids} $ui(nativeAnnotationMap) {
        foreach id $ids {catch {::GX::Native2D::core object_style $scene $id [dict create selected 0]}}
    }
    if {$idx<0 || $idx>=[llength $ui(annotations)]} {
        ::GX::Native2D::core gizmo $scene {visible 0}
        return
    }
    set a [lindex $ui(annotations) $idx]
    set logical [dict get $a id]
    if {![dict exists $ui(nativeAnnotationMap) $logical]} return
    foreach id [dict get $ui(nativeAnnotationMap) $logical] {
        ::GX::Native2D::core object_style $scene $id [dict create selected 1]
    }
    lassign [annotationPivot $a] px py
    set height [dict get $ui(workingInfo) height]
    ::GX::Native2D::core pivot $scene custom [list $px [expr {$height-$py}]]
    set grid [::GX::Native2D::core grid $scene]
    ::GX::Native2D::core gizmo $scene [dict create visible 1 mode $ui(annotationTransform) axes_angle [dict get $grid angle]]
}
proc ::GX::SII::annotationNativeDragBegin {x y} {
    variable ui
    if {[info exists ui(selectedAnnotationIds)] && [llength $ui(selectedAnnotationIds)]>1} {
        set ui(status) {Multiple annotations selected. Use Copy/Paste, or select one object for the Native2D transform gizmo.}
        return 0
    }
    if {!$ui(annotating) || $ui(annotationTransform) eq "none" || $ui(annotationTool) ne "Select"} {return 0}
    set scene [annotationScene]
    set idx [annotationCurrentIndex]
    if {$idx<0} {return 0}
    set handle [::GX::Native2D::core gizmo_hit $scene [list $x $y] 5]
    if {$handle eq "none"} {return 0}
    if {$handle ni {pivot rotate x y xy free}} {
        # Supported transform types are determined by the running Native2D core.
        set gizmo [::GX::Native2D::core gizmo $scene]
        if {[dict get $gizmo mode] ni {translate rotate}} {return 0}
    }
    set a [lindex $ui(annotations) $idx]
    set ui(annotationNativeDrag) [dict create index $idx before $a handle $handle \
        start [list $x $y] initial_pivot [::GX::Native2D::core pivot $scene] \
        parameters {} changed 0]
    if {$handle ne "pivot"} {
        ::GX::Native2D::core drag_begin $scene
    }
    return 1
}
proc ::GX::SII::annotationNativeModel {drag} {
    # Reconstruct the retained semantic recipe from the exact Native2D gizmo
    # receipt (no Tcl hit/rotation/pointer geometry calculation).
    set a [dict get $drag before]
    set d [dict get $drag parameters]
    if {$d eq {}} {return $a}
    set handle [dict get $drag handle]
    if {$handle eq "pivot"} {
        variable ui
        if {![dict exists $d world_point]} {return $a}
        lassign [dict get $d world_point] x y
        dict set a pivot_x $x
        dict set a pivot_y [expr {[dict get $ui(workingInfo) height]-$y}]
    } elseif {$handle eq "rotate"} {
        dict set a rotation [expr {[get $a rotation 0]-[dict get $d radians]*180.0/acos(-1)}]
    } elseif {[dict exists $d translation]} {
        lassign [dict get $d translation] dx dy
        foreach key {x1 x2} {if {[dict exists $a $key]} {dict set a $key [expr {round([dict get $a $key]+$dx)}]}}
        foreach key {y1 y2} {if {[dict exists $a $key]} {dict set a $key [expr {round([dict get $a $key]-$dy)}]}}
        if {[dict exists $a pivot_x]} {dict set a pivot_x [expr {[dict get $a pivot_x]+$dx}]}
        if {[dict exists $a pivot_y]} {dict set a pivot_y [expr {[dict get $a pivot_y]-$dy}]}
    }
    return $a
}
proc ::GX::SII::annotationNativeDragMove {x y} {
    variable ui
    if {![info exists ui(annotationNativeDrag)]} return
    set scene [annotationScene]
    set drag $ui(annotationNativeDrag)
    set h [dict get $drag handle]
    if {[catch {
        set d [::GX::Native2D::core gizmo_parameters $scene $h [dict get $drag start] [list $x $y]]
        if {$h eq "pivot"} {
            ::GX::Native2D::core pivot $scene custom [dict get $d world_point]
        } elseif {$h eq "rotate"} {
            ::GX::Native2D::core drag_rotate $scene [dict get $d pivot] [dict get $d radians]
        } else {
            ::GX::Native2D::core drag_translate $scene {*}[dict get $d translation]
        }
        dict set drag parameters $d
        dict set drag changed 1
        set ui(annotationNativeDrag) $drag
        annotationNativePresent
    } msg]} {
        annotationNativeDragCancel
        set ui(status) "Native2D transform cancelled: $msg"
    }
}
proc ::GX::SII::annotationNativePresent {} {
    variable ui
    if {![info exists ui(annotationNativeDrag)]} return
    set drag $ui(annotationNativeDrag)
    set a [dict get $drag before]
    set logical [dict get $a id]
    set c [annotationCanvas]
    set scene [annotationScene]
    $c delete sii_annotation_$logical
    set kind [dict get $a kind]
    set tags [list figure_annotation sii_annotation_$logical]
    if {$kind eq "text"} {
        # Glyphs are Tk presentation only; the Native2D proxy, pivot, and
        # transform receipt remain the geometry authority.
        set view [annotationNativeModel $drag]
        set ih [dict get $ui(workingInfo) height]
        lassign [annotationTransformPoint $view [dict get $view x1] [dict get $view y1]] x y
        lassign [::GX::Native2D::core device $scene [list $x [expr {$ih-$y}]]] px py
        lassign [::GX::Native2D::core device $scene [list [expr {$x+1}] [expr {$ih-$y}]]] dx dy
        set fontSize [expr {max(3,min(700,round([dict get $view size]*abs($dx-$px))))}]
        $c create text $px $py -text [dict get $view text] -fill [dict get $view color] \
            -angle [expr {-[get $view rotation 0]}] -font [list [get $view font_family DejaVu-Sans] -$fontSize] -anchor nw -tags $tags
    } else {
        if {[dict exists $ui(nativeAnnotationMap) $logical]} {
            foreach token [dict get $ui(nativeAnnotationMap) $logical] {
                set image [::GX::native2DPresentationObjectSnapshot $scene $token 512]
                ::GX::native2DCanvasDrawObject $c $image [dict create rgb #252a30] $tags
            }
        }
    }
    $c delete native_gizmo
    catch {::GX::native2DCanvasDrawGizmo $c $scene #252a30}
}
proc ::GX::SII::annotationNativeDragCommit {} {
    variable ui
    if {![info exists ui(annotationNativeDrag)]} return
    set drag $ui(annotationNativeDrag)
    set scene [annotationScene]
    unset ui(annotationNativeDrag)
    if {[dict get $drag handle] ne "pivot"} {
        if {[catch {::GX::Native2D::core drag_commit $scene} msg]} {
            catch {::GX::Native2D::core drag_cancel $scene}
            set ui(status) "Native2D transform rejected: $msg"
            nativeDrawAnnotations
            return
        }
    }
    if {[dict get $drag changed]} {
        set new [annotationNativeModel $drag]
        if {[catch {set new [validateAnnotation $new [dict get $ui(workingInfo) width] [dict get $ui(workingInfo) height]]} msg]} {
            set ui(status) "Native2D transform is outside the image: $msg"
        } else {
            if {$new ne [dict get $drag before]} {
                recordFigureEdit
                lset ui(annotations) [dict get $drag index] $new
                refreshAnnotations
                annotationSelectIndex [dict get $drag index]
                saveState
            }
        }
    }
    nativeDrawAnnotations
}
proc ::GX::SII::annotationNativeDragCancel {} {
    variable ui
    if {![info exists ui(annotationNativeDrag)]} return
    set drag $ui(annotationNativeDrag)
    unset ui(annotationNativeDrag)
    set scene [annotationScene]
    if {[dict get $drag handle] eq "pivot"} {
        set p [dict get $drag initial_pivot]
        if {[dict get $p mode] eq "custom"} {
            catch {::GX::Native2D::core pivot $scene custom [dict get $p point]}
        } else {catch {::GX::Native2D::core pivot $scene [dict get $p mode]}}
    } else {catch {::GX::Native2D::core drag_cancel $scene}}
    nativeDrawAnnotations
}
# Menu construction is identical in purpose to the Curve Workbench scene
# context menu: the provider supplies actions, CORE supplies semantic menus.
proc ::GX::SII::annotationContext {x y screenX screenY} {
    variable ui
    if {$ui(pending) || ![info exists ui(workingInfo)]} return
    set hit [annotationHit $x $y]
    set c [annotationCanvas]
    set target {}
    set actions {}
    if {$hit ne {}} {
        set idx [lindex $hit 0]
        if {!$ui(annotating)} {annotationSelectMode object}
        annotationSelectIndex $idx
        set a [lindex $ui(annotations) $idx]
        set target [dict create entity object logical [dict get $a id]]
        set actions [list \
            [list "Rename '[get $a name [dict get $a id]]'..." {::GX::SII::annotationRenameDialog}] \
            [list {Translate (Native2D)} {::GX::SII::annotationTransformStart translate}] \
            [list {Rotate (Native2D)} {::GX::SII::annotationTransformStart rotate}] \
            [list {Pivot at cursor} [list ::GX::SII::annotationPivotAt $x $y]] \
            [list {Pivot at object center} {::GX::SII::annotationPivotReset}] \
            [list {Edit style...} {::GX::SII::annotationStyleDialog}] \
            [list {Delete annotation} {::GX::SII::removeAnnotation}]]
        if {[dict get $a kind] eq "text"} {
            set actions [linsert $actions 1 [list {Edit text on image...} [list ::GX::SII::annotationInlineEditor $idx]]]
        }
    } else {
        set xy [toImageXY original $x $y]
        if {$xy eq {}} {return}
        set actions [list [list {Add Text (draw box)} {::GX::SII::annotationChooseTool Text}] \
            [list {Draw arrow} [list ::GX::SII::annotationChooseTool Arrow]] \
            [list {Draw line} [list ::GX::SII::annotationChooseTool Line]] \
            [list {Draw rectangle} [list ::GX::SII::annotationChooseTool Rectangle]] \
            [list {Draw ellipse} [list ::GX::SII::annotationChooseTool Ellipse]] \
            [list {Select / Transform (Native2D)} [list ::GX::SII::annotationTransformStart translate]]]
        if {$ui(annotating)} {lappend actions [list {Finish annotations} {::GX::SII::annotationMode 0}]}
    }
    set menu [::GX::native2DViewportContextMenu $c $target {} $actions {}]
    if {[$menu type 0] eq {separator}} {$menu delete 0}
    if {[llength [info commands ::GX::uiMenuPopup]]} {::GX::uiMenuPopup $menu $screenX $screenY} else {tk_popup $menu $screenX $screenY}
}
proc ::GX::SII::annotationChooseTool {tool} {
    variable ui
    if {![historyResumeForEditing] || [annotationLocked]} return
    if {!$ui(annotating)} {annotationMode 1}
    unset -nocomplain ui(textDraft) ui(annotationStart)
    set ui(annotationTool) $tool
    set ui(selectionMode) object
    set ui(annotationTransform) none
    nativeDrawAnnotations
    annotationToolbarSync
    set ui(status) "Draw $tool — drag on the image. Right-click to change tools."
}
proc ::GX::SII::annotationShapeMenu {} {
    variable ui
    if {![historyResumeForEditing] || [annotationLocked]} return
    set c [annotationCanvas]
    set m $c.shapePopup
    if {![winfo exists $m]} {menu $m -tearoff 0}
    $m delete 0 end
    # Exactly one creation menu for text and vector annotations.
    $m add command -label {Add Text} -command [list ::GX::SII::annotationChooseTool Text]
    $m add separator
    foreach tool {Arrow Line Rectangle Ellipse} {
        $m add command -label "Draw $tool" -command [list ::GX::SII::annotationChooseTool $tool]
    }
    set toolbar [::GX::native2DViewportPanelWidget $c controls]
    set button $toolbar.body.panel
    set X [winfo rootx $button]
    set Y [expr {[winfo rooty $button]+[winfo height $button]}]
    if {[llength [info commands ::GX::uiMenuPopup]]} {::GX::uiMenuPopup $m $X $Y} else {tk_popup $m $X $Y}
}
proc ::GX::SII::annotationListContext {x y X Y} {
    variable ui
    set lb $ui(window).layout.inspector.tabs.annotations.list
    set index [$lb nearest $y]
    if {$index<0 || $index>=[llength $ui(annotations)]} return
    if {!$ui(annotating)} {annotationMode 1}
    annotationSelectIndex $index
    set c [annotationCanvas]
    set a [lindex $ui(annotations) $index]
    set target [dict create entity object logical [dict get $a id]]
    set domain [list [list {Rename...} {::GX::SII::annotationRenameDialog}] \
        [list {Translate (Native2D)} {::GX::SII::annotationTransformStart translate}] \
        [list {Rotate (Native2D)} {::GX::SII::annotationTransformStart rotate}] \
        [list {Edit style...} {::GX::SII::annotationStyleDialog}] \
        [list {Delete annotation} {::GX::SII::removeAnnotation}]]
    if {[dict get $a kind] eq "text"} {set domain [linsert $domain 1 [list {Edit text on image...} [list ::GX::SII::annotationInlineEditor $index]]]}
    set menu [::GX::native2DViewportContextMenu $c $target {} $domain {}]
    if {[$menu type 0] eq {separator}} {$menu delete 0}
    if {[llength [info commands ::GX::uiMenuPopup]]} {::GX::uiMenuPopup $menu $X $Y} else {tk_popup $menu $X $Y}
}
proc ::GX::SII::annotationRenameDialog {} {
    variable ui
    if {[annotationLocked]} return
    set idx [annotationCurrentIndex]
    if {$idx<0} return
    set ui(annotationNameInput) [get [lindex $ui(annotations) $idx] name {}]
    set w $ui(window).renameAnnotation
    catch {destroy $w};toplevel $w
    wm title $w {Rename annotation};wm transient $w $ui(window)
    ttk::label $w.label -text {Object name}
    ttk::entry $w.name -textvariable ::GX::SII::ui(annotationNameInput) -width 38
    ttk::frame $w.buttons
    ttk::button $w.buttons.ok -text Rename -command [list ::GX::SII::annotationRenameApply $w $idx]
    ttk::button $w.buttons.cancel -text Cancel -command [list destroy $w]
    pack $w.label $w.name $w.buttons -fill x -padx 12 -pady 5
    pack $w.buttons.ok $w.buttons.cancel -side left -padx 4
    focus $w.name;$w.name selection range 0 end
}
proc ::GX::SII::annotationRenameApply {w idx} {
    variable ui
    if {[annotationLocked]} return
    if {[catch {
        set a [lindex $ui(annotations) $idx]
        dict set a name [string trim $ui(annotationNameInput)]
        set a [validateAnnotation $a [dict get $ui(workingInfo) width] [dict get $ui(workingInfo) height]]
        if {[dict get $a name] eq {}} {error {Enter an object name}}
        recordFigureEdit
        lset ui(annotations) $idx $a
        refreshAnnotations;annotationSelectIndex $idx;saveState
        destroy $w
    } msg]} {guiError $msg}
}
# One on-image editor for both new and existing text. Final text remains a
# named editable overlay, never destructive raster pixels.
# Text annotations use the Image Inspector working canvas as the live editor.
# Coordinates are always image pixels; Native2D does world/device conversion.
# A floating toolbar is Tk-only chrome. The persistent overlay is data, not
# a Tk canvas-item identity or a destructive edit of the underlying image.
proc ::GX::SII::annotationTextDeviceRect {coords} {
    variable ui
    lassign $coords x1 y1 x2 y2
    set scene [annotationScene]
    set ih [dict get $ui(workingInfo) height]
    lassign [::GX::Native2D::core device $scene [list $x1 [expr {$ih-$y1}]]] ax ay
    lassign [::GX::Native2D::core device $scene [list $x2 [expr {$ih-$y2}]]] bx by
    return [list [expr {min($ax,$bx)}] [expr {min($ay,$by)}] [expr {max($ax,$bx)}] [expr {max($ay,$by)}]]
}
proc ::GX::SII::annotationDrawTextDraft {} {
    variable ui
    if {![info exists ui(window)] || ![info exists ui(native-original)]} return
    set c [annotationCanvas]
    if {![winfo exists $c]} return
    $c delete sii_text_draft
    if {![info exists ui(textDraft)]} return
    lassign [annotationTextDeviceRect $ui(textDraft)] x0 y0 x1 y1
    if {abs($x1-$x0)<3 || abs($y1-$y0)<3} return
    $c create rectangle $x0 $y0 $x1 $y1 -dash {5 4} -outline #00B6E8 -width 2 -tags sii_text_draft
}
proc ::GX::SII::annotationFontDpi {} {
    # A typographic point needs a declared target resolution. Prefer the
    # framework's graphic-output DPI setting, never the source image's EXIF.
    if {[info exists ::GX::cfg(analysis_png_dpi)] &&
        [string is double -strict $::GX::cfg(analysis_png_dpi)] &&
        $::GX::cfg(analysis_png_dpi)>=36 && $::GX::cfg(analysis_png_dpi)<=2400} {
        return $::GX::cfg(analysis_png_dpi)
    }
    return 72
}
proc ::GX::SII::annotationFontUnitDefault {} {
    if {[info exists ::GX::cfg(plot_font_unit)] && $::GX::cfg(plot_font_unit) in {px pt}} {
        return $::GX::cfg(plot_font_unit)
    }
    return px
}
proc ::GX::SII::annotationTextSizePixels {size unit} {
    if {![string is double -strict $size] || $size<1 || $size>1200} {error {Font size must be between 1 and 1200}}
    if {$unit ni {px pt}} {error {Font unit must be px or pt}}
    set px [expr {round(double($size)*($unit eq "pt" ? [annotationFontDpi]/72.0 : 1.0))}]
    return [figureValidInt $px 8 1200 {Font size in image pixels}]
}
proc ::GX::SII::annotationFontOptions {} {
    # List real installed ImageMagick font names, not a made-up style list.
    # The font selected here is also used for the final raster publication.
    variable ui
    if {[info exists ui(magickFonts)]} {return $ui(magickFonts)}
    set fonts {}
    if {![catch {set output [exec [magickPath] -list font 2>@1]}]} {
        foreach line [split $output \n] {
            if {[regexp {^\s*Font:\s*([A-Za-z0-9_.-]+)\s*$} $line -> name]} {lappend fonts $name}
        }
    }
    set ui(magickFonts) [lsort -dictionary -unique $fonts]
    return $ui(magickFonts)
}
proc ::GX::SII::annotationInlineUnitChanged {} {
    variable ui
    if {![info exists ui(inlinePrevUnit)]} {set ui(inlinePrevUnit) $ui(inlineUnit)}
    set old $ui(inlinePrevUnit)
    set new $ui(inlineUnit)
    if {$old ne $new && $old in {px pt} && $new in {px pt} &&
        [string is double -strict $ui(inlineSize)]} {
        set dpi [annotationFontDpi]
        set converted [expr {$old eq "px" ? double($ui(inlineSize))*72.0/$dpi : double($ui(inlineSize))*$dpi/72.0}]
        set ui(inlineSize) [format %.2f $converted]
    }
    set ui(inlinePrevUnit) $new
    annotationInlineLiveStyle
}
proc ::GX::SII::annotationInlineLiveStyle {args} {
    variable ui
    if {![info exists ui(inlineWidget)] || ![winfo exists $ui(inlineWidget)]} return
    set widget $ui(inlineWidget)
    set family $ui(inlineFont)
    if {[catch {set px [annotationTextSizePixels $ui(inlineSize) $ui(inlineUnit)]}]} return
    set scene [annotationScene]
    set ih [dict get $ui(workingInfo) height]
    lassign $ui(inlineAnchor) x y
    lassign [::GX::Native2D::core device $scene [list $x [expr {$ih-$y}]]] sx sy
    lassign [::GX::Native2D::core device $scene [list [expr {$x+1}] [expr {$ih-$y}]]] dx dy
    set drawSize [expr {max(7,min(400,round($px*abs($dx-$sx))))}]
    $widget.edit configure -font [list $family -$drawSize]
    if {[info exists ui(inlineToolbar)] && [winfo exists $ui(inlineToolbar)]} {
        set colorWidget $ui(inlineToolbar).color
        catch {$widget.edit configure -foreground $ui(inlineColor)}
        if {[winfo exists $colorWidget.swatch]} {
            $colorWidget.swatch configure -text {} -width 2 -height 1 \
                -background $ui(inlineColor) \
                -foreground [::GX::uiFieldColorReadableText $ui(inlineColor)]
        }
    }
}
# One on-image editor for new or existing text, with a retained bounding box.
# New text: click or drag a dashed box; then type and use the compact toolbar.
proc ::GX::SII::annotationInlineEditor {idx {x {}} {y {}} {x2 {}} {y2 {}}} {
    variable ui
    if {[annotationLocked] || ![info exists ui(workingInfo)]} return
    if {[info exists ui(inlineWidget)]} {annotationInlineCancel}
    set c [annotationCanvas]
    $c delete sii_text_draft
    set iw [dict get $ui(workingInfo) width];set ih [dict get $ui(workingInfo) height]
    if {$idx eq {new}} {
        if {$x eq {} || $y eq {}} return
        if {$x2 eq {} || abs($x2-$x)<8} {set x2 [expr {min($iw,$x+280)}]}
        if {$y2 eq {} || abs($y2-$y)<8} {set y2 [expr {min($ih,$y+90)}]}
        set bx [expr {max(8,abs($x2-$x))}];set by [expr {max(8,abs($y2-$y))}]
        set x [expr {min($x,$x2)}];set y [expr {min($y,$y2)}]
        set defaultUnit [annotationFontUnitDefault]
        set defaultSize [expr {$defaultUnit eq "pt" ? 12 : $ui(annotation-size)}]
        set a [dict create kind text x1 [expr {int($x)}] y1 [expr {int($y)}] \
            box_width [expr {int($bx)}] box_height [expr {int($by)}] \
            color $ui(annotation-color) size [annotationTextSizePixels $defaultSize $defaultUnit] \
            font_family DejaVu-Sans font_unit $defaultUnit font_value $defaultSize \
            stroke 2 text {}]
    } else {
        if {$idx<0 || $idx>=[llength $ui(annotations)]} return
        set a [lindex $ui(annotations) $idx]
        if {[dict get $a kind] ne {text}} return
    }
    if {!$ui(annotating)} {annotationMode 1}
    set ui(inlineIndex) $idx
    set ui(inlineName) [get $a name {}]
    set ui(inlineColor) [get $a color #FFCC00]
    set ui(inlineFont) [get $a font_family DejaVu-Sans]
    set ui(inlineUnit) [get $a font_unit px]
    set ui(inlineSize) [get $a font_value [get $a size 46]]
    set ui(inlinePrevUnit) $ui(inlineUnit)
    set ui(inlineAnchor) [list [dict get $a x1] [dict get $a y1]]
    set ui(inlineBox) [list [dict get $a x1] [dict get $a y1] \
        [expr {[dict get $a x1]+[get $a box_width 280]}] \
        [expr {[dict get $a y1]+[get $a box_height 90]}]]
    set widget $c.inlineAnnotation
    set toolbar $c.inlineToolbar
    catch {destroy $widget};catch {destroy $toolbar}
    ttk::frame $widget -padding 2
    text $widget.edit -wrap word -undo 1 -height 2 -width 24 -borderwidth 0 \
        -highlightthickness 0 -background #FCFCFC -foreground $ui(inlineColor) \
        -insertbackground #333333
    $widget.edit insert 1.0 [get $a text {}]
    pack $widget.edit -fill both -expand 1
    ttk::frame $toolbar -padding 3 -relief raised -borderwidth 1
    # Framework-owned UI Field API validates and opens the established color chooser.
    ::GX::uiFieldCreate $toolbar.color [dict create type color] ::GX::SII::ui(inlineColor) \
        ::GX::SII::annotationInlineLiveStyle
    grid remove $toolbar.color.entry
    grid remove $toolbar.color.error
    bind $toolbar.color <Configure> {}
    pack $toolbar.color -side left -padx 2
    ttk::combobox $toolbar.font -width 18 -state readonly \
        -textvariable ::GX::SII::ui(inlineFont) -values [annotationFontOptions]
    pack $toolbar.font -side left -padx 2
    ttk::spinbox $toolbar.size -from 1 -to 1200 -increment 1 -width 5 \
        -textvariable ::GX::SII::ui(inlineSize) -command ::GX::SII::annotationInlineLiveStyle
    pack $toolbar.size -side left -padx 2
    ttk::combobox $toolbar.unit -values {px pt} -state readonly -width 3 \
        -textvariable ::GX::SII::ui(inlineUnit)
    pack $toolbar.unit -side left -padx 2
    ttk::button $toolbar.ok -text Apply -command ::GX::SII::annotationInlineApply
    ttk::button $toolbar.cancel -text Cancel -command ::GX::SII::annotationInlineCancel
    pack $toolbar.ok $toolbar.cancel -side left -padx 2
    set ui(inlineWidget) $widget
    set ui(inlineToolbar) $toolbar
    lassign [annotationTextDeviceRect $ui(inlineBox)] left top right bottom
    set tw [expr {max(75,round($right-$left)-8)}]
    set th [expr {max(36,round($bottom-$top)-8)}]
    $widget configure -width $tw -height $th
    set ui(inlineBorder) [$c create rectangle $left $top $right $bottom \
        -outline #12A4E7 -width 2 -dash {5 4} -tags sii_text_inline_editor]
    set ui(inlineCanvasItem) [$c create window [expr {$left+4}] [expr {$top+4}] \
        -anchor nw -window $widget -tags sii_text_inline_editor -width $tw -height $th]
    update idletasks
    set toolbarW [winfo reqwidth $toolbar];set toolbarH [winfo reqheight $toolbar]
    set toolbarX [expr {max(0,min($left,[winfo width $c]-$toolbarW))}]
    set toolbarY [expr {$top-$toolbarH-4>=0 ? $top-$toolbarH-4 : $bottom+5}]
    set ui(inlineToolbarItem) [$c create window $toolbarX $toolbarY -anchor nw \
        -window $toolbar -tags sii_text_inline_editor]
    bind $toolbar.font <<ComboboxSelected>> {::GX::SII::annotationInlineLiveStyle}
    bind $toolbar.unit <<ComboboxSelected>> {::GX::SII::annotationInlineUnitChanged}
    bind $toolbar.size <KeyRelease> {::GX::SII::annotationInlineLiveStyle}
    bind $toolbar.size <FocusOut> {::GX::SII::annotationInlineLiveStyle}
    annotationInlineLiveStyle
    focus $widget.edit
}
proc ::GX::SII::annotationInlineCancel {} {
    variable ui
    if {![info exists ui(inlineWidget)]} return
    set c [annotationCanvas]
    $c delete sii_text_inline_editor
    catch {destroy $ui(inlineWidget)}
    if {[info exists ui(inlineToolbar)]} {catch {destroy $ui(inlineToolbar)}}
    foreach key {inlineWidget inlineToolbar inlineBorder inlineToolbarItem inlineCanvasItem inlineIndex inlineBox} {
        unset -nocomplain ui($key)
    }
    unset -nocomplain ui(inlinePrevUnit) ui(textDraft)
}
proc ::GX::SII::annotationInlineApply {} {
    variable ui
    if {![info exists ui(inlineWidget)] || [annotationLocked]} return
    set widget $ui(inlineWidget)
    set text [string trimright [$widget.edit get 1.0 end-1c] "\n"]
    set idx $ui(inlineIndex)
    if {[catch {
        set pixelSize [annotationTextSizePixels $ui(inlineSize) $ui(inlineUnit)]
        if {[lsearch -exact [annotationFontOptions] $ui(inlineFont)]<0} {error {Select an installed ImageMagick font}}
        if {$idx eq {new}} {
            lassign $ui(inlineBox) x y right bottom
            set a [dict create kind text x1 $x y1 $y \
                box_width [expr {int($right-$x)}] box_height [expr {int($bottom-$y)}] \
                stroke 2 text $text size $pixelSize]
        } else {set a [lindex $ui(annotations) $idx]}
        foreach {key value} [list text $text color $ui(inlineColor) \
            size $pixelSize font_family $ui(inlineFont) font_unit $ui(inlineUnit) \
            font_value $ui(inlineSize) font_dpi [expr {int([annotationFontDpi])}]] {
            dict set a $key $value
        }
        set name [string trim $ui(inlineName)]
        if {$name eq {}} {set name [expr {$text eq {} ? {Text annotation} : [string range $text 0 35]}]}
        dict set a name $name
        set a [validateAnnotation $a [dict get $ui(workingInfo) width] [dict get $ui(workingInfo) height]]
        recordFigureEdit
        if {$idx eq {new}} {lappend ui(annotations) $a;set idx [expr {[llength $ui(annotations)]-1}]} \
            else {lset ui(annotations) $idx $a}
        annotationInlineCancel
        set ui(annotationTool) Select
        set ui(annotationTransform) translate
        refreshAnnotations;annotationSelectIndex $idx;annotationToolbarSync;saveState
    } err]} {guiError $err}
}
proc ::GX::SII::annotationStyleDialog {} {
    variable ui
    if {[annotationLocked]} return
    set idx [annotationCurrentIndex]
    if {$idx<0} return
    set a [lindex $ui(annotations) $idx]
    set ui(styleColor) [dict get $a color]
    set ui(styleStroke) [dict get $a stroke]
    set w $ui(window).styleAnnotation
    catch {destroy $w};toplevel $w
    wm title $w {Annotation style};wm transient $w $ui(window)
    ttk::label $w.lcolor -text {Color (#RRGGBB)}
    ttk::entry $w.color -textvariable ::GX::SII::ui(styleColor)
    ttk::label $w.lstroke -text {Line width (image px)}
    ttk::entry $w.stroke -textvariable ::GX::SII::ui(styleStroke)
    ttk::button $w.apply -text Apply -command [list ::GX::SII::annotationStyleApply $w $idx]
    pack $w.lcolor $w.color $w.lstroke $w.stroke $w.apply -fill x -padx 12 -pady 3
}
proc ::GX::SII::annotationStyleApply {w idx} {
    variable ui
    if {[catch {
        set a [lindex $ui(annotations) $idx]
        dict set a color $ui(styleColor)
        dict set a stroke $ui(styleStroke)
        set a [validateAnnotation $a [dict get $ui(workingInfo) width] [dict get $ui(workingInfo) height]]
        recordFigureEdit
        lset ui(annotations) $idx $a
        refreshAnnotations;annotationSelectIndex $idx;saveState;destroy $w
    } msg]} {guiError $msg}
}
