# SPDX-License-Identifier: GPL-3.0-or-later
# Managed native Frame presentation through the existing canonical scalar-plane,
# descriptor image and image-view owners. No image.raster Dataset is invented.
proc ::GX::_previewScientificFrameChoices {host roles} {
    set variables {};set definitions {}
    foreach variable [_previewScientificVariables [dict get [datasetPreviewGuiContext $host] dataset_id]] {
        if {[dict get $variable rank]>=2} {set id [dict get $variable variable_id];lappend variables $id;dict set definitions $id $variable}
    }
    set selected [datasetPreviewGuiControlGet $host [dict get $roles frame_variable]]
    datasetPreviewGuiChoicesSet $host [dict get $roles frame_variable] [linsert $variables 0 {}]
    if {$selected ni $variables} {set selected {};datasetPreviewGuiControlSet $host [dict get $roles frame_variable] {}}
    set dimensions {};if {$selected ne {}} {set dimensions [dict get $definitions $selected dimension_ids]}
    foreach role {frame_x_dimension frame_y_dimension} {
        set control [dict get $roles $role];set previous [datasetPreviewGuiControlGet $host $control]
        datasetPreviewGuiChoicesSet $host $control [linsert $dimensions 0 {}]
        if {$previous ni $dimensions} {datasetPreviewGuiControlSet $host $control {}}
    }
}
proc ::GX::_previewScientificFrameInputs {host roles} {
    set values {};foreach role {frame_variable frame_x_dimension frame_y_dimension frame_indices} {dict set values $role [datasetPreviewGuiControlGet $host [dict get $roles $role]]}
    return $values
}
proc ::GX::_previewScientificFrameOptions {values} {
    set json [dict get $values frame_indices]
    if {[string length [encoding convertto utf-8 $json]]>4096} {error {Frame indices exceed4096 UTF-8 bytes}}
    if {[string trim $json] eq {}} {set json {{}}}
    set typed [nativeWorkspaceJsonDecode $json]
    if {[lindex $typed 0] ne {object}} {error {Frame indices require a JSON object of actual dimension IDs and integer indices}}
    set fixed {}
    dict for {key value} [lindex $typed 1] {
        if {[lindex $value 0] ne {int}} {error {Frame indices require exact integers, not booleans or floating values}}
        dict set fixed $key [lindex $value 1]
    }
    return [dict create variable_id [dict get $values frame_variable] x_dimension_id [dict get $values frame_x_dimension] y_dimension_id [dict get $values frame_y_dimension] indices $fixed]
}
proc ::GX::_previewScientificFrameView {host form widget operation} {
    _previewScientificGuard $host $form scientific_frame_bind 0
    if {[dict exists $::GX::PreviewCpp::mounts $host scientific_frame_fit_pending]} {dict unset ::GX::PreviewCpp::mounts $host scientific_frame_fit_pending}
    if {$operation eq {fit}} {
        set viewport [_uiFieldTabViewportFor $widget]
        set tools [winfo parent $widget].imageTools
        dict set ::GX::PreviewCpp::mounts $host scientific_frame_fit_pending [list $widget [winfo id $widget]]
        if {$viewport ne {} && [winfo exists $tools]} {uiFieldScrollSee $viewport $viewport.content $tools start}
        after idle [list ::GX::_previewScientificFrameFitReady $host $form $widget $widget]
        return 1
    }
    return [datasetPreviewImageView $widget $operation]
}
proc ::GX::_previewScientificFrameWatchRemove {widget viewport identity callback destroyCallback actual} {
    if {$actual ne $widget} return
    if {[winfo exists $viewport] && [winfo id $viewport] eq $identity} {
        set keep {};foreach line [split [bind $viewport <<GXViewportChanged>>] \n] {if {$line ne $callback} {lappend keep $line}}
        bind $viewport <<GXViewportChanged>> [join $keep \n]
    }
    if {[winfo exists $widget]} {
        set keep {};foreach line [split [bind $widget <Destroy>] \n] {if {$line ne $destroyCallback} {lappend keep $line}}
        bind $widget <Destroy> [join $keep \n]
    }
}
proc ::GX::_previewScientificFrameViewportChanged {host form widget viewport identity actual} {
    if {$actual eq $viewport && [winfo exists $viewport] && [winfo id $viewport] eq $identity} {
        after idle [list ::GX::_previewScientificFrameFitReady $host $form $widget $widget]
    }
}
proc ::GX::_previewScientificFrameWatch {host form widget} {
    set viewport [_uiFieldTabViewportFor $widget]
    if {$viewport eq {}} return
    set identity [winfo id $viewport]
    set previous [datasetPublicationV2DictDefault [dict get $::GX::PreviewCpp::mounts $host] scientific_frame_scroll_watch {}]
    if {$previous ne {}} {
        lassign $previous oldViewport oldIdentity oldCallback oldDestroy
        if {$viewport eq $oldViewport && $identity eq $oldIdentity} return
        _previewScientificFrameWatchRemove $widget $oldViewport $oldIdentity $oldCallback $oldDestroy $widget
    }
    set callback [list ::GX::_previewScientificFrameViewportChanged $host $form $widget $viewport $identity %W]
    # Widget destruction itself clears this binding; its literal arguments
    # still remove the viewport observer after the native mount has retired.
    set destroyCallback [list ::GX::_previewScientificFrameWatchRemove $widget $viewport $identity [string map {% %%} $callback] {} %W]
    bind $viewport <<GXViewportChanged>> +$callback
    bind $widget <Destroy> +$destroyCallback
    dict set ::GX::PreviewCpp::mounts $host scientific_frame_scroll_watch [list $viewport $identity $callback $destroyCallback]
}
proc ::GX::_previewScientificFrameFitReady {host form widget actual} {
    if {$widget ne $actual || ![winfo exists $widget] || ![dict exists $::GX::PreviewCpp::mounts $host scientific_frame_fit_pending]} return
    lassign [dict get $::GX::PreviewCpp::mounts $host scientific_frame_fit_pending] expected identity
    if {$widget ne $expected || [winfo id $widget] ne $identity || [catch {_previewScientificGuard $host $form scientific_frame_bind 0}]} return
    _previewScientificFrameWatch $host $form $widget
    if {![winfo ismapped $widget] || [winfo width $widget]<40 || [winfo height $widget]<40} return
    set bounds [uiFieldVisibleBounds $widget]
    set margin [expr {24+5*[font metrics [$widget cget -font] -linespace]+16}]
    if {[dict get $bounds width]<40 || [dict get $bounds height]<$margin || [dict get $bounds y]>[winfo rooty $widget]} return
    dict unset ::GX::PreviewCpp::mounts $host scientific_frame_fit_pending
    datasetPreviewImageView $widget fit
}
proc ::GX::_previewScientificFrameWidget {host form viewport} {
    set parent [dict get [_datasetPreviewGuiControl $host $viewport] widget]
    set body $parent.scientificFrame
    if {![winfo exists $body]} {
        ttk::frame $body;grid $body -row 0 -column 0 -sticky nsew
        grid columnconfigure $parent 0 -weight 1;grid rowconfigure $parent 0 -weight 1
        grid columnconfigure $body 0 -weight 1;grid rowconfigure $body 1 -weight 1
        text $body.image -height 10 -width 30 -wrap none -state disabled -cursor arrow -takefocus 1 -yscrollcommand [list $body.y set] -xscrollcommand [list $body.x set]
        ttk::scrollbar $body.y -orient vertical -command [list $body.image yview]
        ttk::scrollbar $body.x -orient horizontal -command [list $body.image xview]
        grid $body.image -row 1 -column 0 -sticky nsew;grid $body.y -row 1 -column 1 -sticky ns;grid $body.x -row 2 -column 0 -sticky ew
        ttk::frame $body.imageTools
        foreach {name label operation} {fit Fit fit actual 100% actual in + in out − out} {
            ttk::button $body.imageTools.$name -text $label -width 0 -command [list ::GX::_previewScientificFrameView $host $form $body.image $operation]
            pack $body.imageTools.$name -side left -padx 2
        }
        ttk::label $body.imageTools.scale -text {Preview 100%};pack $body.imageTools.scale -side left -padx 6
        bind $body.image <Destroy> [list ::GX::datasetPreviewImageDestroyed $body.image %W]
        foreach event {<Map> <Configure>} {bind $body.image $event +[list ::GX::_previewScientificFrameFitReady $host $form $body.image %W]}
    }
    return $body.image
}
proc ::GX::_previewScientificFrameBind {host form viewport} {
    set roles [_previewScientificGuard $host $form scientific_frame_bind]
    if {![dict exists $roles frame_view] || [dict get $roles frame_view] ne $viewport} {error {Frame binding requires its exact declared managed panel}}
    set r [dict get $::GX::PreviewCpp::mounts $host];set id [dict get [datasetPreviewGuiContext $host] dataset_id]
    set sequence [expr {[datasetPublicationV2DictDefault $r scientific_sequence 0]+1}]
    dict set ::GX::PreviewCpp::mounts $host scientific_sequence $sequence
    set view [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $r scientific_views {}] $form [_previewScientificEmptyView $id]]
    set artifact {}
    try {
        _previewScientificFrameChoices $host $roles
        set values [_previewScientificFrameInputs $host $roles]
        if {[dict get $values frame_variable] eq {} || [dict get $values frame_x_dimension] eq {} || [dict get $values frame_y_dimension] eq {}} {
            # Initial selection is explicitly empty; a source's first two axes
            # have no automatic scientific meaning.
            if {[dict exists $r scientific_frame_widget]} {error {Select an actual array Variable and distinct X/Y dimensions}}
            set receipt [_previewScientificEnvelope $host $form frame completed {} $view {null {}} $sequence]
            dict set ::GX::PreviewCpp::mounts $host scientific_result $receipt
            set widget [_previewScientificFrameWidget $host $form $viewport]
            if {![dict exists $r scientific_frame_widget]} {$widget configure -state normal;$widget insert end {Select a canonical array Variable and distinct X/Y dimensions, then render.};$widget configure -state disabled}
            return
        }
        set options [_previewScientificFrameOptions $values]
        set prepared [scientificDatasetArrayPlane $id $options]
        _previewScientificGuard $host $form scientific_frame_bind
        if {[_previewScientificFrameInputs $host $roles] ne $values} {error {Frame controls changed during canonical plane preparation}}
        set v [dict get $prepared variable];set plane [dict get $prepared plane];set indices {}
        dict for {dimension index} [dict get $prepared indices] {lappend indices [dict create dimension_id $dimension index $index]}
        set frame [dict create variable_id [dict get $v variable_id] dtype [dict get $v dtype] unit [dict get $v unit] x_dimension_id [dict get $prepared x_dimension_id] y_dimension_id [dict get $prepared y_dimension_id] source_revision [dict get $prepared source_revision] starts [dict get $prepared starts] counts [dict get $prepared counts] indices $indices minimum [dict get $plane minimum] maximum [dict get $plane maximum] finite_count [dict get $plane finite_count] width [dict get $plane width] height [dict get $plane height]]
        set next [dict replace $view frame $frame source [_previewScientificIdentity $id]]
        set receipt [_previewScientificEnvelope $host $form frame completed {} $next {object {}} $sequence]
        set directory [dict get $r allocation path];set artifact [file join $directory scientific-plane-$sequence.png]
        if {[file exists $artifact]} {error {Frame artifact identity is already occupied}}
        scientificDatasetArrayPlaneWrite $prepared $artifact
        _previewScientificGuard $host $form scientific_frame_bind
        if {[_previewScientificFrameInputs $host $roles] ne $values || [datasetRevisionToken $id] ne [dict get $prepared source_revision]} {error {Frame source or controls changed before presentation}}
        set widget [_previewScientificFrameWidget $host $form $viewport]
        datasetPreviewImageRepresentationPresent $widget [dict create path [file tail $artifact] media_type image/png label {Scientific scalar plane}] $directory {fit_upscale 1 fit_margin_lines 5 fit_visible_viewport 1}
        $widget insert end "\n[dict get $v canonical] ([dict get $v unit]); X [dict get $frame x_dimension_id], Y [dict get $frame y_dimension_id]. Exact starts [dict get $frame starts], counts [dict get $frame counts]; fixed indices [dict get $prepared indices].\nRange [dict get $frame minimum] to [dict get $frame maximum]; [dict get $frame finite_count] finite cells. Gray = nonfinite; nearest-cell display, no interpolation.\nCanonical SHA-256: [datasetField $id canonical_sha256 [datasetField $id sha256 {}]]. Full provenance and revision are available in Source and Metadata.\n"
        $widget configure -state disabled
        dict set ::GX::PreviewCpp::mounts $host scientific_frame_widget $widget
        dict set ::GX::PreviewCpp::mounts $host scientific_frame_form $form
        dict set ::GX::PreviewCpp::mounts $host scientific_views $form $next
        dict set ::GX::PreviewCpp::mounts $host scientific_result $receipt
        dict set ::GX::PreviewCpp::mounts $host scientific_frame_fit_pending [list $widget [winfo id $widget]]
        after idle [list ::GX::_previewScientificFrameFitReady $host $form $widget $widget]
    } on error {message options} {
        if {[dict exists $::GX::PreviewCpp::mounts $host]} {
            dict set ::GX::PreviewCpp::mounts $host scientific_result [_previewScientificEnvelope $host $form frame failed [string range $message 0 2047] $view {null {}} $sequence]
        }
        return -options $options $message
    } finally {
        # The descriptor owns the decoded photo; no persistent scientific cache
        # or artifact path is exposed to restricted C++ code.
        if {$artifact ne {} && [file exists $artifact]} {file delete $artifact}
    }
}
