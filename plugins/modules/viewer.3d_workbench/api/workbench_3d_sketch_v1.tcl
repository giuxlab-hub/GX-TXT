# SPDX-License-Identifier: GPL-3.0-or-later
# Legacy presentation bridge to the same public CORE managed Sketch component.
# The Workbench retains its existing Document, plane and P017 History owner.
namespace eval ::GX::Workbench3D {variable sketchComponent {};variable sketchWindow {};variable sketchDisplayed {}}
proc ::GX::Workbench3D::sketchClose {{retain 1} {refresh 1}} {
    variable sketchComponent;variable sketchWindow;variable model;variable sketchDisplayed
    if {$sketchComponent ne {} && [llength [info commands $sketchComponent]]} {
        if {[catch {$sketchComponent guard}]} {$sketchComponent destroy} else {
            set result [$sketchComponent close]
            if {[dict get $result status] eq {cancelled}} {return $result}
        }
    }
    set sketchComponent {}
    if {$sketchWindow ne {} && [winfo exists $sketchWindow]} {destroy $sketchWindow}
    set sketchWindow {}
    # Resident native actors survive editor closure; no full scene rebuild.
    return [dict create status closed]
}
proc ::GX::Workbench3D::sketchPresentSaved {} {
    variable sketchComponent;variable model;variable sketchDisplayed
    if {![dict exists $model sketch_documents]} {set documents {}} else {set documents [dict keys [dict get $model sketch_documents]]}
    foreach old [dict keys $sketchDisplayed] {
        if {$old ni $documents} {
            set binding [dict get $sketchDisplayed $old]
            if {[llength [info commands $binding]]} {$binding detach}
            dict unset sketchDisplayed $old
        }
    }
    if {![llength $documents]} return
    if {![winfo exists $::GX::Engine3D::window.canvas]} return
    if {![llength [info commands ::GX::nativeCadSketchSceneAttach]]} {source [file join $::GX::scriptDir core tcl native_cad_sketch_v1.tcl]}
    set surface [::GX::native3DGuiHostSurface]
    try {
        # Batch checked metadata admission; full solver/History is lazy.
        ::GX::nativeCadSketchQuickOpenList $documents [dict get $model working_unit]
        foreach id $documents {
            dict set sketchDisplayed $id [::GX::nativeCadSketchSceneAttach $surface $id [dict create working_unit [dict get $model working_unit] edit_command ::GX::Workbench3D::sketchEditRequest]]
        }
    } finally {$surface dispose}
}
proc ::GX::Workbench3D::sketchGuiCommand {action {values {}}} {
    variable sketchComponent;variable sketchWindow;variable document;variable model;variable module;variable provider
    if {$action ni {sketch_create sketch_open sketch_close}} {error {Unknown finite Workbench Sketch command}}
    if {$action eq {sketch_close}} {
        if {$values ne {}} {error {Sketch close accepts no values}}
        return [dict merge [sketchClose] [dict create action $action workbench_document_id $document]]
    }
    if {![llength [info commands ::GX::nativeCadSketchCreate]]} {source [file join $::GX::scriptDir core tcl native_cad_sketch_v1.tcl]}
    set requested new
    if {$action eq {sketch_create}} {
        if {$values ne {}} {error {Sketch create uses the Workbench working plane and unit}}
    } else {
        if {$values ne {} && [dict keys $values] ne {document_id}} {error {Sketch open accepts only document_id}}
        if {[dict exists $values document_id]} {
            set requested [dict get $values document_id]
            if {![dict exists $model sketch_documents $requested]} {error {Sketch is not associated with this Workbench Document}}
        } elseif {[info exists ::GX::Workbench3D::sketchSelected] && $::GX::Workbench3D::sketchSelected ne {} && [dict exists $model sketch_documents $::GX::Workbench3D::sketchSelected]} {
            set requested $::GX::Workbench3D::sketchSelected
        } elseif {[dict exists $model sketch_documents] && [dict size [dict get $model sketch_documents]]} {
            set requested [lindex [dict keys [dict get $model sketch_documents]] end]
        } else {error {Create an associated Sketch first}}
    }
    if {$requested ne {new} && $sketchComponent ne {} && [llength [info commands $sketchComponent]] && [$sketchComponent get document_id] eq $requested} {
        $sketchComponent guard
        return [dict create action $action status open workbench_document_id $document sketch_document_id $requested component $sketchComponent widget [$sketchComponent widget] sketch [$sketchComponent state]]
    }
    if {[dict get [sketchClose 1 0] status] eq {cancelled}} {return [dict create action $action status cancelled workbench_document_id $document]}
    set view [::GX::viewerSceneGet $module $provider]
    set plane {}
    foreach {target source} {origin working_plane_origin normal working_plane_normal u_axis working_plane_u_axis} {dict set plane $target [split [dict get $view $source] {;}]}
    # The resource frame owns controls/lifecycle, never a second display.
    set sketchWindow $::GX::Engine3D::window.sketch
    ttk::frame $sketchWindow
    set surface [::GX::native3DGuiHostSurface]
    try {
        set sketchComponent [::GX::nativeCadSketchCreate $sketchWindow [dict create document_id $requested working_unit [dict get $model working_unit] plane $plane presentation canvas viewport $surface]]
        $sketchComponent canvasControls
        set id [$sketchComponent get document_id]
        dict set ::GX::Workbench3D::sketchDisplayed $id [$sketchComponent get resident]
        if {$requested eq {new}} {
            set before $model
            dict set model sketch_documents $id [dict create document_id $id working_unit [$sketchComponent get working_unit] plane [$sketchComponent get plane]]
            commit $before {Create working-plane Sketch} [dict create sketch_document_id $id] {} [list $id]
        }
        # Native resident resource updates preserve the current scene/camera.
        return [dict create action $action status open workbench_document_id $document sketch_document_id $id component $sketchComponent widget [$sketchComponent widget] sketch [$sketchComponent state]]
    } on error {message options} {
        if {$sketchComponent ne {} && [llength [info commands $sketchComponent]]} {$sketchComponent destroy;set sketchComponent {}}
        if {[llength [info commands $surface]]} {$surface dispose}
        if {[winfo exists $sketchWindow]} {destroy $sketchWindow};set sketchWindow {}
        return -options $options $message
    }
}

proc ::GX::Workbench3D::sketchEditRequest {receipt} {
    return [sketchGuiCommand sketch_open [dict create document_id [dict get $receipt document_id]]]
}
proc ::GX::Workbench3D::sketchPicked {pick} {
    if {![string match sketch-resource/* [dict get $pick layer_id]]} {return 0}
    set surface [::GX::native3DGuiHostSurface]
    try {set receipt [::GX::nativeCadSketchSceneResolvePick $surface $pick]} finally {$surface dispose}
    if {$receipt eq {}} {return 0}
    set ::GX::Workbench3D::sketchSelected [dict get $receipt document_id]
    set ::GX::Workbench3D::status "Selected Sketch $::GX::Workbench3D::sketchSelected; use Open Sketch to edit the same scientific Document"
    return 1
}
