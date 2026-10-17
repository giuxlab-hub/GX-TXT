# Simple editor and article figure UI. All UI strings English.
# SPDX-License-Identifier: GPL-3.0-or-later
# Two tool surfaces, one authoritative working image and one shared recipe.
# Presets are data, not separate hidden ImageMagick pipelines.
proc ::GX::SII::basicPresetCatalog {} {
    return [list \
        [list {Photo | Balance tonal range} {Automatically span the available tones; use for flat photographs.} {{auto_level {}}}] \
        [list {Photo | Gentle contrast} {Add moderate midtone contrast without automatic histogram stretching.} {{sigmoidal {contrast 4 midpoint 50}}}] \
        [list {Photo | Sharpen details} {Enhance fine boundaries; may amplify noise and compression artifacts.} {{unsharp {radius 0 sigma 1 gain 0.8 threshold 0.04}}}] \
        [list {Photo | Soften grain} {Slight Gaussian smoothing; fine texture is intentionally reduced.} {{gaussian_blur {radius 0 sigma 0.8}}}] \
        [list {Color | More saturated} {Increase saturation by 20 percent; not appropriate for quantitative color measurements.} {{modulate {brightness 100 saturation 120 hue 100}}}] \
        [list {Color | Less saturated} {Reduce saturation by 25 percent without converting to grayscale.} {{modulate {brightness 100 saturation 75 hue 100}}}] \
        [list {Color | Convert to grayscale} {Convert to grayscale. This is a display conversion, not a measured intensity calibration.} {{colorspace {space Gray}}}] \
        [list {Scan | Remove small specks} {Use ImageMagick despeckling on scanning artifacts; tiny legitimate marks may disappear.} {{despeckle {}}}] \
        [list {Scan | Dark text on white} {Create a high-contrast black-and-white scan. Continuous tone information will be lost.} {{colorspace {space Gray}} {threshold {threshold 60}}}] \
        [list {Scan | Clarify faint writing} {Extend the tonal range and apply a moderate unsharp filter.} {{auto_level {}} {unsharp {radius 0 sigma 0.8 gain 0.5 threshold 0.05}}}] \
        [list {Microscopy | Gentle sharpening} {Light edge enhancement for visual preparation, never calibrated feature measurement.} {{unsharp {radius 0 sigma 0.7 gain 0.35 threshold 0.06}}}] \
        [list {Microscopy | Show edges} {Edge-detection visualization; output is not an unaltered micrograph.} {{edge {radius 1}}}] \
        [list {Diagram | Increase contrast} {Strengthen midtone separation for line art and diagrams.} {{sigmoidal {contrast 7 midpoint 50}}}] \
        [list {Diagram | Invert colors} {Swap light and dark foreground/background using the negative operation.} {{negate {}}}] \
        [list {Diagram | Sharpen strokes} {Accent printed lines and symbols; may cause edge halos.} {{unsharp {radius 0 sigma 0.85 gain 1 threshold 0.05}}}] \
    ]
}
proc ::GX::SII::presetSelectionChanged {} {
    variable ui
    set selected $ui(basicPreset)
    set ui(basicPresetDescription) {Select a task to see its processing recipe.}
    set ui(basicPresetOperations) {}
    foreach item [basicPresetCatalog] {
        lassign $item title description steps
        if {$selected ne $title} continue
        set ui(basicPresetDescription) $description
        set names {}
        foreach step $steps {
            lassign $step op params
            lappend names [dict get [catalogGet $op] label]
        }
        set ui(basicPresetOperations) "Operations: [join $names { → }]"
        return
    }
}
proc ::GX::SII::previewSelectedPreset {} {
    variable ui
    foreach item [basicPresetCatalog] {
        lassign $item title description steps
        if {$title ne $ui(basicPreset)} continue
        applyPreset $steps
        return
    }
    guiError {Select a preset before requesting a preview.}
}
proc ::GX::SII::editorSwitch {mode} {
    variable ui
    if {$mode ni {basic advanced}} {error {Invalid editor mode}}
    set ui(editorMode) $mode
    if {![info exists ui(window)]} return
    set base $ui(window).layout.inspector.tabs.simple
    if {![winfo exists $base.basic] || ![winfo exists $base.advanced]} return
    pack forget $base.basic
    pack forget $base.advanced
    pack $base.$mode -fill both -expand 1
    if {$mode eq {advanced}} {populateCatalog}
    if {[llength [info commands ::GX::SII::sidebarSelect]]} {sidebarSelect simple}
}
proc ::GX::SII::buildSimpleTab {f} {
    variable ui
    set ui(editorMode) basic
    ttk::frame $f.switch
    ttk::radiobutton $f.switch.basic -text {Basic Editor} -variable ::GX::SII::ui(editorMode) -value basic -command {::GX::SII::editorSwitch basic}
    ttk::radiobutton $f.switch.advanced -text {Advanced Editor} -variable ::GX::SII::ui(editorMode) -value advanced -command {::GX::SII::editorSwitch advanced}
    pack $f.switch.basic $f.switch.advanced -side left -expand 1 -fill x -padx 2
    pack $f.switch -fill x -pady {0 8}
    ttk::frame $f.basic
    ttk::frame $f.advanced
    pack $f.basic -fill both -expand 1
    set b $f.basic
    ttk::label $b.info -text {Choose a named task preset, or adjust the working image manually. Image corrections require Accept or Discard; originals are never overwritten.} -wraplength 300
    pack $b.info -fill x -pady 5
    ttk::label $b.presetsTitle -text {Task presets} -font TkHeadingFont
    pack $b.presetsTitle -anchor w
    set titles [lmap item [basicPresetCatalog] {lindex $item 0}]
    set ui(basicPreset) [lindex $titles 0]
    ttk::combobox $b.presets -state readonly -width 34 -textvariable ::GX::SII::ui(basicPreset) -values $titles
    pack $b.presets -fill x -pady 4
    bind $b.presets <<ComboboxSelected>> ::GX::SII::presetSelectionChanged
    ttk::label $b.presetAbout -textvariable ::GX::SII::ui(basicPresetDescription) -wraplength 300 -justify left
    ttk::label $b.presetOps -textvariable ::GX::SII::ui(basicPresetOperations) -wraplength 300 -foreground #425775
    pack $b.presetAbout $b.presetOps -fill x -pady 2
    ttk::button $b.previewPreset -text {Preview selected preset} -command ::GX::SII::previewSelectedPreset
    pack $b.previewPreset -fill x -pady 5
    presetSelectionChanged
    ttk::separator $b.separator -orient horizontal
    pack $b.separator -fill x -pady 7
    ttk::label $b.quick -text {Manual adjustments} -font TkHeadingFont
    pack $b.quick -anchor w
    foreach {key label min max initial} {
        brightness Brightness -100 100 0
        contrast Contrast -100 100 0
        gamma Gamma 0.1 4 1
        degrees Rotation -180 180 0
    } {
        ttk::frame $b.$key
        ttk::label $b.$key.label -text $label -width 12
        ttk::scale $b.$key.scale -from $min -to $max -variable ::GX::SII::ui(quick-$key)
        ttk::label $b.$key.value -textvariable ::GX::SII::ui(quick-$key) -width 6
        set ui(quick-$key) $initial
        pack $b.$key.label -side left
        pack $b.$key.scale -side left -expand yes -fill x
        pack $b.$key.value -side left
        pack $b.$key -fill x -pady 3
    }
    ttk::button $b.apply -text {Preview manual adjustments} -command ::GX::SII::applyQuick
    ttk::button $b.crop -text {Preview crop from selected ROI} -command ::GX::SII::cropQuick
    pack $b.apply $b.crop -fill x -pady 3
    ttk::label $b.tip -text {For individual operations and explicit ROI processing use Advanced Editor.} -wraplength 300
    pack $b.tip -fill x -pady 7
    ttk::label $f.advanced.info -text {Search all ImageMagick operations, inspect availability, adjust validated parameters, and choose Whole Image or ROI. An unavailable operation cannot be applied.} -wraplength 300
    pack $f.advanced.info -fill x -pady 4
    ttk::frame $f.advanced.operations
    pack $f.advanced.operations -fill both -expand yes
    buildOperationsTab $f.advanced.operations
}
proc ::GX::SII::applyPreset {definitions} {
    variable ui
    if {$ui(sourceId) eq ""} return
    if {[catch {
        set steps {}
        set useRoi [expr {[llength $ui(roi)]==4 && $ui(scope) eq "roi"}]
        foreach definition $definitions {
            lassign $definition op params
            if {$useRoi && ![dict get [catalogGet $op] roi]} {
                error "[dict get [catalogGet $op] label] cannot process only an ROI. Switch to Advanced Editor, select Whole image, or clear the ROI."
            }
            lappend steps [dict create op $op params $params \
                scope [expr {$useRoi ? "roi" : "all"}] \
                roi [expr {$useRoi ? $ui(roi) : {}}]]
        }
        previewSteps $steps
    } err]} {guiError $err}
}
proc ::GX::SII::applyQuick {} {
    variable ui
    set b [round $ui(quick-brightness)];set c [round $ui(quick-contrast)]
    set g [format %.3f $ui(quick-gamma)];set r [format %.2f $ui(quick-degrees)]
    set ops {}
    if {$b!=0 || $c!=0} {lappend ops [list brightness_contrast [dict create brightness $b contrast $c]]}
    if {$g!=1} {lappend ops [list gamma [dict create gamma $g]]}
    if {$r!=0} {lappend ops [list rotate [dict create degrees $r]]}
    if {[llength $ops]} {applyPreset $ops}
}
proc ::GX::SII::cropQuick {} {
    variable ui
    if {[llength $ui(roi)]!=4} {guiError {Select a crop region on the working image first.};return}
    lassign $ui(roi) x y w h
    # Crop changes image geometry: ImageMagick crop is a whole-image operator,
    # but its explicit rectangle is taken from the currently selected ROI.
    previewSteps [list [dict create op crop params [dict create rect "${w}x${h}+${x}+${y}"] \
        scope all roi {}]]
}
proc ::GX::SII::figureSettings {} {
    variable ui
    return [dict create width $ui(figure-width) height $ui(figure-height) margin $ui(figure-margin) \
        gutter $ui(figure-gutter) layout $ui(figure-layout) background $ui(figure-background)]
}
proc ::GX::SII::buildFigureTab {f} {
    variable ui
    ttk::label $f.h -text {Article Figure Studio} -font TkHeadingFont;pack $f.h -anchor w -pady 3
    ttk::label $f.intro -text {Add current images as independent panels; choose a layout, then render the figure. Individual image corrections remain editable.} -wraplength 340
    pack $f.intro -fill x
    # Keep buttons fully visible in a narrow sidebar: avoid a clipped row of
    # three side-by-side buttons with minimum requested width > inspector width.
    ttk::frame $f.actions;pack $f.actions -fill x -pady 3
    foreach {key title command} {add {Add current} addCurrentPanel update {Update selected} updateCurrentPanel remove {Remove selected} removePanel} {
        ttk::button $f.actions.$key -text $title -command ::GX::SII::$command
    }
    grid $f.actions.add -row 0 -column 0 -sticky ew -padx 2 -pady 2
    grid $f.actions.update -row 0 -column 1 -sticky ew -padx 2 -pady 2
    grid $f.actions.remove -row 1 -column 0 -columnspan 2 -sticky ew -padx 2 -pady 2
    grid columnconfigure $f.actions 0 -weight 1 -uniform buttons
    grid columnconfigure $f.actions 1 -weight 1 -uniform buttons
    listbox $f.panels -height 6 -exportselection 0
    pack $f.panels -fill x -pady 5
    foreach {name title default} {width Width 2400 height Height 1600 margin Margin 32 gutter Gutter 24} {
        ttk::frame $f.$name;pack $f.$name -fill x -pady 2
        ttk::label $f.$name.l -text $title -width 12
        ttk::entry $f.$name.e -textvariable ::GX::SII::ui(figure-$name) -width 13
        pack $f.$name.l -side left;pack $f.$name.e -side right
        set ui(figure-$name) $default
    }
    ttk::label $f.layoutlabel -text Layout
    ttk::combobox $f.layout -textvariable ::GX::SII::ui(figure-layout) -state readonly -values {grid horizontal vertical}
    set ui(figure-layout) grid
    set ui(figure-background) #FFFFFF
    pack $f.layoutlabel $f.layout -fill x -pady 2
    ttk::button $f.preview -text {Preview composed figure} -command ::GX::SII::previewFigure
    pack $f.preview -fill x -pady 7
    ttk::label $f.tip -text {Annotations can be added directly on the working canvas. For a composition, choose Preview composed figure to make it the visible editing surface.} -wraplength 340
    pack $f.tip -fill x
}
proc ::GX::SII::refreshPanels {} {
    variable ui
    if {![info exists ui(window)]} return
    set w $ui(window).layout.inspector.tabs.figure.panels
    if {![winfo exists $w]} return
    $w delete 0 end
    set i 0
    foreach p $ui(panels) {
        incr i
        $w insert end "$i. [dict get $p source_id] ([llength [dict get $p steps]] edits)"
    }
}
proc ::GX::SII::addCurrentPanel {} {
    variable ui
    if {$ui(sourceId) eq ""} {guiError {Open an image first.};return}
    if {[catch {
        if {[llength $ui(panels)]>=12} {error {Maximum 12 panels}}
        set info [sourceInfo $ui(sourceId)]
        recordFigureEdit
        lappend ui(panels) [dict create source_id $ui(sourceId) source_sha [dict get $info sha256] steps [validateSteps $ui(steps)]]
        refreshPanels;saveState
    } err]} {guiError $err}
}
proc ::GX::SII::updateCurrentPanel {} {
    variable ui
    set lb $ui(window).layout.inspector.tabs.figure.panels
    set chosen [$lb curselection]
    if {![llength $chosen]} {guiError {Select a figure panel to update.};return}
    if {[catch {
        set source [sourceInfo $ui(sourceId)]
        recordFigureEdit
        lset ui(panels) [lindex $chosen 0] [dict create source_id $ui(sourceId) source_sha [dict get $source sha256] steps [validateSteps $ui(steps)]]
        refreshPanels;saveState
    } err]} {guiError $err}
}
proc ::GX::SII::removePanel {} {
    variable ui
    set chosen [$ui(window).layout.inspector.tabs.figure.panels curselection]
    if {![llength $chosen]} return
    recordFigureEdit
    set ui(panels) [lreplace $ui(panels) [lindex $chosen 0] [lindex $chosen 0]]
    refreshPanels;saveState
}
proc ::GX::SII::previewFigure {} {
    variable ui
    if {![llength $ui(panels)]} {guiError {Add one or more images to the figure first.};return}
    if {$ui(pending)} {guiError {Accept or discard the pending adjustment first.};return}
    if {[catch {
        checkSession
        set output [guiTemp .png]
        # Preview only; full-resolution figure is rendered at explicit Dataset publication.
        figureCreate $ui(panels) [figureSettings] {} $output png8
        if {!$ui(figurePreviewActive)} {
            set ui(imageAnnotations) $ui(annotations)
            set ui(annotations) $ui(figureAnnotations)
        }
        set ui(workingFile) $output
        set ui(workingInfo) [inspectFile $output]
        set ui(preview-original) [guiTemp .png]
        previewFile $output $ui(preview-original) 2400 2400
        lodReset
        set ui(figurePreviewActive) 1
        set ui(native-size-original) {}
        refreshAnnotations
        nativeDisplay original
        set ui(status) {Working canvas: article figure composition. Annotations are editable; Publish Dataset renders the full-resolution figure.}
    } err]} {guiError $err}
}
proc ::GX::SII::buildAnnotationsTab {f} {
    variable ui
    foreach {key value} {annotation-text {} annotation-color #FFCC00 annotation-size 46 annotation-stroke 4} {
        set ui($key) $value
    }
    foreach name {x1 x2 y1 y2} {set ui(annotation-$name) 0}
    ttk::label $f.h -text {Annotations} -font TkHeadingFont
    ttk::label $f.tip -text {Use the canvas context menu (right-click) to add text, arrows and shapes. Select an object for Native2D transform/pivot tools. Pan has its own toolbar icon.} -wraplength 315
    ttk::checkbutton $f.active -text {Edit annotations} -variable ::GX::SII::ui(annotating) -command ::GX::SII::annotationModeChanged
    pack $f.h $f.tip $f.active -fill x -pady 3
    ttk::label $f.objects -text {Objects (select or right-click an image object)}
    pack $f.objects -fill x
    listbox $f.list -height 6 -exportselection 0
    pack $f.list -fill x -pady 3
    bind $f.list <<ListboxSelect>> ::GX::SII::selectAnnotation
    bind $f.list <Button-3> {::GX::SII::annotationListContext %x %y %X %Y}
    ttk::label $f.hint -text {A selected annotation can be translated, rotated or given a custom pivot using the Native2D gizmo. Exit annotations with Esc or the pointer icon; overlays stay visible.} -wraplength 315
    pack $f.hint -fill x -pady 4
    # Advanced coordinates are optional, never part of the normal workflow.
    ttk::labelframe $f.position -text {Exact coordinates (image px)}
    if {$ui(showAnnotationCoordinates)} {pack $f.position -fill x -pady 5}
    foreach {name title} {x1 X1 y1 Y1 x2 X2 y2 Y2} {
        ttk::label $f.position.${name}l -text $title
        ttk::entry $f.position.$name -textvariable ::GX::SII::ui(annotation-$name) -width 7
    }
    grid $f.position.x1l -row 0 -column 0;grid $f.position.x1 -row 0 -column 1
    grid $f.position.y1l -row 0 -column 2;grid $f.position.y1 -row 0 -column 3
    grid $f.position.x2l -row 1 -column 0;grid $f.position.x2 -row 1 -column 1
    grid $f.position.y2l -row 1 -column 2;grid $f.position.y2 -row 1 -column 3
}
# Annotation layers are retained as editable logical objects. Only the
# presentation is rendered into Native2D/Tk, never into source raster pixels.
proc ::GX::SII::annotationsEnsureIds {} {
    variable ui
    set result {};set used {}
    foreach a $ui(annotations) {
        set id [get $a id {}]
        if {![regexp {^ann[0-9]+$} $id] || $id in $used} {
            if {![info exists ui(annotationSerial)]} {set ui(annotationSerial) 0}
            while 1 {
                set id ann[incr ui(annotationSerial)]
                if {$id ni $used} break
            }
            dict set a id $id
        } else {
            set number [string range $id 3 end]
            if {![info exists ui(annotationSerial)] || $number>$ui(annotationSerial)} {set ui(annotationSerial) $number}
        }
        if {![dict exists $a name] || [string trim [dict get $a name]] eq {}} {
            if {[dict get $a kind] eq "text"} {
                set text [get $a text {}]
                set name [string range $text 0 36]
                if {[string trim $name] eq {}} {set name "Text $id"}
            } else {set name "[string totitle [dict get $a kind]] $id"}
            dict set a name $name
        }
        lappend used $id
        lappend result $a
    }
    set ui(annotations) $result
}
# Selection belongs to the canvas/controller, never the optional sidebar list.
proc ::GX::SII::annotationCurrentIndex {} {
    variable ui
    if {![info exists ui(annotationActiveId)] || $ui(annotationActiveId) eq {}} {return -1}
    set i 0
    foreach a $ui(annotations) {
        if {[get $a id {}] eq $ui(annotationActiveId)} {return $i}
        incr i
    }
    return -1
}
proc ::GX::SII::annotationSelectIndex {index} {
    variable ui
    set list $ui(window).layout.inspector.tabs.annotations.list
    if {$index>=0 && $index<[llength $ui(annotations)]} {
        set a [lindex $ui(annotations) $index]
        set ui(annotationActiveId) [dict get $a id]
        set ui(selectedAnnotationIds) [list $ui(annotationActiveId)]
        foreach key {text color size stroke x1 y1 x2 y2} {
            if {[dict exists $a $key]} {set ui(annotation-$key) [dict get $a $key]}
        }
    } else {
        set ui(annotationActiveId) {}
        set ui(selectedAnnotationIds) {}
    }
    if {[winfo exists $list]} {
        $list selection clear 0 end
        if {$index>=0 && $index<[llength $ui(annotations)]} {
            $list selection set $index
            $list see $index
        }
    }
    nativeDrawAnnotations
}
proc ::GX::SII::refreshAnnotations {} {
    variable ui
    if {![info exists ui(window)]} return
    set w $ui(window).layout.inspector.tabs.annotations.list
    if {![winfo exists $w]} return
    annotationsEnsureIds
    set active [expr {[info exists ui(annotationActiveId)] ? $ui(annotationActiveId) : {}}]
    $w delete 0 end
    foreach a $ui(annotations) {
        set label "[get $a name [dict get $a kind]]  ([string totitle [dict get $a kind]])"
        if {$ui(showAnnotationCoordinates)} {append label " @ [dict get $a x1],[dict get $a y1]"}
        $w insert end $label
    }
    set index [annotationCurrentIndex]
    if {$index>=0} {$w selection set $index}
    nativeDrawAnnotations
}
proc ::GX::SII::selectAnnotation {} {
    variable ui
    set list $ui(window).layout.inspector.tabs.annotations.list
    set choice [$list curselection]
    if {[llength $choice] != 1} return
    set index [lindex $choice 0]
    set ui(annotationActiveId) [get [lindex $ui(annotations) $index] id {}]
    set ui(selectedAnnotationIds) [list $ui(annotationActiveId)]
    if {$index<0} return
    set a [lindex $ui(annotations) $index]
    foreach key {text color size stroke x1 y1 x2 y2} {
        if {[dict exists $a $key]} {set ui(annotation-$key) [dict get $a $key]}
    }
    nativeDrawAnnotations
}
proc ::GX::SII::updateAnnotation {} {
    variable ui
    if {[annotationLocked]} return
    set index [annotationCurrentIndex]
    if {$index<0} return
    if {[catch {
        set a [lindex $ui(annotations) $index]
        dict set a color $ui(annotation-color)
        dict set a stroke $ui(annotation-stroke)
        foreach key {x1 y1} {dict set a $key $ui(annotation-$key)}
        if {[dict get $a kind] ne "text"} {
            foreach key {x2 y2} {dict set a $key $ui(annotation-$key)}
        }
        if {[dict get $a kind] eq "text"} {dict set a text $ui(annotation-text);dict set a size $ui(annotation-size)}
        set id [dict get $a id]
        set a [validateAnnotation $a [dict get $ui(workingInfo) width] [dict get $ui(workingInfo) height]]
        dict set a id $id
        recordFigureEdit
        lset ui(annotations) $index $a
        refreshAnnotations;annotationSelectIndex $index;saveState
    } err]} {guiError $err}
}
proc ::GX::SII::removeAnnotation {} {
    variable ui
    if {[annotationLocked]} return
    set index [annotationCurrentIndex]
    if {$index<0} return
    recordFigureEdit
    set ui(annotations) [lreplace $ui(annotations) $index $index]
    set ui(annotationActiveId) {}
    set ui(selectedAnnotationIds) {}
    refreshAnnotations;nativeDrawAnnotations;saveState
}
proc ::GX::SII::annotationLocked {} {
    variable ui
    if {[historyReadOnly]} {return 1}
    if {[info exists ui(pending)] && $ui(pending)} {
        set ui(status) {Pending adjustment: accept or discard the preview before editing annotations.}
        return 1
    }
    return 0
}
# Detect only tagged overlay graphics; background pixels are never selectable.
proc ::GX::SII::annotationHit {x y} {
    variable ui
    set c $ui(window).layout.main.panes.original.canvas
    # A resize handle is an explicit editing target and has priority over the
    # corresponding Native2D stroke underneath it.
    foreach item [lreverse [$c find overlapping [expr {$x-5}] [expr {$y-5}] [expr {$x+5}] [expr {$y+5}]]] {
        if {[lsearch -exact [$c gettags $item] sii_resize_handle]<0} continue
        foreach tag [$c gettags $item] {
            if {![regexp {^sii_annotation_(ann[0-9]+)$} $tag -> found]} continue
            set i 0
            foreach a $ui(annotations) {
                if {[get $a id {}] eq $found} {return [list $i resize]}
                incr i
            }
        }
    }
    # Semantic Native2D object pick (Curve Workbench selection model).
    if {[info exists ui(nativeAnnotationMap)] && [dict size $ui(nativeAnnotationMap)]} {
        set ids {}
        dict for {logical tokens} $ui(nativeAnnotationMap) {foreach token $tokens {lappend ids $token}}
        if {[llength $ids] && ![catch {
            set member [::GX::Native2D::core selection_pick [annotationScene] $ids [list $x $y] 13 object]
        }] && $member ne {}} {
            set token [dict get $member id]
            dict for {logical tokens} $ui(nativeAnnotationMap) {
                if {$token in $tokens} {
                    set index 0
                    foreach a $ui(annotations) {
                        if {[get $a id {}] eq $logical} {return [list $index move]}
                        incr index
                    }
                }
            }
        }
    }
    foreach item [lreverse [$c find overlapping [expr {$x-12}] [expr {$y-12}] [expr {$x+12}] [expr {$y+12}]]] {
        set id {};set mode move
        foreach tag [$c gettags $item] {
            if {[regexp {^sii_annotation_(ann[0-9]+)$} $tag -> found]} {set id $found}
            if {$tag eq "sii_resize_handle"} {set mode resize}
        }
        if {$id eq {}} continue
        set index 0
        foreach a $ui(annotations) {
            if {[get $a id {}] eq $id} {return [list $index $mode]}
            incr index
        }
    }
    return {}
}
proc ::GX::SII::annotationMoveOrResize {base mode x y} {
    variable ui
    set w [dict get $ui(workingInfo) width];set h [dict get $ui(workingInfo) height]
    set new $base
    if {$mode eq "rotate"} {
        lassign [annotationPivot $base] cx cy
        lassign $ui(annotationPressImage) sx sy
        set before [expr {atan2($sy-$cy,$sx-$cx)}]
        set after [expr {atan2($y-$cy,$x-$cx)}]
        dict set new rotation [expr {[get $base rotation 0]+($after-$before)*180.0/acos(-1)}]
        return $new
    } elseif {$mode eq "resize" && [dict get $base kind] ne "text"} {
        lassign [annotationInversePoint $base $x $y] rx ry
        dict set new x2 [round $rx];dict set new y2 [round $ry]
    } else {
        lassign $ui(annotationPressImage) sx sy
        set dx [expr {$x-$sx}];set dy [expr {$y-$sy}]
        foreach key {x1 x2} {if {[dict exists $base $key]} {dict set new $key [expr {[dict get $base $key]+$dx}]}}
        foreach key {y1 y2} {if {[dict exists $base $key]} {dict set new $key [expr {[dict get $base $key]+$dy}]}}
        if {[dict exists $base pivot_x]} {dict set new pivot_x [expr {[dict get $base pivot_x]+$dx}]}
        if {[dict exists $base pivot_y]} {dict set new pivot_y [expr {[dict get $base pivot_y]+$dy}]}
    }
    foreach key {x1 x2} {if {[dict exists $new $key]} {dict set new $key [expr {max(0,min($w,[dict get $new $key]))}]}}
    foreach key {y1 y2 pivot_y} {if {[dict exists $new $key]} {dict set new $key [expr {max(0,min($h,[dict get $new $key]))}]}}
    if {[dict exists $new pivot_x]} {dict set new pivot_x [expr {max(0,min($w,[dict get $new pivot_x]))}]}
    return $new
}
proc ::GX::SII::canvasStart {x y {state 0}} {
    variable ui
    if {[annotationLocked]} return
    # Taking canvas focus allows Edit keyboard shortcuts after clicking the image,
    # without hijacking native Ctrl+A/C/V inside text fields.
    focus [annotationCanvas]
    if {[info exists ui(canvasMode)] && $ui(canvasMode) eq "pan"} {panStart original $x $y;return}
    if {[info exists ui(selectionMode)] && $ui(selectionMode) eq "polygon" && $ui(annotating)} {
        annotationPolygonPoint $x $y;return
    }
    if {[info exists ui(selectionMode)] && $ui(selectionMode) eq "window" && $ui(annotating)} {
        set ui(selectionWindowStart) [list $x $y]
        annotationGestureDraw [list [list $x $y] [list $x $y]] window
        return
    }
    if {!$ui(annotating)} {roiStart $x $y;return}
    if {[annotationNativeDragBegin $x $y]} return
    unset -nocomplain ui(annotationStart) ui(annotationGhost) ui(annotationEditIndex)
    set tool $ui(annotationTool)
    if {$tool eq "ROI"} {roiStart $x $y;return}
    set at [toImageXY original $x $y]
    if {$tool eq "Select"} {
        if {[info exists ui(annotationRotateArmed)] && $ui(annotationRotateArmed)} {
            set index [annotationCurrentIndex]
            if {$index<0 || $at eq {}} return
            set ui(annotationEditIndex) $index
            set ui(annotationEditBase) [lindex $ui(annotations) $index]
            set ui(annotationPressImage) $at
            set ui(annotationStart) $at
            set ui(annotationEditMode) rotate
            unset ui(annotationRotateArmed)
            return
        }
        set hit [annotationHit $x $y]
        if {$hit eq {}} {annotationSelectIndex -1;return}
        lassign $hit index mode
        if {$state & 0x0001} {
            annotationSelectionToggle $index
            return
        }
        annotationSelectIndex $index
        if {$at eq {}} return
        set ui(annotationPressImage) $at
        set ui(annotationStart) $at
        set ui(annotationEditIndex) $index
        set ui(annotationEditMode) $mode
        set ui(annotationEditBase) [lindex $ui(annotations) $index]
        return
    }
    if {$at eq {}} return
    set ui(annotationStart) $at
    if {$tool eq "Text"} {
        # The actual box size is chosen by a drag (or a bounded default click).
        set ui(textDraft) [list {*}$at {*}$at]
        nativeDrawAnnotations
        return
    }
    lassign $at x1 y1
    set ui(annotationGhost) [dict create id ann_preview kind [string tolower $tool] x1 $x1 y1 $y1 x2 $x1 y2 $y1 color $ui(annotation-color) stroke $ui(annotation-stroke)]
    nativeDrawAnnotations
}
proc ::GX::SII::canvasDrag {x y} {
    variable ui
    if {[annotationLocked]} return
    if {[info exists ui(selectionWindowStart)]} {
        annotationGestureDraw [list $ui(selectionWindowStart) [list $x $y]] window
        return
    }
    if {[info exists ui(canvasMode)] && $ui(canvasMode) eq "pan"} {panDrag original $x $y;return}
    if {!$ui(annotating)} {roiDrag $x $y;return}
    if {[info exists ui(annotationNativeDrag)]} {annotationNativeDragMove $x $y;return}
    if {$ui(annotationTool) eq "ROI"} {roiDrag $x $y;return}
    if {![info exists ui(annotationStart)]} return
    set at [toImageXY original $x $y]
    if {$ui(annotationTool) eq "Text" && [info exists ui(textDraft)]} {
        if {$at ne {}} {set ui(textDraft) [list {*}$ui(annotationStart) {*}$at]}
        nativeDrawAnnotations
        return
    }
    if {$at eq {}} return
    lassign $at px py
    if {[info exists ui(annotationEditIndex)]} {
        set ui(annotationGhost) [annotationMoveOrResize $ui(annotationEditBase) $ui(annotationEditMode) $px $py]
    } elseif {$ui(annotationTool) ne "Text" && $ui(annotationTool) ne "Select"} {
        dict set ui(annotationGhost) x2 $px
        dict set ui(annotationGhost) y2 $py
    }
    # Only redraw overlay objects; never recompute image pixels on pointer motion.
    nativeDrawAnnotations
}
proc ::GX::SII::canvasCommit {x y} {
    variable ui
    if {[annotationLocked]} return
    if {[info exists ui(selectionWindowStart)]} {
        lassign $ui(selectionWindowStart) sx sy
        unset ui(selectionWindowStart)
        annotationSelectRegion [list [list $sx $sy] [list $x $sy] [list $x $y] [list $sx $y]]
        [annotationCanvas] delete sii_selection_gesture
        return
    }
    if {[info exists ui(selectionMode)] && $ui(selectionMode) eq "polygon" && $ui(annotating)} return
    if {[info exists ui(canvasMode)] && $ui(canvasMode) eq "pan"} {unset -nocomplain ui(native-pan-original);return}
    if {!$ui(annotating)} {roiFinish $x $y;return}
    if {[info exists ui(annotationNativeDrag)]} {annotationNativeDragCommit;return}
    if {$ui(annotationTool) eq "ROI"} {roiFinish $x $y;return}
    if {![info exists ui(annotationStart)]} return
    if {$ui(annotationTool) eq "Text" && [info exists ui(textDraft)]} {
        set coords $ui(textDraft)
        unset -nocomplain ui(textDraft) ui(annotationStart) ui(annotationGhost)
        annotationInlineEditor new [lindex $coords 0] [lindex $coords 1] [lindex $coords 2] [lindex $coords 3]
        return
    }
    if {[catch {
        set xy [toImageXY original $x $y]
        if {$xy eq {}} {set xy $ui(annotationStart)}
        lassign $xy x2 y2
        set index -1
        if {[info exists ui(annotationEditIndex)]} {
            set index $ui(annotationEditIndex)
            set a [annotationMoveOrResize $ui(annotationEditBase) $ui(annotationEditMode) $x2 $y2]
        } elseif {$ui(annotationTool) eq "Select"} {
            return
        } else {
            lassign $ui(annotationStart) x1 y1
            set kind [string tolower $ui(annotationTool)]
            set a [dict create kind $kind x1 $x1 y1 $y1 color $ui(annotation-color) stroke $ui(annotation-stroke)]
            if {$kind eq "text"} {
                dict set a text $ui(annotation-text)
                dict set a size $ui(annotation-size)
            } else {dict set a x2 $x2;dict set a y2 $y2}
        }
        set stableId [get $a id {}]
        set a [validateAnnotation $a [dict get $ui(workingInfo) width] [dict get $ui(workingInfo) height]]
        if {$stableId ne {}} {dict set a id $stableId}
        if {$index<0 || $a ne [lindex $ui(annotations) $index]} {
            recordFigureEdit
            if {$index<0} {
                set ui(annotations) [concat $ui(annotations) [list $a]]
                set index [expr {[llength $ui(annotations)]-1}]
            } else {lset ui(annotations) $index $a}
            refreshAnnotations;annotationSelectIndex $index;saveState
        }
    } err options]} {
        # Rejected user geometry is not an exceptional failure of the Viewer.
        # Do not push a History entry or leave a half-finished gesture active.
        if {[string match {Cannot create *} $err]} {
            set ui(status) "$err Nothing was added. Select a drawing tool and drag again."
        } else {eventFailure {Annotation edit} $err $options}
    }
    unset -nocomplain ui(annotationStart) ui(annotationGhost) ui(annotationEditIndex) ui(annotationEditBase)
    nativeDrawAnnotations
}
proc ::GX::SII::canvasDoubleClick {x y} {
    variable ui
    if {[annotationLocked]} return
    if {$ui(annotating) && [info exists ui(selectionMode)] && $ui(selectionMode) eq "polygon"} {
        annotationPolygonFinish
        return
    }
    if {!$ui(annotating)} {pixelAt $x $y;return}
    set hit [annotationHit $x $y]
    if {$hit eq {}} {pixelAt $x $y;return}
    annotationSelectIndex [lindex $hit 0]
    set a [lindex $ui(annotations) [lindex $hit 0]]
    if {[dict get $a kind] eq "text"} {annotationInlineEditor [lindex $hit 0]}
}
proc ::GX::SII::annotationEditTextDialog {} {
    variable ui
    set index [annotationCurrentIndex]
    if {$index<0 || [dict get [lindex $ui(annotations) $index] kind] ne "text"} return
    set w $ui(window).editAnnotation
    catch {destroy $w}
    toplevel $w
    wm title $w {Edit text annotation}
    wm transient $w $ui(window)
    ttk::label $w.title -text {Annotation text}
    ttk::entry $w.text -textvariable ::GX::SII::ui(annotation-text) -width 44
    ttk::label $w.sizel -text {Font size (image pixels)}
    ttk::entry $w.size -textvariable ::GX::SII::ui(annotation-size)
    ttk::button $w.apply -text {Apply changes} -command [list ::GX::SII::annotationEditApply $w]
    pack $w.title $w.text $w.sizel $w.size $w.apply -fill x -padx 10 -pady 5
    focus $w.text
    $w.text selection range 0 end
}
proc ::GX::SII::annotationEditApply {w} {
    updateAnnotation
    if {[winfo exists $w]} {destroy $w}
}
proc ::GX::SII::recordFigureEdit {} {
    variable ui
    set ui(editDomain) annotations
    lappend ui(figureUndo) [dict create panels $ui(panels) annotations $ui(annotations)]
    if {[llength $ui(figureUndo)]>60} {set ui(figureUndo) [lrange $ui(figureUndo) end-59 end]}
    set ui(figureRedo) {}
}
proc ::GX::SII::undoFigure {} {
    variable ui
    if {[annotationLocked]} return
    if {![llength $ui(figureUndo)]} return
    lappend ui(figureRedo) [dict create panels $ui(panels) annotations $ui(annotations)]
    set state [lindex $ui(figureUndo) end]
    set ui(figureUndo) [lrange $ui(figureUndo) 0 end-1]
    set ui(panels) [dict get $state panels]
    set ui(annotations) [dict get $state annotations]
    refreshPanels;refreshAnnotations;nativeDisplay original;saveState
}
proc ::GX::SII::redoFigure {} {
    variable ui
    if {[annotationLocked]} return
    if {![llength $ui(figureRedo)]} return
    lappend ui(figureUndo) [dict create panels $ui(panels) annotations $ui(annotations)]
    set state [lindex $ui(figureRedo) end]
    set ui(figureRedo) [lrange $ui(figureRedo) 0 end-1]
    set ui(panels) [dict get $state panels]
    set ui(annotations) [dict get $state annotations]
    refreshPanels;refreshAnnotations;nativeDisplay original;saveState
}


# Explicit editing mode: overlays remain visible after exit, whereas pointer
# gestures revert to image ROI and normal browsing. CORE owns tool glyphs.
proc ::GX::SII::annotationMode {enabled} {
    variable ui
    if {![info exists ui(window)] || ![winfo exists $ui(window)]} return
    if {$enabled && ![historyResumeForEditing]} return
    if {!$enabled && $ui(pending)} {
        # Esc finishes annotation editing but must never dismiss/relabel a
        # pending image adjustment transaction.
        set ui(annotating) 0
        return
    }
    if {$enabled && $ui(pending)} {
        set ui(annotating) 0
        set ui(status) {Accept or discard the image adjustment before editing annotations.}
        return
    }
    if {[info exists ui(annotationNativeDrag)]} {annotationNativeDragCancel}
    if {!$enabled && [info exists ui(inlineWidget)]} {annotationInlineCancel}
    set ui(canvasMode) [expr {$enabled ? "annotate" : "view"}]
    set ui(annotating) [expr {!!$enabled}]
    unset -nocomplain ui(annotationStart) ui(annotationGhost) ui(annotationEditIndex) ui(annotationRotateArmed) ui(textDraft)
    set textCanvas [annotationCanvas]
    if {[winfo exists $textCanvas]} {$textCanvas delete sii_text_draft}
    if {$enabled} {
        set ui(annotationTool) Select
        if {$ui(annotationTransform) eq "none"} {set ui(annotationTransform) translate}
        # The annotation inspector is optional: activating tools must not reveal it.
    }
    if {!$enabled} {set ui(annotationTransform) none}
    set canvas $ui(window).layout.main.panes.original.canvas
    if {[winfo exists $canvas]} {
        $canvas configure -cursor [expr {$enabled ? "crosshair" : "arrow"}]
        annotationToolbarSync
    }
    if {[info exists ui(annotations)] && [info exists ui(workingInfo)]} {nativeDrawAnnotations}
    set ui(status) [expr {$enabled ? {ANNOTATIONS — draw/select objects; right-click to move, rotate or set pivot; click pointer icon or Esc to finish.} : {Image editing — annotations remain visible; ROI and image tools are active.}}]
}
proc ::GX::SII::annotationModeChanged {} {
    variable ui
    annotationMode $ui(annotating)
}
# The same registered GX-TXT Configuration authority used by the sidebar.
proc ::GX::SII::annotationCoordinateConfigId {} {
    if {![llength [info commands ::GX::configurationModuleFields]]} {return {}}
    foreach {id descriptor} [::GX::configurationModuleFields viewer.scientific_image_inspector] {
        if {[dict get $descriptor module_key] eq "annotation_coordinates"} {return $id}
    }
    return {}
}
proc ::GX::SII::annotationCoordinatePreference {} {
    set id [annotationCoordinateConfigId]
    if {$id eq {}} {return 0}
    if {![catch {set conf [::GX::configurationResolve $id]}] && [dict exists $conf effective]} {
        return [expr {[dict get $conf effective] ? 1 : 0}]
    }
    return 0
}
proc ::GX::SII::annotationCoordinateToggle {} {
    variable ui
    set id [annotationCoordinateConfigId]
    if {$id ne {}} {
        if {[catch {
            set previous [::GX::configurationScopedValue $id user]
            ::GX::configurationCommit [list [dict create id $id scope user value $ui(showAnnotationCoordinates) expected $previous]]
        } err]} {
            set ui(showAnnotationCoordinates) [annotationCoordinatePreference]
            guiError "Unable to save GX-TXT configuration: $err"
            return
        }
    }
    set panel $ui(window).layout.inspector.tabs.annotations.position
    if {$ui(showAnnotationCoordinates)} {pack $panel -fill x -pady 5 -before $ui(window).layout.inspector.tabs.annotations.list} else {pack forget $panel}
    refreshAnnotations
    sidebarContentResize
}
# Context actions mirror Curve Workbench: object hit, semantic selection,
# Native2D ViewportHost context menu, then the provider-owned actions.
proc ::GX::SII::annotationContext {x y screenX screenY} {
    variable ui
    if {!$ui(annotating) || $ui(pending)} return
    set hit [annotationHit $x $y]
    if {$hit eq {}} return
    set index [lindex $hit 0]
    annotationSelectIndex $index
    set a [lindex $ui(annotations) $index]
    set actions [list \
        [list {Move (drag object)} {::GX::SII::annotationMoveArm}] \
        [list {Rotate with mouse} {::GX::SII::annotationRotateArm}] \
        [list {Set rotation angle...} {::GX::SII::annotationRotationDialog}] \
        [list {Rotate +90 degrees} [list ::GX::SII::annotationRotateBy 90]] \
        [list {Rotate -90 degrees} [list ::GX::SII::annotationRotateBy -90]] \
        [list {Set pivot here} [list ::GX::SII::annotationPivotAt $x $y]] \
        [list {Pivot at object center} {::GX::SII::annotationPivotReset}] \
        [list {Delete annotation} {::GX::SII::removeAnnotation}]]
    if {[dict get $a kind] eq "text"} {set actions [linsert $actions 0 [list {Edit text...} {::GX::SII::annotationEditTextDialog}]]}
    set c $ui(window).layout.main.panes.original.canvas
    set target [dict create entity object logical [dict get $a id]]
    set menu [::GX::native2DViewportContextMenu $c $target {} $actions {}]
    # Shared host composes a separating entry for a domain-only menu; remove it.
    if {[$menu type 0] eq {separator}} {$menu delete 0}
    if {[llength [info commands ::GX::uiMenuPopup]]} {::GX::uiMenuPopup $menu $screenX $screenY} else {tk_popup $menu $screenX $screenY}
}
proc ::GX::SII::annotationMoveArm {} {
    variable ui
    set ui(annotationTool) Select
    unset -nocomplain ui(annotationRotateArmed)
    set ui(status) {Drag the selected annotation to move it.}
}
proc ::GX::SII::annotationRotateArm {} {
    variable ui
    set ui(annotationTool) Select
    set ui(annotationRotateArmed) 1
    set ui(status) {Rotate: drag the mouse around the annotation pivot.}
}
proc ::GX::SII::annotationRotateBy {delta} {
    variable ui
    if {[annotationLocked]} return
    set idx [annotationCurrentIndex]
    if {$idx<0} return
    set a [lindex $ui(annotations) $idx]
    dict set a rotation [expr {[get $a rotation 0]+double($delta)}]
    set a [validateAnnotation $a [dict get $ui(workingInfo) width] [dict get $ui(workingInfo) height]]
    recordFigureEdit
    lset ui(annotations) $idx $a
    refreshAnnotations;annotationSelectIndex $idx;saveState
}
proc ::GX::SII::annotationPivotAt {x y} {
    variable ui
    if {[annotationLocked]} return
    set idx [annotationCurrentIndex]
    if {$idx<0} return
    set at [toImageXY original $x $y]
    if {$at eq {}} return
    lassign $at px py
    set a [lindex $ui(annotations) $idx]
    recordFigureEdit
    dict set a pivot_x $px
    dict set a pivot_y $py
    lset ui(annotations) $idx $a
    nativeDrawAnnotations;saveState
}
proc ::GX::SII::annotationPivotReset {} {
    variable ui
    if {[annotationLocked]} return
    set idx [annotationCurrentIndex]
    if {$idx<0} return
    set a [lindex $ui(annotations) $idx]
    recordFigureEdit
    dict unset a pivot_x
    dict unset a pivot_y
    lset ui(annotations) $idx $a
    nativeDrawAnnotations;saveState
}
proc ::GX::SII::annotationRotationDialog {} {
    variable ui
    set idx [annotationCurrentIndex]
    if {$idx<0} return
    set ui(annotationAngleInput) [get [lindex $ui(annotations) $idx] rotation 0]
    set w $ui(window).annotationRotation
    catch {destroy $w}
    toplevel $w
    wm title $w {Rotate annotation}
    wm transient $w $ui(window)
    ttk::label $w.label -text {Rotation (degrees, clockwise)}
    ttk::entry $w.angle -textvariable ::GX::SII::ui(annotationAngleInput)
    ttk::button $w.apply -text Apply -command [list ::GX::SII::annotationRotationApply $w]
    ttk::button $w.cancel -text Cancel -command [list destroy $w]
    pack $w.label $w.angle $w.apply $w.cancel -fill x -padx 12 -pady 5
    focus $w.angle
}
proc ::GX::SII::annotationRotationApply {w} {
    variable ui
    if {![string is double -strict $ui(annotationAngleInput)] || abs($ui(annotationAngleInput))>3600} {
        guiError {Enter a rotation between -3600 and 3600 degrees.};return
    }
    set idx [annotationCurrentIndex]
    if {$idx<0} return
    set prior [get [lindex $ui(annotations) $idx] rotation 0]
    annotationRotateBy [expr {double($ui(annotationAngleInput))-$prior}]
    destroy $w
}
