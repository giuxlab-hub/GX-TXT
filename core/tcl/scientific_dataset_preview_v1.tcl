# SPDX-License-Identifier: GPL-3.0-or-later
# Display is a projection of the canonical schema. Stable IDs remain the
# numerical selection authority; neither v000N nor raw ordinals are parsed.
proc ::GX::scientificDatasetPreviewVariableLabel {id variableId} {
    set variable [datasetVariableById $id $variableId]
    set label [dict get $variable canonical]
    if {[dict get $variable unit] ne {}} {append label " (source [dict get $variable unit])"}
    append label " — $variableId"
    return $label
}
proc ::GX::scientificDatasetPreviewAxisSelected {axis} {
    variable ui
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
    if {$mode ne "imported" || $ui(previewMap,id) ne [list [dict get [datasetCatalogSnapshot] session_token] $id]} return
    set widget .top.nb.preview.mapping.axes.$axis
    # Resolve through the current public schema, not a persistent label/ID map.
    foreach variableId [dict get [scientificDatasetAxes $id] numeric] {
        if {[$widget get] eq [scientificDatasetPreviewVariableLabel $id $variableId]} {
            set ui(previewMap,$axis) $variableId
            scientificDatasetFilterPersist ::GX::ui previewMap
            return
        }
    }
    scientificDatasetPreviewControls $id [scientificDatasetAxes $id]
}
proc ::GX::scientificDatasetPreviewControls {id axes {preparedDimensions @discover}} {
    variable ui
    set bar .top.nb.preview.mapping
    if {![winfo exists $bar]} {
        ttk::frame $bar
        grid columnconfigure $bar 0 -weight 1
        ttk::frame $bar.axes;grid $bar.axes -row 0 -column 0 -sticky ew
        foreach key {x y z} {
            ttk::label $bar.axes.${key}Label -text [string toupper $key]
            ttk::combobox $bar.axes.$key -textvariable ::GX::ui(previewMap,label,$key) -state readonly -width 27
            bind $bar.axes.$key <<ComboboxSelected>> [list ::GX::scientificDatasetPreviewAxisSelected $key]
            pack $bar.axes.${key}Label $bar.axes.$key -side left -padx 3
        }
        ttk::button $bar.axes.apply -text Render -command ::GX::datasetPreviewRender
        pack $bar.axes.apply -side left -padx 6
        ttk::button $bar.axes.coordinates -text {Dataset coordinates…} -command ::GX::scientificDatasetPreviewCoordinateEditor
        pack $bar.axes.coordinates -side left -padx 4
        ttk::button $bar.axes.xyz -text {⟳ 3D XYZ} -command ::GX::native3DPreviewXYZActivate
        pack $bar.axes.xyz -side left -padx 4
        bind $bar.axes <Configure> {::GX::uiFieldControlsLayout %W %w}
        ttk::frame $bar.filters;grid $bar.filters -row 1 -column 0 -sticky w
        ttk::label $bar.mode -textvariable ::GX::ui(previewMap,status) -wraplength 850
        grid $bar.mode -row 2 -column 0 -sticky w -padx 3
    }
    grid $bar -row 1 -column 0 -columnspan 2 -sticky ew
    set identity [list [dict get [datasetCatalogSnapshot] session_token] $id]
    set reset [expr {![info exists ui(previewMap,id)] || $ui(previewMap,id) ne $identity}]
    if {$reset} {set ui(previewMap,id) $identity}
    set saved [datasetPreviewConfigurationRead $id]
    foreach key {x y z} {
        if {$reset || ![info exists ui(previewMap,$key)] || $ui(previewMap,$key) ni [dict get $axes numeric]} {set ui(previewMap,$key) [datasetPublicationV2DictDefault $axes $key {}]}
        if {$reset && [dict exists $saved $key] && [dict get $saved $key] in [dict get $axes numeric]} {set ui(previewMap,$key) [dict get $saved $key]}
        set labels [lmap variableId [dict get $axes numeric] {scientificDatasetPreviewVariableLabel $id $variableId}]
        $bar.axes.$key configure -values $labels
        set ui(previewMap,label,$key) [expr {$ui(previewMap,$key) eq {} ? {} : [scientificDatasetPreviewVariableLabel $id $ui(previewMap,$key)]}]
        dict set axes $key $ui(previewMap,$key)
    }
    scientificDatasetFilterControls $bar.filters $id ::GX::ui previewMap $reset {} 0 $preparedDimensions
    if {$ui(previewMap,dimensions) eq {}} {grid remove $bar.filters} else {grid $bar.filters}
    set ui(previewMap,status) [scientificDatasetFilterMode $ui(previewMap,dimensions) $ui(previewMap,filters) $ui(previewMap,separate)]
    return $axes
}
proc ::GX::scientificDatasetArrayPreview {id output} {
    foreach variable [datasetVariableSchemaV3 $id] {
        if {[dict get $variable enabled]&&[dict get $variable rank]>=2&&[dict get $variable value_kind] ne "text"} {set v $variable;break}
    }
    if {![info exists v]} {return {}}
    set starts {};set counts {};set shape [datasetSchemaV3SplitIds [dict get $v shape]]
    for {set i 0} {$i<[llength $shape]} {incr i} {lappend starts 0;lappend counts [expr {$i<[llength $shape]-2?1:min(128,[lindex $shape $i])}]}
    if {0 in $counts} {error {Array is empty.}}
    native2DEnsure
    if {![llength [info commands ::gx::native2d::_preview_plane]]} {
        error {The shared Native2D adapter lacks native array Preview support}
    }
    set nx [lindex $counts end];set ny [lindex $counts end-1]
    set handle [datasetAccessOpen $::GX::currentSession $id]
    try {
        # Both transports use the existing canonical owner and C storage order.
        # Prefer its typed block without serializing every numeric cell in Tcl.
        if {[dict get [datasetAccessCapabilities $handle] typed_binary_read] &&
            [dict get $v dtype] in [datasetBinaryTransportDtypes]} {
            set chunk [datasetAccessReadHyperslabBinary $handle [dict get $v variable_id] $starts $counts]
            set block [dict get $chunk binary_block]
            datasetBinaryValidateBlock $block [expr {$nx*$ny}]
            set column [dict create dtype [dict get $block dtype] endian [dict get $block endian] raw [binary decode base64 [dict get $block base64]]]
        } else {
            set chunk [datasetAccessReadHyperslab $handle [dict get $v variable_id] $starts $counts]
            set column [dict create dtype [dict get $chunk dtype] values [dict get $chunk values]]
        }
        set plane [::gx::native2d::_preview_plane $column $nx $ny]
    } finally {datasetAccessClose $handle}
    set lo [dict get $plane minimum];set hi [dict get $plane maximum]
    set encoder [datasetPreviewTool magick]
    if {$encoder eq {}} {error {Configured PNG encoder is unavailable}}
    set stream [file tempfile temporary [file join [file dirname [file normalize $output]] .array-preview-XXXXXX]];close $stream
    try {
        resourceLifecycleWriteBytes $temporary [dict get $plane ppm]
        exec $encoder $temporary PNG:$output
    } finally {file delete -force $temporary}
    return "[dict get $v canonical] ([dict get $v unit]); exact storage plane starts $starts, counts $counts. Range $lo to $hi. Gray = nonfinite; nearest-cell display, no interpolation. Coordinate IDs: [dict get $v coordinate_variable_ids]. Open Dataset for coordinate axes and explicit planes."
}

proc ::GX::scientificDatasetPreviewCoordinateEditor {} {
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
    if {$mode ne "imported"||$id eq {}} {error {Select a canonical scientific Dataset}}
    datasetCoordinateEditorOpen $id .
}
