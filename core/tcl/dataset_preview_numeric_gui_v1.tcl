# SPDX-License-Identifier: GPL-3.0-or-later
# Additive Preview GUI facilities. Actual canonical identity is supplied by the
# current Preview host; authored modules never choose a Dataset path or ID here.
proc ::GX::datasetPreviewGuiChoicesSet {host id choices} {
    set control [_datasetPreviewGuiControl $host $id]
    set type [dict get $control type];set widget [dict get $control widget]
    if {$type ni {choice combobox} || [llength $choices]>4096 || [string bytelength $choices]>1048576} {error {Use a declared choice control and bounded choices}}
    set previous [datasetPreviewGuiControlGet $host $id]
    if {$type eq {choice}} {uiFieldChoicesSet $widget $choices} else {$widget configure -values $choices}
    # Validate the old selection before replacing its allowed domain. Reading
    # it through the new domain would reject an ordinary choice refresh.
    if {$previous ni $choices} {datasetPreviewGuiControlSet $host $id [lindex $choices 0]}
    return $choices
}
proc ::GX::datasetPreviewGuiPlotCreate {host id {properties {}} {options {}}} {
    foreach key [dict keys $properties] {if {$key ni {title}} {error {Embedded Preview Plot accepts only its presentation title}}}
    set widget [datasetPreviewGuiControlCreate $host $id panel {} $options]
    dict set ::GX::PreviewGui::mounts $host controls $id type plot
    dict set ::GX::PreviewGui::mounts $host controls $id properties $properties
    ttk::label $widget.empty -text {No canonical waveform selected}
    pack $widget.empty -fill both -expand 1
    return $widget
}
proc ::GX::datasetPreviewGuiPlotBind {host id selection} {
    set record [_datasetPreviewGuiRequire $host]
    set control [_datasetPreviewGuiControl $host $id]
    if {[dict get $control type] ne {plot}} {error {Select a declared Preview Plot}}
    foreach key [dict keys $selection] {if {$key ni {x_variable_id y_variable_id x_scale y_scale}} {error {Preview Plot selection supports actual X/Y Variables and axis scales only}}}
    foreach key {x_variable_id y_variable_id} {if {![dict exists $selection $key]} {error {Both canonical X and Y Variables are required}}}
    set spec [_viewerGuiCanonicalPlotSpec [dict get $record dataset] [dict get $selection x_variable_id] [dict get $selection y_variable_id]]
    if {[dict exists $control properties title]} {dict set spec title [dict get $control properties title]}
    set panel [lindex [dict get $spec panels] 0]
    foreach {key axis} {x_scale x y_scale y_left} {
        if {[dict exists $selection $key]} {
            set scale [dict get $selection $key]
            if {$scale ni {linear log}} {error {Choose the public Plot axis scale linear or log}}
            dict set panel axes $axis scale $scale
        }
    }
    dict set spec panels [list $panel]
    set widget [dict get $control widget]
    # Existing Plot v4 retained-presentation context acknowledges disposable
    # Preview preferences while retaining exact scientific/coordinate checks.
    set context {retain_presentation 1}
    if {[winfo exists $widget.plot]} {
        set plot [::GX::PlotDatasetAPIv4::widgetConfigure $widget.plot $spec $context]
    } else {
        set plot [::GX::PlotDatasetAPIv4::widgetCreate $widget.plot $spec $context]
        destroy $widget.empty
        pack $plot -fill both -expand 1
    }
    _datasetPreviewGuiRequire $host
    dict set ::GX::PreviewGui::mounts $host controls $id canonical_selection $selection
    return [dict create dataset_id [dict get $record dataset] selection $selection receipt [::GX::PlotDatasetAPIv4::widgetReceipt $plot]]
}
proc ::GX::datasetPreviewGuiPlotView {host id operation} {
    set control [_datasetPreviewGuiControl $host $id]
    if {[dict get $control type] ne {plot} || $operation ni {fit zoom_in zoom_out}} {error {Choose a declared Preview Plot and Fit/Zoom operation}}
    set plot [dict get $control widget].plot
    if {![winfo exists $plot]} {error {Bind a canonical waveform first}}
    if {$operation eq {fit}} {return [::GX::PlotDatasetAPIv4::widgetView $plot fit]}
    foreach axis [dict get [::GX::PlotDatasetAPIv4::widgetReceipt $plot] axes] {
        if {[dict get $axis axis] eq {x}} {::GX::PlotDatasetAPIv4::widgetView $plot zoom [dict get $axis panel_id] [expr {$operation eq {zoom_in}?1.25:.8}] .5 .5}
    }
}
proc ::GX::datasetPreviewGuiTableSet {host id rows} {
    set control [_datasetPreviewGuiControl $host $id]
    if {[dict get $control type] ne {table} || [llength $rows]>1000 || [string bytelength $rows]>4194304} {error {Choose a declared read-only table and a bounded page}}
    set table [uiFieldComponentTableWidget [dict get $control widget]]
    set count [llength [$table cget -columns]]
    foreach row $rows {if {[llength $row]>$count} {error {Presented table row exceeds its declared columns}}}
    $table delete [$table children {}]
    foreach row $rows {$table insert {} end -values $row}
    if {[datasetPublicationV2DictDefault [dict get $control properties] scrollbars none] in {horizontal both}} {uiFieldInspectionColumnsSchedule $table}
    return [dict create rows [llength $rows] read_only 1]
}
