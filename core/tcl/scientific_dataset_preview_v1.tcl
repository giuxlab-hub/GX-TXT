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
proc ::GX::scientificDatasetPreviewControls {id axes} {
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
    scientificDatasetFilterControls $bar.filters $id ::GX::ui previewMap $reset
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
    set handle [datasetAccessOpen $::GX::currentSession $id]
    try {set values [dict get [datasetAccessReadHyperslab $handle [dict get $v variable_id] $starts $counts] values]} finally {datasetAccessClose $handle}
    set lo Inf;set hi -Inf
    foreach value $values {if {![catch {expr {abs($value)<Inf}} finite]&&$finite} {set lo [expr {min($lo,$value)}];set hi [expr {max($hi,$value)}]}}
    if {$lo eq "Inf"} {error {Array plane has no finite values.}}
    set nx [lindex $counts end];set ny [lindex $counts end-1]
    set small [image create photo -width $nx -height $ny];set large [image create photo]
    try {
        set row {};set y 0
        foreach value $values {
            set color #b8b8b8
            if {![catch {expr {abs($value)<Inf}} finite]&&$finite} {set t [expr {$hi==$lo?.5:($value-$lo)/($hi-$lo)}];set color [format #%02x%02x%02x [expr {int(255*$t)}] [expr {int(180*(1-abs(2*$t-1)))}] [expr {int(255*(1-$t))}]]}
            lappend row $color
            if {[llength $row]==$nx} {$small put [list $row] -to 0 $y;incr y;set row {}}
        }
        set scale [expr {max(1,min(8,int(640.0/$nx),int(420.0/$ny)))}]
        $large copy $small -zoom $scale $scale;$large write $output -format png
    } finally {image delete $small $large}
    return "[dict get $v canonical] ([dict get $v unit]); exact storage plane starts $starts, counts $counts. Range $lo to $hi. Gray = nonfinite; nearest-cell display, no interpolation. Coordinate IDs: [dict get $v coordinate_variable_ids]. Open Dataset for coordinate axes and explicit planes."
}

proc ::GX::scientificDatasetPreviewCoordinateEditor {} {
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
    if {$mode ne "imported"||$id eq {}} {error {Select a canonical scientific Dataset}}
    datasetCoordinateEditorOpen $id .
}
