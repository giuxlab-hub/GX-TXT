# Scientific Image Inspector — context-sensitive raster / ROI actions.
# SPDX-License-Identifier: GPL-3.0-or-later
# Native2D remains the sole coordinate/viewport authority; the editor owns
# the selected pixel rectangle and uses the validated ImageMagick catalog.
namespace eval ::GX::SII {}

proc ::GX::SII::roiContainsDevice {x y} {
    variable ui
    if {![info exists ui(roi)] || [llength $ui(roi)]!=4 || ![info exists ui(workingInfo)]} {return 0}
    if {$ui(figurePreviewActive)} {return 0}
    set point [toImageXY original $x $y]
    if {$point eq {}} {return 0}
    lassign $point px py
    lassign $ui(roi) left top width height
    return [expr {$px >= $left && $px < $left+$width && $py >= $top && $py < $top+$height}]
}

# One canvas context dispatcher; ROI and Figure contexts take priority over the
# annotation background menu. No ImageMagick operation is silently accepted.
proc ::GX::SII::workingCanvasContext {x y screenX screenY} {
    variable ui
    if {![info exists ui(workingInfo)]} {return}
    if {$ui(pending)} {pendingCanvasContext $screenX $screenY;return}
    if {$ui(figurePreviewActive)} {figureCanvasContext $screenX $screenY;return}
    if {[roiContainsDevice $x $y]} {
        roiCanvasContext $x $y $screenX $screenY
    } else {
        annotationContext $x $y $screenX $screenY
    }
}
proc ::GX::SII::contextPopup {m X Y} {
    if {[llength [info commands ::GX::uiMenuPopup]]} {
        ::GX::uiMenuPopup $m $X $Y
    } else {tk_popup $m $X $Y}
}
proc ::GX::SII::figureCanvasContext {X Y} {
    variable ui
    set c $ui(window).layout.main.panes.original.canvas
    set m $c.figureContext
    if {![winfo exists $m]} {menu $m -tearoff 0}
    $m delete 0 end
    $m add command -label {Edit source image} -command ::GX::SII::editSourceImage
    $m add command -label {Figure Studio settings...} -command {::GX::SII::sidebarSelect figure}
    $m add command -label {Publish composed figure as Dataset...} -command ::GX::SII::publishDialog
    contextPopup $m $X $Y
}
proc ::GX::SII::pendingCanvasContext {X Y} {
    variable ui
    set c $ui(window).layout.main.panes.original.canvas
    set m $c.pendingContext
    if {![winfo exists $m]} {menu $m -tearoff 0}
    $m delete 0 end
    $m add command -label {Accept adjustment preview} -command ::GX::SII::acceptPreview
    $m add command -label {Discard adjustment preview} -command ::GX::SII::discardPreview
    contextPopup $m $X $Y
}
proc ::GX::SII::roiClear {} {
    variable ui
    set ui(roi) {};set ui(scope) all;set ui(analysisUseRoi) 0
    set ui(roiLabel) {ROI: none (whole image)}
    set ui(status) {ROI cleared. Working image remains unchanged.}
    nativeDisplay original
}
proc ::GX::SII::roiAnalysis {action} {
    variable ui
    if {[llength $ui(roi)]!=4} return
    set ui(target) Working
    set ui(analysisUseRoi) 1
    set ui(scope) roi
    switch -- $action {
        histogram {computeHistogram}
        statistics {computeStats}
        default {error {Unknown ROI analysis action}}
    }
}
proc ::GX::SII::roiChoosePreset {steps} {
    variable ui
    set ui(scope) roi
    applyPreset $steps
}
proc ::GX::SII::roiCanvasContext {x y X Y} {
    variable ui
    set c $ui(window).layout.main.panes.original.canvas
    set m $c.roiContext
    if {![winfo exists $m]} {menu $m -tearoff 0}
    $m delete 0 end
    lassign $ui(roi) left top width height
    $m add command -label "Selected ROI: ${width}x${height} at ${left},${top}" -state disabled
    $m add separator
    $m add command -label {Preview crop to ROI} -command ::GX::SII::cropQuick
    $m add command -label {ROI statistics (working image)} -command [list ::GX::SII::roiAnalysis statistics]
    $m add command -label {ROI histogram (working image)} -command [list ::GX::SII::roiAnalysis histogram]
    set where [toImageXY original $x $y]
    if {$where ne {}} {
        $m add command -label {Inspect pixel here} -command [list ::GX::SII::pixelAtXY {*}$where]
    }
    $m add separator
    set presets $m.presets
    if {![winfo exists $presets]} {menu $presets -tearoff 0}
    $presets delete 0 end
    foreach entry [basicPresetCatalog] {
        lassign $entry title description operations
        set compatible 1
        foreach operation $operations {
            set spec [catalogGet [lindex $operation 0]]
            if {![dict get $spec roi] || [dict get [operationStatus [lindex $operation 0]] state] ne "executable"} {
                set compatible 0;break
            }
        }
        if {$compatible} {$presets add command -label $title -command [list ::GX::SII::roiChoosePreset $operations]}
    }
    $m add cascade -label {ROI task presets} -menu $presets -state [expr {[$presets index end] eq "none" ? "disabled" : "normal"}]
    # All installed ROI-safe operations appear in categories and use a single
    # shared generated parameter form. No raw ImageMagick command text.
    set categories {}
    foreach spec [catalogList] {
        if {![dict get $spec roi] || [dict get [operationStatus [dict get $spec id]] state] ne "executable"} continue
        set family [dict get $spec family]
        if {$family ni $categories} {lappend categories $family}
    }
    set parent $m.operators
    if {![winfo exists $parent]} {menu $parent -tearoff 0}
    $parent delete 0 end
    set index 0
    foreach family [lsort -dictionary $categories] {
        set sub $parent.group[incr index]
        if {![winfo exists $sub]} {menu $sub -tearoff 0}
        $sub delete 0 end
        foreach spec [catalogList] {
            if {[dict get $spec family] ne $family || ![dict get $spec roi]} continue
            if {[dict get [operationStatus [dict get $spec id]] state] ne "executable"} continue
            $sub add command -label [dict get $spec label] \
                -command [list ::GX::SII::roiOperationDialog [dict get $spec id]]
        }
        $parent add cascade -label $family -menu $sub
    }
    $m add cascade -label {ROI operations} -menu $parent -state [expr {[llength $categories] ? "normal" : "disabled"}]
    $m add separator
    $m add command -label {Open Advanced Editor (ROI)} -command ::GX::SII::roiOpenAdvanced
    $m add command -label {Clear ROI selection} -command ::GX::SII::roiClear
    contextPopup $m $X $Y
}
proc ::GX::SII::roiOpenAdvanced {} {
    variable ui
    set ui(scope) roi
    editorSwitch advanced
}
proc ::GX::SII::roiOperationDialog {op} {
    variable ui
    if {![historyResumeForEditing] || $ui(pending)} return
    if {[llength $ui(roi)] != 4 || $ui(figurePreviewActive)} return
    set spec [catalogGet $op]
    if {![dict get $spec roi] || [dict get [operationStatus $op] state] ne "executable"} {
        set ui(status) "Operation $op is not available for ROI editing."
        return
    }
    set fields [dict get $spec params]
    if {![llength $fields]} {
        roiOperationPreview $op {} $ui(roi)
        return
    }
    set w $ui(window).roiEditor
    if {[winfo exists $w]} {destroy $w}
    toplevel $w
    wm transient $w $ui(window)
    wm title $w "ROI: [dict get $spec label]"
    ttk::label $w.info -text "[dict get $spec label] — selected ROI: $ui(roi)" -wraplength 355
    ttk::label $w.description -text [dict get $spec about] -wraplength 355
    pack $w.info $w.description -fill x -padx 10 -pady 4
    foreach field $fields {
        lassign $field key type default minimum maximum choices
        set ui(roiParam-$key) $default
        ttk::frame $w.$key
        ttk::label $w.$key.label -text "[string totitle [string map {_ { }} $key]]:" -width 14
        if {$type eq "enum"} {
            ttk::combobox $w.$key.input -state readonly -values $choices -width 22 \
                -textvariable ::GX::SII::ui(roiParam-$key)
        } else {
            ttk::entry $w.$key.input -width 24 -textvariable ::GX::SII::ui(roiParam-$key)
        }
        pack $w.$key.label -side left;pack $w.$key.input -side left -fill x -expand 1
        pack $w.$key -fill x -padx 10 -pady 2
    }
    ttk::label $w.error -text {} -foreground #a52020 -wraplength 355
    pack $w.error -fill x -padx 10 -pady 3
    ttk::frame $w.buttons
    ttk::button $w.buttons.apply -text {Preview operation} \
        -command [list ::GX::SII::roiDialogApply $w $op $ui(roi)]
    ttk::button $w.buttons.cancel -text Cancel -command [list destroy $w]
    pack $w.buttons.apply $w.buttons.cancel -side left -padx 5
    pack $w.buttons -fill x -padx 10 -pady 8
    focus $w.[lindex [lindex $fields 0] 0].input
}
proc ::GX::SII::roiDialogApply {w op originalRoi} {
    variable ui
    if {![winfo exists $w]} return
    set raw {}
    foreach field [dict get [catalogGet $op] params] {
        set key [lindex $field 0]
        dict set raw $key $ui(roiParam-$key)
    }
    if {[catch {set values [validate $op $raw]} err]} {
        $w.error configure -text "Invalid parameter: $err";return
    }
    if {$ui(roi) ne $originalRoi} {
        $w.error configure -text {ROI changed. Reopen the context menu for the new selection.};return
    }
    if {[roiOperationPreview $op $values $originalRoi]} {destroy $w}
}
proc ::GX::SII::roiOperationPreview {op params originalRoi} {
    variable ui
    if {$ui(roi) ne $originalRoi || [llength $ui(roi)]!=4} {
        set ui(status) {ROI has changed; operation not applied.}
        return 0
    }
    if {[catch {
        set params [validate $op $params]
        set step [dict create op $op params $params scope roi roi $originalRoi]
        previewSteps [list $step]
    } err opts]} {
        eventFailure {ROI image adjustment} $err $opts
        return 0
    }
    return [expr {$ui(pending) ? 1 : 0}]
}
