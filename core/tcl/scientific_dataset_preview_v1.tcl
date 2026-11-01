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
        ttk::frame $bar.heading
        ttk::button $bar.heading.toggle -text {Show axes / filters} -width 0 -command ::GX::scientificDatasetPreviewSettingsToggle
        ttk::label $bar.heading.summary -textvariable ::GX::ui(previewMap,compact_status) -wraplength 400 -anchor w
        pack $bar.heading.toggle -side left -padx 3 -pady 2
        pack $bar.heading.summary -side left -fill x -expand 1 -padx 6
        bind $bar.heading.summary <Configure> [list $bar.heading.summary configure -wraplength %w]
        grid $bar.heading -row 0 -column 0 -sticky ew
        set content [uiFieldScrollableCreate $bar.settings 500]
        $bar.settings.scroll configure -height 160
        grid columnconfigure $content 0 -weight 1
        set ui(previewMap,settings_open) 0
        ttk::frame $bar.axes;grid $bar.axes -in $content -row 0 -column 0 -sticky ew
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
        ttk::frame $bar.filters;grid $bar.filters -in $content -row 1 -column 0 -sticky ew
        ttk::label $bar.mode -textvariable ::GX::ui(previewMap,status) -wraplength 850
        grid $bar.mode -in $content -row 2 -column 0 -sticky ew -padx 3
        bind $bar.mode <Configure> [list $bar.mode configure -wraplength %w]
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
    set ui(previewMap,compact_status) "[llength [datasetPublicationV2DictDefault $ui(previewMap,filters) @predicates {}]] configured row predicates"
    # The settings keep their existing widget paths/callbacks and full state;
    # only their presentation is folded. A bounded shared scroll region keeps
    # settings and the scientific/component viewport reachable at large fonts.
    set queue [list $bar.axes $bar.filters $bar.mode]
    while {[llength $queue]} {
        set widget [lindex $queue 0];set queue [lrange $queue 1 end]
        set callback [list ::GX::uiFieldScrollSee $bar.settings.scroll $bar.settings.scroll.content $widget]
        if {$callback ni [split [bind $widget <FocusIn>] \n]} {bind $widget <FocusIn> +$callback}
        if {[winfo class $widget] in {Frame TFrame Label TLabel Button TButton}} {
            foreach {event delta} {<MouseWheel> %D <Button-4> 1 <Button-5> -1} {
                # These retained controls have an ancestor geometry parent;
                # delegate their wheel to the existing scroll-region owner.
                bind $widget $event "[list ::GX::_uiFieldScrollableWheel $bar.settings $bar.settings.scroll.content $delta];break"
            }
        }
        lappend queue {*}[winfo children $widget]
    }
    return $axes
}
proc ::GX::scientificDatasetPreviewSettingsToggle {} {
    variable ui
    set bar .top.nb.preview.mapping
    if {![winfo exists $bar.settings]} return
    set ui(previewMap,settings_open) [expr {!$ui(previewMap,settings_open)}]
    if {$ui(previewMap,settings_open)} {
        grid $bar.settings -row 1 -column 0 -sticky ew
        $bar.heading.toggle configure -text {Hide axes / filters}
    } else {
        grid remove $bar.settings
        $bar.heading.toggle configure -text {Show axes / filters}
    }
}
# Existing scalar-plane renderer, with additive explicit Variable/dimension
# selection. Older callers retain the first-array/last-two-dimension defaults.
proc ::GX::scientificDatasetArrayPlane {id {options {}} {output {}}} {
    set requested [datasetPublicationV2DictDefault $options variable_id {}]
    if {[dict exists $options variable_id] && $requested eq {}} {error {Select an actual canonical array Variable}}
    foreach variable [datasetVariableSchemaV3 $id] {
        if {![dict get $variable enabled] || [dict get $variable rank]<2 || [dict get $variable value_kind] eq {text}} continue
        if {$requested eq {} || [dict get $variable variable_id] eq $requested} {set v $variable;break}
    }
    if {![info exists v]} {if {$requested ne {}} {error {Select an actual enabled canonical array Variable}};return {}}
    set shape [datasetSchemaV3SplitIds [dict get $v shape]];set dimensions [datasetSchemaV3SplitIds [dict get $v dimension_ids]]
    set rank [llength $shape]
    if {$rank<2 || [llength $dimensions]!=$rank} {error {Canonical array dimensions are incomplete}}
    set x [datasetPublicationV2DictDefault $options x_dimension_id [lindex $dimensions end]]
    set y [datasetPublicationV2DictDefault $options y_dimension_id [lindex $dimensions end-1]]
    set xi [lsearch -exact $dimensions $x];set yi [lsearch -exact $dimensions $y]
    if {$xi<0 || $yi<0 || $xi==$yi} {error {Select distinct actual X and Y dimensions}}
    set fixed [datasetPublicationV2DictDefault $options indices {}]
    if {[catch {dict size $fixed}]} {error {Fixed array indices require a dictionary}}
    dict for {dimension index} $fixed {if {$dimension ni $dimensions || $dimension in [list $x $y]} {error {Fixed indices may name only actual non-X/Y dimensions}}}
    set starts {};set counts {};set indices {}
    for {set axis 0} {$axis<$rank} {incr axis} {
        set extent [lindex $shape $axis];set dimension [lindex $dimensions $axis]
        if {![string is wideinteger -strict $extent] || $extent<1} {error {Array is empty or its shape is invalid}}
        if {$axis in [list $xi $yi]} {lappend starts 0;lappend counts [expr {min(128,$extent)}]
        } else {
            set index [datasetPublicationV2DictDefault $fixed $dimension 0]
            if {![string is wideinteger -strict $index] || $index<0 || $index>=$extent} {error {Fixed canonical array index is outside its actual dimension}}
            lappend starts $index;lappend counts 1;dict set indices $dimension $index
        }
    }
    set nx [lindex $counts $xi];set ny [lindex $counts $yi]
    set before [datasetRevisionToken $id]
    native2DEnsure
    if {![llength [info commands ::gx::native2d::_preview_plane]]} {error {The shared Native2D adapter lacks native array Preview support}}
    set handle [datasetAccessOpen $::GX::currentSession $id]
    try {
        if {[dict get [datasetAccessCapabilities $handle] typed_binary_read] && [dict get $v dtype] in [datasetBinaryTransportDtypes]} {
            set chunk [datasetAccessReadHyperslabBinary $handle [dict get $v variable_id] $starts $counts]
            set block [dict get $chunk binary_block];datasetBinaryValidateBlock $block [expr {$nx*$ny}]
            set raw [binary decode base64 [dict get $block base64]]
            if {$xi<$yi} {
                # Canonical C order makes the earlier dimension slower. Reorder
                # complete typed byte cells for presentation, never decode or
                # rewrite canonical scientific payloads or integer values.
                set width [expr {[string length $raw]/($nx*$ny)}];set transposed {}
                for {set row 0} {$row<$ny} {incr row} {for {set col 0} {$col<$nx} {incr col} {set at [expr {($col*$ny+$row)*$width}];append transposed [string range $raw $at [expr {$at+$width-1}]]}}
                set raw $transposed
            }
            set column [dict create dtype [dict get $block dtype] endian [dict get $block endian] raw $raw]
        } else {
            set chunk [datasetAccessReadHyperslab $handle [dict get $v variable_id] $starts $counts];set values [dict get $chunk values]
            if {$xi<$yi} {set transposed {};for {set row 0} {$row<$ny} {incr row} {for {set col 0} {$col<$nx} {incr col} {lappend transposed [lindex $values [expr {$col*$ny+$row}]]}};set values $transposed}
            set column [dict create dtype [dict get $chunk dtype] values $values]
        }
        if {$xi<$yi} {
            # The v1 provider plan promises original canonical C order. A
            # transposed presentation uses the same built-in scalar renderer.
            set plane [::gx::native2d::_preview_plane $column $nx $ny]
        } else {set plane [datasetPreviewNativePlane $id $v $starts $counts $column $nx $ny $output [datasetPublicationV2DictDefault $options primary_component {}]]}
    } finally {datasetAccessClose $handle}
    if {[datasetRevisionToken $id] ne $before} {error {Canonical array source changed during plane preparation}}
    return [dict create variable $v starts $starts counts $counts indices $indices x_dimension_id $x y_dimension_id $y x_count $nx y_count $ny source_revision $before plane $plane]
}
proc ::GX::scientificDatasetArrayPreview {id output {receiptVar {}} {options {}}} {
    if {$receiptVar ne {}} {upvar 1 $receiptVar nativeReceipt;set nativeReceipt {}}
    set prepared [scientificDatasetArrayPlane $id $options $output]
    if {$prepared eq {}} {return {}}
    set v [dict get $prepared variable];set starts [dict get $prepared starts];set counts [dict get $prepared counts];set plane [dict get $prepared plane]
    if {$receiptVar ne {} && [dict exists $plane native_provider]} {set nativeReceipt [dict get $plane native_provider]}
    set lo [dict get $plane minimum];set hi [dict get $plane maximum]
    scientificDatasetArrayPlaneWrite $prepared $output
    return "[dict get $v canonical] ([dict get $v unit]); exact storage plane starts $starts, counts $counts. Range $lo to $hi. Gray = nonfinite; nearest-cell display, no interpolation. Coordinate IDs: [dict get $v coordinate_variable_ids]. Open Dataset for coordinate axes and explicit planes."
}

proc ::GX::scientificDatasetPreviewCoordinateEditor {} {
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
    if {$mode ne "imported"||$id eq {}} {error {Select a canonical scientific Dataset}}
    datasetCoordinateEditorOpen $id .
}

# Serialization shared by generic array Preview and the native Frame host.
proc ::GX::scientificDatasetArrayPlaneWrite {prepared output} {
    set plane [dict get $prepared plane]
    set encoder [datasetPreviewTool magick]
    if {$encoder eq {}} {error {Configured PNG encoder is unavailable}}
    set stream [file tempfile temporary [file join [file dirname [file normalize $output]] .array-preview-XXXXXX]];close $stream
    try {
        resourceLifecycleWriteBytes $temporary [dict get $plane ppm]
        exec $encoder $temporary PNG:$output
    } finally {file delete -force $temporary}
    return $output
}
