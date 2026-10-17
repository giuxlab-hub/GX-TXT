# Scientific Image Inspector Native2D canvas integration. No private raster registry.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SII {variable nativeReady 0}

# These helpers replace only the Viewer's inherited tooltip bindings. CORE's
# global .gxViewportTip was positioned relative to the GX-TXT root and could
# briefly map at the desktop origin on Windows. Do not patch CORE or the
# corresponding Curve Workbench widgets.
proc ::GX::SII::tooltipHide {} {
    variable ui
    if {[info exists ui(tooltipAfter)]} {after cancel $ui(tooltipAfter);unset ui(tooltipAfter)}
    if {[info exists ui(window)] && [winfo exists $ui(window).siiTooltip]} {
        destroy $ui(window).siiTooltip
    }
}
proc ::GX::SII::tooltipBind {widget description} {
    # Shared ViewportHost currently uses widget-level Enter/Leave bindings.
    # Replacing them here is limited to this Viewer's control widgets.
    bind $widget <Enter> [list ::GX::SII::tooltipSchedule $widget $description]
    bind $widget <Leave> {::GX::SII::tooltipHide}
    bind $widget <ButtonPress> +{::GX::SII::tooltipHide}
    bind $widget <Destroy> +{::GX::SII::tooltipHide}
}
proc ::GX::SII::tooltipSchedule {widget description} {
    variable ui
    tooltipHide
    if {![winfo exists $widget] || ![winfo ismapped $widget]} return
    set ui(tooltipAfter) [after 450 [list ::GX::SII::tooltipShow $widget $description]]
}
proc ::GX::SII::tooltipShow {widget description} {
    variable ui
    unset -nocomplain ui(tooltipAfter)
    if {![winfo exists $widget] || ![winfo ismapped $widget] ||
        ![info exists ui(window)] || ![winfo exists $ui(window)]} return
    set px [winfo pointerx $widget];set py [winfo pointery $widget]
    if {$px<[winfo rootx $widget] || $px>=[winfo rootx $widget]+[winfo width $widget] ||
        $py<[winfo rooty $widget] || $py>=[winfo rooty $widget]+[winfo height $widget]} return
    set tip $ui(window).siiTooltip
    if {[winfo exists $tip]} {destroy $tip}
    toplevel $tip
    wm withdraw $tip
    wm overrideredirect $tip 1
    ttk::label $tip.text -text $description -padding 6 -wraplength 380
    pack $tip.text
    update idletasks
    set tw [winfo reqwidth $tip];set th [winfo reqheight $tip]
    # Clamp to the Viewer *and* the visible screen. If the toolbar is near the
    # bottom, show the hint above the pointer rather than below the window.
    set wx [winfo rootx $ui(window)];set wy [winfo rooty $ui(window)]
    set wr [expr {$wx+[winfo width $ui(window)]}]
    set wb [expr {$wy+[winfo height $ui(window)]}]
    set right [expr {min([winfo screenwidth $widget],$wr)}]
    set bottom [expr {min([winfo screenheight $widget],$wb)}]
    set x [expr {max(0,$wx,min($px+12,$right-$tw-4))}]
    set y [expr {$py+22+$th>$bottom ? $py-$th-7 : $py+22}]
    set y [expr {max(0,$wy,min($y,$bottom-$th-4))}]
    wm geometry $tip +[expr {int($x)}]+[expr {int($y)}]
    wm deiconify $tip
    raise $tip
}
# A callback error in Tk's event loop is otherwise forwarded to GX-TXT's
# application-wide background-error dialog (which obscures the entire canvas).
# Keep the failure local, report actionable context and retain the Tcl trace on
# stderr for diagnosis. A failed pointer action does not commit a new annotation.
proc ::GX::SII::eventFailure {where message options} {
    variable ui
    if {![info exists ui(lastEventFailure)] || $ui(lastEventFailure) ne [list $where $message]} {
        set ui(lastEventFailure) [list $where $message]
        set trace [expr {[dict exists $options -errorinfo] ? [dict get $options -errorinfo] : $message}]
        puts stderr "Scientific Image Inspector — $where: $trace"
    }
    set ui(status) "$where failed: $message. The operation was not accepted; choose another tool or try again."
}
proc ::GX::SII::guardEvent {where callback} {
    variable ui
    if {[catch {uplevel #0 $callback} message options]} {
        if {[info exists ui(annotationNativeDrag)]} {catch {annotationNativeDragCancel}}
        unset -nocomplain ui(annotationStart) ui(annotationGhost) ui(annotationEditIndex) ui(annotationEditBase) ui(textDraft)
        catch {if {[info exists ui(window)] && [winfo exists $ui(window)]} {nativeDrawAnnotations}}
        eventFailure $where $message $options
        return 0
    }
    unset -nocomplain ui(lastEventFailure)
    return 1
}
proc ::GX::SII::nativeCanvasCreate {} {
    variable ui
    ::GX::native2DEnsure
    foreach which {original processed} {
        set frame $ui(window).layout.main.panes.$which
        set canvas $frame.canvas
        set native [::GX::Native2D::core scene]
        set ui(native-$which) $native
        set ui(native-size-$which) {}
        # The Native2D framework owns viewport chrome, unit-aware world/device
        # transforms, grid and geometry. Image pixels are displayed via Tk's
        # bounded preview because CORE's reference image presenter requires
        # persistent Interactive Document resources (inappropriate per preview).
        ::GX::native2DViewportHostCreate $frame $canvas $native \
            [list ::GX::SII::guardEvent {Viewport redraw} [list ::GX::SII::nativeDisplay $which]]
        # Use CORE's complete shared View toolbar. Its internal layout requires
        # the standard `more` overflow control; do not emulate this panel.
        if {$which eq "original"} {
            set commands [dict create select [list ::GX::SII::annotationSelectMode object] \
                transform [list ::GX::SII::annotationTransformStart translate] \
                pan [list ::GX::SII::annotationPanMode] \
                panel [list ::GX::SII::annotationShapeMenu] \
                zoom_in [list ::GX::SII::nativeZoom $which 0.8] \
                zoom_out [list ::GX::SII::nativeZoom $which 1.25]]
            ::GX::native2DViewportControls $canvas {select transform pan panel zoom_in zoom_out} $commands
            # Avoid the shared Action dispatcher's unconditional scene redraw
            # when a menu is merely opened or an editing mode is selected.
            # The handlers use Native2D and redraw only as needed.
            foreach action {select transform pan panel zoom_in zoom_out} {
                set button $frame.controls.body.$action
                $button configure -command [list ::GX::SII::guardEvent "Viewport $action" [dict get $commands $action]]
            }
            set toolsContainer [dict get $::GX::ViewportHost::hosts $canvas container]
            bind $toolsContainer.controls.body.transform <Button-3> [list ::GX::SII::annotationTransformPopup %X %Y]
            bind $toolsContainer.controls.body.select <Button-3> [list ::GX::SII::annotationSelectPopup %X %Y]
            # No second control panel obscures the image: native icons and
            # canvas context menus own all annotation tool choices.
            foreach {action description} {
                select {Select annotations; right-click for Object, Window, Polygon or Image ROI}
                transform {Transform annotations using the Native2D gizmo; right-click for Rotate}
                pan {Pan the image without moving annotations}
                panel {Add text, arrows, lines, rectangles or ellipses}
                zoom_in {Zoom in} zoom_out {Zoom out}
            } {tooltipBind $toolsContainer.controls.body.$action $description}
            tooltipBind $toolsContainer.controls.body.more {Additional viewport actions}
        } else {
            ::GX::native2DViewportControls $canvas {zoom_in zoom_out} \
                [dict create zoom_in [list ::GX::SII::nativeZoom $which 0.8] \
                    zoom_out [list ::GX::SII::nativeZoom $which 1.25]]
            foreach {action scale} {zoom_in 0.8 zoom_out 1.25} {
                set button $frame.controls.body.$action
                $button configure -command [list ::GX::SII::guardEvent "Comparison $action" \
                    [list ::GX::SII::nativeZoom $which $scale]]
                tooltipBind $button [string totitle [string map {_ { }} $action]]
            }
            tooltipBind $frame.controls.body.more {Additional viewport actions}
        }
        bind $canvas <Configure> +[list ::GX::SII::nativeDisplayLater $which]
    }
    set ::GX::SII::nativeReady 1
}
proc ::GX::SII::nativeDisplayLater {which} {
    variable ui
    if {[info exists ui(native-after-$which)]} {after cancel $ui(native-after-$which)}
    set ui(native-after-$which) [after idle [list ::GX::SII::guardEvent {Viewport redraw} [list ::GX::SII::nativeDisplay $which]]]
}
proc ::GX::SII::nativeConfigure {which} {
    variable ui
    if {![info exists ui(native-$which)]} return
    set scene $ui(native-$which)
    set c $ui(window).layout.main.panes.$which.canvas
    if {![winfo exists $c] || ![info exists ui(preview-$which)]} return
    set info [expr {$which eq "original" ? $ui(workingInfo) : $ui(processedInfo)}]
    set iw [dict get $info width];set ih [dict get $info height]
    set width [expr {max(80,[winfo width $c])}];set height [expr {max(80,[winfo height $c])}]
    if {$ui(native-size-$which) ne [list $iw $ih]} {
        set ui(native-size-$which) [list $iw $ih]
        ::GX::Native2D::core view $scene [list $width $height 0 0 0 0 [list 0 0 $iw $ih]]
        ::GX::Native2D::core aspect $scene xy_equal
    } else {
        set view [::GX::Native2D::core view_requested $scene]
        lset view 0 $width;lset view 1 $height
        ::GX::Native2D::core view $scene $view
    }
}
# Route the legacy image display entrypoint through the Native2D host.
proc ::GX::SII::displayPreview {which} {nativeDisplay $which}
proc ::GX::SII::nativeDisplay {which} {
    variable ui
    if {![info exists ui(preview-$which)] || ![info exists ui(native-$which)]} return
    set c $ui(window).layout.main.panes.$which.canvas
    if {![winfo exists $c]} return
    if {[catch {nativeConfigure $which}]} return
    set scene $ui(native-$which)
    set info [expr {$which eq "original" ? $ui(workingInfo) : $ui(processedInfo)}]
    set iw [dict get $info width];set ih [dict get $info height]
    lassign [::GX::Native2D::core device $scene [list 0 $ih]] x0 y0
    lassign [::GX::Native2D::core device $scene [list $iw 0]] x1 y1
    set targetW [expr {max(1,round(abs($x1-$x0)))}]
    set targetH [expr {max(1,round(abs($y1-$y0)))}]
    # Pixel budget is explicit: this is a display-only LOD, not a scientific raster.
    if {$targetW>3400 || $targetH>3400 || wide($targetW)*$targetH>7000000} {
        set scale [expr {min(3400.0/$targetW,3400.0/$targetH,sqrt(7000000.0/($targetW*$targetH)))}]
        set targetW [expr {max(1,int($targetW*$scale))}]
        set targetH [expr {max(1,int($targetH*$scale))}]
        set ui(status) {Display preview is capped; exported pixels still use the full-resolution source.}
    }
    if {![info exists ui(photo-$which)] || ![info exists ui(native-photo-file-$which)] || $ui(native-photo-file-$which) ne $ui(preview-$which)} {
        if {[info exists ui(scaled-$which)]} {catch {image delete $ui(scaled-$which)};unset -nocomplain ui(scaled-$which)}
        if {[info exists ui(photo-$which)]} {catch {image delete $ui(photo-$which)}}
        set ui(photo-$which) [image create photo -file $ui(preview-$which)]
        set ui(native-photo-file-$which) $ui(preview-$which)
        unset -nocomplain ui(native-zoom-$which)
    }
    set source $ui(photo-$which)
    set sw [image width $source];set sh [image height $source]
    set best 1e99;set n 1;set d 1
    for {set denom 1} {$denom<=48} {incr denom} {
        set numerator [expr {int(round(double($targetW)*$denom/$sw))}]
        if {$numerator<1 || $numerator>96} continue
        set err [expr {abs($sw*double($numerator)/$denom-$targetW)+abs($sh*double($numerator)/$denom-$targetH)}]
        if {$err<$best} {set best $err;set n $numerator;set d $denom}
    }
    set signature [list $n $d $ui(preview-$which)]
    if {![info exists ui(native-zoom-$which)] || $ui(native-zoom-$which) ne $signature} {
        if {[info exists ui(scaled-$which)]} {catch {image delete $ui(scaled-$which)}}
        set ui(scaled-$which) [image create photo]
        $ui(scaled-$which) copy $source -zoom $n $n -subsample $d $d
        set ui(native-zoom-$which) $signature
    }
    $c delete canvas_image
    $c delete construction_grid
    $c delete figure_annotation
    $c delete roi
    $c create image [round $x0] [round $y0] -anchor nw -image $ui(scaled-$which) -tags canvas_image
    # Native construction grid is optional because its pixel units are not a
    # physical micrometer/length calibration.
    if {[llength [info commands ::GX::native2DCanvasGrid]]} {
        set grid [::GX::Native2D::core grid $scene]
        dict set grid enabled 1
        dict set grid visible $ui(grid)
        ::GX::Native2D::core grid $scene $grid
        if {$ui(grid)} {catch {::GX::native2DCanvasGrid $scene $c}}
    }
    if {$which eq "original"} {
        nativeDrawAnnotations
        drawRoi
    }
    $c lower canvas_image
    lodRequest $which
}
proc ::GX::SII::round {x} {expr {int(floor($x+0.5))}}
proc ::GX::SII::nativeZoom {which factor {x ""} {y ""}} {
    variable ui
    if {![info exists ui(native-$which)]} return
    set c $ui(window).layout.main.panes.$which.canvas
    if {$x eq ""} {set x [expr {[winfo width $c]/2}]}
    if {$y eq ""} {set y [expr {[winfo height $c]/2}]}
    ::GX::Native2D::core zoom $ui(native-$which) $factor [list $x $y]
    nativeDisplay $which
    if {$ui(sync)} {
        set other [expr {$which eq "original" ? "processed" : "original"}]
        if {[info exists ui(native-$other)]} {
            ::GX::Native2D::core zoom $ui(native-$other) $factor [list $x $y]
            nativeDisplay $other
        }
    }
}
proc ::GX::SII::wheel {which delta {x ""} {y ""}} {
    if {![string is integer -strict $delta] || $delta == 0} return
    # In Native2D a zoom factor below 1 magnifies the view.
    nativeZoom $which [expr {$delta>0 ? 0.8 : 1.25}] $x $y
}
proc ::GX::SII::panStart {which x y} {
    variable ui
    set ui(native-pan-$which) [list $x $y]
}
proc ::GX::SII::panDrag {which x y} {
    variable ui
    if {![info exists ui(native-pan-$which)]} return
    lassign $ui(native-pan-$which) sx sy
    set dx [expr {$x-$sx}];set dy [expr {$y-$sy}]
    set ui(native-pan-$which) [list $x $y]
    ::GX::Native2D::core pan $ui(native-$which) $dx $dy
    nativeDisplay $which
    if {$ui(sync)} {
        set other [expr {$which eq "original" ? "processed" : "original"}]
        if {[info exists ui(native-$other)]} {
            ::GX::Native2D::core pan $ui(native-$other) $dx $dy
            nativeDisplay $other
        }
    }
}
proc ::GX::SII::fitViews {} {
    variable ui
    foreach which {original processed} {
        if {![info exists ui(native-$which)] || ![info exists ui(preview-$which)]} continue
        set ui(native-size-$which) {}
        nativeDisplay $which
    }
}
proc ::GX::SII::toImageXY {which x y} {
    variable ui
    if {![info exists ui(native-$which)] || ![info exists ui(preview-$which)]} {return {}}
    set info [expr {$which eq "original" ? $ui(workingInfo) : $ui(processedInfo)}]
    lassign [::GX::Native2D::core world $ui(native-$which) [list $x $y]] px worldy
    set py [expr {[dict get $info height]-$worldy}]
    if {$px<0 || $py<0 || $px>=[dict get $info width] || $py>=[dict get $info height]} {return {}}
    return [list [expr {int(floor($px))}] [expr {int(floor($py))}]]
}
proc ::GX::SII::drawRoi {} {
    variable ui
    if {![info exists ui(native-original)]} return
    set c $ui(window).layout.main.panes.original.canvas
    if {![winfo exists $c]} return
    $c delete roi
    if {![info exists ui(roi)] || [llength $ui(roi)]!=4 || ![info exists ui(workingInfo)]} return
    lassign $ui(roi) x y w h
    set ih [dict get $ui(workingInfo) height]
    lassign [::GX::Native2D::core device $ui(native-original) [list $x [expr {$ih-$y}]]] x0 y0
    lassign [::GX::Native2D::core device $ui(native-original) [list [expr {$x+$w}] [expr {$ih-$y-$h}]]] x1 y1
    $c create rectangle $x0 $y0 $x1 $y1 -outline #FFCC00 -dash {7 3} -width 2 -tags roi
}
proc ::GX::SII::nativeDrawAnnotations {} {
    variable ui
    # Native2D drag transactions must retain object identities until commit.
    if {[info exists ui(annotationNativeDrag)]} {annotationNativePresent;return}
    if {![info exists ui(annotations)] || ![info exists ui(workingInfo)] || ![info exists ui(native-original)]} return
    set c $ui(window).layout.main.panes.original.canvas
    $c delete figure_annotation
    $c delete figure_annotation_live
    $c delete figure_annotation_handle
    # CORE gizmo items have their own tag, not figure_annotation. Remove the
    # previous presentation before asking Native2D for a fresh one. Otherwise
    # repeated selection, pan, and refresh leave stacked pivot/axis glyphs.
    $c delete native_gizmo
    set scene $ui(native-original)
    set ih [dict get $ui(workingInfo) height]
    if {[info exists ui(nativeAnnotationIds)]} {
        foreach id $ui(nativeAnnotationIds) {catch {::GX::Native2D::core delete $scene $id}}
    }
    set ui(nativeAnnotationIds) {}
    set ui(nativeAnnotationMap) {}
    annotationsEnsureIds
    set annotationIndex 0
    set failedAnnotations {}
    foreach original $ui(annotations) {
        set currentIndex $annotationIndex
        incr annotationIndex
        set overlayId [get $original id "at index $currentIndex"]
        set priorTokenCount [llength $ui(nativeAnnotationIds)]
        try {
        if {[info exists ui(annotationGhost)] && [info exists ui(annotationEditIndex)] && $currentIndex == $ui(annotationEditIndex)} {set a $ui(annotationGhost)} else {set a $original}
        set a [validateAnnotation $a [dict get $ui(workingInfo) width] $ih]
        set overlayTags [list figure_annotation sii_annotation_$overlayId]
        set kind [dict get $a kind]
        set x [dict get $a x1];set y [expr {$ih-[dict get $a y1]}]
        set rotation [get $a rotation 0]
        set color [dict get $a color]
        if {$kind eq "text"} {
            # The glyph painter is Tk, but its editable selection geometry is
            # a retained Native2D rectangle so CORE owns the transform gizmo.
            set tw [get $a box_width [expr {max(14.0,[string length [get $a text {}]]*[dict get $a size]*0.59)}]]
            set th [get $a box_height [expr {max(9.0,[dict get $a size]*1.2)}]]
            set proxy [dict create family rectangle controls [list [list $x [expr {$y-$th}]] [list [expr {$x+$tw}] $y]] matrix [annotationNativeMatrix $a $ih]]
            set pid [::GX::Native2D::core sketch_create $scene $proxy 17]
            lappend ui(nativeAnnotationIds) $pid
            dict lappend ui(nativeAnnotationMap) $overlayId $pid
            lassign [annotationTransformPoint $a [dict get $a x1] [dict get $a y1]] ax ay
            lassign [::GX::Native2D::core device $scene [list $ax [expr {$ih-$ay}]]] px py
            # Text is a retained logical annotation whose on-screen font follows
            # Native2D image-pixel scale. Tk paints glyphs only; placement and
            # geometric zoom remain owned by Native2D.
            lassign [::GX::Native2D::core device $scene [list [expr {$x+1}] $y]] pxNext pyNext
            set textScale [expr {abs($pxNext-$px)}]
            set deviceSize [expr {max(3,min(700,int(round([dict get $a size]*$textScale))))}]
            set family [get $a font_family DejaVu-Sans]
            $c create text $px $py -text [dict get $a text] -fill $color -anchor nw -angle [expr {-$rotation}] -font [list $family -$deviceSize] -tags $overlayTags
            continue
        }
        set x2 [dict get $a x2];set y2 [expr {$ih-[dict get $a y2]}]
        # Native2D owns vector geometries, coordinate conversions, sampled
        # curves and strokes. Tk only receives the framework presentation.
        set definitions {}
        switch -- $kind {
            line - arrow {
                lappend definitions [dict create family line controls [list [list $x $y] [list $x2 $y2]]]
                if {$kind eq "arrow"} {
                    set angle [expr {atan2($y2-$y,$x2-$x)}]
                    set wing [expr {max(9,4*[dict get $a stroke])}]
                    foreach delta {2.65 -2.65} {
                        set tip [list [expr {$x2+$wing*cos($angle+$delta)}] [expr {$y2+$wing*sin($angle+$delta)}]]
                        lappend definitions [dict create family line controls [list [list $x2 $y2] $tip]]
                    }
                }
            }
            rectangle {lappend definitions [dict create family rectangle controls [list [list $x $y] [list $x2 $y2]]]}
            ellipse {
                set rx [expr {max(1,abs($x2-$x)/2.0)}]
                set ry [expr {max(1,abs($y2-$y)/2.0)}]
                lappend definitions [dict create family ellipse controls [list [list [expr {($x+$x2)/2.0}] [expr {($y+$y2)/2.0}]]] radius_x $rx radius_y $ry]
            }
        }
        scan [string range $color 1 end] %2x%2x%2x red green blue
        set style [dict create color [list [expr {$red/255.0}] [expr {$green/255.0}] [expr {$blue/255.0}] 1] \
            line_width [dict get $a stroke] marker 0]
        foreach definition $definitions {
            dict set definition matrix [annotationNativeMatrix $a $ih]
            set id [::GX::Native2D::core sketch_create $scene $definition 257]
            lappend ui(nativeAnnotationIds) $id
            dict lappend ui(nativeAnnotationMap) $overlayId $id
            ::GX::Native2D::core object_style $scene $id $style
            set snapshot [::GX::native2DPresentationObjectSnapshot $scene $id 512]
            ::GX::native2DCanvasDrawObject $c $snapshot [dict create rgb #252a30] $overlayTags
        }
        } on error {message options} {
            # A legacy Workspace or a failed gesture can contain an invalid
            # Native2D shape. Keep the authoritative recipe untouched, remove
            # only transient geometry for this annotation, and continue with
            # every other object. The global toolbar must remain operable.
            foreach token [lrange $ui(nativeAnnotationIds) $priorTokenCount end] {
                catch {::GX::Native2D::core delete $scene $token}
            }
            set ui(nativeAnnotationIds) [lrange $ui(nativeAnnotationIds) 0 [expr {$priorTokenCount-1}]]
            if {[dict exists $ui(nativeAnnotationMap) $overlayId]} {
                dict unset ui(nativeAnnotationMap) $overlayId
            }
            $c delete sii_annotation_$overlayId
            set kindLabel [get $original kind unknown]
            set objectName [get $original name unnamed]
            set coordinates "[get $original x1 ?],[get $original y1 ?]"
            if {[dict exists $original x2]} {
                append coordinates " -> [get $original x2 ?],[get $original y2 ?]"
            }
            lappend failedAnnotations "$objectName ($overlayId, $kindLabel, $coordinates): $message"
        }
    }
    # Diagnostic only on change to avoid overwriting every toolbar/status
    # message, including native zoom and Timeline inspection feedback.
    set failureSignature [join $failedAnnotations {; }]
    if {![info exists ui(annotationRenderFailures)] || $ui(annotationRenderFailures) ne $failureSignature} {
        set ui(annotationRenderFailures) $failureSignature
        if {$failureSignature ne {}} {
            set ui(status) "Skipped invalid annotation(s): $failureSignature. Other tools remain available; edit the affected coordinates."
            puts stderr "Scientific Image Inspector — recoverable Native2D annotation: $failureSignature"
        }
    }
    # Native geometry is already projected into Tk by the framework presenter.
    # Selection outlines are UI-only highlights around those existing items,
    # not a second geometrical object model or scientific bounding authority.
    if {$ui(annotating) && [info exists ui(selectedAnnotationIds)]} {
        foreach selectedId $ui(selectedAnnotationIds) {
            set bbox [$c bbox sii_annotation_$selectedId]
            if {[llength $bbox] != 4} continue
            lassign $bbox sx sy ex ey
            $c create rectangle [expr {$sx-3}] [expr {$sy-3}] [expr {$ex+3}] [expr {$ey+3}] \
                -outline #1BB8F5 -dash {5 3} -width 1 -tags figure_annotation_handle
        }
    }
    if {$ui(annotating) && [info exists ui(annotationTransform)] && $ui(annotationTransform) ne "none"} {
        annotationGizmoConfigure
        catch {::GX::native2DCanvasDrawGizmo $c $scene #252a30}
    } else {catch {::GX::Native2D::core gizmo $scene {visible 0}}}
    if {![info exists ui(annotationNativeDrag)] && [info exists ui(annotationGhost)] && ![info exists ui(annotationEditIndex)]} {
        nativeDrawGhost $ui(annotationGhost)
    }
    annotationDrawTextDraft
    set index [annotationCurrentIndex]
    if {$ui(annotating) && (![info exists ui(annotationTransform)] || $ui(annotationTransform) eq "none") && $index>=0 && $index<[llength $ui(annotations)]} {
        set a [lindex $ui(annotations) $index]
        set id [dict get $a id]
        foreach point {1 2} {
            if {$point==2 && [dict get $a kind] eq "text"} continue
            lassign [annotationTransformPoint $a [dict get $a x$point] [dict get $a y$point]] ix iy
            lassign [::GX::Native2D::core device $scene [list $ix [expr {$ih-$iy}]]] hx hy
            set handleTags [list figure_annotation_handle sii_annotation_$id]
            if {$point==2} {lappend handleTags sii_resize_handle}
            $c create rectangle [expr {$hx-5}] [expr {$hy-5}] [expr {$hx+5}] [expr {$hy+5}] -outline #222222 -fill #00CCFF -width 1 -tags $handleTags
        }
        lassign [annotationPivot $a] pivotx pivoty
        lassign [::GX::Native2D::core device $scene [list $pivotx [expr {$ih-$pivoty}]]] px py
        $c create oval [expr {$px-4}] [expr {$py-4}] [expr {$px+4}] [expr {$py+4}] \
            -outline #FFAA00 -fill #252a30 -width 2 -tags {figure_annotation_handle sii_pivot_marker}
    }
}
# Live placement preview is presentation-only. Native2D owns the coordinate
# conversion; Tk items are temporary gesture feedback, never persistent data.
proc ::GX::SII::nativeDrawGhost {a} {
    variable ui
    set c $ui(window).layout.main.panes.original.canvas
    set scene $ui(native-original)
    set h [dict get $ui(workingInfo) height]
    set x1 [dict get $a x1];set y1 [expr {$h-[dict get $a y1]}]
    set x2 [dict get $a x2];set y2 [expr {$h-[dict get $a y2]}]
    if {$x1==$x2 && $y1==$y2} return
    set defs {}
    switch -- [dict get $a kind] {
        line - arrow {
            lappend defs [dict create family line controls [list [list $x1 $y1] [list $x2 $y2]]]
            if {[dict get $a kind] eq "arrow"} {
                set angle [expr {atan2($y2-$y1,$x2-$x1)}]
                set wing [expr {max(9,4*[dict get $a stroke])}]
                foreach delta {2.65 -2.65} {
                    lappend defs [dict create family line controls [list [list $x2 $y2] [list [expr {$x2+$wing*cos($angle+$delta)}] [expr {$y2+$wing*sin($angle+$delta)}]]]]
                }
            }
        }
        rectangle {lappend defs [dict create family rectangle controls [list [list $x1 $y1] [list $x2 $y2]]]}
        ellipse {
            lappend defs [dict create family ellipse controls [list [list [expr {($x1+$x2)/2.0}] [expr {($y1+$y2)/2.0}]]] radius_x [expr {max(1,abs($x2-$x1)/2.0)}] radius_y [expr {max(1,abs($y2-$y1)/2.0)}]]
        }
        default {return}
    }
    scan [string range [dict get $a color] 1 end] %2x%2x%2x red green blue
    set style [dict create color [list [expr {$red/255.0}] [expr {$green/255.0}] [expr {$blue/255.0}] 1] line_width [dict get $a stroke] marker 0]
    foreach definition $defs {
        if {[catch {
            set id [::GX::Native2D::core sketch_create $scene $definition 257]
            ::GX::Native2D::core object_style $scene $id $style
            set snapshot [::GX::native2DPresentationObjectSnapshot $scene $id 512]
            ::GX::native2DCanvasDrawObject $c $snapshot [dict create rgb #252a30] {figure_annotation_live}
            ::GX::Native2D::core delete $scene $id
        } msg]} {
            if {[info exists id]} {catch {::GX::Native2D::core delete $scene $id}}
            set ui(status) "Live annotation preview: $msg"
        }
    }
}
proc ::GX::SII::nativeCanvasDispose {} {
    variable ui
    foreach which {original processed} {
        if {[info exists ui(native-$which)]} {
            set scene $ui(native-$which)
            catch {::GX::Native2D::core destroy $scene}
            unset -nocomplain ui(native-$which)
        }
    }
}

proc ::GX::SII::actualPreviewPixels {} {
    variable ui
    foreach which {original processed} {
        if {![info exists ui(native-$which)] || ![info exists ui(photo-$which)]} continue
        set info [expr {$which eq "original" ? $ui(workingInfo) : $ui(processedInfo)}]
        set scene $ui(native-$which)
        lassign [::GX::Native2D::core device $scene [list 0 [dict get $info height]]] x0 y0
        lassign [::GX::Native2D::core device $scene [list [dict get $info width] 0]] x1 y1
        set current [expr {abs($x1-$x0)}]
        if {$current<1} continue
        set desired [image width $ui(photo-$which)]
        ::GX::Native2D::core zoom $scene [expr {$current/double($desired)}] \
            [list [expr {[winfo width $ui(window).layout.main.panes.$which.canvas]/2}] \
                  [expr {[winfo height $ui(window).layout.main.panes.$which.canvas]/2}]]
        nativeDisplay $which
    }
    set ui(status) {1:1 display preview pixels. Full-resolution source pixels may differ from this reduced preview.}
}
